#! /bin/bash
# shellcheck disable=SC2086,SC2089,SC2090

set -o errexit -o nounset -o pipefail

BUFFER="${BUFFER:-"2h"}"               # safety margin added on top of the voting period
CI="${CI:-""}"                         # when set, skip the interactive confirmation
COMMIT_ID="$1"
CONTEXT="${CONTEXT:-"instagoric"}"
DEPOSIT_AMOUNT="${DEPOSIT_AMOUNT:-"500000000"}"
DEPOSIT_DENOM="${DEPOSIT_DENOM:-"ubld"}"
NAMESPACE="${NAMESPACE:-"devnet"}"
POD_NAME="${POD_NAME:-""}"
RPC="${RPC:-""}"                       # tendermint RPC; auto-derived from NAMESPACE if empty
SAMPLES="${SAMPLES:-"100"}"            # block span used to compute the mean block time
UPGRADE_DATE="${UPGRADE_DATE:-""}"     # target time, e.g. "2026-06-02 18:00:00 UTC"
UPGRADE_HEIGHT="${UPGRADE_HEIGHT:-""}" # explicit height wins over everything
UPGRADE_TO="$2"
VOID="/dev/null"
VOTING_PERIOD="${VOTING_PERIOD:-""}"   # e.g. "2h"; auto-detected from chain gov params if empty


# This script will find the first wallet that has the required assets
FIND_FUNDING_WALLET_SCRIPT="
  #! /usr/bin/env bash
  set -o errexit -o pipefail

  KEYS_JSON=\"\$(
      agd keys list --home \"/state/\$CHAIN_ID\" --keyring-backend \"test\" --output json
  )\"
  WALLET_COUNT=\"\$(echo \"\$KEYS_JSON\" | jq 'length')\"

  for i in \$(seq 0 \$((WALLET_COUNT - 1)))
  do
    NAME=\"\$(echo \"\$KEYS_JSON\" | jq --raw-output \".[\$i].name\")\"
    ADDRESS=\"\$(echo \"\$KEYS_JSON\" | jq --raw-output \".[\$i].address\")\"

    BALANCE_JSON=\"\$(agd query bank balances \"\$ADDRESS\" --home \"/state/\$CHAIN_ID\" --output json 2> $VOID || echo \"\")\"
    BAL=\"\$(echo \"\$BALANCE_JSON\" | jq --raw-output '.balances[] | select(.denom == \"$DEPOSIT_DENOM\") | .amount' 2> $VOID || echo \"\")\"

    if test -n \"\$BAL\" && test \"\$BAL\" -gt $DEPOSIT_AMOUNT
    then
      echo -n \"\$NAME\"
      break
    fi
  done
"

ZIP_URL="https://github.com/Agoric/agoric-sdk/archive/${COMMIT_ID}.zip"

CHECKSUM="sha256:$(
  curl "$ZIP_URL" --location --output - --silent | \
  shasum -a 256 | \
  cut -d ' ' -f 1
)"

UPGRADE_INFO="{
  \"binaries\": {
    \"any\": \"$ZIP_URL//agoric-sdk-${COMMIT_ID}?checksum=$CHECKSUM\"
  },
  \"source\": \"$ZIP_URL?checksum=$CHECKSUM\"
}"

# Guard against the classic footgun: a height that is not ahead of the tip
# would make the proposal a no-op.
assert_height_in_future() {
  local current

  current="$(rpc_current_height 2> "$VOID" || echo "")"

  if test -n "$current" && test "$UPGRADE_HEIGHT" -le "$current"
  then
    log_error "UPGRADE_HEIGHT=$UPGRADE_HEIGHT is not ahead of current height $current"
  fi

  CURRENT_HEIGHT="$current"
  test -n "$current" && BLOCKS_AHEAD="$((UPGRADE_HEIGHT - current))"
}

