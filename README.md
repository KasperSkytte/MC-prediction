# ASMC-prediction
Predicting Activated Sludge Microbial Communities based on time series of continuous sludge samples by using graph neural network models.

## Requirements
### Data
The required data must be in the typical amplicon data format with an abundance table for each ASV/OTU, taxonomy table, and sample metadata. The sample metadata must contain a variable with sampling dates. If it can be loaded succesfully using the [ampvis2](https://kasperskytte.github.io/ampvis2/) R package everything should "just run" as long as there is enough data.

### Required Python and R packages
Install required Python packages with `pipenv` based on the lock file, and similarly for R use `renv`. For GPU support ensure you have a version of Tensorflow that matches your nvidia drivers and CUDA.

## Usage
Simply run the wrapper script `run.bash` will run `reformat.R` to first sort, filter, and format the data, look up known Genus-level functions on the [midasfieldguide.org](https://midasfieldguide.org) etc, and then run `main.py` that will start model training and evaluation.

### Docker (recommended)
This image has all required tools installed and tested together, and this image have been used to produce the results for the paper.
Pull image with `docker pull ghcr.io/kasperskytte/asmc-prediction:main` or build scratch from this repository with `docker build -t ghcr.io/kasperskytte/asmc-prediction:main .`. The image does not contain any scripts, it's simply to contain the software and dependencies used (exact versions, tested). Ideally use [development containers](https://code.visualstudio.com/docs/devcontainers/tutorial) with VSCode. Otherwise run through docker:
```
docker run -it --rm -v "${PWD}":/tf -u $(id -u):$(id -g) ghcr.io/kasperskytte/asmc-prediction:main run.bash

```

The image has CUDA support to speed up computation if you have a modern nvidia GPU. To enable add the `--gpus all` to the docker run command above and make sure you have installed recent nvidia drivers and the `nvidia-container-toolkit`. With newer versions of Ubuntu, you can simply run

```
sudo apt-get update
sudo apt-get install docker.io nvidia-container-toolkit
```

before starting the container. Remember to restart the docker daemon for the changes to take effect with `sudo systemctl restart dockerd`. If this doesn't work follow the guidelines at https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html#install-guide. The container has been based on CUDA version 11.4, but you can adapt.

## Options in config.json:
| Parameter | Default value | Description |
| --- | --- | --- |
| abund_file    | "data/datasets/Damhusåen-C/ASVtable.csv" |  CSV/text file with abundance data (OTU/ASVs in rows, samples in columns) |
| taxonomy_file | "data/datasets/Damhusåen-C/taxonomy.csv" |  File with taxonomy for each OTU/ASV (Kingdom->Species) |
| metadata_file | "data/metadata.csv" |  Sample metadata (Sample IDs must be in the first column) |
| results_dir   | "results" |  Folder with all output and logs |
| metadata_date_col | "Date" |  Name of the column in the metadata that contains the sampling dates |
| tax_level | "OTU" |  Taxonomic level at which to aggregate OTU/ASVs (Only works and makes sense at OTU/ASV level) |
| tax_add   | ["Species", "Genus"] |  Additional taxonomy levels to add to plot titles |
| functions | ["AOB", "NOB", "PAO", "GAO", "Filamentous"] |  Array of metabolic functions to use for pre-clusterin |
| only_pos_func | false |  If true only keeps a taxon if it's assigned to at least one function according to midasfieldguide.org |
| pseudo_zero   | 0.01 | Pseudo zero |
| max_zeros_pct | 0.60 | Filter taxa that have abundance of pseudo-zero in more than this percent of samples |
| top_n_taxa    |  200 | Number of most abundant taxa to use from the dataset |
| num_features  |  200 |   |
| num_per_group |  5 | Max number of taxa per group |
| iterations    |  10 | Max iterations of model training before continuing |
| max_epochs_lstm   |  200 | Max number of epochs when using LSTM |
| window_size   |  10 | How many samples are used as input for predictions |
| predict_timestamp |  10 | How many samples into the future to predict for each moving window |
| num_clusters_idec |  10 | How many IDEC clusters to create (should be automatic though) |
| tolerance_idec    |  0.001 | Stop IDEC model training if not improving more than this tolerance |
| transform |  divmean | Data transformation to use. One of "divmean", "normalize", "standardize", "none" |
| cluster_idec  |  false | Whether to create IDEC clusters and perform model training+testing |
| cluster_func  |  false | Whether to create function clusters and perform model training+testing |
| cluster_abund |  true | Whether to create ranked abundance clusters and perform model training+testing |
| cluster_graph |  true | Whether to create graph clusters and perform model training+testing |
| smoothing_factor |  4 | Data smoothing factor |
| splits | [0.80, 0,05, 0.15] | Fractions with which to split the data into train+val+test dataset |

vscode extensions:
R
quarto
jupyter
python
(pylance)


## IDEC
Everything in the 'idec/' folder is from:\
https://github.com/XifengGuo/IDEC-toy

IDEC is from the paper:\
Xifeng Guo, Long Gao, Xinwang Liu, Jianping Yin.
[Improved Deep Embedded Clustering with Local Structure Preservation](https://xifengguo.github.io/papers/IJCAI17-IDEC.pdf). IJCAI 2017.
