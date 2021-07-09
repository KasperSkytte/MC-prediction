import numpy as np
import pandas as pd
from scipy.signal import lfilter
import os


def create_directories(figures_dir, results_dir):
    """Creates the required output directories."""
    os.makedirs(figures_dir, exist_ok=True)
    os.makedirs(results_dir, exist_ok=True)


def get_mode(data_file):
    """Determines whether the granularity of the data is on ASV or species level."""
    data_file_ending = data_file.split('_')[-1].lower()
    if data_file_ending == 'asv.csv':
        return 'ASV'
    elif data_file_ending == 'species.csv':
        return 'Species'
    else:
        raise Exception('Abundance data filename must end in either "_asv.csv" or "_species.csv"')


def preprocess_abundance_data(data_file, meta_file, data_dir):
        """Load the dataset and the corresponding metadata with the specified filenames.
           The metadata is filtered so it only contains data about the samples in the dataset.
           The data is transposed, unnecessary information is dropped 
           and the samples are sorted by date."""
        mode = get_mode(data_file)
        if mode == 'ASV':
            levels = ['ASV','Species','Genus']
        elif mode == 'Species':
            levels = ['Species','Genus']
        
        data = pd.read_csv(data_dir + data_file)
        data = data.transpose(copy=False)
        taxonomy = data.loc[levels]
        taxonomy.fillna('', inplace=True)

        # Remove species and genus prefix.
        species_index = taxonomy.index.get_loc('Species')
        genus_index = taxonomy.index.get_loc('Genus')
        for i in range(taxonomy.shape[1]):
                taxonomy.iloc[species_index,i] = taxonomy.iloc[species_index,i].replace('s__', '', 1)
                taxonomy.iloc[genus_index,i] = taxonomy.iloc[genus_index,i].replace('g__', '', 1)

        data.drop(levels, axis=0, inplace=True)
        data.columns = taxonomy.loc[levels[0]]
        data = data.astype('float32', copy=False)

        meta = pd.read_csv(data_dir + meta_file, index_col=0, parse_dates=['Date'])
        meta = meta[~meta.index.duplicated(keep='first')]
        meta = meta.filter(data.index, axis=0)
        meta.sort_values(by='Date', inplace=True)
        
        if meta.shape[0] != data.shape[0]:
            raise Exception('Some samples are missing metadata!')

        # Sort samples in data chronologically.
        data = data.reindex(index=meta.index, copy=False)

        trans_data_path = data_dir + 'transformed_' + data_file
        trans_meta_path = data_dir + 'transformed_metadata_' + data_file
        trans_taxonomy_path = data_dir + 'transformed_taxonomy_' + data_file

        data.to_csv(trans_data_path, float_format='%.3f')
        meta.to_csv(trans_meta_path)
        taxonomy.to_csv(trans_taxonomy_path, header=False)


def fix_genus_names(dataframe):
    """Makes the genus names the same across different data sources."""
    for i in range(len(dataframe)):
        dataframe.iloc[i,0] = dataframe.iloc[i,0].replace(' ', '_')
        if dataframe.iloc[i,0].startswith('g__'):
            dataframe.iloc[i,0] = dataframe.iloc[i,0][3:]


def preprocess_functionality_data(func_file, data_dir):
    """Preprocesses the functionality file by fix the genus naming, removing unnecessary columns 
       and shortening functionality values."""
    func_info = pd.read_csv(data_dir + func_file, usecols=list(range(0,41)), sep=';', dtype=str)
    fix_genus_names(func_info)
    func_info.replace('Variable', 'var', inplace=True)
    func_info.replace('Negative', 'neg', inplace=True)
    func_info.replace('Positive', 'pos', inplace=True)
    func_info.replace('Not Assessed', 'na', inplace=True)
    func_info.rename({'Canonical name': 'Genus'}, axis=1, inplace=True)
    return func_info


def concat_functionality_data(func_data, data_dir):
    """Merges the two functionality files. Because of problems with getting filamentous 
       functionality information from MiDAS Field Guide, the program currently relies on another 
       source of functionality information from the file: 'MiDAS_knownfunctions.csv'. 
       If this workaround is no longer necessary in the future, remove the call to this function."""
    func_data_other = pd.read_csv(data_dir + 'MiDAS_knownfunctions.csv', dtype=str)
    fix_genus_names(func_data_other)
    return pd.concat([func_data_other, func_data], axis=0, join='inner', ignore_index=True).drop_duplicates('Genus')


def add_functionalities_to_taxonomy_file(taxonomy_file, data_dir, func_data, functionalities):
    """Adds functionality information to the taxonomy file."""
    taxonomy = pd.read_csv(data_dir + taxonomy_file, index_col=0, dtype=str)
    taxonomy = taxonomy.transpose(copy=False)
    func_data.set_index(func_data.columns[0], inplace=True)
    
    # Only use ASVs/species which we have functional information about.
    # taxonomy = taxonomy.loc[taxonomy['Genus'].isin(func_data.index)]

    for func in functionalities:
        taxonomy[func] = ['na'] * taxonomy.shape[0]

    for i in range(func_data.shape[0]):
        genus = func_data.iloc[i]

        for func in functionalities:
            in_situ = genus.loc[func + ':In situ']
            other = genus.loc[func + ':Other']
            if in_situ == 'na':
                taxonomy.loc[taxonomy['Genus'] == genus.name, func] = other
            else:
                taxonomy.loc[taxonomy['Genus'] == genus.name, func] = in_situ
    
    taxonomy.to_csv(data_dir + taxonomy_file.replace('transformed', 'functional'), index_label=taxonomy.columns.name)


