import numpy as np
import pandas as pd
import tensorflow as tf
from load_data import load_data, smooth, transform

class DataHandler:
    def __init__(
        self,
        config,
        num_features,
        window_width,
        window_batch_size=10,
        window_shift=1,
        splits=[0.70, 0.15, 0.15],
        predict_timestamp=3
    ):
        """Create a DataHandler which is able to load and manipulate data in different ways."""
        #self.is_normalized = False
        self.transform_mean = None
        self.transform_std = None
        self.transform_min = None
        self.transform_max = None
        self.window_width = window_width
        self.window_shift = window_shift
        self.window_batch_size = window_batch_size  # can find a best from 8 10 16
        self.max_num_features = num_features
        self.predict_timestamp = predict_timestamp
        self._clusters = None
        self.clusters_func = None
        self.clusters_idec = None
        
        self._load_data(config)
        self.use_splits(splits)
        self.clusters_abund, self.clusters_abund_size = self._make_abundance_clusters()
    
    @property
    def train(self):
        if self._clusters is None:
            return self._all.iloc[:self._train_val_index, :self.max_num_features]
        else:
            return self._all.iloc[:self._train_val_index, self._clusters]
    
    @property
    def val(self):
        if self._train_val_index == self._val_test_index:
            return self.test  # if no val data, it should be test
        elif self._clusters is None:
            return self._all.iloc[self._train_val_index:self._val_test_index, :self.max_num_features]
        else:
            return self._all.iloc[self._train_val_index:self._val_test_index, self._clusters]
    
    @property
    def test(self):
        if self._clusters is None:
            return self._all.iloc[self._val_test_index:, :self.max_num_features]
        else:
            return self._all.iloc[self._val_test_index:, self._clusters]
    
    @property
    def all(self):
        if self._clusters is None:
            return self._all.iloc[:, :self.max_num_features]
        else:
            return self._all.iloc[:, self._clusters]

    @property
    def all_nontrans(self):
        if self._clusters is None:
            return self._all_nontrans.iloc[:, :self.max_num_features]
        else:
            return self._all_nontrans.iloc[:, self._clusters]

    @property
    def train_batched(self):
        """Batches of training data."""
        return self._make_batched_dataset(self.train, endindex=True)

    @property
    def val_batched(self):
        """Batches of validation data."""
        return self._make_batched_dataset(self.val, endindex=True)

    @property
    def test_batched(self):
        """Batches of test data."""
        return self._make_batched_dataset(self.test, endindex=True)

    @property
    def all_batched(self):
        """Batches of all the data."""
        return self._make_batched_dataset(self.all, endindex=False)

    @property
    def num_features(self):
        """Number of features in each sample."""
        if self._clusters is not None:
            return np.sum(self._clusters)
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
        clust = np.zeros(self.clusters_func.shape, dtype=int)
        if self.max_num_features is None:
            return clust
        i = 0
        c = 0
        while i < (clust.size - self.max_num_features):
            for _ in range(self.max_num_features):
                clust[i] = c
                i += 1
            c += 1
        while i < clust.size:
            clust[i] = c
            i += 1
        c += 1
        return clust, c

    def use_cluster(self, number, cluster_type='abund'):
        """Cluster type is which type of cluster to use:
             abund: means that the x most abundant are in the first cluster, 
                    the next x most abundant are in second cluster and so forth.
             func:  means that the functions are used to cluster the taxa i.e. 
                    having a positive value in the same function means being in the same cluster.
             idec:  means using the clusters found with IDEC. An IDEC model has to be trained first to use this."""
        if number is None:
            self._clusters = None
        else:
            if cluster_type == 'func':
                self._clusters = self.clusters_func == number
                self._only_mark_first_max_num_features()
            elif cluster_type == 'idec':
                self._clusters = self.clusters_idec == number
                self._only_mark_first_max_num_features()
            elif cluster_type == 'abund':
                self._clusters = self.clusters_abund == number
                self._only_mark_first_max_num_features()
            else:
                self._clusters = None
                raise Exception('Unknown cluster type.')

    def _only_mark_first_max_num_features(self):
        """Only use the x most abundant taxa in a given cluster."""
        if self.max_num_features is None:
            return
        count = 0
        for i in range(self._clusters.size):
            if self._clusters[i]:
                count += 1
                if count > self.max_num_features:
                    self._clusters[i] = False

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
        data_raw, meta, func_tax, clusters, functions = load_data(config)

        data_smooth = smooth(data_raw, factor = config['smoothing_factor'])
        data_transformed, mean, std, min, max = transform(data_smooth, transform = config['transform'])

        self._all = pd.DataFrame(data=np.transpose(data_transformed), 
                            index=meta.index, 
                            columns=func_tax[:,0])
        self._all_nontrans = pd.DataFrame(data=np.transpose(data_smooth), 
                            index=meta.index, 
                            columns=func_tax[:,0])

        self.data_raw = data_raw # N * T
        self.func_tax = func_tax
        self.meta = meta
        self.transform_mean = mean
        self.transform_std = std
        self.transform_min = min
        self.transform_max = max
        self.clusters_func = clusters
        self.functions = functions
        self.num_samples = data_raw.shape[-1] #  T_
