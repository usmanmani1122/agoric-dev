#! /bin/bash
# shellcheck disable=SC1091,SC2086,SC2115

set -o errexit -o errtrace

ACCOUNTS_RECOVERY_KEYS=(
    "arch theme perfect teach attract hazard brain fossil wing rapid cave quit rotate crowd stomach paddle alpha copper goat daring atom physical rigid brave"
    "urban provide assist perfect tower trust tooth cage bunker hurt spatial blame focus insane neck excite shine curtain clinic little pair only blouse game"
    "clinic pause person south add cabin visual best outdoor engage enhance jealous best robust hill inspire ridge clap spike pyramid thrive round police unable"
    "soldier thank cargo raw asset fresh monster stumble absorb between hint rib dumb cake fox ring canvas type jump term slush piano tiger mule"
    "lumber shuffle lottery palm sense hollow swift drink lazy media bicycle neutral caught garbage link churn copper desert domain twin stereo expect air genius"
    "spike siege world rather ordinary upper napkin voice brush oppose junior route trim crush expire angry seminar anchor panther piano image pepper chest alone"
    "soap hub stick bomb dish index wing shield cruel board siren force glory assault rotate busy area topple resource okay clown wedding hint unhappy"
)
AMOUNT="1000000000000000000"
BLOCK_COMPUTE_LIMIT="6500000000"
CHAIN_BOOTSTRAP_VAT_CONFIG="${CHAIN_BOOTSTRAP_VAT_CONFIG:-"@agoric/vm-config/decentral-core-config.json"}"
EXTERNAL_RPC_ADDRESS=""
EXTERNAL_SEED=""
GENESIS_FILE_PATH=""
GENESIS_SOURCE_URL=""
JSOT_BINARY_NAME="jsot"
LATEST_HEIGHT=""
MONIKER="${MONIKER:-"blockchain-node"}"
NETWORK_CONFIG=""
NETWORK_CONFIG_URL="${NETWORK_CONFIG_URL:-""}"
RESET="${RESET:-"false"}"
RPC_PORT="26657"
SNAPSHOT_CHUNKS_DOWNLOAD_PATH="/state/tmp"
SNAPSHOT_INTERVAL="1000"
SLOGSENDER="${SLOGSENDER:-"@agoric/telemetry/src/context-aware-slog-file.js"}"
TRUSTED_BLOCK_HASH=""
TRUSTED_BLOCK_HEIGHT="${TRUSTED_BLOCK_HEIGHT:-""}"
UBLD_COIN="ubld"
VALIDATOR_KEY_NAME="validator"
VOID="/dev/null"
VOTING_PERIOD="${VOTING_PERIOD:-"1m"}"

ACCOUNTS=("gov1" "gov2" "gov3" "gov4" "my-wallet" "user1" "$VALIDATOR_KEY_NAME")
COINS=(
    "uist"
    "$UBLD_COIN"
    "ibc/toyusdc"                                                          # test_usdc
    "ibc/06362C6F7F4FB702B94C13CD2E7C03DEC357683FD978936340B43FBFBC5351EB" # test_atom
    "ibc/BA313C4A19DFBF943586C0387E6B11286F9E416B4DD27574E6909CABE0E342FA" # main_ATOM
    "ibc/295548A78785A1007F232DE286149A6FF512F180AF5657780FC89C009E2C348F" # main_usdc_axl
    "ibc/6831292903487E58BF9A195FDDC8A2E626B3DF39B88F4E7F41C935CADBAF54AC" # main_usdc_grav
    "ibc/F2331645B9683116188EF36FC04A809C28BD36B54555E8705A37146D0182F045" # main_usdt_axl
    "ibc/386D09AE31DA7C0C93091BB45D08CB7A0730B1F697CD813F06A5446DCF02EEB2" # main_usdt_grv
    "ibc/3914BDEF46F429A26917E4D8D434620EC4817DC6B6E68FB327E190902F1E9242" # main_dai_axl
    "ibc/3D5291C23D776C3AA7A7ABB34C7B023193ECD2BC42EA19D3165B2CF9652117E7" # main_dai_grv
    "provisionpass"                                                        # for swingset provisioning
)
CURRENT_DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>"$VOID" && pwd)"
GENESIS_AMOUNT="50000000$UBLD_COIN"
JSOT_DOWNLOAD_PATH="https://storage.googleapis.com/agoric-snapshots-public/$JSOT_BINARY_NAME"

