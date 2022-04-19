#!/usr/bin/env bash
set -eu
datasets_folder=data/datasets
datasets=$(find $datasets_folder/* -maxdepth 0 -type d -exec echo -n '"{}" ' \;)

find ${datasets_folder}/* -maxdepth 0 -type d |\
  while read -r f;
  do
    cat << EOF > config.json
{
    "abund_file": "$f/ASVtable.csv",
    "taxonomy_file": "$f/taxonomy.csv",
    "metadata_file": "data/metadata.csv",
    "results_dir": "results",
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
    "top_n_taxa": 100,
    "num_features": 10,
    "iterations": 1,
    "max_epochs_lstm": 200,
    "window_size": 10,
    "num_clusters_idec": 10,
    "tolerance_idec": 0.001,
    "splits": [
        0.70,
        0.10,
        0.15
    ]
}
EOF
    bash run.bash
  done
