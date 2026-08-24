[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.16840270.svg)](https://doi.org/10.5281/zenodo.16840270)

# MC-prediction
Predicting microbial community dynamics from time series of environmental samples using graph neural network models. Community abundance data is all that's needed, but supplementing it with environmental variables such as temperature measurements can improve prediction accuracy. Accurate predictions as far as 6 months or more into the future have been obtained. Initially developed for data from activated sludge from full-scale wastewater treatment plants, but works just as well on data from other environments as well, such as the human gut, as demonstrated in the published article. The prediction models themselves are implemented in Python, while R is used to pre-format the data and analyze the results.

Now with a **new and improved model design** that is even more accurate compared to the one used in the published article.

Published Nature Communications article here: https://www.nature.com/articles/s41467-025-64175-7

## Workflow outline
1. ASVs are pre-filtered and, if necessary, aggregated at a higher taxonomic level. Sparse ASVs consisting mostly of zeroes are dropped, only the most abundant ones are kept by default, and known Genus-level functions are looked up on [midasfieldguide.org](https://midasfieldguide.org).
2. The abundance data is smoothed and transformed, so the models see relative changes over time rather than absolute abundances.
3. ASVs are clustered into smaller groups before prediction and a separate model is trained for each group. Clustering by correlation graph is recommended, in which case the graph is also passed on to the model itself, but grouping by IDEC, metabolic functions, or ranked abundance is available too.
4. The data is split into three parts, training, evaluation, and testing, and each model is trained several times over, keeping the best run. Predictions then extend into the future, at one or more horizons at a time. The idea is to retrain every time you get new data to obtain predictions in a continuously updated time series data set.
5. Predicted and actual abundances are written out per cluster as well as combined across all clusters, together with R², plots, and the trained model weights.

## Usage
Adjust the settings in `config.json` and then run the wrapper script `run.bash`. This will run `reformat.R` to first sort, filter, and format the data, look up known Genus-level functions on the [midasfieldguide.org](https://midasfieldguide.org) etc, and then run `main.py` which will start model training and evaluation. The most convenient is to run through the prebuilt container available on GHCR, for example:

```
apptainer exec --no-home --cleanenv  docker://ghcr.io/kasperskytte/mc-prediction:main conda run -n mc-prediction bash ./run.bash
```

## Requirements
### Data
The required data must be in the typical amplicon data format with an abundance table for each ASV/OTU, taxonomy table, and sample metadata. The sample metadata **must contain** at least one variable with **sampling dates** in year-month-day format. As long as the data can be loaded succesfully using the [ampvis2](https://kasperskytte.github.io/ampvis2/) R package, everything should "just run" as long as there is enough data (preferably 100+, but ideally more samples). The data and results used for the article is available under `data/` and can be used as example data.

### Python and R packages
Use the conda `environment.yml` file to create an environment with the required software. To installed required R packages, use the `renv.lock` file to restore the R library using the [`renv`](https://rstudio.github.io/renv/articles/renv.html) package.
For GPU support ensure you have a version of Tensorflow that matches your nvidia drivers and CUDA. It's also necessary to set an environment variable before creating the environment in order to install some required NVIDIA dependencies for network inference: `export PIP_EXTRA_INDEX_URL='https://pypi.nvidia.com'`.

### Docker container
To facilitate complete reproducibility a (very large) Docker container has been built with **everything** included, and can be run through Docker, Apptainer/Singularity, Podman, VSCode dev containers (through Docker), or any other OCI compatible container engine:
```
docker run -it --nvidia ghcr.io/kasperskytte/mc-prediction:main
apptainer run --nv docker://ghcr.io/kasperskytte/mc-prediction:main
```

If you want to accelerate processing by using a GPU ensure the [NVIDIA container toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) has been installed and configured for Docker or [apptainer](https://apptainer.org/docs/user/latest/gpu.html).

The required software is then available in the conda environment `mc-prediction` inside the container, which can be activate using `conda activate /opt/conda/envs/mc-prediction/`. Depending on how you start the container you may also have to initialize conda first using `. /opt/conda/etc/profile.d/conda.sh`.

### Hardware requirements and performance
The workflow can run on a standard laptop just fine (as of 2023), but may require extra RAM and a NVIDIA GPU if you really need extra speed, however many other steps in the implementation are the bottlenecks, it's not the model training time that takes much time. There is usually little speed to gain with a GPU, however that depends on the input data. Typical processing time using CPU only is 4-8 hours per dataset under `data/datasets`. Here are some hardware guidelines:

 - 4 cores/8 threads
 - 16GB RAM, preferably 32GB depending on input data
 - 100GB storage space
 - (not required) NVIDIA GPU with CUDA support


## Settings:
Everything is configured in `config.json`. The ones you'll actually touch:

| Parameter | Default | What it does |
| --- | --- | --- |
| `abund_file`, `taxonomy_file`, `metadata_file` | `"data/datasets/Aalborg E/..."` | Your three input files |
| `results_dir` | `"results"` | Where output and logs go |
| `metadata_date_col` | `"Date"` | Sampling date column in the metadata |
| `metadata_temperature_col` | `"week_mean_temperature"` | Temperature column, if you have one |
| `tax_level` | `"OTU"` | Level to aggregate taxa at (`OTU`, `Species` or `Genus`). It's recommended to use the lowest possible one for the best predictions |
| `top_n_taxa` | `200` | How many of the most abundant taxa to keep |
| `num_per_group` | `5` | Max taxa per cluster |
| `window_size` | `10` | How many past samples each prediction is based on |
| `predict_timestamp` | `[1, 3, 5, 10]` | How far ahead to predict, in samples |
| `iterations` | `10` | Training restarts per cluster; the best one is kept |
| `max_epochs` | `200` | Epoch cap, with early stopping |
| `cluster_graph`, `cluster_abund`, `cluster_func`, `cluster_idec` | graph only | Which clustering strategies to use before training |
| `use_baseline` | `false` | Use the simpler published model instead of the graph+TCN one |
| `use_temperature_and_timestamps` | `true` | Feed timestamps and temperature to the model (enhanced model only) |
| `splits` | `[0.80, 0.05, 0.15]` | Train/validation/test fractions |

The rest are model hyperparameters (`graph_sparsity`, `dropout`, `kernel_size`,
`residual_channels`) and IDEC options. They're all in `config.json` if you want to
experiment. The defaults are the ones used in the article.

## Output

Each run writes to `results_dir`:

- `data_reformatted/` — the tables that actually went into the model
- `data_splits/` — which samples ended up in train, validation and test
- `graph_matrix/` — the learned correlation graphs as adjacency matrices
- `data_predicted/` — true vs. predicted abundances, per cluster and combined (`_all_`)
- `R_square/` and `graph_*_performance.txt` — how well it did
- `figures/` — prediction plots
- `*_weights/` — trained model weights

## Analysis from the paper

The published results shown in the article are available on
[figshare](https://doi.org/10.6084/m9.figshare.25288159.v1). Unpack into `analysis/` and
run the R markdown to regenerate the figures. The exact version of the code used for the article is tagged at [`v1.1.1`](https://github.com/KasperSkytte/MC-prediction/releases/tag/v1.1.1).

## Credit

Everything in `idec/` is copied from https://github.com/XifengGuo/IDEC-toy — should have
been a submodule. IDEC is from Xifeng Guo, Long Gao, Xinwang Liu, Jianping Yin,
[Improved Deep Embedded Clustering with Local Structure Preservation](https://xifengguo.github.io/papers/IJCAI17-IDEC.pdf),
IJCAI 2017.
