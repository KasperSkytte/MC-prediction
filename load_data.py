import numpy as np
import pandas as pd
from scipy.signal import lfilter

def filter_sparse_samples(data, percentage, pseudo_zero):
    """Removes ASV/species abundance time series consisting of more zeroes than the specified percentage."""
    num_of_samples = data.shape[0]
    zeroes_count = (data < pseudo_zero).sum(axis=0)
    to_remove = zeroes_count > num_of_samples * percentage
    data = data.drop(columns=to_remove[to_remove == True].index)
    return data


def assign_clusters(func_tax, functions):
    """Assign labels/clusters according to functions.
       Even if an ASV/species is positive in more than one function, it will only be assigned
       one cluster."""
    # Find positive functions.
    func_start_column = func_tax.shape[1] - len(functions)
    positives = func_tax[:,func_start_column:] == 'POS'

    # Check if any ASV/species has more than one positive function.
    if np.any(np.sum(positives, axis=1) > 1):
        print('An ASV/species is positive in more than one function!')

    # Assign clusters.
    clusters = np.full(func_tax.shape[0], len(functions), dtype=int)
    for i in range(len(functions)):
        clusters[positives[:,i]] = i

    # if np.any(clusters == len(functions)):
    #     functions = functions.tolist()
    #     functions.append('None')

    print('Cluster labels:     ', functions)
    print('Cluster sizes:      ', np.unique(clusters, axis=0, return_counts=True)[1])
    print('Total taxa: ', func_tax.shape[0])

    return clusters

def load_data(config):
    """Load the data from the different files.

       Parameters:
         config : Dictionary of values from config.json."""

    # default file paths
    pp_dir = config['results_dir'] + '/data_reformatted/'
    pp_abund = pp_dir + 'abundances.csv'
    pp_tax_wfunctions = pp_dir + 'taxonomy_wfunctions.csv'

    # read abundance data
    abund = pd.read_csv(pp_abund, index_col=0)
    abund = abund.astype('float32', copy=False)

    # read metadata and sort chronologically
    meta = pd.read_csv(pp_dir + 'metadata.csv', index_col=0, parse_dates=['Date'])
    meta.sort_values(by='Date', inplace=True)

    # also sort samples in abund chronologically according to metadata
    abund = abund.reindex(index=meta.index, copy=False)

    # read taxonomy_wfunctions
    func_tax = pd.read_csv(pp_tax_wfunctions, index_col=0, dtype=str)
    func_start_column = func_tax.columns.get_loc('Genus') + 1
    func_in_file = func_tax.columns[func_start_column:].to_numpy()

    # filter sparse samples with many zeros
    abund = filter_sparse_samples(abund, config['max_zeros_pct'], config['pseudo_zero'])

    # Filter taxa with no positive value in any of the chosen functional groups
    if config['only_pos_func']:
        func_start_column = func_tax.columns.get_loc('Genus') + 1
        positives = func_tax.iloc[:,func_start_column:] == 'POS'
        func_tax = func_tax.loc[positives.any(axis=1)]

    # Make abund and taxonomy contain the same taxa (intersect).
    func_tax = func_tax.filter(abund.columns, axis=0)
    abund = abund.filter(func_tax.index, axis=1)

    # Convert to numpy
    func_tax.reset_index(inplace=True)
    func_tax = func_tax.to_numpy().astype(str)
    abund = abund.to_numpy().astype(float)
    abund = np.transpose(abund)

    clusters = assign_clusters(func_tax, functions = config['functions'])

    return abund, meta, func_tax, clusters, config['functions']

def normalize(data):
    """Normalize the data by division with the mean."""
    mean = data.mean(axis=1)
    result = data / mean.reshape(-1,1)
    return result, mean


def smooth(data, factor=8):
    """Smoothing factor is the number of data points to use for smoothing."""
    b = [1.0 / factor] * factor
    a = 1
    return lfilter(b, a, data)


if __name__ == "__main__":
    import json
    with open('config.json', 'r') as config_file:
        config = json.load(config_file)

    load_data(config)
