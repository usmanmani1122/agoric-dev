#! /bin/bash
# shellcheck disable=SC1091,SC2086,SC2115

set -o errexit

CURRENT_DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SDK_SRC="${SDK_SRC:-"/workspace/repositories/agoric-sdk"}"

CLI_PATH="$SDK_SRC/packages/agoric-cli"

check_for_dependencies() {
    if ! test -d "$SDK_SRC"; then
        log_error "[FATAL] $SDK_SRC not a valid SDK source"
        exit 1
    fi
    SDK_SRC="$(readlink --canonicalize "$SDK_SRC")"

    if ! which make >/dev/null; then
        log_error "[FATAL] make not installed"
        exit 1
    fi

    if ! which node >/dev/null || ! which yarn >/dev/null; then
        if test -n "$NVM_DIR"; then
            source "$NVM_DIR/nvm.sh"
        else
            log_error "[FATAL] yarn or node not installed"
            exit 1
        fi
    fi
}

create_and_link_builds() {
    make --directory "$SDK_SRC/packages/cosmic-swingset" all
    yarn --cwd "$CLI_PATH" build
    ln --force --symbolic \
        "$CLI_PATH/bin/agoric" \
        "$CLI_PATH/bin/agops" \
        /usr/local/bin/
}

log_error() {
    printf "\033[31m%s\033[0m\n" "$1"
}

rm --force --recursive $SDK_SRC/golang/cosmos/build/*
check_for_dependencies
create_and_link_builds
"$CURRENT_DIRECTORY_PATH/check-binaries.sh"
