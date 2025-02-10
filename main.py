#!/usr/bin/env python3
import pandas as pd
import tensorflow as tf
import numpy as np

from sklearn import preprocessing
from sklearn.linear_model import LinearRegression
from sklearn.metrics import r2_score
from sklearn.covariance import GraphicalLasso, EmpiricalCovariance
from tensorflow import keras
from bray_curtis import BrayCurtis
from data_handler import DataHandler
from load_data import rev_transform
from idec.IDEC import IDEC
from plotting import plot_prediction, train_tsne, plot_tsne, create_boxplot
from correlation import calc_cluster_correlations, calc_correlation_aggregates
from re import sub
from os import mkdir, path

#fixes "No algorithm worked!" error, see
#https://github.com/tensorflow/tensorflow/issues/43174#issuecomment-730959541
from tensorflow.compat.v1 import ConfigProto
from tensorflow.compat.v1 import InteractiveSession

config = ConfigProto()
config.gpu_options.allow_growth = True
session = InteractiveSession(config=config)

graph_sparsity = 0.01  # can find from 0.01 ~ 0.1, the graph_sparsity is bigger, the learned graph is more sparse
dropout_conf = 0.1  # can find from 0, 0.1, 0.2, 0.3
kernel_size_conf = 3  # can find from 2, 3, 4
residual_channels = 8  # can find from 4, 8, 16
dilation_channels = residual_channels
skip_channels = residual_channels * 4   # can find from * 2, 4, 8
end_channels = skip_channels * 1  # can find from * 2, 4


class nconv(tf.keras.Model):
    def __init__(self):
        super(nconv, self).__init__()

    def call(self, x, A):
        x = tf.einsum('nvlc,vw->nwlc', x, A)
        return x


class linear(tf.keras.Model):
    def __init__(self, c_in, c_out):
        super(linear, self).__init__()
        self.mlp = keras.layers.Conv2D(filters=c_out, kernel_size=(1, 1), padding='same',
                                       strides=(1, 1), use_bias=True)

    def call(self, x):
        return self.mlp(x)


class gcn(tf.keras.Model):
    def __init__(self, c_in, c_out, support_len=1, order=1):
        super(gcn, self).__init__()
        self.nconv = nconv()
        c_in = (order*support_len+1)*c_in
        self.mlp = linear(c_in, c_out)
        self.dropout = keras.layers.Dropout(dropout_conf)
        self.order = order

    def call(self, x, support):
        out = [x]
        for a in support:
            x1 = self.nconv(x, a)
            out.append(x1)
            for k in range(2, self.order + 1):
                x2 = self.nconv(x1, a)
                out.append(x2)
                x1 = x2
        h = keras.layers.concatenate(out, axis=-1)
        h = self.mlp(h)
        h = self.dropout(h)
        return h


