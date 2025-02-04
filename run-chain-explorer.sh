#! /bin/bash
# shellcheck disable=SC1091

set -o errexit -o errtrace -o nounset

source "$NVM_DIR/nvm.sh"

yarn \
 --cwd "$PING_PUB_SOURCE" \
 serve \
  --host \
  --port "$CHAIN_EXPLORER_PORT"