# Show the resolved parameters and require an explicit confirmation before
# submitting. Skipped when running non-interactively (CI set).
confirm_proposal_parameters() {
  local input="n"

  if test -n "$CI"
  then
    return
  fi

  printf "
Namespace:        %s
Context:          %s
Pod:              %s
RPC:              %s
Proposal:         %s
Commit:           %s
Deposit:          %s
Funding wallet:   %s
Upgrade height:   %s
Current height:   %s
Blocks ahead:     %s
Mean block time:  %s
Target time:      %s

Submit this upgrade proposal (y/Y)? " \
    "$NAMESPACE" \
    "$CONTEXT" \
    "$POD_NAME" \
    "$RPC" \
    "$UPGRADE_TO" \
    "$COMMIT_ID" \
    "$DEPOSIT_AMOUNT$DEPOSIT_DENOM" \
    "$FUNDING_WALLET" \
    "$UPGRADE_HEIGHT" \
    "${CURRENT_HEIGHT:-"unknown"}" \
    "${BLOCKS_AHEAD:-"unknown"}" \
    "${MEAN_BLOCK_TIME:-"n/a (height provided)"}" \
    "${TARGET_TIME:-"n/a (height provided)"}"

  read -r input

  if test "$input" != "y" && test "$input" != "Y"
  then
    log_error "Action cancelled by user"
  fi
}

# Parse an arbitrary date string to epoch seconds (GNU date, then BSD/macOS).
date_to_epoch() {
  date -d "$1" -u '+%s' 2> "$VOID" \
    || date -f '%Y-%m-%d %H:%M:%S' -j -u "${1% UTC}" '+%s'
}

derive_endpoints() {
  case "$NAMESPACE" in
    devnet)
      API_DEFAULT="https://devnet.api.agoric.net"
      POD_DEFAULT="validator-primary-0"
      RPC_DEFAULT="https://devnet.rpc.agoric.net:443"
      ;;
    emerynet)
      API_DEFAULT="https://emerynet.api.agoric.net"
      POD_DEFAULT="validator-primary-0"
      RPC_DEFAULT="https://emerynet.rpc.agoric.net:443"
      ;;
    ollinet)
      API_DEFAULT="https://ollinet.api.agoric.net"
      POD_DEFAULT="fork-0"
      RPC_DEFAULT="https://ollinet.rpc.agoric.net:443"
      ;;
    *)
      log_error "Unexpected namespace '$NAMESPACE' (expected one of: devnet, emerynet, ollinet)"
      ;;
  esac

  test -z "$RPC" && RPC="$RPC_DEFAULT"
  test -z "$POD_NAME" && POD_NAME="$POD_DEFAULT"
}

# Convert a Go-ish duration ("7200s", "2h", "1h30m", or a bare number of
# seconds) into an integer number of seconds. No regex, so it stays friendly
# to `test`-style bash.
duration_to_seconds() {
  local d="$1"
  local num
  local rest
  local total="0"
  local unit

  # A bare integer is already seconds.
  case "$d" in
    '') echo -n 0 && return ;;
    *[!0-9]*) ;;
    *) echo -n "$d" && return ;;
  esac

  while test -n "$d"
  do
    num="${d%%[!0-9]*}" # leading digits
    test -z "$num" && break
    rest="${d#"$num"}"          # remainder, starts with the unit char
    unit="${rest%"${rest#?}"}"  # first char of remainder
    d="${rest#?}"               # drop the unit char
    case "$unit" in
      s) total=$((total + num)) ;;
      m) total=$((total + num * 60)) ;;
      h) total=$((total + num * 3600)) ;;
      d) total=$((total + num * 86400)) ;;
      *) ;;
    esac
  done

  echo -n "$total"
}

