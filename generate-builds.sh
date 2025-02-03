#!/bin/bash
# shellcheck disable=SC1091,SC2086,SC2115

set -o errexit -o nounset

CURRENT_DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SDK_SRC="${SDK_SRC:-"/workspace/repositories/agoric-sdk"}"

CLI_PATH="$SDK_SRC/packages/agoric-cli"

source "$NVM_DIR/nvm.sh"

rm --force --recursive $SDK_SRC/golang/cosmos/build/*

make --directory "$SDK_SRC/packages/cosmic-swingset" all
yarn --cwd "$CLI_PATH" build

ln --force --symbolic \
 "$CLI_PATH/bin/agoric" \
 "$CLI_PATH/bin/agops" \
 /usr/local/bin/

"$CURRENT_DIRECTORY_PATH/check-binaries.sh"