def create_graph_model(num_features, predict_timestamp, graph, window_width, use_timestamps, kernel_size=kernel_size_conf, blocks=2, layers=2):
    """Create a model without tuning hyperparameters.
       Returns: a keras graph-model."""

    out_dim = predict_timestamp
    start_conv = keras.layers.Conv2D(filters=residual_channels, kernel_size=(1, 1),
                                     padding='same', strides=(1, 1), use_bias=True)
    receptive_field = 1
    supports_len = 1
    filter_convs = []
    gate_convs = []
    residual_convs = []
    skip_convs = []
    bn = []
    gconv = []
    supports = [graph]
    for b in range(blocks):
        additional_scope = kernel_size - 1
        new_dilation = 1
        for i in range(layers):
            # dilated convolutions (TCN)
            filter_convs.append(keras.layers.Conv2D(filters=dilation_channels, kernel_size=(1, kernel_size),
                                     padding='valid', strides=(1, 1), use_bias=True, dilation_rate=new_dilation))

            gate_convs.append(keras.layers.Conv2D(filters=dilation_channels, kernel_size=(1, kernel_size),
                                     padding='valid', strides=(1, 1), use_bias=True, dilation_rate=new_dilation))

            # 1x1 convolution for residual connection
            residual_convs.append(keras.layers.Conv2D(filters=residual_channels, kernel_size=(1, 1),
                                    padding='valid', strides=(1, 1), use_bias=True))

            # 1x1 convolution for skip connection
            skip_convs.append(keras.layers.Conv2D(filters=skip_channels, kernel_size=(1, 1),
                                    padding='valid', strides=(1, 1), use_bias=True))
            bn.append(keras.layers.BatchNormalization(axis=-1))
            new_dilation *= 2
            receptive_field += additional_scope
            additional_scope *= 2
            gconv.append(gcn(dilation_channels, residual_channels, support_len=supports_len))

    end_conv_1 = keras.layers.Conv2D(filters=end_channels, kernel_size=(1, 1),
                                    padding='valid', strides=(1, 1), use_bias=True)

    end_conv_2 = keras.layers.Conv2D(filters=out_dim, kernel_size=(1, 1),
                            padding='valid', strides=(1, 1), use_bias=True)

    if use_timestamps:
        input_x_ = tf.keras.Input(shape=(window_width, num_features, 2))
    else:
        input_x_ = tf.keras.Input(shape=(window_width, num_features, 1))
    # input_x = tf.keras.layers.Reshape((window_width, num_features, 1))(input_x_)
    input_x = tf.keras.layers.Permute((2, 1, 3))(input_x_)
    if window_width < receptive_field:
        x = tf.keras.layers.ZeroPadding2D(padding=((0, 0), (receptive_field-window_width, 0)))(input_x)
    else:
        x = input_x
    x = start_conv(x)
    skip = 0
    for i in range(blocks * layers):
        residual = x
        # dilated convolution
        filter = filter_convs[i](residual)
        filter = tf.tanh(filter)
        gate = gate_convs[i](residual)
        gate = tf.sigmoid(gate)
        x = filter * gate

        # parametrized skip connection

        s = x
        s = skip_convs[i](s)
        try:
            skip = skip[:, :, -s.get_shape().as_list()[2]:, :]
        except:
            skip = 0
        skip = s + skip

        x = gconv[i](x, supports)

        x = x + residual[:, :, -x.get_shape().as_list()[2]:, :]

        x = bn[i](x)

    x = tf.nn.relu(skip)
    x = tf.reduce_mean(x, axis=-2, keepdims=True)
    x = tf.nn.relu(end_conv_1(x))
    x = end_conv_2(x)
    x = tf.keras.layers.Reshape((num_features, predict_timestamp))(x)
    x = tf.keras.layers.Permute((2, 1))(x)
    graph_model = tf.keras.Model(inputs=input_x_, outputs=x)
    graph_model.compile(loss = BrayCurtis(name='bray_curtis'),
                  optimizer = keras.optimizers.Adam(learning_rate=0.001),
                  metrics = [tf.keras.losses.MeanSquaredError(), tf.keras.losses.MeanAbsoluteError()])
    return graph_model


