# ASMC-prediction
Predicting Activated Sludge Microbial Communities based on time series of continuous sludge samples by using deep learning, mainly LSTM and IDEC for pre-clustering

## IDEC
Everything in the 'idec/' folder is from:\
https://github.com/XifengGuo/IDEC-toy

IDEC is from the paper:\
Xifeng Guo, Long Gao, Xinwang Liu, Jianping Yin. 
[Improved Deep Embedded Clustering with Local Structure Preservation](https://xifengguo.github.io/papers/IJCAI17-IDEC.pdf). IJCAI 2017.

## Requirements
### Data
Data files needed in the 'data' directory to run main.py:\
Abundance data:                              (e.g. aalborg_west_ASV.csv)\
Metadata about the samples:                  (e.g. metadata_filtered.csv)\
Functionality info from MiDAS Field Guide:   (e.g. MiDAS_Metadata.csv)

The filename of the abundance data file must end in either '_asv.csv' or '_species.csv' as this is used to infer whether the data is about ASVs or species.

Because of problems with getting filamentous functionality information from MiDAS Field Guide, the program currently relies on another source of functionality information from the file: 'MiDAS_knownfunctions.csv'    (from Kasper's mail 10/12/20 - originally called 'knownfunctions.csv').\
If this workaround is no longer necessary in the future, the line containing: 'func_data = concat_functionality_data(func_data, config['data_dir'])' should be removed from the file 'preprocessing.py'. 

### Python packages
Install all necessary Python packages with:
pip install -r requirements.txt

One of the requirements is 'TensorFlow 2' which is currently supported on Python 3.6-3.8 (https://www.tensorflow.org/install/)

## Usage
Some settings/parameters can be tweaked in the file 'config.json' including which data files to use (see the list below).
If changing 'metadata_file' or 'functionality_file' options in 'config.json' it can be necessary to also set 'force_preprocessing' to 'true' for the next run. This will force recalculation of some of the preprocessing steps using the new data.\
The program can be run with:\
python ./main.py

### Explanations of the options in config.json:
| Parameter                     | Description |
| ---                           | ---         |
| data_file                     | Name of the abundance data file. |
| metadata_file                 | Name of the metadata file. |
| functionality_file            | Name of the functionality file. |
| data_dir                      | Path to the data directory. |
| figures_dir                   | Path to a directory where figures are saved. |
| results_dir                   | Path to a directory where results are saved. |
| functionalities_used          | Which functionalities to use. |
| force_preprocessing           | If 'true', forces preprocessing. Otherwise tries to skip some preprocessing steps which are only necessary to run when the data files changes. |
| only_pos_func                 | If 'true', only uses ASVs/species with a positive value in at least one functionality. |
| low_abundance_threshold       | Discards ASVs/species which have an abundance of 0 in more than 'low_abundance_threshold'\*100 percent of the samples. |
| num_time_series_used          | Number of ASVs/species used for the prediction. |
| max_epochs_lstm               | The maximum number of epochs used for training the LSTM. |
| window_size                   | The size of the windows used for the LSTM i.e. how many samples that are used to predict the following sample. |
| tolerance_idec                | The training of the IDEC model stops if less than 'tolerance_idec'\*100 percent ASVs/species change cluster each iteration. |
