#! /bin/bash

curl --silent \
    "https://raw.githubusercontent.com/Agoric/agoric-sdk/refs/heads/master/scripts/smoketest-binaries.sh" |
    /bin/bash >/dev/null

if ! agops --version >/dev/null 2>&1; then
    echo "agops binary not found"
    exit 1
fi