def find_best_graph(data, iterations, num_clusters, max_epochs, early_stopping, cluster_type, predict_timestamp, use_timestamps):
    print(f'\nFitting {num_clusters} cluster(s) of type {cluster_type}')
    best_performances = []
    metric_names = []
    if cluster_type == "graph":
        matrix_save = pd.DataFrame(data=data.graph_matrix,
                        index=data.all.columns,
                        columns=data.all.columns)
        matrix_save.to_csv(f'{graph_dir}/graph_all.csv')
    for c in range(num_clusters):
        c_id = c
        print(f'\nCluster: {c}')
        data.use_cluster(c, cluster_type)
        best_model = None
        best_performance = [100]
        if data.all.shape[1] == 0:
            print(f'Empty cluster, skipping')
            continue
        elif data.all.shape[1] == 1:
            c = sub(';.*$', '', data.all.columns[0])
            graph_matrix = np.ones(shape=(1, 1))
        elif data.all.shape[1] > 1:
            print(data.all.columns.values)
            standsacle = preprocessing.StandardScaler()
            standsacle.fit(data.all[:])
            graph_train_data = standsacle.transform(data.all[:], copy=True)
            try:
                cov_init = GraphicalLasso(alpha=graph_sparsity, mode='cd', max_iter=500, assume_centered=True).fit(
                    graph_train_data)
            except Exception as e:
                print('EmpiricalCovariance precision_')
                cov_init = EmpiricalCovariance(store_precision=True, assume_centered=True).fit(graph_train_data)

            adj_mx = cov_init.precision_
            d_add = np.diag(np.diag(adj_mx)) * 2
            adj_mx = adj_mx + d_add
            d = np.array(adj_mx.sum(1))
            d_inv = np.power(d, -0.5).flatten()
            d_inv[np.isinf(d_inv)] = 0.
            d_mat_inv = np.diag(d_inv)
            graph_matrix = d_mat_inv.dot(adj_mx).dot(d_mat_inv)
            if cluster_type == "graph":
                matrix_save = pd.DataFrame(data=graph_matrix,
                                           index=data.all.columns,
                                           columns=data.all.columns)
                matrix_save.to_csv(f'{graph_dir}/graph_cluster_{c}.csv')
            print(f'graph matrix: {graph_matrix}')

        for i in range(iterations):
            print(f'Cluster: {c}, Iteration: {i}')
            graph_model = create_graph_model(data.num_features, predict_timestamp, graph=graph_matrix,
                                             window_width=data.window_width, use_timestamps=use_timestamps)
            graph_model.fit(data.train_batched,
                           epochs=max_epochs,
                           validation_data=data.val_batched,  # if no val data, it should be test_batched
                           callbacks=[early_stopping],
                           verbose=0)
            test_performance = graph_model.evaluate(data.test_batched)
            if i == 0:
                best_model = graph_model
                best_performance = test_performance
            elif test_performance[0] < best_performance[0]:
                best_model = graph_model
                best_performance = test_performance

        best_performances.append(best_performance)
        best_model.save_weights(f'{results_dir}/graph_{cluster_type}_weights/cluster_{c}')

        prediction, actual_prediction, R_square = make_prediction(data, best_model, use_timestamps)
        R_square.to_csv(f'{R_square_dir}/graph_{cluster_type}_cluster_{c}_R_square.csv')
        
        # reverse transform and overwrite.
        # Better to implement it in data_handler,
        # but this does the job
        if cluster_type == "abund":
            prediction = rev_transform(
                DF = prediction,
                mean = data.transform_mean[data.clusters_abund == c_id],
                std = data.transform_std[data.clusters_abund == c_id],
                min = data.transform_min[data.clusters_abund == c_id],
                max = data.transform_max[data.clusters_abund == c_id],
                transform = data.transform_type
            )
        elif cluster_type == "graph":
            prediction = rev_transform(
                DF=prediction,
                mean=data.transform_mean[data.clusters_graph == c_id],
                std=data.transform_std[data.clusters_graph == c_id],
                min=data.transform_min[data.clusters_graph == c_id],
                max=data.transform_max[data.clusters_graph == c_id],
                transform=data.transform_type
            )
        elif cluster_type == "func":
            prediction = rev_transform(
                DF = prediction,
                mean = data.transform_mean[data.clusters_func == c_id],
                std = data.transform_std[data.clusters_func == c_id],
                min = data.transform_min[data.clusters_func == c_id],
                max = data.transform_max[data.clusters_func == c_id],
                transform = data.transform_type
            )
        elif cluster_type == "idec":
            prediction = rev_transform(
                DF = prediction,
                mean = data.transform_mean[data.clusters_idec == c_id],
                std = data.transform_std[data.clusters_idec == c_id],
                min = data.transform_min[data.clusters_idec == c_id],
                max = data.transform_max[data.clusters_idec == c_id],
                transform = data.transform_type
            )
        
        if cluster_type == "abund":
            actual_prediction = rev_transform(
                DF = actual_prediction,
                mean = data.transform_mean[data.clusters_abund == c_id],
                std = data.transform_std[data.clusters_abund == c_id],
                min = data.transform_min[data.clusters_abund == c_id],
                max = data.transform_max[data.clusters_abund == c_id],
                transform = data.transform_type
            )
        elif cluster_type == "graph":
            actual_prediction = rev_transform(
                DF=actual_prediction,
                mean=data.transform_mean[data.clusters_graph == c_id],
                std=data.transform_std[data.clusters_graph == c_id],
                min=data.transform_min[data.clusters_graph == c_id],
                max=data.transform_max[data.clusters_graph == c_id],
                transform=data.transform_type
            )
        elif cluster_type == "func":
            actual_prediction = rev_transform(
                DF = actual_prediction,
                mean = data.transform_mean[data.clusters_func == c_id],
                std = data.transform_std[data.clusters_func == c_id],
                min = data.transform_min[data.clusters_func == c_id],
                max = data.transform_max[data.clusters_func == c_id],
                transform = data.transform_type
            )
        elif cluster_type == "idec":
            actual_prediction = rev_transform(
                DF = actual_prediction,
                mean = data.transform_mean[data.clusters_idec == c_id],
                std = data.transform_std[data.clusters_idec == c_id],
                min = data.transform_min[data.clusters_idec == c_id],
                max = data.transform_max[data.clusters_idec == c_id],
                transform = data.transform_type
            )
            
        dates = data.get_metadata(data.all, 'Date').dt.date
        dates_test = data.get_metadata(data.test, 'Date').dt.date
        # Date of the first sample in the test set and
        # date of the first predicted result which only uses input data from the test set.
        dates_pred_test_start = [dates_test.iloc[0], dates_test.iloc[data.window_width]]

        # Plot prediction results.
        plot_prediction(
            data,
            prediction = prediction,
            dates = dates,
            asvs = data.all.columns[:4],
            highlight_dates = dates_pred_test_start,
            save_filename = f'graph_{cluster_type}_cluster_{c}.png'
        )

        #write predicted values to CSV files
        if not path.exists(data_predicted_dir):
            mkdir(data_predicted_dir)
        prediction.to_csv(f'{data_predicted_dir}/graph_{cluster_type}_cluster_{c}_predicted.csv')
        actual_prediction.to_csv(f'{data_predicted_dir}/graph_{cluster_type}_cluster_{c}_actual_prediction.csv')
        data.all.to_csv(f'{data_predicted_dir}/graph_{cluster_type}_cluster_{c}_dataall.csv')
        data.all_nontrans.to_csv(f'{data_predicted_dir}/graph_{cluster_type}_cluster_{c}_dataall_nontrans.csv')

        metric_names = best_model.metrics_names

    metric_names[0] = 'bray-curtis'
    with open(f'{results_dir}/graph_{cluster_type}_performance.txt', 'w') as outfile:
        c = 0
        outfile.write(str(metric_names) + '\n')
        for performance in best_performances:
            outfile.write(str(c) + ': ' + str(performance) + '\n')
            c += 1


