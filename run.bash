#!/usr/bin/env bash
set -eu

#set timezone
export TZ="Europe/Copenhagen"

rm -rf results data/preprocessed
mkdir -p results/figures data/preprocessed

timestamp=$(date '+%Y%m%d_%H%M%S')
logFile="log_${timestamp}.txt"

main() {
  echo "#################################################"
  echo "Script: $(realpath "$0")"
  echo "System time: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Current user name: $(whoami)"
  echo "Running in docker container:" $(if [ -f '/.dockerenv' ]; then echo yes; else echo no; fi)
  echo "Current working directory: $(pwd)"
  echo "Log file: $(realpath -m "$logFile")"
  echo "Configuration:"
  cat config.json
  echo "#################################################"
  echo
  Rscript preprocess.R
  python main.py
}

main |& tee results/"$logFile"

chown 1000:1000 -R results
mv results "results_${timestamp}"