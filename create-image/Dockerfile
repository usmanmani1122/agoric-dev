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

    case "$TARGETPLATFORM" in
        "linux/amd64")
            GOARCH="amd64"
            ;;
        "linux/arm64")
            GOARCH="arm64"
            ;;
        *)
            echo "Unsupported target platform: $TARGETPLATFORM"
            exit 1
            ;;
    esac

    export GNUPGHOME="$(mktemp --directory)"
    GO_FILENAME="go${GOLANG_VERSION}.linux-${GOARCH}.tar.gz"

    sha256="$(
        curl "https://go.dev/dl/?mode=json" --silent | \
        jq --arg GO_FILENAME "$GO_FILENAME" --raw-output \
         '.[].files[] | select(.filename == $GO_FILENAME) | .sha256'
    )"
    url="https://dl.google.com/go/$GO_FILENAME"

    curl "$url.asc" --output "go.tgz.asc"
    curl "$url" --output "go.tgz"
    echo "$sha256 *go.tgz" | sha256sum --check -

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

    mkdir --parents "$PING_PUB_SOURCE"
    git clone "https://github.com/ping-pub/explorer.git" "$PING_PUB_SOURCE"

    rm $PING_PUB_SOURCE/chains/mainnet/*.json $PING_PUB_SOURCE/chains/testnet/*.json

    cat <<JSON_EOF> "$PING_PUB_SOURCE/chains/mainnet/agoric.json"
{
    "addr_prefix": "agoric",
    "api": ["http://localhost:$CHAIN_EXPLORER_PORT/api"],
    "assets": [
        {
            "base": "ubld",
            "coingecko_id": "agoric",
            "exponent": "6",
            "logo": "",
            "symbol": "BLD"
        },
        {
            "base": "uist",
            "coingecko_id": "",
            "exponent": "6",
            "logo": "",
            "symbol": "IST"
        }
    ],
    "chain_name": "agoric",
    "coin_type": "564",
    "coingecko": "agoric",
    "logo": "https://agoric.explorers.guru/chains/agoric.svg",
    "min_tx_fee": "8000",
    "rpc": ["http://localhost:$CHAIN_EXPLORER_PORT/rpc"],
    "sdk_version": "0.45.4",
    "theme_color": "#812CD6"
}
JSON_EOF

cat <<JS_EOF> "$PING_PUB_SOURCE/vite.config.ts"
import { fileURLToPath, URL } from 'node:url';

import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import vueJsx from '@vitejs/plugin-vue-jsx';
import Layouts from 'vite-plugin-vue-layouts';
import DefineOptions from 'unplugin-vue-define-options/vite';
import AutoImport from 'unplugin-auto-import/vite';
import Pages from 'vite-plugin-pages';

import VueI18nPlugin from '@intlify/unplugin-vue-i18n/vite';

export default defineConfig({
    define: {
        'process.env': {},
    },
    plugins: [
        vue({
            template: {
                compilerOptions: {
                isCustomElement: (tag) =>
                    [
                    'ping-connect-wallet',
                    'ping-token-convert',
                    'ping-tx-dialog',
                    ].includes(tag),
                },
            },
        }),
        vueJsx(),
        Pages({
            dirs: ['./src/modules', './src/pages'],
            exclude: ['**/*.ts'],
        }),
        Layouts({
            layoutsDirs: './src/layouts/',
        }),
        AutoImport({
            imports: [
                'vue',
                'vue-router',
                '@vueuse/core',
                '@vueuse/math',
                'vue-i18n',
                'pinia',
            ],
            vueTemplate: true,
        }),
        VueI18nPlugin({
            runtimeOnly: true,
            compositionOnly: true,
            include: [
                fileURLToPath(
                    new URL('./src/plugins/i18n/locales/**', import.meta.url)
                ),
            ],
        }),
        DefineOptions(),
    ],
    resolve: {
        alias: {
            '@': fileURLToPath(new URL('./src', import.meta.url)),
        },
    },
    optimizeDeps: {
        entries: ['./src/**/*.vue'],
    },
    server: {
        proxy: {
            '^/api/.*': {
                target: 'http://localhost:$API_PORT',
                changeOrigin: true,
                rewrite: (path) => path.replace(/^\/api*/g, "")
            },
            '^/rpc/.*': {
                target: 'http://localhost:$RPC_PORT',
                changeOrigin: true,
                rewrite: (path) => path.replace(/^\/rpc*/g, "")
            },
        },
    },
});
JS_EOF

    . "$NVM_DIR/nvm.sh"
    yarn --cwd "$PING_PUB_SOURCE"
    yarn --cwd "$PING_PUB_SOURCE" build
DOCKER_SCRIPT
########################################################
# Finished installation of Ping Pub Explorer           #
########################################################
