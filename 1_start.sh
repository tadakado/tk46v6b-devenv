#!/bin/bash

cd `dirname $0`
PWD=`pwd`

if [ ! -d zmk/app ]; then
    echo "ERROR: $PWD/zmk is missing. Run: git submodule update --init" >&2
    exit 1
fi

colima start
docker rm -f zmk-dev 2>/dev/null || true
output=$(devcontainer up --workspace-folder "$PWD/zmk")
container_id=$(echo "$output" | grep -o '"containerId":"[^"]*"' | cut -d'"' -f4)
current_name=$(docker inspect -f '{{.Name}}' "$container_id" | sed 's#^/##')
if [ "$current_name" != "zmk-dev" ]; then
    docker rename "$container_id" zmk-dev
fi

# git in the container runs as root, but the bind-mounted /workspaces/zmk tree
# (and anything west clones into it) belongs to the host user, so git refuses it
# as "dubious ownership". /root is a volume, so this setting persists.
docker exec zmk-dev git config --global --get-all safe.directory 2>/dev/null | grep -qx '\*' \
    || docker exec zmk-dev git config --global --add safe.directory '*'

if ! docker exec zmk-dev test -d /workspaces/zmk/.west; then
    echo "west workspace not found, running west init + west update..."
    # Skip the "optional" group (tflite-micro, thrift, ...): ZMK doesn't use it,
    # and it would be cloned into the bind mount rather than a volume.
    docker exec -w /workspaces/zmk zmk-dev bash -c \
        "west init -l app && west config manifest.group-filter -- -optional && west update"
fi

# Apply the local Zephyr / ZMK patches (patches/). Idempotent: already-applied
# patches are skipped, so this also covers a fresh clone or a new west update.
./local_patches.sh apply
