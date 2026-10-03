#!/bin/sh

docker stop zmk-dev
docker rm zmk-dev
#docker volume ls | grep zmk- | awk '{print $2}' | xargs docker volume rm
docker volume rm zmk-config zmk-modules zmk-root-user
