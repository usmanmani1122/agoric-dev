#! /bin/bash

set -o errexit -o pipefail

EXTRA_ARGS=()
IMAGE="agoric-custom-dev:latest"
PROFILE="/bin/bash"
WORKING_DIRECTORY="/"

while [[ $# -gt 0 ]]; do
  case "$1" in
  -i | --image)
    IMAGE="$2"
    shift 2
    ;;
  --image=*)
    IMAGE="${1#*=}"
    shift
    ;;
  -p | --profile)
    PROFILE="$2"
    shift 2
    ;;
  --profile=*)
    PROFILE="${1#*=}"
    shift
    ;;
  -w | --working-directory)
    WORKING_DIRECTORY="$2"
    shift 2
    ;;
  --working-directory=*)
    WORKING_DIRECTORY="${1#*=}"
    shift
    ;;
  *)
    EXTRA_ARGS=("$@")
    break
    ;;
  esac
done

CONTAINER_ID=$(docker ps --all --filter "ancestor=$IMAGE" --quiet)

if test -z "$CONTAINER_ID"; then
  echo "No container found with image '$IMAGE'"
  exit 1
fi

docker exec \
  --interactive \
  --tty \
  --workdir "$WORKING_DIRECTORY" \
  "$CONTAINER_ID" \
  "$PROFILE" \
  "${EXTRA_ARGS[@]}"
