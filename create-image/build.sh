#!/bin/bash

ARCH="$(uname -m)"
DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
DOCKER_PLATFORM=""

case "$ARCH" in
  arm64|aarch64)
    DOCKER_PLATFORM="linux/arm64"
    ;;
  x86_64)
    DOCKER_PLATFORM="linux/amd64"
    ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

docker buildx build \
  --file "$DIRECTORY_PATH/Dockerfile" \
  --platform "$DOCKER_PLATFORM" \
  --tag "agoric-custom-dev:latest" \
  .
