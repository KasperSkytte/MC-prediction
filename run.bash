#!/usr/bin/env bash
set -eu
rm -rf results figures
mkdir -p results figures data/preprocessed

Rscript preprocess.R
python main.py