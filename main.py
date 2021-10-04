import pandas as pd
import tensorflow as tf
import numpy as np
from tensorflow import keras

from bray_curtis import BrayCurtis
from data_handler import DataHandler
from idec.IDEC import IDEC
from plotting import plot_four_results, train_tsne, plot_tsne, create_boxplot
from correlation import calc_cluster_correlations, calc_correlation_aggregates


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
    index_pred = data.all.index[data.window_width:]
    return pd.DataFrame(data = prediction, index = index_pred, columns = data.all.columns)


def create_lstm_model(num_features):
    """Create a model without tuning hyperparameters.
       Returns: a keras LSTM-model."""
    lstm_model = keras.Sequential()
    # Shape [batch, time, features] => [batch, time, lstm_units]
    lstm_model.add(keras.layers.LSTM(units=120))
    # Dropout layer.
    lstm_model.add(keras.layers.Dropout(rate=0.20))
    # Shape [batch, time, lstm_units] => [batch, time, features]
    lstm_model.add(keras.layers.Dense(units=num_features))

    lstm_model.compile(loss = BrayCurtis(name='bray_curtis'), 
                  optimizer = keras.optimizers.Adam(learning_rate=0.001),
                  metrics = [tf.metrics.MeanSquaredError(), tf.metrics.MeanAbsoluteError()])
    return lstm_model


def load_lstm_model(num_features, cluster, cluster_type):
    lstm_model = create_lstm_model(num_features)
    lstm_model.load_weights(f'{results_dir}/lstm_{cluster_type}_weights/cluster_{cluster}')
    return lstm_model


def find_best_lstm(data, iterations, num_clusters, max_epochs, early_stopping, cluster_type):
    best_performances = []
    metric_names = []
    for c in range(num_clusters):
        data.use_cluster(c, cluster_type)
        best_model = None
        best_performance = [100]
        for i in range(iterations):
            print(f'Cluster: {c}, Iteration: {i}')
            lstm_model = create_lstm_model(data.num_features)
            lstm_model.fit(data.train_batched,
                           epochs=max_epochs,
                           validation_data=data.val_batched,
                           callbacks=[early_stopping],
                           verbose=0)
            test_performance = lstm_model.evaluate(data.test_batched)
            if test_performance[0] < best_performance[0]:
                best_model = lstm_model
                best_performance = test_performance

        best_performances.append(best_performance)
        best_model.save_weights(f'{results_dir}/lstm_{cluster_type}_weights/cluster_{c}')

        prediction = make_prediction(data, best_model)

        dates = data.get_metadata(data.all, 'Date').dt.date
        dates_test = data.get_metadata(data.test, 'Date').dt.date
        # Date of the first sample in the test set and 
        # date of the first predicted result which only uses input data from the test set.
        dates_pred_test_start = [dates_test.iloc[0], dates_test.iloc[data.window_width]]

        # Plot prediction results.
        plot_four_results(data.all, prediction, dates, data.all.columns[:4], dates_pred_test_start, f'lstm_{cluster_type}_cluster_{c}.png')

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

    # Number of taxa to use at the time for the prediction.
    num_features = config['num_time_series_used']

    # Number of clusters to use.
    num_clusters = config['idec_nclusters']

    # Number of models to train when running find_best_idec/lstm.
    iterations = config['iterations']

    # Define training, validation and test splits.
    splits = config['splits']

    # Open dataset with DataHandler.
    data = DataHandler(config, num_features, window_width=config['window_size'], window_batch_size=10, splits=splits)
    
    # Callback used in the training to stop early when the model no longer improves.
    early_stopping = keras.callbacks.EarlyStopping(monitor = 'val_loss',
                                                   patience = 5,
                                                   mode = 'min',
                                                   restore_best_weights=True)

    # Find best IDEC model.
    find_best_idec(data, iterations, num_clusters, config['tolerance_idec'])

    # Load the best existing IDEC model.
    idec_model = load_idec_model(data.num_samples, num_clusters)
    data.clusters_idec = idec_model.predict_clusters(data.data_raw)
    create_tsne(data, num_clusters)

    # Find the best LSTM models.
    find_best_lstm(data, iterations, num_clusters, config['max_epochs_lstm'], early_stopping, 'abund')
    find_best_lstm(data, iterations, num_clusters, config['max_epochs_lstm'], early_stopping, 'func')
    find_best_lstm(data, iterations, num_clusters, config['max_epochs_lstm'], early_stopping, 'idec')

    # Load existing LSTM models. As they are trained for individual clusters, the type and 
    # index of the cluster must be specified.
    cluster_type = 'func'
    cluster_index = 1
    data.use_cluster(cluster_index, cluster_type)
    lstm = load_lstm_model(data.num_features, cluster_index, cluster_type)

    # Make a prediction using a model.
    prediction = make_prediction(data, lstm)
    print(lstm.evaluate(data.test_batched))

    # Preparation for plotting prediction results.
    dates = data.get_metadata(data.all, 'Date').dt.date
    dates_test = data.get_metadata(data.test, 'Date').dt.date
    # Date of the first sample in the test set and 
    # date of the first predicted result which only uses input data from the test set.
    dates_pred_test_start = [dates_test.iloc[0], dates_test.iloc[data.window_width]]

    # # Plot prediction results.
    #plot_four_results(data.all, prediction, dates, data.all.columns[:4], dates_pred_test_start)