def create_tsne(data, num_clusters):
    data_embedded = train_tsne(data.data_raw)
    plot_tsne(data_embedded, data.clusters_func, num_clusters, 'function')
    plot_tsne(data_embedded, data.clusters_idec, num_clusters, 'IDEC')


def create_idec_model(input_dim, num_clusters):
    return IDEC(dims=[input_dim, 500, 500, 2000, 10], n_clusters=num_clusters)


def load_idec_model(input_dim, num_clusters):
    idec_model = create_idec_model(input_dim, num_clusters)
    idec_model.load_weights(results_dir + '/idec/IDEC_best.h5')
    return idec_model


def find_best_idec(data, iterations, num_clusters, tolerance, results_dir):
    x = data.data_raw
    y = data.clusters_func
    best_model = None
    best_performance = [-1]
    best_r_vals = None
    for i in range(iterations):
        print('Iteration:', i+1)
        idec_model = create_idec_model(data.num_samples, num_clusters)
        idec_model.model.summary()
        idec_model.pretrain(x, batch_size=32, epochs=200, optimizer='adam', save_dir = results_dir + '/idec')
        idec_model.compile(loss=['kld', 'mse'], loss_weights=[0.1, 1], optimizer='adam')
        idec_model.fit(x, y=y, batch_size=32, tol=tolerance, ae_weights=None, save_dir = results_dir + '/idec')
        clust_metrics = idec_model.metrics
        data.clusters_idec = idec_model.y_pred
        cluster_sizes, r_values, p_values = calc_cluster_correlations(data.data_raw, data.clusters_idec, num_clusters)
        means, stds, p_means, weighted_avg = calc_correlation_aggregates(cluster_sizes, r_values, p_values)
        test_performance = (clust_metrics, cluster_sizes, means, stds, p_means, weighted_avg)

        if test_performance[-1] > best_performance[-1]:
            best_model = idec_model
            best_performance = test_performance
            best_r_vals = r_values

    best_model.model.save_weights(results_dir + '/idec/IDEC_best.h5')
    data.clusters_idec = best_model.y_pred
    create_tsne(data, num_clusters)
    create_boxplot(best_r_vals, 'abs(r-values)', 'idec')

    # Calculate function cluster correlation for comparison.
    cluster_sizes, r_values, p_values = calc_cluster_correlations(data.data_raw, y, num_clusters)
    means, stds, p_means, weighted_avg = calc_correlation_aggregates(cluster_sizes, r_values, p_values)
    create_boxplot(r_values, 'abs(r-values)', 'func')

    with open(results_dir + '/clusters.txt', 'w') as outfile:
        outfile.write('function clustering:\n')
        outfile.write('Cluster sizes: ' + str(cluster_sizes) + '\n')
        outfile.write('r (mean): ' + str(np.around(np.array(means), 5)) + '\n')
        outfile.write('r (std):  ' + str(np.around(np.array(stds), 5)) + '\n')
        outfile.write('p (mean): ' + str(np.around(np.array(p_means), 5)) + '\n')
        outfile.write('r (weighted avg of means): ' + str(np.around(np.array(weighted_avg), 5)) + '\n\n')

        outfile.write('IDEC clustering:\n')
        outfile.write('Cluster sizes: ' + str(best_performance[1]) + '\n')
        outfile.write('r (mean): ' + str(np.around(np.array(best_performance[2]), 5)) + '\n')
        outfile.write('r (std):  ' + str(np.around(np.array(best_performance[3]), 5)) + '\n')
        outfile.write('p (mean): ' + str(np.around(np.array(best_performance[4]), 5)) + '\n')
        outfile.write('r (weighted avg of means): ' + str(np.around(np.array(best_performance[5]), 5)) + '\n\n')
        outfile.write('IDEC: ' + str(best_performance[0]) + '\n')


