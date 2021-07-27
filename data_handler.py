import numpy as np
import pandas as pd
import tensorflow as tf
from preprocessing import preprocess_data, smooth, normalize

class DataHandler:
    def __init__(self, config, num_features, window_width, window_batch_size=10, window_shift=1, splits=[0.70, 0.15, 0.15]):
        """Create a DataHandler which is able to load and manipulate data in different ways."""
        self.is_normalized = False
        self._normalization_mean = None
        self.window_width = window_width
        self.window_shift = window_shift
        self.window_batch_size = window_batch_size
        self.max_num_features = num_features
        self._clusters = None
        self.clusters_func = None
        self.clusters_idec = None
        
        self._load_and_preprocess_data(config)
        self.use_splits(splits)
        self.clusters_abund = self._make_abundance_clusters()
    
    @property
    def train(self):
        if self._clusters is None:
            return self._all.iloc[:self._train_val_index, :self.max_num_features]
        else:
            return self._all.iloc[:self._train_val_index, self._clusters]
    
    @property
    def val(self):
        if self._train_val_index == self._val_test_index:
            return self.train
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
    def train_batched(self):
        """Batches of training data."""
        return self._make_batched_dataset(self.train)

    @property
    def val_batched(self):
        """Batches of validation data."""
        return self._make_batched_dataset(self.val)

    @property
    def test_batched(self):
        """Batches of test data."""
        return self._make_batched_dataset(self.test)

    @property
    def all_batched(self):
        """Batches of all the data."""
        return self._make_batched_dataset(self.all)

    @property
    def num_features(self):
        """Number of features in each sample."""
        if self._clusters is not None:
            return np.sum(self._clusters)
        elif self.max_num_features is None:
            return self._all.shape[1]
        else:
            return np.min((self._all.shape[1], self.max_num_features))

    def _make_batched_dataset(self, dataset):
        """Create a windowed and batched dataset."""
        dataset = dataset.to_numpy()
        return tf.keras.preprocessing.sequence.TimeseriesGenerator(
            data=dataset,
            targets=dataset,
            length=self.window_width,
            stride=self.window_shift,
            shuffle=False,
            batch_size=self.window_batch_size)

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
        return clust
    
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

    def _load_and_preprocess_data(self, config):
        pp_dir = config['data_dir'] + '/preprocessed/'
        meta = pp_dir + config['metadata_filename']

        data_raw, func_tax, clusters, functions = preprocess_data(config)

        data_raw = smooth(data_raw)
        data_raw, mean = normalize(data_raw)

        meta = pd.read_csv(meta, index_col=0, parse_dates=['Date'])

        data = pd.DataFrame(data=np.transpose(data_raw), 
                            index=meta.index, 
                            columns=func_tax[:,0])

        self.data_raw = data_raw
        self._all = data
        self.func_tax = func_tax
        self.meta = meta
        self._normalization_mean = mean
        self.clusters_func = clusters
        self.functions = functions
        self.num_samples = data_raw.shape[-1]
