#!/bin/bash

cd `dirname $0`
PWD=`pwd`

colima start
docker rm -f zmk-dev 2>/dev/null || true
output=$(devcontainer up --workspace-folder "$PWD/zmk")
container_id=$(echo "$output" | grep -o '"containerId":"[^"]*"' | cut -d'"' -f4)
current_name=$(docker inspect -f '{{.Name}}' "$container_id" | sed 's#^/##')
if [ "$current_name" != "zmk-dev" ]; then
    docker rename "$container_id" zmk-dev
fi

if ! docker exec zmk-dev test -d /workspaces/zmk/.west; then
    echo "west workspace not found, running west init + west update..."
    docker exec -w /workspaces/zmk zmk-dev bash -c "west init -l app && west update"
fi
