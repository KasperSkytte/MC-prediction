import numpy as np
import pandas as pd
import tensorflow as tf
from load_data import load_data, smooth, transform
from sklearn.covariance import GraphicalLasso, EmpiricalCovariance
from sklearn import preprocessing

class DataHandler:
    def __init__(
        self,
        config,
        num_features,
        window_width,
        window_batch_size=10,
        window_shift=1,
        splits=[0.70, 0.15, 0.15],
        predict_timestamp=3,
        num_per_group=5
    ):
        """Create a DataHandler which is able to load and manipulate data in different ways."""
        #self.is_normalized = False
        self.transform_mean = None
        self.transform_std = None
        self.transform_min = None
        self.transform_max = None
        self.transform_type = None
        self.window_width = window_width
        self.window_shift = window_shift
        self.window_batch_size = window_batch_size  # can find a best from 8 10 16
        self.max_num_features = num_features
        self.num_per_group = num_per_group
        self.predict_timestamp = predict_timestamp
        self.clusters = None
        self.clusters_func = None
        self.clusters_idec = None
        
        self._load_data(config)
        self.use_splits(splits)
        self.clusters_abund, self.clusters_abund_size = self._make_abundance_clusters()
        self.clusters_graph, self.clusters_graph_size = self._make_graph_clusters()
        assert self.clusters_abund_size == self.clusters_graph_size
    
    @property
    def train(self):
        if self.clusters is None:
            return self._all.iloc[:self._train_val_index, :self.max_num_features]
        else:
            return self._all.iloc[:self._train_val_index, self.clusters]
    
    @property
    def val(self):
        if self._train_val_index == self._val_test_index:
            return self.test
        elif self.clusters is None:
            return self._all.iloc[self._train_val_index:self._val_test_index, :self.max_num_features]
        else:
            return self._all.iloc[self._train_val_index:self._val_test_index, self.clusters]
    
    @property
    def test(self):
        if self.clusters is None:
            return self._all.iloc[self._val_test_index:, :self.max_num_features]
        else:
            return self._all.iloc[self._val_test_index:, self.clusters]
    
    @property
    def all(self):
        if self.clusters is None:
            return self._all.iloc[:, :self.max_num_features]
        else:
            return self._all.iloc[:, self.clusters]

    @property
    def all_nontrans(self):
        if self.clusters is None:
            return self._all_nontrans.iloc[:, :self.max_num_features]
        else:
            return self._all_nontrans.iloc[:, self.clusters]

    @property
    def train_batched(self):
        """Batches of training data."""
        return self._make_batched_dataset(self._all.iloc[:self._train_val_index+self.predict_timestamp, self.clusters], endindex=True)

    @property
    def val_batched(self):
        """Batches of validation data."""
        return self._make_batched_dataset(self._all.iloc[self._train_val_index-self.predict_timestamp:self._val_test_index+self.predict_timestamp,
                       self.clusters], endindex=True)

    @property
    def test_batched(self):
        """Batches of test data."""
        return self._make_batched_dataset(self._all.iloc[self._val_test_index-self.predict_timestamp:, self.clusters], endindex=True)

    @property
    def all_batched(self):
        """Batches of all the data."""
        return self._make_batched_dataset(self.all, endindex=False)

    @property
    def num_features(self):
        """Number of features in each sample."""
        if self.clusters is not None:
            return np.sum(self.clusters)
        elif self.max_num_features is None:
            return self._all.shape[1]
        else:
            return np.min((self._all.shape[1], self.max_num_features))

    def _make_batched_dataset(self, dataset, endindex):
        """Create a windowed and batched dataset."""
        dataset = dataset.to_numpy()
        T_, N_ = dataset.shape
        target = dataset
        for i in range(self.predict_timestamp-1):
            target = np.concatenate((target, np.roll(dataset, -(i+1), axis=0)), axis=1)
        target = target.reshape([T_, self.predict_timestamp, N_])
        if endindex:
            return tf.keras.preprocessing.sequence.TimeseriesGenerator(
                data=dataset,
                targets=target,
                length=self.window_width,
                stride=1,
                shuffle=True,
                end_index=T_ - self.predict_timestamp,
                batch_size=self.window_batch_size # can find the best from 8 10 16
            )
        else:
            return tf.keras.preprocessing.sequence.TimeseriesGenerator(
                data=dataset,
                targets=target,
                length=self.window_width,
                stride=1,
                shuffle=False,
                batch_size=self.window_batch_size
            )

    def _make_abundance_clusters(self):
        clust = np.zeros(self.max_num_features, dtype=int)
        if self.num_per_group is None:
            return clust
        i = 0
        c = 0
        while i < (clust.size - self.num_per_group):
            for _ in range(self.num_per_group):
                clust[i] = c
                i += 1
            c += 1
        while i < clust.size:
            clust[i] = c
            i += 1
        c += 1
        return clust, c

    def _make_graph_clusters(self):
        clust = np.zeros(self.max_num_features, dtype=int)
        if self.num_per_group is None:
            return clust
        clust = clust - 1
        standsacle = preprocessing.StandardScaler()
        x = self._all.iloc[:, :]
        standsacle.fit(x[:])
        graph_train_data = standsacle.transform(x[:], copy=True)
        try:
            cov_init = GraphicalLasso(alpha=0.0001, mode='cd', max_iter=500, assume_centered=True).fit(graph_train_data)
        except Exception as e:
            print('EmpiricalCovariance precision_')
            cov_init = EmpiricalCovariance(store_precision=True, assume_centered=True).fit(graph_train_data)
        adj_mx = np.abs(cov_init.precision_)
        d = np.array(adj_mx.sum(1))
        d_add = np.diag(d)
        d = d * 2
        d_inv = np.power(d, -0.5).flatten()
        d_inv[np.isinf(d_inv)] = 0.
        d_mat_inv = np.diag(d_inv)
        self.graph_matrix = d_mat_inv.dot(adj_mx+d_add).dot(d_mat_inv)
        graph_matrix = self.graph_matrix.copy()

        i = 0
        c = 0
        while i < self.max_num_features:
            if clust[i] != -1:
                i += 1
                continue
            clust[i] = c
            temp = graph_matrix[i]
            top_number = temp.argsort()
            graph_matrix[:, i] = -1
            assert i in top_number[-self.num_per_group:]
            for j in range(self.num_per_group):
                if clust[top_number[-j-1]] == -1:
                    clust[top_number[-j-1]] = c
                    graph_matrix[:, top_number[-j-1]] = -1
            c += 1
            i += 1
        return clust, c

    def use_cluster(self, number, cluster_type='abund'):
        """Cluster type is which type of cluster to use:
             abund: means that the x most abundant are in the first cluster, 
                    the next x most abundant are in second cluster and so forth.
             func:  means that the functions are used to cluster the taxa i.e. 
                    having a positive value in the same function means being in the same cluster.
             idec:  means using the clusters found with IDEC. An IDEC model has to be trained first to use this."""
        if number is None:
            self.clusters = None
        else:
            if cluster_type == 'func':
                self.clusters = self.clusters_func == number
                self._only_mark_first_max_num_features()
            elif cluster_type == 'idec':
                self.clusters = self.clusters_idec == number
                self._only_mark_first_max_num_features()
            elif cluster_type == 'abund':
                self.clusters = self.clusters_abund == number
                self._only_mark_first_max_num_features()
            elif cluster_type == 'graph':
                self.clusters = self.clusters_graph == number
            else:
                self.clusters = None
                raise Exception('Unknown cluster type.')

    def _only_mark_first_max_num_features(self):
        """Only use the x most abundant taxa in a given cluster."""
        if self.num_per_group is None:
            return
        count = 0
        for i in range(self.clusters.size):
            if self.clusters[i]:
                count += 1
                if count > self.num_per_group:
                    self.clusters[i] = False

    def use_splits(self, splits):
        """Split the entire dataset into training, validation and test sets.
           train_size: the size of the training set in percent.
           val_size: the size of the validation set in percent."""
        train_size, val_size, test_size = splits
        val_test_cutoff = train_size + val_size
        assert train_size + val_size + test_size <= 1.0, 'The total size of the training, validation and test sets must not be greater than 1.0.'
        num_samples = self._all.shape[0]
        self._train_val_index = int(num_samples*train_size)
        self._val_test_index = int(num_samples*val_test_cutoff)

    def get_metadata(self, dataframe, attribute):
        """Return the specified attribute from the metadata for the samples in the dataframe."""
        return self.meta.loc[dataframe.index][attribute]

    def _load_data(self, config):
        data_raw, meta, func_tax, clusters_func, functions = load_data(config)
        data_raw = data_raw[:self.max_num_features]
        func_tax = func_tax[:self.max_num_features]
        clusters_func = clusters_func[:self.max_num_features]

        data_smooth = smooth(data_raw, factor = config['smoothing_factor'])
        data_transformed, mean, std, min, max, transform_type = transform(data_smooth, transform = config['transform'])

        self._all = pd.DataFrame(data=np.transpose(data_transformed), 
                            index=meta.index, 
                            columns=func_tax[:,0])
        self._all_nontrans = pd.DataFrame(data=np.transpose(data_smooth), 
                            index=meta.index, 
                            columns=func_tax[:,0])

        self.data_raw = data_raw # N * T
        self.data_transformed = data_transformed
        self.func_tax = func_tax
        self.meta = meta
        self.transform_mean = mean
        self.transform_std = std
        self.transform_min = min
        self.transform_max = max
        self.transform_type = transform_type
        self.clusters_func = clusters_func
        self.functions = functions
        self.num_samples = data_raw.shape[-1] #  T_