def make_prediction(data, lstm_model, use_timestamps):
    actual_prediction = data.all[-data.window_width:].to_numpy().reshape([1, data.window_width, -1, 1])
    if use_timestamps:
        _, T_, N_, _ = actual_prediction.shape
        data_timestamps = data.data_timestamps[-data.window_width:].reshape([1, data.window_width, 1, 1])
        data_timestamps = np.repeat(data_timestamps, N_, 2)
        actual_prediction = np.concatenate((actual_prediction, data_timestamps), axis=3)
        
    actual_prediction = lstm_model.predict(actual_prediction)
    actual_prediction = actual_prediction.reshape([data.predict_timestamp, -1])
    
    prediction = lstm_model.predict(data.all_batched)
    prediction = prediction[:, 0]
    index_pred = data.all.index[data.window_width:]

    val_prediction = lstm_model.predict(data.val_batched)
    test_prediction = lstm_model.predict(data.test_batched)
    y_pred = np.concatenate([val_prediction, test_prediction], axis=0)
    y_pred = np.reshape(y_pred, [y_pred.shape[0] * y_pred.shape[1], y_pred.shape[2]])

    current_i = 0
    for ___, test_i in data.test_batched:
        if current_i == 0:
            test_true = test_i
            current_i += 1
        else:
            test_true = np.concatenate([test_true, test_i], axis=0)
    current_i = 0
    for ___, val_i in data.val_batched:
        if current_i == 0:
            val_true = val_i
            current_i += 1
        else:
            val_true = np.concatenate([val_true, val_i], axis=0)

    y_true = np.concatenate([val_true, test_true], axis=0)
    y_true = np.reshape(y_true, [y_true.shape[0]*y_true.shape[1], y_true.shape[2]])
    model = LinearRegression().fit(y_pred, y_true)
    y_pred = model.predict(y_pred)
    r2 = r2_score(y_true, y_pred, multioutput='raw_values')
    r2 = np.reshape(r2, [1, r2.shape[0]])

    predictionpd = pd.DataFrame(data=prediction, index=index_pred, columns=data.all.columns)
    R_square = pd.DataFrame(data=r2, index=['R_square 1:1'], columns=data.all.columns)
    
    #needs to be reverse transformed for real values
    return predictionpd, pd.DataFrame(data = actual_prediction, columns = data.all.columns), R_square

