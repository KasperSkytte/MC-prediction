#!/usr/bin/env bash
set -eu
#set timezone
export TZ="Europe/Copenhagen"

timestamp=$(date '+%Y%m%d_%H%M%S')
logFile="log_${timestamp}.txt"

results_dir=$(cat config.json | jq -r '.results_dir')
if [ -f "$results_dir" ]
then
  echo "Folder ${results_dir} already exists, please clear or move, and then rerun."
  exit 1
fi
mkdir -p \
  "${results_dir}" \
  "${results_dir}/data_reformatted" \
  "${results_dir}/figures"

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
  Rscript reformat.R
  python main.py
}

main |& tee "${results_dir}/${logFile}"

chown 1000:1000 -R ${results_dir}
mv results "${results_dir}_${timestamp}"

duration=$(printf '%02dh:%02dm:%02ds\n' $(($SECONDS/3600)) $(($SECONDS%3600/60)) $(($SECONDS%60)))
echo "Time elapsed: $duration!"
