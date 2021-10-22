#!/usr/bin/env bash
set -eu
#set timezone
export TZ="Europe/Copenhagen"

#default error message if bad usage
usageError() {
  echo "Invalid usage: $1" 1>&2
  echo ""
  eval "bash $0 -h"
}

#fetch and check options provided by user
#flags for required options, checked after getopts loop
p_flag=0
while getopts ":hp:" opt; do
case ${opt} in
  h )
    echo "This script wraps things up to run both preprocessing (R) and prediction (python)"
    echo "and saves the terminal output as a log file including settings."
    echo "The idea is you manually preproces the amplicon data, fx"
    echo "filtering control samples, remove outliers etc, before doing prediction"
    echo "by inspecting and running a preprocessing R script."
    echo "Then run this script passing on the path to the R script."
    echo ""
    echo "Options:"
    echo "  -h    Display this help text and exit."
    echo "  -p    Path to preprocessing R script."
    exit 1
    ;;
  p )
    preprocess_script="$OPTARG"
    p_flag=1
    ;;
  \? )
    usageError "Invalid Option: -$OPTARG"
    exit 1
    ;;
  : )
    usageError "Option -$OPTARG requires an argument"
    exit 1
    ;;
esac
done
shift $((OPTIND -1)) #reset option pointer

#check all required options
if [ $p_flag -eq 0 ]
then
	usageError "option -p is required"
	exit 1
fi

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
  Rscript "$preprocess_script"
  Rscript reformat.R
  python main.py
}

main |& tee results/"$logFile"

chown 1000:1000 -R results
mv results "results_${timestamp}"