def create_lstm_model(num_features, predict_timestamp=1):
    """Create a model without tuning hyperparameters.
       Returns: a keras LSTM-model."""
    lstm_model = keras.Sequential()
    # Shape [batch, time, features] => [batch, lstm_units]
    lstm_model.add(keras.layers.LSTM(units=120))
    # Dropout layer.
    lstm_model.add(keras.layers.Dropout(rate=0.20))
    # Shape [batch, lstm_units] => [batch, lstm_units]
    lstm_model.add(keras.layers.Dense(units=120, activation='tanh'))
    # Shape [batch, lstm_units] => [batch, predict_timestamp, features]
    lstm_model.add(keras.layers.Dense(units=predict_timestamp * num_features))
    lstm_model.add(keras.layers.Reshape([predict_timestamp, num_features]))
    lstm_model.add(keras.layers.ReLU())


    lstm_model.compile(loss = BrayCurtis(name='bray_curtis'),
                  optimizer = keras.optimizers.Adam(learning_rate=0.001),
                  metrics = [tf.keras.losses.MeanSquaredError(), tf.keras.losses.MeanAbsoluteError()])
    return lstm_model


def load_lstm_model(num_features, cluster, cluster_type):
    lstm_model = create_lstm_model(num_features)
    lstm_model.load_weights(f'{results_dir}/lstm_{cluster_type}_weights/cluster_{cluster}')
    return lstm_model


