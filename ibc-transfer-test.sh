#! /bin/bash
# shellcheck disable=SC2046,SC2086,SC2089,SC2090

set -o errexit -o nounset -o pipefail

# --- configuration (env-overridable) ----------------------------------------

AMOUNT="${AMOUNT:-"1"}"                               # integer amount to send (micro-denom)
API="${API:-"https://emerynet.api.agoric.net"}"       # source-chain LCD/REST
SRC_CHAIN_ID=""                                       # resolved from the node (RPC/status, then API); env CHAIN_ID ignored
CI="${CI:-""}"                                        # when set, skip the confirmation prompt
COUNTERPARTY_API="${COUNTERPARTY_API:-""}"            # counterparty LCD/REST (needed for authoritative pass)
COUNTERPARTY_CHAIN_ID="${1:-""}"                      # e.g. osmo-test-5  (positional arg)
DENOM="${DENOM:-"ubld"}"                              # source-chain base denom to send
FROM="${FROM:-""}"                                    # source keyring key name / address
GAS_PRICES="${GAS_PRICES:-"0.01ubld"}"                # source-chain gas price
HOME_DIR="${HOME_DIR:-""}"
KEYRING_BACKEND="${KEYRING_BACKEND:-"test"}"          # source keyring backend
POLL_INTERVAL="${POLL_INTERVAL:-"5"}"                 # seconds between status polls
POLL_TIMEOUT="${POLL_TIMEOUT:-"300"}"                 # seconds to wait for the ack (keep < TIMEOUT_MINUTES*60)
PORT="${PORT:-"transfer"}"                            # ICS-20 port
RECEIVER="${RECEIVER:-""}"                            # bech32 address on the counterparty
RPC="${RPC:-"https://emerynet.rpc.agoric.net"}"       # source CometBFT RPC
TIMEOUT_MINUTES="${TIMEOUT_MINUTES:-"30"}"            # IBC packet timeout (relative, from now)
VOID="/dev/null"

# Optional return ("on chain") leg. Provide ALL of B_BINARY/B_FROM/B_NODE/
# B_GAS_PRICES to run it automatically; otherwise the command is printed.
B_BINARY="${B_BINARY:-""}"                            # e.g. osmosisd
B_FROM="${B_FROM:-""}"                                # key name on the counterparty
B_NODE="${B_NODE:-""}"                                # counterparty RPC
B_GAS_PRICES="${B_GAS_PRICES:-""}"                    # e.g. 0.025uosmo
B_KEYRING_BACKEND="${B_KEYRING_BACKEND:-"test"}"
B_HOME_DIR="${B_HOME_DIR:-""}"

# --- logging -----------------------------------------------------------------

log_error() {
  printf "\033[31m[FATAL] %s\033[0m\n" "$1" >&2
  exit 1
}

log_info() {
  echo "[INFO] $1"
}

log_success() {
  printf "\033[32m[OK] %s\033[0m\n" "$1"
}

log_warning() {
  printf "\033[33m[WARN] %s\033[0m\n" "$1" >&2
}

# --- integer comparison for cosmos balances (length-prefixed, then numeric) --

# int_ge A B / int_gt A B -> exit 0 if true; exit 2 if either side is non-numeric.
int_ge() {
  local a
  local b

  a="$(_norm "${1:-""}")"
  b="$(_norm "${2:-""}")"

  if test "$a" == "NaN" || test "$b" == "NaN"
  then
    return 2
  fi

  if test "${#a}" -ne "${#b}"
  then
    test "${#a}" -gt "${#b}"
    return
  fi

  ! test "$a" -lt "$b"
}

int_gt() {
  local a
  local b

  a="$(_norm "${1:-""}")"
  b="$(_norm "${2:-""}")"

  if test "$a" == "NaN" || test "$b" == "NaN"
  then
    return 2
  fi

  if test "${#a}" -ne "${#b}"
  then
    test "${#a}" -gt "${#b}"
    return
  fi

  test "$a" -gt "$b"
}

