#!/usr/bin/bash -l
#SBATCH --job-name=mc-prediction
#SBATCH --output=/dev/null
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=3
#SBATCH --mem=9G
#SBATCH --time=1-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=abc@bio.aau.dk
#SBATCH --account=phn
#SBATCH --array=0-30

set -euo pipefail

# Runs the workflow for every dataset in here.
# The number of folders must match the number of jobs in the array
datasets_folder="data/datasets"

# not so simple to iterate over directories whose names contain spaces
datasets=()
while IFS= read -r dir; do
    datasets+=("$dir")
done < <(find "${datasets_folder}"/* -maxdepth 1 -type d | sort)

config_file="config_${SLURM_ARRAY_TASK_ID}.json"
cat << EOF > "${config_file}"
{
    "abund_file": "${datasets[${SLURM_ARRAY_TASK_ID}]}/ASVtable.csv",
    "taxonomy_file": "${datasets[${SLURM_ARRAY_TASK_ID}]}/taxonomy.csv",
    "metadata_file": "${datasets[${SLURM_ARRAY_TASK_ID}]}/metadata.csv",
    "results_dir": "results_${SLURM_ARRAY_TASK_ID}",
    "metadata_date_col": "Date",
    "tax_level": "OTU",
    "tax_add": ["Species", "Genus"],
    "functions": [
        "AOB",
        "NOB",
        "PAO",
        "GAO",
        "Filamentous"
    ],
    "only_pos_func": false,
    "pseudo_zero": 0.01,
    "max_zeros_pct": 0.60,
    "top_n_taxa": 200,
    "num_features": 200,
    "num_per_group": 5,
    "iterations": 10,
    "max_epochs": 200,
    "window_size": 10,
    "predict_timestamp": 10,
    "num_clusters_idec": 40,
    "tolerance_idec": 0.001,
    "transform": "divmean",
    "cluster_idec": true,
    "cluster_func": true,
    "cluster_abund": true,
    "cluster_graph": true,
    "use_timestamps": true,
    "smoothing_factor": 4,
    "splits": [
        0.80,
        0.05,
        0.15
    ]
}
EOF

# First pull container manually before submitting job:
#   apptainer pull mc-prediction.sif docker://ghcr.io/kasperskytte/mc-prediction:main
# Mount config.json when running in parallel to avoid overwriting files across jobs.
# Also remember to comment out the renv line in .Rprofile or remove the file 
# to ensure the library inside the container is used. Or mount over with an empty file like below.
apptainer exec \
  --no-home \
  --cleanenv \
  -B "${PWD}" \
  -B "${config_file}:${PWD}/config.json" \
  -B "$(mktemp):${PWD}/.Rprofile" \
  mc-prediction.sif \
  conda run -n mc-prediction bash ./run.bash

rm "${config_file}"