def find_best_lstm(data, iterations, num_clusters, max_epochs, early_stopping, cluster_type, predict_timestamp=1):
    print(f'\nFitting {num_clusters} cluster(s) of type {cluster_type}')
    best_performances = []
    metric_names = []
    for c in range(num_clusters):
        c_id = c
        print(f'\nCluster: {c}')
        data.use_cluster(c, cluster_type)
        best_model = None
        best_performance = [100]
        if data.all.shape[1] == 0:
            print(f'Empty cluster, skipping')
            continue
        elif data.all.shape[1] == 1:
            c = sub(';.*$', '', data.all.columns[0])
        elif data.all.shape[1] > 1:
            print(data.all.columns.values)

        for i in range(iterations):
            print(f'Cluster: {c}, Iteration: {i}')
            lstm_model = create_lstm_model(data.num_features, predict_timestamp)
            lstm_model.fit(data.train_batched,
                           epochs=max_epochs,
                           validation_data=data.val_batched,  # if no val data, it should be test_batched
                           callbacks=[early_stopping],
                           verbose=0)
            test_performance = lstm_model.evaluate(data.test_batched)
            if test_performance[0] < best_performance[0]:
                best_model = lstm_model
                best_performance = test_performance

        best_performances.append(best_performance)
        best_model.save_weights(f'{results_dir}/lstm_{cluster_type}_weights/cluster_{c}')

        prediction, actual_prediction, R_square = make_prediction(data, best_model)
        R_square.to_csv(f'{R_square_dir}/graph_{cluster_type}_cluster_{c}_R_square.csv')
        
        # reverse transform and overwrite.
        # Better to implement it in data_handler,
        # but this does the job
        if cluster_type == "abund":
            prediction = rev_transform(
                DF = prediction,
                mean = data.transform_mean[data.clusters_abund == c_id],
                std = data.transform_std[data.clusters_abund == c_id],
                min = data.transform_min[data.clusters_abund == c_id],
                max = data.transform_max[data.clusters_abund == c_id],
                transform = data.transform_type
            )
        elif cluster_type == "func":
            prediction = rev_transform(
                DF = prediction,
                mean = data.transform_mean[data.clusters_func == c_id],
                std = data.transform_std[data.clusters_func == c_id],
                min = data.transform_min[data.clusters_func == c_id],
                max = data.transform_max[data.clusters_func == c_id],
                transform = data.transform_type
            )
        elif cluster_type == "idec":
            prediction = rev_transform(
                DF = prediction,
                mean = data.transform_mean[data.clusters_idec == c_id],
                std = data.transform_std[data.clusters_idec == c_id],
                min = data.transform_min[data.clusters_idec == c_id],
                max = data.transform_max[data.clusters_idec == c_id],
                transform = data.transform_type
            )

        if cluster_type == "abund":
            actual_prediction = rev_transform(
                DF = actual_prediction,
                mean = data.transform_mean[data.clusters_abund == c_id],
                std = data.transform_std[data.clusters_abund == c_id],
                min = data.transform_min[data.clusters_abund == c_id],
                max = data.transform_max[data.clusters_abund == c_id],
                transform = data.transform_type
            )
        elif cluster_type == "graph":
            actual_prediction = rev_transform(
                DF=actual_prediction,
                mean=data.transform_mean[data.clusters_graph == c_id],
                std=data.transform_std[data.clusters_graph == c_id],
                min=data.transform_min[data.clusters_graph == c_id],
                max=data.transform_max[data.clusters_graph == c_id],
                transform=data.transform_type
            )
        elif cluster_type == "func":
            actual_prediction = rev_transform(
                DF = actual_prediction,
                mean = data.transform_mean[data.clusters_func == c_id],
                std = data.transform_std[data.clusters_func == c_id],
                min = data.transform_min[data.clusters_func == c_id],
                max = data.transform_max[data.clusters_func == c_id],
                transform = data.transform_type
            )
        elif cluster_type == "idec":
            actual_prediction = rev_transform(
                DF = actual_prediction,
                mean = data.transform_mean[data.clusters_idec == c_id],
                std = data.transform_std[data.clusters_idec == c_id],
                min = data.transform_min[data.clusters_idec == c_id],
                max = data.transform_max[data.clusters_idec == c_id],
                transform = data.transform_type
            )

        dates = data.get_metadata(data.all, 'Date').dt.date
        dates_test = data.get_metadata(data.test, 'Date').dt.date
        # Date of the first sample in the test set and
        # date of the first predicted result which only uses input data from the test set.
        dates_pred_test_start = [dates_test.iloc[0], dates_test.iloc[data.window_width]]

        # Plot prediction results.
        plot_prediction(
            data,
            prediction = prediction,
            dates = dates,
            asvs = data.all.columns[:4],
            highlight_dates = dates_pred_test_start,
            save_filename = f'lstm_{cluster_type}_cluster_{c}.png'
        )

        #write predicted values to CSV files
        if not path.exists(data_predicted_dir):
            mkdir(data_predicted_dir)
        prediction.to_csv(f'{data_predicted_dir}/lstm_{cluster_type}_cluster_{c}_predicted.csv')
        actual_prediction.to_csv(f'{data_predicted_dir}/graph_{cluster_type}_cluster_{c}_actual_prediction.csv')
        data.all.to_csv(f'{data_predicted_dir}/lstm_{cluster_type}_cluster_{c}_dataall.csv')
        data.all_nontrans.to_csv(f'{data_predicted_dir}/lstm_{cluster_type}_cluster_{c}_dataall_nontrans.csv')

        metric_names = best_model.metrics_names

    metric_names[0] = 'bray-curtis'
    with open(f'{results_dir}/lstm_{cluster_type}_performance.txt', 'w') as outfile:
        c = 0
        outfile.write(str(metric_names) + '\n')
        for performance in best_performances:
            outfile.write(str(c) + ': ' + str(performance) + '\n')
            c += 1