# Normalize a non-negative integer string (strip leading zeros) or print NaN.
_norm() {
  local x="${1:-""}"

  case "$x" in
    ''|*[!0-9]*) printf 'NaN' && return ;;
  esac

  while test "${#x}" -gt 1
  do
    case "$x" in
      0*) x="${x#0}" ;;
      *) break ;;
    esac
  done

  printf '%s' "$x"
}

# --- small REST/CLI helpers --------------------------------------------------

# `agd` flags common to every query/tx, kept in one place.
agd_common() {
  echo -n "--chain-id $SRC_CHAIN_ID --home $HOME_DIR --keyring-backend $KEYRING_BACKEND --node $RPC"
}

api_get() {
  curl --max-time "20" --silent "$API$1" 2> "$VOID" || echo ""
}

counterparty_balance() {
  local out

  out="$(
    curl --max-time "20" --silent "$COUNTERPARTY_API/cosmos/bank/v1beta1/balances/$1/by_denom?denom=$2" 2> "$VOID" \
    | jq --raw-output '.balance.amount // "0"' 2> "$VOID"
  )" || true

  printf '%s' "$out"
}

# Voucher denom on the COUNTERPARTY: ibc/ + UPPER(sha256("transfer/<channel>/<denom>")),
# where <channel> is the receiving chain's channel (= source channel's
# counterparty.channel_id, i.e. B_CHANNEL). Only valid for a base denom.
ibc_denom_hash() {
  local hex
  local path

  case "$DENOM" in
    ibc/*) log_error "ibc_denom_hash only supports a base denom, got '$DENOM'" ;;
  esac

  path="$PORT/$B_CHANNEL/$DENOM"

  hex="$(
    printf '%s' "$path" | \
    shasum -a 256 2> "$VOID" | \
    cut -d ' ' -f 1
  )"

  test -z "$hex" && hex="$(
    printf '%s' "$path" | \
    sha256sum | \
    cut -d ' ' -f 1
  )"
  echo -n "ibc/$(
    echo -n "$hex" | \
    tr '[:lower:]' '[:upper:]'
  )"
}

resolve_chain_id() {
  SRC_CHAIN_ID="$(
    curl --max-time "20" --silent "$RPC/status" \
    | jq --raw-output '.result.node_info.network // empty' 2> "$VOID" || echo ""
  )"

  if test -z "$SRC_CHAIN_ID"
  then
    SRC_CHAIN_ID="$(
      api_get "/cosmos/base/tendermint/v1beta1/node_info" \
      | jq --raw-output '.default_node_info.network // empty' 2> "$VOID" || echo ""
    )"
  fi

  if test -z "$SRC_CHAIN_ID"
  then
    log_error "Could not resolve source chain-id from $RPC/status or $API node_info"
  fi
}

# Print the balance amount, or empty string on a REST error (caller decides).
src_balance() {
  local out

  out="$(
    api_get "/cosmos/bank/v1beta1/balances/$1/by_denom?denom=$2" \
    | jq --raw-output '.balance.amount // "0"' 2> "$VOID"
  )" || true

  printf '%s' "$out"
}

# --- channel discovery -------------------------------------------------------

# Walk every OPEN transfer channel, resolve channel -> connection_hops[0] ->
# connection.client_id -> (client chain-id, client status), and pick the FIRST
# channel that targets COUNTERPARTY_CHAIN_ID with an ACTIVE (non-expired) client
# AND a non-empty counterparty channel id.
discover_channel() {
  local ch
  local ch_json
  local channels
  local client
  local client_chain
  local client_status
  local connection
  local cp_chan

  channels="$(
    api_get "/ibc/core/channel/v1/channels?pagination.limit=1000" \
    | jq --raw-output '.channels[] | select(.port_id == "'"$PORT"'" and .state == "STATE_OPEN") | .channel_id' 2> "$VOID" || echo ""
  )"

  test -z "$channels" && log_error "No OPEN '$PORT' channels found on the source chain"

  for ch in $channels
  do
    ch_json="$(api_get "/ibc/core/channel/v1/channels/$ch/ports/$PORT")"

    connection="$(
      echo "$ch_json" | \
      jq --raw-output '.channel.connection_hops[0] // empty' 2> "$VOID" || echo ""
    )"
    test -z "$connection" && continue

    client="$(
      api_get "/ibc/core/connection/v1/connections/$connection" \
      | jq --raw-output '.connection.client_id // empty' 2> "$VOID" || echo ""
    )"
    test -z "$client" && continue

    client_chain="$(
      api_get "/ibc/core/client/v1/client_states/$client" \
      | jq --raw-output '.client_state.chain_id // empty' 2> "$VOID" || echo ""
    )"
    test "$client_chain" != "$COUNTERPARTY_CHAIN_ID" && continue

    client_status="$(
      api_get "/ibc/core/client/v1/client_status/$client" \
      | jq --raw-output '.status // empty' 2> "$VOID" || echo ""
    )"
    cp_chan="$(
      echo "$ch_json" | \
      jq --raw-output '.channel.counterparty.channel_id // empty' 2> "$VOID" || echo ""
    )"

    if test "$client_status" != "Active"
    then
      log_warning "Skipping $ch -> $COUNTERPARTY_CHAIN_ID: client $client is '${client_status:-unknown}', not Active"
      continue
    fi

    if test -z "$cp_chan"
    then
      log_warning "Skipping $ch -> $COUNTERPARTY_CHAIN_ID: empty counterparty channel id"
      continue
    fi

    B_CHANNEL="$cp_chan"
    CLIENT_ID="$client"
    CONNECTION="$connection"
    SRC_CHANNEL="$ch"

    log_info "Selected channel $ch (client $client, Active) -> $COUNTERPARTY_CHAIN_ID via $cp_chan"
    return 0
  done

  log_error "No OPEN '$PORT' channel to '$COUNTERPARTY_CHAIN_ID' has an ACTIVE client. Bring up / refresh a relayer first."
}

# --- transfer + verification -------------------------------------------------

confirm() {
  local input=""
  test -n "$CI" && return

  printf "
Source chain:        %s
Counterparty chain:  %s
Source channel:      %s   (client %s, connection %s)
Counterparty chan:   %s
Send:                %s%s  ->  %s
From:                %s
Packet timeout:      %s min
Verify arrival via:  %s

Submit this IBC transfer (y/Y)? " \
    "$SRC_CHAIN_ID" "$COUNTERPARTY_CHAIN_ID" \
    "$SRC_CHANNEL" "$CLIENT_ID" "$CONNECTION" \
    "$B_CHANNEL" \
    "$AMOUNT" "$DENOM" "$RECEIVER" \
    "$FROM" "$TIMEOUT_MINUTES" \
    "${COUNTERPARTY_API:-"(none set -> INCONCLUSIVE; source-side resolution only)"}"

  read -r input || input=""   # EOF (non-interactive) -> treat as cancel
  if test "$input" != "y" && test "$input" != "Y"
  then
    log_error "Cancelled by user"
  fi
}

send_transfer() {
  local bcode
  local out
  local timeout_ns="$((TIMEOUT_MINUTES * 60 * 1000000000))"

  log_info "Submitting ibc-transfer ..."

  # NB: do not merge stderr; `--gas auto` prints the gas estimate to stderr and
  # would corrupt the JSON on stdout.
  out="$(
    agd tx ibc-transfer transfer \
    "$PORT" "$SRC_CHANNEL" "$RECEIVER" "$AMOUNT$DENOM" \
    $(agd_common) \
    --broadcast-mode "sync" \
    --from "$FROM" \
    --gas "auto" \
    --gas-adjustment "1.4" \
    --gas-prices "$GAS_PRICES" \
    --output "json" \
    --packet-timeout-height "0-0" \
    --packet-timeout-timestamp "$timeout_ns" \
    --yes
  )" || log_error "Failed to broadcast transfer (see error above)"

  TXHASH="$(
    printf '%s' "$out" | \
    jq --raw-output '.txhash // empty' 2> "$VOID" || echo ""
  )"
  test -z "$TXHASH" && log_error "No txhash in broadcast response: $out"

  bcode="$(
    printf '%s' "$out" | \
    jq --raw-output '.code // 0' 2> "$VOID" || echo "1"
  )"
  test "$bcode" != "0" && \
  log_error "Transfer rejected at broadcast (code=$bcode): $(printf '%s' "$out" | jq --raw-output '.raw_log // ""')"

  log_info "Broadcast txhash: $TXHASH"
}

# Poll until the tx is included, assert it executed cleanly, and read back the
# packet sequence emitted by the send_packet event.
await_inclusion() {
  local code=""
  local elapsed="0"
  local txjson=""

  while test "$elapsed" -lt "$POLL_TIMEOUT"
  do
    txjson="$(agd query tx "$TXHASH" --node "$RPC" --output "json" 2> "$VOID" || echo "")"

    if test -n "$txjson" && printf '%s' "$txjson" | jq --exit-status '.txhash' > "$VOID" 2>&1
    then
      break
    fi

    sleep "$POLL_INTERVAL"
    elapsed="$((elapsed + POLL_INTERVAL))"
  done

  test -z "$txjson" && log_error "Transfer tx $TXHASH not found after ${POLL_TIMEOUT}s"

  code="$(
    printf '%s' "$txjson" | \
    jq --raw-output '.code // 0' 2> "$VOID" || echo "1"
  )"
  test "$code" != "0" && log_error "Transfer tx failed (code=$code): $(printf '%s' "$txjson" | jq --raw-output '.raw_log // ""')"

  # cosmos-sdk >=0.50 puts events at top-level .events (plain string attrs);
  # the .logs[] branch is a legacy <=0.46 fallback.
  SEQUENCE="$(printf '%s' "$txjson" | jq --raw-output '
    ( [ .events[]?         | select(.type=="send_packet") | .attributes[]? | select(.key=="packet_sequence") | .value ]
    + [ .logs[]?.events[]? | select(.type=="send_packet") | .attributes[]? | select(.key=="packet_sequence") | .value ] )
    | map(select(. != null and . != "")) | .[0] // empty' 2> "$VOID" || echo "")"

  test -z "$SEQUENCE" && log_error "Could not read packet sequence from tx $TXHASH"
  log_success "Transfer committed on $SRC_CHAIN_ID (packet sequence $SEQUENCE)"
}

# A packet commitment for our sequence is written by our send tx and deleted
# when the packet is RESOLVED (ack OR timeout OR error-ack). We therefore wait
# to OBSERVE the commitment first, then wait for it to clear -- this both proves
# the relayer acted and guards against an empty/lagging REST page short-cutting
# to a false "done". Whether tokens actually arrived is decided by verify_arrival.
await_resolution() {
  local elapsed="0"
  local idx
  local seen="0"

  log_info "Waiting up to ${POLL_TIMEOUT}s for the relayer to resolve packet $SEQUENCE on $SRC_CHANNEL ..."

  while test "$elapsed" -lt "$POLL_TIMEOUT"
  do
    idx="$(
      api_get "/ibc/core/channel/v1/channels/$SRC_CHANNEL/ports/$PORT/packet_commitments?pagination.limit=1000" \
      | jq --raw-output '[.commitments[]?.sequence] | index("'"$SEQUENCE"'")' 2> "$VOID" || echo ""
    )"

    if test -n "$idx" && test "$idx" != "null"
    then
      seen="1"
    elif test "$seen" == "1" && test "$idx" == "null"
    then
      log_success "Packet $SEQUENCE resolved on source (commitment cleared)"
      return 0
    fi

    sleep "$POLL_INTERVAL"
    elapsed="$((elapsed + POLL_INTERVAL))"
  done

  test "$seen" == "0" && log_error "Never observed packet $SEQUENCE commitment within ${POLL_TIMEOUT}s (source REST issue?)"
  log_error "Packet $SEQUENCE still unresolved after ${POLL_TIMEOUT}s -- relayer likely not relaying $SRC_CHANNEL"
}

# Authoritative arrival check on the counterparty (the off-chain / egress leg).
verify_arrival() {
  local got

  if test -z "$COUNTERPARTY_API"
  then
    OFFCHAIN_VERIFIED="unverified"
    log_warning "COUNTERPARTY_API not set -- cannot confirm tokens ARRIVED on $COUNTERPARTY_CHAIN_ID."
    log_warning "A cleared commitment only means the packet was resolved (ack OR timeout/refund)."
    log_warning "Set COUNTERPARTY_API=<counterparty LCD> for an authoritative pass."
    return 0
  fi

  VOUCHER="$(ibc_denom_hash)"
  got="$(counterparty_balance "$RECEIVER" "$VOUCHER")"
  test -z "$got" && log_error "Could not read voucher balance from $COUNTERPARTY_API (REST error?)"

  log_info "Voucher on $COUNTERPARTY_CHAIN_ID: $VOUCHER"
  log_info "$RECEIVER holds $got (was $CP_BAL_BEFORE)"

  if int_gt "$got" "$CP_BAL_BEFORE"
  then
    OFFCHAIN_VERIFIED="yes"
    log_success "Tokens arrived on $COUNTERPARTY_CHAIN_ID (off-chain/egress leg verified)"
  else
    log_error "Voucher balance did NOT increase on $COUNTERPARTY_CHAIN_ID -- packet resolved without delivery (timeout/refund or error ack). FAILED."
  fi
}

# Optional "on chain" return leg.
return_leg() {
  local back_cmd
  local bcode
  local before
  local elapsed
  local now
  local rhash
  local rout
  local txjson

  VOUCHER="${VOUCHER:-"$(ibc_denom_hash)"}"
  back_cmd="$B_BINARY tx ibc-transfer transfer $PORT $B_CHANNEL $SENDER_ADDR ${AMOUNT}${VOUCHER} --broadcast-mode sync --chain-id $COUNTERPARTY_CHAIN_ID --from \"$B_FROM\" --gas auto --gas-adjustment 1.4 --gas-prices ${B_GAS_PRICES:-<B_GAS_PRICES>} --keyring-backend $B_KEYRING_BACKEND --node ${B_NODE:-<B_RPC>} --output json --yes"

  if test -z "$B_BINARY" || test -z "$B_FROM" || test -z "$B_NODE" || test -z "$B_GAS_PRICES"
  then
    log_info "Return ('on chain') leg not run (set B_BINARY/B_FROM/B_NODE/B_GAS_PRICES to automate)."
    log_info "To bring the tokens back, run this ON $COUNTERPARTY_CHAIN_ID:"
    echo "  $back_cmd"
    return 0
  fi

  before="$(src_balance "$SENDER_ADDR" "$DENOM")"
  test -z "$before" && log_error "Could not read pre-return $DENOM balance for $SENDER_ADDR"

  log_info "Submitting return transfer on $COUNTERPARTY_CHAIN_ID ..."
  rout="$(
    eval "$back_cmd" "$(test -n "$B_HOME_DIR" && echo "--home \"$B_HOME_DIR\"")" 2> "$VOID"
  )" || log_error "Return transfer broadcast failed on $COUNTERPARTY_CHAIN_ID"

  rhash="$(
    printf '%s' "$rout" | \
    jq --raw-output '.txhash // empty' 2> "$VOID" || echo ""
  )"
  test -z "$rhash" && log_error "No txhash in return broadcast response: $rout"
  log_info "Return txhash on $COUNTERPARTY_CHAIN_ID: $rhash"

  # Confirm the burn actually executed on B (ties the source credit below to
  # this return packet rather than to any unrelated balance change).
  elapsed="0"
  while test "$elapsed" -lt "$POLL_TIMEOUT"
  do
    txjson="$(
      "$B_BINARY" query tx "$rhash" --node "$B_NODE" --output "json" 2> "$VOID" || echo ""
    )"

    if test -n "$txjson" && printf '%s' "$txjson" | jq --exit-status '.txhash' > "$VOID" 2>&1
    then
      bcode="$(
        printf '%s' "$txjson" | \
        jq --raw-output '.code // 0' 2> "$VOID" || echo "1"
      )"
      test "$bcode" != "0" && log_error "Return tx failed on $COUNTERPARTY_CHAIN_ID (code=$bcode)"
      break
    fi

    sleep "$POLL_INTERVAL"
    elapsed="$((elapsed + POLL_INTERVAL))"
  done

  log_info "Waiting up to ${POLL_TIMEOUT}s for the escrow to be released back on $SRC_CHAIN_ID ..."

  elapsed="0"
  while test "$elapsed" -lt "$POLL_TIMEOUT"
  do
    now="$(src_balance "$SENDER_ADDR" "$DENOM")"

    if test -n "$now" && int_gt "$now" "$before"
    then
      log_success "Tokens returned to $SENDER_ADDR on $SRC_CHAIN_ID ($before -> $now) -- round trip verified"
      return 0
    fi

    sleep "$POLL_INTERVAL"
    elapsed="$((elapsed + POLL_INTERVAL))"
  done

  log_warning "Return tx executed on $COUNTERPARTY_CHAIN_ID but no credit observed on $SRC_CHAIN_ID within ${POLL_TIMEOUT}s -- check the relayer for the return path"
}

# --- main --------------------------------------------------------------------
main() {
  OFFCHAIN_VERIFIED="unverified"

  test -z "$COUNTERPARTY_CHAIN_ID" && \
  log_error "Usage: FROM=<key> RECEIVER=<bech32-on-B> $0 <counterparty-chain-id>"

  test -z "$FROM" && \
  log_error "Set FROM=<key name or address in the keyring>"

  test -z "$HOME_DIR" && \
  log_error "Set HOME_DIR=<home path>"

  test -z "$RECEIVER" && \
  log_error "Set RECEIVER=<bech32 address on $COUNTERPARTY_CHAIN_ID to receive the voucher>"

  resolve_chain_id
  discover_channel

  test -n "${B_CHANNEL:-}" || \
  log_error "Counterparty channel was not resolved for $SRC_CHANNEL"

  SENDER_ADDR="$(
    agd keys show "$FROM" \
    --address --home "$HOME_DIR" --keyring-backend "$KEYRING_BACKEND" 2> "$VOID" || true
  )"

  if test -z "$SENDER_ADDR"
  then
    if [[ "$FROM" =~ ^[a-z]+1[02-9ac-hj-np-z]{38,}$ ]]
    then
      SENDER_ADDR="$FROM"   # already a bech32 address
    else
      log_error "Could not resolve an address for key '$FROM' (check KEYRING_BACKEND / HOME_DIR)"
    fi
  fi

  SRC_BAL_BEFORE="$(src_balance "$SENDER_ADDR" "$DENOM")"
  test -z "$SRC_BAL_BEFORE" && \
  log_error "Could not read $DENOM balance for $SENDER_ADDR from $API (REST error?)"
  int_ge "$SRC_BAL_BEFORE" "$AMOUNT" || log_error "Sender $SENDER_ADDR has ${SRC_BAL_BEFORE}${DENOM}, needs >= ${AMOUNT}${DENOM}"

  CP_BAL_BEFORE="0"
  if test -n "$COUNTERPARTY_API"
  then
    CP_BAL_BEFORE="$(counterparty_balance "$RECEIVER" "$(ibc_denom_hash)")"
    test -z "$CP_BAL_BEFORE" && CP_BAL_BEFORE="0"
  fi

  confirm

  send_transfer
  await_inclusion
  await_resolution
  verify_arrival
  return_leg

  case "$OFFCHAIN_VERIFIED" in
    yes) log_success "IBC transfer test PASSED for $SRC_CHAIN_ID <-> $COUNTERPARTY_CHAIN_ID over $SRC_CHANNEL" ;;
    *)   log_warning "IBC transfer test INCONCLUSIVE: packet $SEQUENCE was resolved on $SRC_CHAIN_ID, but arrival on $COUNTERPARTY_CHAIN_ID was not authoritatively confirmed (set COUNTERPARTY_API to verify)." ;;
  esac
}

main
