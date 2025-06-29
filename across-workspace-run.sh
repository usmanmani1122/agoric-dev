#! /bin/bash

set -o errexit -o nounset

args=("${@:2}")
command="$1"
workspaces=$(yarn workspaces list --json | jq 'select(.location != ".") | .location' --raw-output)

for workspace in $workspaces; do
    echo "> $command ${args[*]} $workspace"
    "$command" "${args[@]}" "$workspace"
done