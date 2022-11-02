#!/usr/bin/env bash
#This script runs run.bash for different numbers 
#of predicted samples into the future
dataset="Aalborg E"
npredictions="3 5 10 15 20"
set -u
for i in $npredictions
do
    cat << EOF > config.json
{
    "abund_file": "data/datasets/$dataset/ASVtable.csv",
    "taxonomy_file": "data/datasets/$dataset/taxonomy.csv",
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
    "top_n_taxa": 200,
    "num_features": 20,
    "iterations": 10,
    "max_epochs_lstm": 200,
    "window_size": 10,
    "predict_timestamp": $i,
    "num_clusters_idec": 5,
    "tolerance_idec": 0.001,
    "transform": "divmean",
    "cluster_idec": true,
    "cluster_func": true,
    "cluster_abund": true,
    "smoothing_factor": 4,
    "splits": [
        0.85,
        0.0,
        0.15
    ]
}
EOF
    bash run.bash
done
