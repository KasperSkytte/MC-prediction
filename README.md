[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.16840270.svg)](https://doi.org/10.5281/zenodo.16840270)

# MC-prediction

Predicting microbial community dynamics based on time series of continuous environmental
samples, using graph neural network models. Developed and tested for activated sludge
samples specifically, but can also be used for predicting the community dynamics in any
other environment (may require some adjustments, see below). Data pre-formatting and
result analysis is done in R, the prediction models themselves are implemented in Python.

Published article: https://www.nature.com/articles/s41467-025-64175-7

This `enhanced` branch extends the published model with an optional graph+TCN backbone
that can additionally take sampling timestamps and temperature into account as covariates,
and predict several horizons at once (e.g. 1, 3, 5, and 10 samples ahead) from a single
model. See [Model design choices](#model-design-choices) below.

## How it works

1. `run.bash` is the entry point. It reads `config.json` and runs, in order:
   - `reformat.R`: loads your abundance/taxonomy/metadata files with
     [ampvis2](https://kasperskytte.github.io/ampvis2/), aggregates taxa at the chosen
     taxonomic level, keeps only the top N most abundant taxa, and (for activated sludge
     data) looks up known genus-level functions from
     [midasfieldguide.org](https://midasfieldguide.org). Output goes to
     `<results_dir>/data_reformatted/`.
   - `main.py`: loads the reformatted data, splits it into train/validation/test sets,
     groups taxa into one or more clusters (see below), and trains a model per cluster to
     predict future abundances from a sliding window of past samples.
2. Taxa are grouped into clusters before training (training one model per cluster instead
   of one global model). Up to four independent clustering strategies can be enabled at
   once via `config.json`:
   - `cluster_graph` (default, recommended): taxa are grouped by a learned correlation
     graph (`GraphicalLasso`), and that same graph is fed into the model as its adjacency
     matrix.
   - `cluster_abund`: taxa are grouped into fixed-size buckets by abundance rank.
   - `cluster_func`: taxa are grouped by known biological function (`functions` in
     `config.json`, e.g. AOB/NOB/PAO/GAO/Filamentous). Only meaningful for datasets with
     MiDAS genus-level function annotations (i.e. activated sludge).
   - `cluster_idec`: taxa are grouped using a deep-embedded-clustering autoencoder
     (`idec/`, vendored from https://github.com/XifengGuo/IDEC-toy). Slower, and needs
     enough samples/taxa to train an autoencoder meaningfully.
3. Results (trained weights, predictions, R², figures, logs) are written under
   `results_dir`, and `run.bash` renames that folder with a timestamp when done.

## Requirements

### Data

The required data must be in the typical amplicon data format: an abundance table
(OTU/ASVs in rows, samples in columns), a taxonomy table (Kingdom → Species per
OTU/ASV), and sample metadata containing at least one column with sampling dates in
year-month-day format. As long as the data loads successfully with the
[ampvis2](https://kasperskytte.github.io/ampvis2/) R package, everything should "just
run" as long as there's enough data (preferably 100+, ideally 1000+ samples). The data
used for the article is under `data/` and can be used as example/reference data.

### Python and R packages

Use the conda `environment.yml` file to create an environment with the required
software. To install the required R packages, use the `renv.lock` file to restore the
R library using the [`renv`](https://rstudio.github.io/renv/articles/renv.html) package.
For GPU support ensure you have a version of Tensorflow that matches your NVIDIA drivers
and CUDA. It's also necessary to set an environment variable before creating the
environment in order to install some required NVIDIA dependencies for network inference:
`export PIP_EXTRA_INDEX_URL='https://pypi.nvidia.com'`.

### Docker container

To facilitate complete reproducibility a (very large) Docker container has been built
with **everything** included, and can be used through Docker, Apptainer, Podman, VSCode
dev containers (through Docker), or any other OCI compatible container engine:
```
docker run -it --nvidia ghcr.io/kasperskytte/mc-prediction:main
apptainer run --nv docker://ghcr.io/kasperskytte/mc-prediction:main
```

If you want to accelerate processing using a GPU, ensure the
[NVIDIA container toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
has been installed and configured for Docker or
[apptainer](https://apptainer.org/docs/user/latest/gpu.html).

The required software is available inside the container in the conda environment
`mc-prediction`, activated with `conda activate /opt/conda/envs/mc-prediction/`.
Depending on how you start the container you may also have to initialize conda first
using `. /opt/conda/etc/profile.d/conda.sh`.

### Hardware requirements and performance

The workflow runs fine on a standard laptop, but extra RAM and an NVIDIA GPU help if you
need more speed — model training itself usually isn't the bottleneck, other steps in the
pipeline are. Typical processing time is 4-8 hours per dataset under `data/datasets`.
Rough guidelines:

- 4 cores/8 threads
- 16GB RAM, preferably 32GB depending on input data
- 100GB storage space
- (not required) NVIDIA GPU with CUDA support

## Usage

Adjust the settings in `config.json` (see the [reference table](#configjson-reference)
below) and run the wrapper script:
```
bash run.bash
```

## Running on your own dataset

1. Prepare three files for your dataset (see [Data](#data) above for the expected
   format): an abundance table, a taxonomy table, and a sample metadata table with a
   date column (and, optionally, a numeric temperature column if you want to use it as
   a covariate).
2. Point `config.json` at your files and columns:
   - `abund_file`, `taxonomy_file`, `metadata_file`
   - `metadata_date_col`: name of the date column in your metadata
   - `metadata_temperature_col`: name of the temperature column, if you have one. If
     it's missing or entirely empty, `reformat.R`/`main.py` will print a warning and
     automatically fall back to running without temperature/timestamp covariates.
3. If your dataset isn't activated sludge, the biological `functions` lookup
   (`cluster_func`, and the `AOB`/`NOB`/`PAO`/`GAO`/`Filamentous` columns from
   [midasfieldguide.org](https://midasfieldguide.org)) won't be meaningful — leave
   `cluster_func` set to `false`, and rely on `cluster_graph` and/or `cluster_abund`
   instead, which don't depend on any activated-sludge-specific reference data.
4. Choose a taxonomic aggregation level with `tax_level` (`OTU`, `Species`, or `Genus`).
5. Pick which cluster type(s) to train (`cluster_graph`/`cluster_abund`/`cluster_func`/
   `cluster_idec` — you can enable more than one to compare them) and whether to use the
   enhanced or baseline model (`use_baseline`, see below).
6. Run `bash run.bash`. If the chosen `results_dir` already exists and isn't empty, the
   script refuses to run to avoid overwriting previous results — remove/move it first.

## Model design choices

- `use_baseline: false` (default) uses the enhanced graph+TCN model
  (`create_graph_model` in `main.py`): it can take timestamps and/or temperature as
  covariates (`use_temperature_and_timestamps`) and predicts several horizons at once —
  `predict_timestamp` is a list, e.g. `[1, 3, 5, 10]` samples ahead.
- `use_baseline: true` uses a simpler model (`create_baseline_model`) without covariate
  injection, predicting a single horizon (the largest value in `predict_timestamp` is
  used, with a warning printed if more than one was given).
- A handful of architecture hyperparameters are exposed directly in `config.json`
  (`graph_sparsity`, `dropout`, `kernel_size`, `residual_channels`) so you can experiment
  with model design without editing `main.py`. Their current defaults reproduce the
  originally published model.

## config.json reference

| Parameter | Default value | Description |
| --- | --- | --- |
| abund_file    | `"data/datasets/Aalborg E/ASVtable.csv"` | CSV/text file with abundance data (OTU/ASVs in rows, samples in columns) |
| taxonomy_file | `"data/datasets/Aalborg E/taxonomy.csv"` | File with taxonomy for each OTU/ASV (Kingdom → Species) |
| metadata_file | `"data/datasets/Aalborg E/metadata.csv"` | Sample metadata (sample IDs must be in the first column) |
| results_dir   | `"results"` | Folder for all output and logs |
| metadata_date_col | `"Date"` | Name of the column in the metadata that contains the sampling dates |
| metadata_temperature_col | `"week_mean_temperature"` | Name of the column in the metadata that contains the sampling temperatures |
| tax_level | `"OTU"` | Taxonomic level at which to aggregate OTU/ASVs (`OTU`, `Species`, or `Genus`) |
| tax_add   | `["Species", "Genus"]` | Additional taxonomy levels to add to plot titles |
| functions | `["AOB", "NOB", "PAO", "GAO", "Filamentous"]` | Metabolic functions to use for `cluster_func` (activated sludge / MiDAS-specific) |
| only_pos_func | `false` | If true, only keep a taxon if it's assigned to at least one function according to midasfieldguide.org |
| pseudo_zero   | `0.01` | Pseudo zero, used when filtering sparse taxa and computing zero counts |
| max_zeros_pct | `0.60` | Filter out taxa with abundance below `pseudo_zero` in more than this fraction of samples |
| top_n_taxa    | `200` | Number of most abundant taxa to keep from the dataset |
| num_features  | `200` | Max number of taxa (features) actually used for modelling |
| num_per_group | `5` | Max number of taxa per cluster (for `cluster_abund`/`cluster_graph`) |
| iterations    | `10` | Number of random-restart training runs per cluster; the best one (by test loss) is kept |
| max_epochs   | `200` | Max number of training epochs (with early stopping) |
| window_size   | `10` | How many past samples are used as input for a prediction |
| predict_timestamp | `[1, 3, 5, 10]` | How many samples into the future to predict. A list of horizons for the enhanced model; only the max is used for the baseline model |
| num_clusters_idec |  `40` | Number of IDEC clusters to create (only used if `cluster_idec` is enabled) |
| tolerance_idec    |  `0.001` | Stop IDEC model training once improvement drops below this tolerance |
| graph_sparsity | `0.01` | GraphicalLasso sparsity for the learned taxon-correlation graph. Higher = sparser graph. Try 0.01 to 0.1 |
| dropout | `0` | Dropout rate used inside the graph convolution blocks. Try 0, 0.1, 0.2, 0.3 |
| kernel_size | `4` | Dilated convolution kernel size (temporal receptive field). Try 2, 3, 4 |
| residual_channels | `8` | Number of channels in the residual/dilation/graph-conv layers. Try 4, 8, 16 |
| transform | `"divmean"` | Data transformation to use: one of `"divmean"`, `"normalize"`, `"standardize"`, `"none"` |
| cluster_idec  |  `false` | Whether to create IDEC clusters and train+test a model per cluster |
| cluster_func  |  `false` | Whether to create biological-function clusters and train+test a model per cluster |
| cluster_abund |  `false` | Whether to create ranked-abundance clusters and train+test a model per cluster |
| cluster_graph |  `true` | Whether to create graph clusters and train+test a model per cluster |
| use_baseline | `false` | Whether to use the simpler baseline model instead of the enhanced graph+TCN model |
| use_temperature_and_timestamps | `true` | Whether to feed sampling timestamps and temperature into the model as covariates (enhanced model only, ignored if `use_baseline` is true) |
| smoothing_factor |  `4` | Moving-average smoothing window applied to the abundance data |
| splits | `[0.80, 0.05, 0.15]` | Fractions to split the data into train+val+test sets |

## Outputs

Each run writes to `results_dir` (renamed to `<results_dir>_<timestamp>` once
`run.bash` finishes), including:
- `data_reformatted/`: the reformatted abundance/taxonomy/metadata tables used as input.
- `data_splits/`: which sample dates went into the train/val/test split.
- `graph_matrix/`: the learned taxon-correlation graph(s), as CSV adjacency matrices.
- `{graph}_{cluster_type}_weights/`: trained model weights per cluster.
- `data_predicted/`: per-cluster and combined (`_all_`) CSVs of true vs. predicted
  abundances, for each prediction horizon.
- `R_square/`: R² of predicted vs. true values per cluster.
- `figures/`: prediction plots per cluster (and clustering diagnostics, if `cluster_idec`
  is enabled).
- `graph_{cluster_type}_performance.txt`: final test-set loss/metrics per cluster.

## Batch processing multiple datasets

`sbatch_array.sh` is a SLURM array-job template that runs the workflow once per
subfolder under `data/datasets/` (each subfolder needs its own `ASVtable.csv`,
`taxonomy.csv`, and `metadata.csv`), using the Apptainer/Singularity container. Adjust
the `#SBATCH` directives and the `--array` range to match the number of dataset folders
before submitting.

## Article analysis

The results presented in the article produced using this workflow are available at
[figshare](https://doi.org/10.6084/m9.figshare.25288159.v1). Unpack into `analysis/` and
run the R markdown to reproduce the figures.

## Credit

Everything in the `idec/` folder is copied from:
https://github.com/XifengGuo/IDEC-toy. Should have been a submodule.

IDEC is from the paper: Xifeng Guo, Long Gao, Xinwang Liu, Jianping Yin.
[Improved Deep Embedded Clustering with Local Structure Preservation](https://xifengguo.github.io/papers/IJCAI17-IDEC.pdf). IJCAI 2017.
