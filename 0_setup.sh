#!/bin/bash

colima start

cd `dirname $0`
PWD=`pwd`

mkdir -p zmk-config zmk-modules

docker volume rm zmk-config
docker volume rm zmk-modules

docker volume create --driver local -o o=bind -o type=none -o device="$PWD/zmk-config/" zmk-config
docker volume create --driver local -o o=bind -o type=none -o device="$PWD/zmk-modules/" zmk-modules