estimate_upgrade_height() {
  local h0
  local h1
  local ms
  local now
  local secs_until
  local span
  local t0
  local t1
  local target_epoch

  if test -z "$RPC"
  then
    log_error "Could not derive an RPC endpoint for namespace '$NAMESPACE'. Set RPC=..."
  fi

  # Auto-detect the on-chain voting period if the caller did not pin one.
  if test -z "$VOTING_PERIOD" && test -n "$API_DEFAULT"
  then
    VOTING_PERIOD="$(
      curl --max-time "20" --silent "$API_DEFAULT/cosmos/gov/v1/params/voting" \
        | jq --raw-output '.params.voting_period // .voting_params.voting_period // empty' 2> "$VOID" || echo ""
    )"
  fi

  if test -z "$VOTING_PERIOD"
  then
    VOTING_PERIOD="2h"
    log_warning "Falling back to VOTING_PERIOD=2h (could not read it from chain)."
  fi

  # Resolve the target wall-clock time (as epoch seconds).
  now="$(date -u '+%s')"

  if test -n "$UPGRADE_DATE"
  then
    target_epoch="$(date_to_epoch "$UPGRADE_DATE")"
  else
    target_epoch=$((now + $(duration_to_seconds "$VOTING_PERIOD") + $(duration_to_seconds "$BUFFER")))
  fi

  secs_until=$((target_epoch - now))

  # Mirror the estimator's warning: need at least votingPeriod + 1h of runway.
  if test "$secs_until" -lt "$(($(duration_to_seconds "$VOTING_PERIOD") + 3600))"
  then
    log_warning "Only ${secs_until}s until target; that may be too soon for the voting period"
  fi

  # Sample two block timestamps SAMPLES apart and take the mean block time.
  h1="$(rpc_current_height)"

  h0=$((h1 - SAMPLES))

  t0="$(iso_to_epoch "$(rpc_block_time "$h0")")"
  t1="$(iso_to_epoch "$(rpc_block_time "$h1")")"

  span=$((t1 - t0))

  if test "$span" -le 0
  then
    log_error "Bad block-time sample (span=${span}s). Try a larger SAMPLES"
  fi

  ms=$((span * 1000 / SAMPLES)) # mean block time, milliseconds
  UPGRADE_HEIGHT=$((h1 + secs_until * SAMPLES / span))

  MEAN_BLOCK_TIME="~$((ms / 1000)).$(printf '%02d' $(((ms % 1000) / 10)))s over $SAMPLES blocks"
  TARGET_TIME="$(date -u -d "@$target_epoch" '+%Y-%m-%d %H:%M:%S UTC' 2> "$VOID" || date -u -r "$target_epoch" '+%Y-%m-%d %H:%M:%S UTC') (voting $VOTING_PERIOD + buffer $BUFFER)"
}

execute_command_inside_pod() {
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

# Parse an RFC3339 block timestamp (e.g. 2026-06-02T08:52:02.5Z) to epoch
# seconds, tolerating the fractional part and trailing Z.
iso_to_epoch() {
  local clean="${1%Z}"

  clean="${clean%.*}"

  date -d "$clean" -u '+%s' 2> "$VOID" \
    || date -f '%Y-%m-%dT%H:%M:%S' -j -u "$clean" '+%s'
}

log_error() {
    printf "\033[31m[FATAL] %s\033[0m\n" "$1"
    exit 1
}

log_info() {
    echo "[INFO] $1"
}

log_warning() {
    printf "\033[33m[WARN] %s\033[0m\n" "$1"
}

main() {
  derive_endpoints

  FUNDING_WALLET="$(execute_command_inside_pod "$FIND_FUNDING_WALLET_SCRIPT")"

  if test -z "$FUNDING_WALLET"
  then
    log_error "No wallet found with the $DEPOSIT_AMOUNT$DEPOSIT_DENOM assets, can not submit the upgrade proposal"
  fi

  if test -z "$UPGRADE_HEIGHT"
  then
    estimate_upgrade_height
  fi

  assert_height_in_future
  confirm_proposal_parameters

  log_info "Submitting upgrade proposal '$UPGRADE_TO' to be executed at height '$UPGRADE_HEIGHT'"

  execute_command_inside_pod "
    agd tx upgrade software-upgrade \"$UPGRADE_TO\" \
     --broadcast-mode \"sync\" \
     --chain-id \"\$CHAIN_ID\" \
     --deposit \"$DEPOSIT_AMOUNT$DEPOSIT_DENOM\" \
     --from \"$FUNDING_WALLET\" \
     --gas \"auto\" \
     --keyring-backend \"test\" \
     --home \"/state/\$CHAIN_ID\" \
     --summary \"This proposal if voted will upgrade the chain to $UPGRADE_TO\" \
     --title \"Upgrade to $UPGRADE_TO\" \
     --upgrade-height \"$UPGRADE_HEIGHT\" \
     --upgrade-info $(echo -n $UPGRADE_INFO | jq --raw-input --slurp .) \
     --yes
  "
}

rpc_current_height() {
  curl --max-time "20" --silent "$RPC/status" \
    | jq --raw-output '.result.sync_info.latest_block_height'
}

rpc_block_time() {
  curl --max-time "20" --silent "$RPC/block?height=$1" \
    | jq --raw-output '.result.block.header.time'
}

main
