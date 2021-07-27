import numpy as np
import pandas as pd
from scipy.signal import lfilter
import os

def filter_sparse_samples(data, percentage):
    """Removes ASV/species abundance time series consisting of more zeroes than the specified percentage."""
    num_of_samples = data.shape[0]
    zeroes_count = (data == 0.0).sum(axis=0)
    to_remove = zeroes_count > num_of_samples * percentage
    data = data.drop(columns=to_remove[to_remove == True].index)
    return data


def assign_clusters(func_tax, functions):
    """Assign labels/clusters according to functions.
       Even if an ASV/species is positive in more than one function, it will only be assigned 
       one cluster."""
    # Find positive functions.
    func_start_column = func_tax.shape[1] - len(functions)
    positives = func_tax[:,func_start_column:] == 'pos'

    # Check if any ASV/species has more than one positive function.
    if np.any(np.sum(positives, axis=1) > 1):
        print('An ASV/species is positive in more than one function!')

    # Assign clusters.
    clusters = np.full(func_tax.shape[0], len(functions), dtype=int)
    for i in range(len(functions)):
        clusters[positives[:,i]] = i

    if np.any(clusters == len(functions)):
        functions = functions.tolist()
        functions.append('None')

    print('Cluster labels:     ', functions)
    print('Cluster sizes:      ', np.unique(clusters, axis=0, return_counts=True)[1])
    print('Total taxa: ', func_tax.shape[0])

    return clusters

def do_preprocess(config):
    """Some preprocessing steps which are only necessary to run when the data files change.
        
       Parameters:
         config : Dictionary of values from config.json."""

    # create output folders
    os.makedirs(config['figures_dir'], exist_ok=True)
    os.makedirs(config['results_dir'], exist_ok=True)
    preprocessed_dir = config['data_dir'] + '/preprocessed/'
    os.makedirs(preprocessed_dir, exist_ok=True)

    # read abundance data and transpose
    abund = pd.read_csv(config['data_dir'] + config['abund_filename'])
    abund = abund.transpose(copy=False)

    # extract taxonomy, fill NA's with '', and write out
    taxonomy = abund.loc[config['tax_cols']]
    taxonomy.fillna('', inplace=True)
    taxonomy.to_csv(preprocessed_dir + 'taxonomy.csv', header=False)

    # remove taxonomy from abundance data
    abund.drop(config['tax_cols'], axis=0, inplace=True)

    # use the first-mentioned tax level in config->tax_cols as ID's for abund
    abund.columns = taxonomy.loc[config['tax_cols'][0]]
    abund = abund.astype('float32', copy=False)

    # read metadata, filter duplicates, and remove any samples not present in abund, sort
    meta = pd.read_csv(config['data_dir'] + config['metadata_filename'], index_col=0, parse_dates=['Date'])
    meta = meta[~meta.index.duplicated(keep='first')]
    meta = meta.filter(abund.index, axis=0)
    meta.sort_values(by='Date', inplace=True)
    
    if meta.shape[0] != abund.shape[0]:
        raise Exception('Some samples are missing metadata!')

    # Sort samples in abund chronologically according to metadata
    abund = abund.reindex(index=meta.index, copy=False)

    # Read genus-level functions
    func_data = pd.read_csv(config['data_dir'] + config['function_filename'], dtype=str)
    func_data.set_index(func_data.columns[0], inplace=True)
    
    # Only use taxa which we have functional information about.
    # taxonomy = taxonomy.loc[taxonomy['Genus'].isin(func_data.index)]

    # Merge taxonomy and functions
    taxonomy = taxonomy.transpose(copy=False)
    for func in config['functions']:
        taxonomy[func] = ['na'] * taxonomy.shape[0]

    for i in range(func_data.shape[0]):
        genus = func_data.iloc[i]

        for func in config['functions']:
            in_situ = genus.loc[func + ':In situ']
            other = genus.loc[func + ':Other']
            if in_situ == 'na':
                taxonomy.loc[taxonomy['Genus'] == genus.name, func] = other
            else:
                taxonomy.loc[taxonomy['Genus'] == genus.name, func] = in_situ
    
    # Write out transformed/preprocessed data
    abund.to_csv(preprocessed_dir + config['abund_filename'], float_format='%.3f')
    meta.to_csv(preprocessed_dir + config['metadata_filename'])
    taxonomy.to_csv(preprocessed_dir + 'taxonomy_wfunctions.csv', index=False, header=True)

def preprocess_data(config):
    """Pre-processes the data.
       
       Parameters:
         config : Dictionary of values from config.json."""
    
    # preprocess if forced or if it hasn't been done yet
    if config['force_preprocessing'] or \
       (not os.path.exists(pp_abund) or not os.path.exists(pp_tax_wfunctions)):
        do_preprocess(config)

    abund = pd.read_csv(pp_abund, index_col=0)
    func_tax = pd.read_csv(pp_tax_wfunctions, index_col=0, dtype=str)
    func_start_column = func_tax.columns.get_loc('Genus') + 1
    func_in_file = func_tax.columns[func_start_column:].to_numpy()

    # preprocess if the functions in the config.json file are not equal to the functions in the preprocessed file.
    if not np.array_equal(func_in_file, config['functions']):
        do_preprocess(config)
        func_tax = pd.read_csv(pp_tax_wfunctions, index_col=0, dtype=str)
        func_in_file = func_tax.columns[func_start_column:].to_numpy()

    # filter sparse samples with many zeros
    abund = filter_sparse_samples(abund, config['max_zeros_pct'])

    # Filter taxa with no positive value in any of the chosen functional groups
    if config['only_pos_func']:
        func_start_column = func_tax.columns.get_loc('Genus') + 1
        positives = func_tax.iloc[:,func_start_column:] == 'pos'
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

    return abund, func_tax, clusters, config['functions']

def normalize(data):
    """Normalized the data by division with the mean."""
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

    do_preprocess(config)
    preprocess_data(config)
