#!/usr/bin/env bash
set -eu
sudo docker build -t kasperskytte/predict .
sudo docker run -it --rm -v $(realpath .):/tf -p 8888:8888 -u $(id -u):$(id -g) kasperskytte/predict
