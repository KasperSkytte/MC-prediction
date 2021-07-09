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
function info from MiDAS Field Guide:   (e.g. MiDAS_Metadata.csv)

### Python packages
Install all necessary Python packages with:
pip install -r requirements.txt

One of the requirements is 'TensorFlow 2' which is currently supported on Python 3.6-3.8 (https://www.tensorflow.org/install/)

## Usage
Some settings/parameters can be tweaked in the file 'config.json' including which data files to use (see the list below).
If changing 'metadata_filename' or 'function_filename' options in 'config.json' it can be necessary to also set 'force_preprocessing' to 'true' for the next run. This will force recalculation of some of the preprocessing steps using the new data.\
The program can be run with:\
python ./main.py

## Docker
Pull image with `docker pull kasperskytte/asmc-prediction` (append `-{version}` to pull a specific and locked version based on specific GitHub tags) or build from this repository with `docker build -t kasperskytte/asmc-prediction .`. The image does not contain any scripts, it's simply to contain the software and dependencies used (exact versions, tested).

Then run with:
```
docker run -it --rm -v "${PWD}":/tf -u $(id -u):$(id -g) kasperskytte/asmc-prediction python main.py

```

The image has CUDA support to speed up computation if you have a modern nvidia GPU. To enable add the `--gpus all` to the docker run command above and make sure you have installed recent nvidia drivers and the nvidia-container-toolkit. With never versions of Ubuntu, you can simply run 

```
sudo apt-get update
sudo apt-get install docker.io nvidia-container-runtime 
```

before starting the container. If this doesn't work follow the guidelines at https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html#install-guide

### Explanations of the options in config.json:
| Parameter                     | Description |
| ---                           | ---         |
| abund_filename                     | Name of the abundance data file. |
| metadata_filename                 | Name of the metadata file. |
| function_filename            | Name of the function file. |
| data_dir                      | Path to the data directory. |
| figures_dir                   | Path to a directory where figures are saved. |
| results_dir                   | Path to a directory where results are saved. |
| functions          | Which functions to use. |
| force_preprocessing           | If 'true', forces preprocessing. Otherwise tries to skip some preprocessing steps which are only necessary to run when the data files changes. |
| only_pos_func                 | If 'true', only uses taxa with a positive value in at least one function. |
| max_zeros_pct       | Discards taxa which have an abundance of 0 in more than 'max_zeros_pct'\*100 percent of the samples. |
| num_time_series_used          | Number of taxa used for the prediction. |
| max_epochs_lstm               | The maximum number of epochs used for training the LSTM. |
| window_size                   | The size of the windows used for the LSTM i.e. how many samples that are used to predict the following sample. |
| idec_nclusters                | Number of IDEC clusters |
| tolerance_idec                | The training of the IDEC model stops if less than 'tolerance_idec'\*100 percent taxa change cluster each iteration. |
| splits                        | How to partition the data into training, validation, and testing sets. Must sum to <= 1 |
