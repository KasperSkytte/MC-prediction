#!/usr/bin/env python3
import pandas as pd
import tensorflow as tf
import numpy as np

from tensorflow import keras
from bray_curtis import BrayCurtis
from data_handler import DataHandler
from load_data import rev_transform
from idec.IDEC import IDEC
from plotting import plot_prediction, train_tsne, plot_tsne, create_boxplot
from correlation import calc_cluster_correlations, calc_correlation_aggregates
from re import sub
from os import mkdir, path

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


def find_best_idec(data, iterations, num_clusters, tolerance):
    x = data.data_raw
    y = data.clusters_func
    best_model = None
    best_performance = [-1]
    best_r_vals = None
    for i in range(iterations):
        print('Iteration:', i+1)
        idec_model = create_idec_model(data.num_samples, num_clusters)
        idec_model.model.summary()
        idec_model.pretrain(x, batch_size=32, epochs=200, optimizer='adam')
        idec_model.compile(loss=['kld', 'mse'], loss_weights=[0.1, 1], optimizer='adam')
        idec_model.fit(x, y=y, batch_size=32, tol=tolerance, ae_weights=None)
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

    with open(results_dir + '/idec_performance.txt', 'w') as outfile:
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


def make_prediction(data, lstm_model):
    prediction = lstm_model.predict(data.all_batched)
    prediction = prediction[:, 0]
    index_pred = data.all.index[data.window_width:]

    #needs to be reverse transformed for real values
    return pd.DataFrame(data = prediction, index = index_pred, columns = data.all.columns)

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
                           validation_data=data.test_batched,  # if no val data, it should be test_batched
                           callbacks=[early_stopping],
                           verbose=0)
            test_performance = lstm_model.evaluate(data.test_batched)
            if test_performance[0] < best_performance[0]:
                best_model = lstm_model
                best_performance = test_performance

        best_performances.append(best_performance)
        best_model.save_weights(f'{results_dir}/lstm_{cluster_type}_weights/cluster_{c}')

        prediction = make_prediction(data, best_model)
        # reverse transform and overwrite.
        # Better to implement it in data_handler,
        # but this does the job
        if cluster_type == "abund":
            prediction = rev_transform(
                DF = prediction,
                mean = data.transform_mean[c_id],
                std = data.transform_std[c_id],
                min = data.transform_min[c_id],
                max = data.transform_max[c_id],
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
    data_predicted_dir = f'{results_dir}/data_predicted'
    data_splits_dir = f'{results_dir}/data_splits'

    if not path.exists(results_dir):
        mkdir(results_dir)
    if not path.exists(data_predicted_dir):
        mkdir(data_predicted_dir)
    if not path.exists(data_splits_dir):
        mkdir(data_splits_dir)

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
        predict_timestamp = config['predict_timestamp']
    )

    #write sample names and dates for each 3-way split data set
    data.get_metadata(data.train, 'Date').dt.date.to_csv(f'{data_splits_dir}/dates_train.csv')
    data.get_metadata(data.val, 'Date').dt.date.to_csv(f'{data_splits_dir}/dates_val.csv')
    data.get_metadata(data.test, 'Date').dt.date.to_csv(f'{data_splits_dir}/dates_test.csv')
    data.get_metadata(data.all, 'Date').dt.date.to_csv(f'{data_splits_dir}/dates_all.csv')

    if config['cluster_idec'] == True:
        # Find best IDEC model.
        find_best_idec(data, config['iterations'], config['num_clusters_idec'], config['tolerance_idec'])

        # Load the best existing IDEC model.
        idec_model = load_idec_model(data.num_samples, config['num_clusters_idec'])
        data.clusters_idec = idec_model.predict_clusters(data.data_raw)
        create_tsne(data, config['num_clusters_idec'])

        # Find the best LSTM models.
        find_best_lstm(
            data,
            config['iterations'],
            config['num_clusters_idec'],
            config['max_epochs_lstm'],
            early_stopping,
            'idec',
            predict_timestamp=config['predict_timestamp']
        )
    
    if config['cluster_func'] == True:
        find_best_lstm(
            data,
            config['iterations'],
            len(config['functions']),
            config['max_epochs_lstm'],
            early_stopping,
            'func',
            predict_timestamp=config['predict_timestamp']
        )
    
    if config['cluster_abund'] == True:
        # new dataset for per-taxon training
        data_abund = DataHandler(
            config,
            num_features = 1,
            window_width = config['window_size'],
            window_batch_size = 10,
            splits = config['splits'],
            predict_timestamp = config['predict_timestamp']
        )
        # Find the best LSTM model on single ASV's
        find_best_lstm(
            data_abund,
            config['iterations'],
            data_abund.clusters_abund_size,
            config['max_epochs_lstm'],
            early_stopping,
            'abund',
            predict_timestamp=config['predict_timestamp']
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
