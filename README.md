[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.16840270.svg)](https://doi.org/10.5281/zenodo.16840270)

# MC-prediction
Predicting microbial community dynamics based on time series of continuous environmental samples by using graph neural network models. Developed and tested for activated sludge samples specifically, but can also be used for predicting the community dynamics in any other environment, but may require some adjustments. The implementation of the prediction model itself is primarily done in Python, but R is used for pre-formatting data and also for analyzing results.

## Requirements
### Data
The required data must be in the typical amplicon data format with an abundance table for each ASV/OTU, taxonomy table, and sample metadata. The sample metadata must contain at least one variable with sampling dates in year-month-day format. As long as the data can be loaded succesfully using the [ampvis2](https://kasperskytte.github.io/ampvis2/) R package, everything should "just run" as long as there is enough data (preferably 100+, but ideally 1000+ samples). The data and results used for the article is under `data/` and can be used as example data.

### Python and R packages
Use the conda `environment.yml` file to create an environment with the required software. To installed required R packages, use the `renv.lock` file to restore the R library using the [`renv`](https://rstudio.github.io/renv/articles/renv.html) package.
For GPU support ensure you have a version of Tensorflow that matches your nvidia drivers and CUDA. It's also necessary to set an environment variable before creating the environment in order to install some required NVIDIA dependencies for network inference: `export PIP_EXTRA_INDEX_URL='https://pypi.nvidia.com'`.

### Docker container
To facilitate complete reproducibility a (very large) Docker container has been built with **everything** included, and can be used through Docker, Apptainer, Podman, VSCode dev containers (through Docker), or any other OCI compatible container engine:
```
docker run -it --nvidia ghcr.io/kasperskytte/mc-prediction:main
apptainer run --nv docker://ghcr.io/kasperskytte/mc-prediction:main
```

If you want to accelerate processing by using a GPU ensure the [NVIDIA container toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) has been installed and configured for Docker or [apptainer](https://apptainer.org/docs/user/latest/gpu.html).

The required software is then available in the conda environment `mc-prediction` inside the container, which can be activate using `conda activate /opt/conda/envs/mc-prediction/`. Depending on how you start the container you may also have to initialize conda first using `. /opt/conda/etc/profile.d/conda.sh`.

### Hardware requirements and performance
The workflow can run on a standard laptop just fine (as of 2023), but may require extra RAM and a NVIDIA GPU if you really need extra speed, however many other steps in the implementation are the bottlenecks, it's not the model training time that takes much time. Typical processing time is 4-8 hours per dataset under `data/datasets`. Here are some hardware guidelines:

 - 4 cores/8 threads
 - 16GB RAM, preferably 32GB depending on input data
 - 100GB storage space
 - (not required) NVIDIA GPU with CUDA support

## Usage
Adjust the settings in `config.json` and then run the wrapper script `run.bash`. This will run `reformat.R` to first sort, filter, and format the data, look up known Genus-level functions on the [midasfieldguide.org](https://midasfieldguide.org) etc, and then run `main.py` which will start model training and evaluation.

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
| max_epochs   |  200 | Max number of epochs when using LSTM |
| window_size   |  10 | How many samples are used as input for predictions |
| predict_timestamp |  10 | How many samples into the future to predict for each moving window |
| num_clusters_idec |  10 | How many IDEC clusters to create (should be automatic though) |
| tolerance_idec    |  0.001 | Stop IDEC model training if not improving more than this tolerance |
| transform |  divmean | Data transformation to use. One of "divmean", "normalize", "standardize", "none" |
| cluster_idec  |  false | Whether to create IDEC clusters and perform model training+testing |
| cluster_func  |  false | Whether to create function clusters and perform model training+testing |
| cluster_abund |  true | Whether to create ranked abundance clusters and perform model training+testing |
| cluster_graph |  true | Whether to create graph clusters and perform model training+testing |
| use_timestamps | true | Whether to take the distance between sample points into account as an additional variable for training the models. |
| smoothing_factor |  4 | Data smoothing factor |
| splits | [0.80, 0,05, 0.15] | Fractions with which to split the data into train+val+test dataset |

## Article analysis
The results presented in the article produced using this workflow are available at [figshare](https://doi.org/10.6084/m9.figshare.25288159.v1). Unpack into `analysis/` and run the R markdown to reproduce the figures.

## Credit
Everything in the 'idec/' folder is copied from: https://github.com/XifengGuo/IDEC-toy. Should have been a submodule.

IDEC is from the paper: Xifeng Guo, Long Gao, Xinwang Liu, Jianping Yin.
[Improved Deep Embedded Clustering with Local Structure Preservation](https://xifengguo.github.io/papers/IJCAI17-IDEC.pdf). IJCAI 2017.