# Add some default accounts
add_default_wallets() {
    for i in "${!ACCOUNTS[@]}"; do
        create_wallet "${ACCOUNTS[$i]}" "${ACCOUNTS_RECOVERY_KEYS[$i]}"
    done
}

# Add a genesis account with some default currencies
add_genesis_account() {
    local coins

    if test "$(jq '.app_state.genutil.gen_txs | length' --raw-output <"$GENESIS_FILE_PATH")" -eq "0"; then
        coins="$(
            IFS=','
            echo "${COINS[*]/#/$AMOUNT}"
        )"

        agd add-genesis-account "$VALIDATOR_KEY_NAME" "$coins" --home "$AGORIC_HOME" --keyring-backend "test"
    fi
}

# Add a genesis transaction
add_genesis_transaction() {
    rm --force --recursive "$AGORIC_HOME"/config/gentx/*

    if test "$(jq '.app_state.genutil.gen_txs | length' --raw-output <"$GENESIS_FILE_PATH")" -eq "0"; then
        agd gentx validator "$GENESIS_AMOUNT" \
            --broadcast-mode "block" --chain-id "$CHAIN_ID" \
            --home "$AGORIC_HOME" --keyring-backend "test" >"$VOID" 2>&1
    fi
}

check_for_dependencies() {
    if ! which node >"$VOID" || ! which yarn >"$VOID"; then
        if test -n "$NVM_DIR"; then
            source "$NVM_DIR/nvm.sh"
        else
            log_error "[FATAL] yarn or node not installed"
            exit 1
        fi
    fi

    if ! which "$JSOT_BINARY_NAME" >"$VOID"; then
        local binary_path="/usr/bin/$JSOT_BINARY_NAME"
        echo "'$JSOT_BINARY_NAME' not found, installing..."
        curl --fail --location --output "$binary_path" --silent "$JSOT_DOWNLOAD_PATH"
        chmod +x "$binary_path"
    fi
}

# Create a wallet
create_wallet() {
    local key=$1
    local recovery_key=$2

    if ! agd keys show "$key" --address --home "$AGORIC_HOME" --keyring-backend "test" >"$VOID" 2>&1; then
        echo "$recovery_key" |
            agd keys add "$key" \
                --home="$AGORIC_HOME" --keyring-backend=test \
                --recover >"$VOID" 2>&1

        key_address=$(
            agd keys show "$key" \
                --address --home "$AGORIC_HOME" \
                --keyring-backend "test"
        )
        echo "Created key '$key' with address '$key_address'"
    fi
}

# This will generate defaults for app.toml, config.toml and genesis.json
generate_defaults() {
    agoric set-defaults ag-chain-cosmos "$AGORIC_HOME"/config >"$VOID" 2>&1
}

# Generate a genesis file from genesis transactions
generate_genesis_file_from_genesis_transaction() {
    if test -d "$AGORIC_HOME/config/gentx" && ! test "$(
        find "$AGORIC_HOME/config/gentx" -maxdepth "1" -type "f" | wc --lines
    )" -eq "0"; then
        agd collect-gentxs --home "$AGORIC_HOME" >"$VOID" 2>&1
    fi
}

get_node_info() {
    local node_url="${1:-"http://0.0.0.0:$RPC_PORT"}"
    agd status --home "$AGORIC_HOME" --node "$node_url"
}

# This will generate app.toml, config.toml and genesis.json config files
initiate() {
    test -f "$AGORIC_HOME/config/app.toml" ||
        agd init "$MONIKER" \
            --chain-id "$CHAIN_ID" --home "$AGORIC_HOME" >"$VOID" 2>&1
}

log_error() {
    printf "\033[31m%s\033[0m\n" "$1"
}

populate_data_for_follower() {
    if test -z "$NETWORK_CONFIG_URL"; then
        return 0
    fi

    NETWORK_CONFIG="$(curl "$NETWORK_CONFIG_URL" --fail --location --silent | jq --raw-output)"

    CHAIN_ID="$(echo "$NETWORK_CONFIG" | jq '.chainName' --raw-output)"
    export AGORIC_HOME="/state/$CHAIN_ID"

    GENESIS_FILE_PATH="$AGORIC_HOME/config/genesis.json"
    reset
    initiate

    EXTERNAL_RPC_ADDRESS="$(echo "$NETWORK_CONFIG" | jq '.rpcAddrs[0]' --raw-output)"
    EXTERNAL_SEED="$(echo "$NETWORK_CONFIG" | jq '.seeds[0]' --raw-output)"
    GENESIS_SOURCE_URL="$(echo "$NETWORK_CONFIG" | jq '.gci' --raw-output)"

    curl "$GENESIS_SOURCE_URL" --fail --location --silent |
        jq '.result.genesis | .app_state |= if has("vbank") then . else .vbank = {"params": {}} end' --raw-output >"$GENESIS_FILE_PATH"

    if test -z "$TRUSTED_BLOCK_HEIGHT"
    then
        LATEST_HEIGHT="$(get_node_info "$EXTERNAL_RPC_ADDRESS" | jq '.SyncInfo.latest_block_height' --raw-output)"
        TRUSTED_BLOCK_HEIGHT="$((("$LATEST_HEIGHT" / "$SNAPSHOT_INTERVAL") * "$SNAPSHOT_INTERVAL" + 1))"
    fi

    TRUSTED_BLOCK_HASH="$(
        curl "$EXTERNAL_RPC_ADDRESS/block?height=$TRUSTED_BLOCK_HEIGHT" --fail --location --silent |
            jq '.result.block_id.hash' --raw-output
    )"

    rm --force --recursive "$SNAPSHOT_CHUNKS_DOWNLOAD_PATH"
    mkdir --parents "$SNAPSHOT_CHUNKS_DOWNLOAD_PATH"
}

# Clear any existing data
reset() {
    if test "$RESET" == "true" || test -n "$NETWORK_CONFIG_URL"; then
        echo "Resetting chain"
        rm --force --recursive "$AGORIC_HOME"/*
    fi
}

# start the chain
start_chain() {
    CONTEXTUAL_SLOGFILE="$AGORIC_HOME/contextual_slogs.json"
    LOG_FILE="$AGORIC_HOME/app.log"
    SLOGFILE="$AGORIC_HOME/slogs.json"

    if test "$RESET" == "--reset"; then
        rm --force "$CONTEXTUAL_SLOGFILE" "$LOG_FILE" "$SLOGFILE"
    fi

    touch "$CONTEXTUAL_SLOGFILE" "$SLOGFILE"

    DEBUG="SwingSet:ls,SwingSet:vat" \
        CHAIN_BOOTSTRAP_VAT_CONFIG="$CHAIN_BOOTSTRAP_VAT_CONFIG" \
        CONTEXTUAL_SLOGFILE="$CONTEXTUAL_SLOGFILE" \
        SLOGFILE="$SLOGFILE" \
        SLOGSENDER="$SLOGSENDER" \
        ag-chain-cosmos start \
        --home "$AGORIC_HOME" --log_format "json" 2>&1 |
        tee --append "$LOG_FILE"
}

# Update some configurations
update_configurations() {
    local contents

    contents="$(
        "$JSOT_BINARY_NAME" toml-to-json "$AGORIC_HOME/config/app.toml" |
            jq --arg snapshot_interval "$SNAPSHOT_INTERVAL" \
                '
            .api.address = "tcp://0.0.0.0:1317" |
            .api.enable = "true" |
            .api."enabled-unsafe-cors" = "true" |
            .api."max-open-connections" = "1000" |
            .api."rpc-max-body-bytes" = "15000000" |
            .api.swagger = "false" |
            ."pruning-interval" = "1000" |
            ."pruning-keep-every" = "1000" |
            ."pruning-keep-recent" = "10000" |
            .rosetta.enable = "false" |
            ."state-sync"."snapshot-interval" = $snapshot_interval |
            ."state-sync"."snapshot-keep-recent" = "10" |
            .telemetry.enabled = "false"
        ' |
            "$JSOT_BINARY_NAME" json-to-toml -
    )"
    echo -E "$contents" >"$AGORIC_HOME/config/app.toml"

    contents="$(
        "$JSOT_BINARY_NAME" toml-to-json "$AGORIC_HOME/config/config.toml" |
            jq --arg rpc_address "tcp://0.0.0.0:$RPC_PORT" \
                '
            .instrumentation.namespace = "cometbft" |
            .instrumentation.prometheus = "false" |
            .p2p.addr_book_strict = "false" |
            .p2p.allow_duplicate_ip = "true" |
            .p2p.max_num_inbound_peers = "150" |
            .p2p.max_num_outbound_peers = "150" |
            .rpc.laddr = $rpc_address
        ' |
            "$JSOT_BINARY_NAME" json-to-toml -
    )"
    echo -E "$contents" >"$AGORIC_HOME/config/config.toml"

    if test -n "$NETWORK_CONFIG_URL"; then
        contents="$(
            "$JSOT_BINARY_NAME" toml-to-json "$AGORIC_HOME/config/config.toml" |
                jq --arg seed_address "$EXTERNAL_SEED" \
                    --arg rpc_servers "$EXTERNAL_RPC_ADDRESS,$EXTERNAL_RPC_ADDRESS" \
                    --arg trust_hash "$TRUSTED_BLOCK_HASH" \
                    --arg trust_height "$TRUSTED_BLOCK_HEIGHT" \
                    '
                .p2p.seeds = $seed_address |
                .statesync.chunk_request_timeout = "120s" |
                .statesync.discovery_time = "60s" |
                .statesync.enable = "true" |
                .statesync.rpc_servers = $rpc_servers |
                .statesync.trust_hash = $trust_hash |
                .statesync.trust_height = $trust_height
            ' |
                "$JSOT_BINARY_NAME" json-to-toml -
        )"
        echo -E "$contents" >"$AGORIC_HOME/config/config.toml"
    fi

    contents="$(
        jq --arg block_compute_limit "$BLOCK_COMPUTE_LIMIT" \
            --arg config_file_path "$CHAIN_BOOTSTRAP_VAT_CONFIG" \
            --arg denom "$UBLD_COIN" \
            --arg voting_period "$VOTING_PERIOD" \
            '
            .app_state.crisis.constant_fee.denom = $denom |
            .app_state.mint.params.mint_denom = $denom |
            .app_state.gov.deposit_params.min_deposit[0].denom = $denom |
            .app_state.gov.params.voting_period = $voting_period |
            .app_state.mint.minter.inflation = "0.000000000000000000" |
            .app_state.mint.params.inflation_max = "0.000000000000000000" |
            .app_state.mint.params.inflation_min = "0.000000000000000000" |
            .app_state.mint.params.inflation_rate_change = "0.000000000000000000" |
            .app_state.slashing.params.signed_blocks_window = "10000" |
            .app_state.staking.params.bond_denom = $denom |
            .app_state.swingset.params.beans_per_unit[0].beans = $block_compute_limit |
            .app_state.swingset.params.bootstrap_vat_config = $config_file_path
        ' <"$GENESIS_FILE_PATH"
    )"
    echo -E "$contents" >"$GENESIS_FILE_PATH"
}

check_for_dependencies
"$CURRENT_DIRECTORY_PATH/check-binaries.sh"

if test -n "$NETWORK_CONFIG_URL"; then
    populate_data_for_follower
else
    export AGORIC_HOME="${AGORIC_HOME:-"/state/$CHAIN_ID"}"
    GENESIS_FILE_PATH="$AGORIC_HOME/config/genesis.json"
    reset
    initiate
fi

set -o nounset

generate_defaults
add_default_wallets
add_genesis_account
add_genesis_transaction
generate_genesis_file_from_genesis_transaction
update_configurations
start_chain
