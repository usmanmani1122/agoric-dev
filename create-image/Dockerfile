# Use the official DevContainers ubuntu base image
FROM mcr.microsoft.com/devcontainers/base:0-ubuntu-22.04


SHELL ["/bin/bash", "-c"]


########################################################
# Starting Miscellaneous installations                 #
########################################################
RUN <<-DOCKER_SCRIPT
    #!/bin/bash

    set -o errexit -o errtrace -o nounset -o pipefail

    apt-get update
    apt-get install \
     apt-transport-https \
     build-essential \
     ca-certificates \
     clang \
     curl \
     expect \
     g++ \
     gcc \
     git \
     gnupg \
     jq \
     less \
     libc6-dev \
     libssl-dev \
     make \
     mercurial \
     netbase \
     nginx \
     openssh-client \
     pkg-config \
     procps \
     python3 \
     subversion \
     vim \
     xvfb \
     --yes
    apt-get clean --yes

    rm --force --recursive /var/lib/apt/lists/*

    apt-get update
    apt-get install python3-pip --yes
    rm --force --recursive /var/lib/apt/lists/*

    python3 -m pip install sqlite-web==0.6.4

    cat <<'SQLITE_WEB'> /usr/local/bin/sqlite_web
#! /usr/bin/python3
# -*- coding: utf-8 -*-

import re
import sys
from sqlite_web.sqlite_web import main

if __name__ == "__main__":
    sys.argv[0] = re.sub(r"(-script\.pyw|\.exe)?$", "", sys.argv[0])
    sys.exit(main())
SQLITE_WEB
DOCKER_SCRIPT
########################################################
# Finished Miscellaneous installations                 #
########################################################


########################################################
# Starting installation of Go lang                     #
########################################################
ARG TARGETPLATFORM
ENV GOLANG_VERSION=1.23.4
ENV GOPATH=/go
ENV GOTOOLCHAIN=local
ENV PATH="${GOPATH}/bin:/usr/local${GOPATH}/bin:${PATH}"

# Refer to https://go.dev/dl for checksums
RUN <<-DOCKER_SCRIPT
    #!/bin/bash

    set -o errexit -o errtrace -o nounset -o pipefail

    AMD_CHECKSUM="6924efde5de86fe277676e929dc9917d466efa02fb934197bc2eba35d5680971"
    ARM_CHECKSUM="16e5017863a7f6071363782b1b8042eb12c6ca4f4cd71528b2123f0a1275b13e"

    case "$TARGETPLATFORM" in
        "linux/amd64")
            GOARCH="amd64"
            CHECKSUM="$AMD_CHECKSUM"
            ;;
        "linux/arm64")
            GOARCH="arm64"
            CHECKSUM="$ARM_CHECKSUM"
            ;;
        *)
            echo "Unsupported target platform: $TARGETPLATFORM"
            exit 1
            ;;
    esac

    export GNUPGHOME="$(mktemp --directory)"

    url="https://dl.google.com/go/go$GOLANG_VERSION.linux-$GOARCH.tar.gz"

    curl "$url.asc" --output "go.tgz.asc"
    curl "$url" --output "go.tgz"
    echo "$CHECKSUM *go.tgz" | sha256sum --check -

    gpg --batch --keyserver "keyserver.ubuntu.com" --recv-keys "EB4C 1BFD 4F04 2F6D DDCC EC91 7721 F63B D38B 4796"
    gpg --batch --keyserver "keyserver.ubuntu.com" --recv-keys "2F52 8D36 D67B 69ED F998 D857 78BD 6547 3CB3 BD13"
    gpg --batch --verify "go.tgz.asc" "go.tgz"
    gpgconf --kill all
    rm --force --recursive "$GNUPGHOME" "go.tgz.asc"
    tar --directory "/usr/local" --extract --file "go.tgz" --gzip
    rm --force "go.tgz"

    mkdir --parents "$GOPATH/src" "$GOPATH/bin"
    chmod --recursive 777 "$GOPATH"

    echo "go version: $(go version)"
DOCKER_SCRIPT
########################################################
# Finished installation of Go lang                     #
########################################################


########################################################
# Starting installation of Node                        #
########################################################
ENV NODE_VERSION=20.9.0
ENV NVM_DIR=/usr/local/nvm
ENV NVM_VERSION=0.40.1
ENV PROFILE=/root/.bashrc

RUN <<-DOCKER_SCRIPT
    #!/bin/bash

    set -o errexit -o errtrace -o nounset -o pipefail

    mkdir --parents "$NVM_DIR"
    touch "$PROFILE"
    curl "https://raw.githubusercontent.com/nvm-sh/nvm/v$NVM_VERSION/install.sh" \
     --output - | bash

    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    
    npm install --global node-gyp yarn
    corepack enable
    
    echo "nvm version: $(nvm --version)"
    echo "node version: $(node --version)"
    echo "npm version: $(npm --version)"
    echo "yarn version: $(yarn --version)"
DOCKER_SCRIPT
########################################################
# Finished installation of Node                        #
########################################################


########################################################
# Starting installation of Ping Pub Explorer           #
########################################################
ENV API_PORT=1317
ENV CHAIN_EXPLORER_PORT=30000
ENV PING_PUB_SOURCE=/usr/src/ping-pub
ENV RPC_PORT=26657
ENV SQLITE_EXPLORER_PORT=30001

RUN <<-DOCKER_SCRIPT
    #!/bin/bash

    set -o errexit -o errtrace -o nounset -o pipefail

    COMMIT_HASH="4d2d093560c52e08458f97f451dc1f0690e00094"
    EXPLORER_FILES_BASE_URL="https://raw.githubusercontent.com/Agoric/instagoric/refs/heads/main/bases/explorer"
    PING_PUB_REPOSITORY_LINK="https://github.com/ping-pub/explorer.git"

    LOGOS_DIRECTORY="$PING_PUB_SOURCE/dist/logos"

    build() {
        yarn --cwd "$PING_PUB_SOURCE"
        yarn --cwd "$PING_PUB_SOURCE" build
    }

    commit_changes() {
        git -C "$PING_PUB_SOURCE" add .
        git -C "$PING_PUB_SOURCE" commit --message "patches" --no-verify
    }

    get_files() {
        curl "$EXPLORER_FILES_BASE_URL/config.patch" --fail --location --output "$HOME/ping-pub.patch" --silent
        curl "$EXPLORER_FILES_BASE_URL/agoric.json" --fail --location --output "$HOME/agoric.json" --silent
    }

    get_logos() {
        mkdir --parents "$LOGOS_DIRECTORY"
        curl "$EXPLORER_FILES_BASE_URL/agoric.png" --fail --location --output "$LOGOS_DIRECTORY/agoric.png" --silent
        curl "$EXPLORER_FILES_BASE_URL/agoric-bld.svg" --fail --location --output "$LOGOS_DIRECTORY/agoric-bld.svg" --silent
    }

    set_chain_data() {
        rm --force $PING_PUB_SOURCE/chains/mainnet/*.json $PING_PUB_SOURCE/chains/testnet/*.json
        jq '.api[] = "/api" | .rpc[] = "/rpc"' --raw-output < "$HOME/agoric.json" > "$PING_PUB_SOURCE/chains/mainnet/agoric.json"
        rm --force "$HOME/agoric.json"
    }

    setup_repository() {
        mkdir --parents "$PING_PUB_SOURCE"

        git clone "$PING_PUB_REPOSITORY_LINK" "$PING_PUB_SOURCE"
        git -C "$PING_PUB_SOURCE" checkout "$COMMIT_HASH"
        git -C "$PING_PUB_SOURCE" config user.email "root@ubuntu.com"
        git -C "$PING_PUB_SOURCE" config user.name "root"

        patch --directory "$PING_PUB_SOURCE" --input "$HOME/ping-pub.patch" --strip "1"
        sed "$PING_PUB_SOURCE/vite.config.ts" \
            --expression "s|\$RPCNODES_SERVICE_HOST|localhost|" \
            --expression "s|\$RPCNODES_SERVICE_PORT_API|$API_PORT|" \
            --expression "s|\$RPCNODES_SERVICE_PORT_RPC|$RPC_PORT|" \
            --in-place

        rm --force "$HOME/ping-pub.patch"
    }

    . "$NVM_DIR/nvm.sh"
    get_files
    setup_repository
    set_chain_data
    commit_changes
    build
    get_logos
DOCKER_SCRIPT
########################################################
# Finished installation of Ping Pub Explorer           #
########################################################