if __name__ == '__main__':
    import json
    with open('config.json', 'r') as config_file:
        config = json.load(config_file)

    results_dir = config['results_dir']
    graph_dir = f'{results_dir}/graph_matrix'
    data_predicted_dir = f'{results_dir}/data_predicted'
    data_splits_dir = f'{results_dir}/data_splits'
    R_square_dir = f'{results_dir}/R_square'
    if not path.exists(R_square_dir):
        mkdir(R_square_dir)

    if not path.exists(results_dir):
        mkdir(results_dir)
    if not path.exists(data_predicted_dir):
        mkdir(data_predicted_dir)
    if not path.exists(data_splits_dir):
        mkdir(data_splits_dir)
    if not path.exists(graph_dir):
        mkdir(graph_dir)

    # Callback used in the training to stop early when the model no longer improves.
    early_stopping = keras.callbacks.EarlyStopping(
        monitor = 'val_loss',
        patience = 5,
        mode = 'min',
        restore_best_weights=True
    )

    # Open dataset with DataHandler.
    data = DataHandler(
        config,
        num_features = config['num_features'],
        window_width = config['window_size'],
        window_batch_size = 10,
        splits = config['splits'],
        predict_timestamp=config['predict_timestamp'],
        num_per_group=config['num_per_group']
    )

    #write sample names and dates for each 3-way split data set
    data.get_metadata(data.train, 'Date').dt.date.to_csv(f'{data_splits_dir}/dates_train.csv')
    data.get_metadata(data.val, 'Date').dt.date.to_csv(f'{data_splits_dir}/dates_val.csv')
    data.get_metadata(data.test, 'Date').dt.date.to_csv(f'{data_splits_dir}/dates_test.csv')
    data.get_metadata(data.all, 'Date').dt.date.to_csv(f'{data_splits_dir}/dates_all.csv')

    if config['cluster_idec'] == True:
        # Find best IDEC model.
        find_best_idec(data, config['iterations'], config['num_clusters_idec'], config['tolerance_idec'], results_dir = results_dir)

        # Load the best existing IDEC model.
        idec_model = load_idec_model(data.num_samples, config['num_clusters_idec'])
        data.clusters_idec = idec_model.predict_clusters(data.data_raw)
        create_tsne(data, config['num_clusters_idec'])

        # Find the best LSTM models.
        find_best_graph(
            data,
            config['iterations'],
            config['num_clusters_idec'],
            config['max_epochs_lstm'],
            early_stopping,
            'idec',
            predict_timestamp=config['predict_timestamp'],
            use_timestamps=config['use_timestamps']
        )
    
    if config['cluster_func'] == True:
        find_best_graph(
            data,
            config['iterations'],
            len(config['functions']),
            config['max_epochs_lstm'],
            early_stopping,
            'func',
            predict_timestamp=config['predict_timestamp'],
            use_timestamps=config['use_timestamps']
        )
    
    if config['cluster_abund'] == True:
        find_best_graph(
            data,
            config['iterations'],
            data.clusters_abund_size,
            config['max_epochs_lstm'],
            early_stopping,
            'abund',
            predict_timestamp=config['predict_timestamp'],
            use_timestamps=config['use_timestamps']
        )

    if config['cluster_graph'] == True:
        data.clusters = None
        find_best_graph(
            data,
            config['iterations'],
            data.clusters_graph_size,
            config['max_epochs_lstm'],
            early_stopping,
            'graph',
            predict_timestamp=config['predict_timestamp'],
            use_timestamps=config['use_timestamps']
        )
    
  # clusters_abund_size   [N / num_features]

    # # Load existing LSTM models. As they are trained for individual clusters, the type and 
    # # index of the cluster must be specified.
    # cluster_type = 'func'
    # cluster_index = 1
    # data.use_cluster(cluster_index, cluster_type)
    # lstm = load_lstm_model(data.num_features, cluster_index, cluster_type)

    # # Make a prediction using a model.
    # prediction = make_prediction(data, lstm)
    # print(lstm.evaluate(data.test_batched))

    # # Preparation for plotting prediction results.
    # dates = data.get_metadata(data.all, 'Date').dt.date
    # dates_test = data.get_metadata(data.test, 'Date').dt.date
    # # Date of the first sample in the test set and 
    # # date of the first predicted result which only uses input data from the test set.
    # dates_pred_test_start = [dates_test.iloc[0], dates_test.iloc[data.window_width]]

    # # # Plot prediction results.
    # plot_prediction(data, prediction, dates, data.all.columns[:4], dates_pred_test_start)
