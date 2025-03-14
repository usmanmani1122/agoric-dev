# Use the official DevContainers ubuntu base image
FROM mcr.microsoft.com/devcontainers/base:0-ubuntu-22.04


SHELL ["/bin/bash", "-c"]


########################################################
# Starting Miscellaneous installations                 #
########################################################
RUN <<-DOCKER_SCRIPT
    #!/bin/bash

    set -o errexit -o errtrace -o nounset -o pipefail

    # add gcloud source
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor --output /usr/share/keyrings/cloud.google.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | \
    tee --append /etc/apt/sources.list.d/google-cloud-sdk.list

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
     google-cloud-cli \
     google-cloud-sdk-gke-gcloud-auth-plugin \
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

    # install kubectl
    KUBECTL_RELEASE_VERSION="$(curl --location --silent https://dl.k8s.io/release/stable.txt)"

    curl "https://dl.k8s.io/release/$KUBECTL_RELEASE_VERSION/bin/linux/amd64/kubectl" \
     --location --remote-name
    curl "https://dl.k8s.io/release/$KUBECTL_RELEASE_VERSION/bin/linux/amd64/kubectl.sha256" \
     --location --remote-name

    echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
    install --group root --mode 0755 --owner root \
     kubectl /usr/local/bin/kubectl

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

    gcloud version
    kubectl version --client
DOCKER_SCRIPT
########################################################
# Finished Miscellaneous installations                 #
########################################################


########################################################
# Starting installation of Go lang                     #
########################################################
ARG TARGETPLATFORM
ENV GOLANG_VERSION=1.22.12
ENV GOPATH=/go
ENV GOTOOLCHAIN=local
ENV PATH="${GOPATH}/bin:/usr/local${GOPATH}/bin:${PATH}"

RUN <<-DOCKER_SCRIPT
    #!/bin/bash

    set -o errexit -o errtrace -o nounset -o pipefail

    AMD_CHECKSUM="4fa4f869b0f7fc6bb1eb2660e74657fbf04cdd290b5aef905585c86051b34d43"
    ARM_CHECKSUM="fd017e647ec28525e86ae8203236e0653242722a7436929b1f775744e26278e7"

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
