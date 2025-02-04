#! /bin/bash

set -o errexit -o errtrace -o nounset

sqlite_web \
 --host "0.0.0.0" \
 --no-browser \
 --port "$SQLITE_EXPLORER_PORT" \
 --query-rows-per-page "10" \
 --read-only "$1" \
 --rows-per-page "10"