def remove_time_series_with_zeroes(data, percentage):
    """Removes ASV/species abundance time series consisting of more zeroes than the specified percentage."""
    num_of_samples = data.shape[0]
    zeroes_count = (data == 0.0).sum(axis=0)
    to_remove = zeroes_count > num_of_samples * percentage
    data = data.drop(columns=to_remove[to_remove == True].index)
    return data


def assign_clusters(func_tax, functionalities):
    """Assign labels/clusters according to functionalities.
       Even if an ASV/species is positive in more than one functionality, it will only be assigned 
       one cluster."""
    # Find positive functionalities.
    func_start_column = func_tax.shape[1] - len(functionalities)
    positives = func_tax[:,func_start_column:] == 'pos'

    # Check if any ASV/species has more than one positive functionality.
    if np.any(np.sum(positives, axis=1) > 1):
        print('An ASV/species is positive in more than one functionality!')

    # Assign clusters.
    clusters = np.full(func_tax.shape[0], len(functionalities), dtype=int)
    for i in range(len(functionalities)):
        clusters[positives[:,i]] = i

    if np.any(clusters == len(functionalities)):
        functionalities = functionalities.tolist()
        functionalities.append('None')

    print('Cluster labels:     ', functionalities)
    print('Cluster sizes:      ', np.unique(clusters, axis=0, return_counts=True)[1])
    print('Total ASVs/species: ', func_tax.shape[0])

    return clusters


def load_and_check_data(data_file, config):
    """Loads the already preprocessed data files if they exists and match the options used in 
       'config.json'. If not they are created/updated."""
    trans_data_path = config['data_dir'] + 'transformed_' + data_file
    func_tax_path = config['data_dir'] + 'functional_taxonomy_' + data_file
    if config['force_preprocessing'] or \
       (not os.path.exists(trans_data_path) or not os.path.exists(func_tax_path)):
        statically_preprocess_data(data_file, config)

    data = pd.read_csv(trans_data_path, index_col=0)
    func_tax = pd.read_csv(func_tax_path, index_col=0, dtype=str)
    func_start_column = func_tax.columns.get_loc('Genus') + 1
    func_in_file = func_tax.columns[func_start_column:].to_numpy()

    # Check if the functionalities in the config.json file are equal to the functionalities in the preprocessed file.
    if not np.array_equal(func_in_file, config['functionalities_used']):
        statically_preprocess_data(data_file, config)
        func_tax = pd.read_csv(func_tax_path, index_col=0, dtype=str)
        func_in_file = func_tax.columns[func_start_column:].to_numpy()

    return data, func_tax, func_in_file


def preprocess_data(data_file, config):
    """Pre-processes the data.
       
       Parameters:
         data_file : The filename of the abundance data file.
         config : Dictionary of values from config.json."""
    data, func_tax, functionalities = load_and_check_data(data_file, config)

    data = remove_time_series_with_zeroes(data, config['low_abundance_threshold'])

    # Only include ASVs/species with at least one positive value in the chosen functionalities.
    if config['only_pos_func']:
        func_start_column = func_tax.columns.get_loc('Genus') + 1
        positives = func_tax.iloc[:,func_start_column:] == 'pos'
        func_tax = func_tax.loc[positives.any(axis=1)]

    # Make data and taxonomy contain the same ASVs/species (calculate intersection).
    func_tax = func_tax.filter(data.columns, axis=0)
    data = data.filter(func_tax.index, axis=1)
    
    # Convert to numpy.
    func_tax.reset_index(inplace=True)
    func_tax = func_tax.to_numpy().astype(str)
    data = data.to_numpy().astype(float)
    data = np.transpose(data)

    clusters = assign_clusters(func_tax, functionalities)

    return data, func_tax, clusters, functionalities


def statically_preprocess_data(data_file, config):
    """Does some preprocessing steps which are only necessary to run when the data files changes.
        
       Parameters:
         data_file : The filename of the abundance data file.
         config : Dictionary of values from config.json."""
    create_directories(config['figures_dir'], config['results_dir'])

    func_data = preprocess_functionality_data(config['functionality_file'], config['data_dir'])

    # REMOVE THE FOLLOWING LINE IF ONLY ONE FILE WITH FUNTIONALITY INFORMATION IS USED.
    func_data = concat_functionality_data(func_data, config['data_dir'])

    preprocess_abundance_data(data_file, config['metadata_file'], config['data_dir'])
    add_functionalities_to_taxonomy_file('transformed_taxonomy_' + data_file, config['data_dir'], 
                                         func_data, config['functionalities_used'])


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

    statically_preprocess_data(config['data_file'], config)
    preprocess_data(config['data_file'], config)
