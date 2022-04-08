#!/usr/bin/env bash
set -eu
datasets_folder="data/datasets"
datasets=$(find $datasets_folder/* -maxdepth 0 -type d -exec echo -n '"{}" ' \;)

find data/datasets/* -maxdepth 0 -type d |\
  while read f;
  do
    cat << EOF > config.json
{
    "abund_file": "$f/ASVtable.csv",
    "taxonomy_file": "$f/taxonomy.csv",
    "metadata_file": "data/metadata.csv",
    "results_dir": "results",
    "metadata_date_col": "Date",
    "tax_level": "OTU",
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
    "num_time_series_used": 10,
    "iterations": 1,
    "max_epochs_lstm": 200,
    "window_size": 10,
    "idec_nclusters": 5,
    "tolerance_idec": 0.001,
    "splits": [
        0.80,
        0.0,
        0.20
    ]
}
EOF
    bash run.bash
  done
