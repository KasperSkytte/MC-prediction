#!/usr/bin/env bash
set -eu
rm -rf results figures
mkdir -p results figures data/preprocessed

#docker pull kasperskytte/rstudio_r4.1.0_ampvis2:2.7.8
#docker pull kasperskytte/asmc-prediction:latest

docker run --rm -v "${PWD}":/rstudio -w /rstudio kasperskytte/rstudio_r4.1.0_ampvis2:2.7.8 Rscript preprocess.R

cmd=${*:-python main.py}
docker run -it --rm --gpus all -v "${PWD}":/tf -u "$(id -u)":"$(id -g)" kasperskytte/asmc-prediction $cmd
