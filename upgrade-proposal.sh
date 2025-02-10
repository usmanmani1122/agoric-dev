#! /bin/bash
# shellcheck disable=SC2086,SC2089,SC2090

set -o errexit -o pipefail

CLUSTER_NAME="${CLUSTER_NAME:-"devnet"}"
COMMIT_ID="$1"
DEPOSIT_AMOUNT="500000000"
DEPOSIT_DENOM="ubld"

# This script will find the first wallet that has the required assets
FIND_FUNDING_WALLET_SCRIPT="
  #!/usr/bin/env bash
  set -o errexit -o pipefail

  KEYS_JSON=\"\$(
      agd keys list --home \"/state/\$CHAIN_ID\" --keyring-backend \"test\" --output json
  )\"
  WALLET_COUNT=\"\$(echo \"\$KEYS_JSON\" | jq 'length')\"

  for i in \$(seq 0 \$((WALLET_COUNT - 1)))
  do
    NAME=\"\$(echo \"\$KEYS_JSON\" | jq --raw-output \".[\$i].name\")\"
    ADDRESS=\"\$(echo \"\$KEYS_JSON\" | jq --raw-output \".[\$i].address\")\"

    BALANCE_JSON=\"\$(agd query bank balances \"\$ADDRESS\" --home \"/state/\$CHAIN_ID\" --output json 2>/dev/null || echo \"\")\"
    BAL=\"\$(echo \"\$BALANCE_JSON\" | jq --raw-output '.balances[] | select(.denom == \"$DEPOSIT_DENOM\") | .amount' 2>/dev/null || echo \"\")\"

    if [ -n \"\$BAL\" ] && [ \"\$BAL\" -gt $DEPOSIT_AMOUNT ]
    then
      echo -n \"\$NAME\"
      break
    fi
  done
"
NAMESPACE="${NAMESPACE:-"instagoric"}"
POD_NAME="${POD_NAME:-"validator-primary-0"}"
PROJECT_NAME="simulationlab"
REGION="us-central1"
UPGRADE_TO="$2"

CONTEXT="gke_${PROJECT_NAME}_${REGION}_${CLUSTER_NAME}"
ZIP_URL="https://github.com/Agoric/agoric-sdk/archive/${COMMIT_ID}.zip"

CHECKSUM="sha256:$(curl "$ZIP_URL" --location --output - --silent | shasum -a 256 | cut -d ' ' -f 1)"

UPGRADE_INFO="{
  \"binaries\": {
    \"any\": \"$ZIP_URL//agoric-sdk-${COMMIT_ID}?checksum=$CHECKSUM\"
  },
  \"source\": \"$ZIP_URL?checksum=$CHECKSUM\"
}"

execute_command_inside_pod() {
  kubectl config get-contexts "$CONTEXT" >/dev/null 2>&1 ||
    gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION"

  local command=$1

  kubectl exec "$POD_NAME" \
    --container "node" \
    --context "$CONTEXT" \
    --namespace "$NAMESPACE" \
    --stdin \
    --tty \
    -- \
    /bin/bash -c "$command"
}

main() {
  FUNDING_WALLET="$(execute_command_inside_pod "$FIND_FUNDING_WALLET_SCRIPT")"

  if test -z "$FUNDING_WALLET"; then
    echo "[FATAL] No wallet found with the $DEPOSIT_AMOUNT$DEPOSIT_DENOM assets, can not submit the upgrade proposal"
    exit 1
  fi

  if test -z "$UPGRADE_HEIGHT"; then
    UPGRADE_HEIGHT="$(
      execute_command_inside_pod \
        "echo -n \$((\$(agd status | jq --raw-output '.SyncInfo.latest_block_height') + 100))"
    )"
  fi

  execute_command_inside_pod "
    agd tx gov submit-proposal software-upgrade \"$UPGRADE_TO\" \
     --broadcast-mode \"block\" \
     --chain-id \"\$CHAIN_ID\" \
     --deposit \"$DEPOSIT_AMOUNT$DEPOSIT_DENOM\" \
     --description \"This proposal if voted will upgrade the chain to $UPGRADE_TO\" \
     --from \"$FUNDING_WALLET\" \
     --gas \"auto\" \
     --keyring-backend \"test\" \
     --home \"/state/\$CHAIN_ID\" \
     --title \"Upgrade to $UPGRADE_TO\" \
     --upgrade-height \"$UPGRADE_HEIGHT\" \
     --upgrade-info $(echo -n $UPGRADE_INFO | jq --raw-input --slurp .) \
     --yes
  "
}

main
