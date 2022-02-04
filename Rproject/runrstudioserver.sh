#!/usr/bin/env bash
set -eu

#no matter from which folder this script is executed
#it will always run from its parent folder
SELFPATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
pushd "$SELFPATH"

docker build -t rstudioserver .

port=80
password="supersafepassword"
containername="rstudioserver"
if [ -n "$(docker ps -qf name=${containername})" ]
then
  docker stop ${containername} &> /dev/null
  echo "stopped already running container: ${containername}"
fi
docker stop ${containername} 2>&1 |:
docker run \
  --rm \
  --name=${containername} \
  -d \
  -v "${PWD}/../":"/home/rstudio/ASMC-prediction" \
  -p ${port}:8787 \
  -e PASSWORD=${password} \
  rstudioserver

popd

echo
echo "Launch RStudio through a browser at one of these adresses:"
echo "http://127.0.0.1:${port} (this machine only)"
for IP in $(hostname -I)
do
  echo "http://${IP}:${port}"
done
echo
echo "Username: rstudio"
echo "Password: ${password}"
