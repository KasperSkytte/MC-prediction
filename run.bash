#!/usr/bin/env bash
set -eu
rm -rf results figures
docker build -t kasperskytte/asmc-prediction .
cmd=${*:-python main.py}
docker run -it --rm --gpus all -v "${PWD}":/tf -u "$(id -u)":"$(id -g)" kasperskytte/asmc-prediction $cmd

