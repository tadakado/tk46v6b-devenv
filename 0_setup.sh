#!/bin/bash

colima start

cd `dirname $0`
PWD=`pwd`

if [ ! -d zmk/app ]; then
    echo "ERROR: $PWD/zmk is missing. Run: git submodule update --init" >&2
    exit 1
fi

mkdir -p zmk-config zmk-modules

# `docker volume rm` fails while any container (even a stopped one) still uses
# the volume, and `volume create` then keeps the old binding -- so the volumes
# would silently stay tied to another checkout. Remove the container first.
if docker inspect zmk-dev >/dev/null 2>&1; then
    echo "Removing existing container zmk-dev (it holds the volumes)..."
    docker rm -f zmk-dev >/dev/null
fi

for v in zmk-config zmk-modules; do
    if docker volume inspect $v >/dev/null 2>&1; then
        docker volume rm $v >/dev/null || { echo "ERROR: could not remove volume $v (still in use?)" >&2; exit 1; }
    fi
done

docker volume create --driver local -o o=bind -o type=none -o device="$PWD/zmk-config/" zmk-config
docker volume create --driver local -o o=bind -o type=none -o device="$PWD/zmk-modules/" zmk-modules

for v in zmk-config zmk-modules; do
    dev=$(docker volume inspect $v --format '{{.Options.device}}')
    if [ "$dev" != "$PWD/$v/" ]; then
        echo "ERROR: volume $v -> $dev (expected $PWD/$v/)" >&2
        exit 1
    fi
    echo "$v -> $dev"
done
