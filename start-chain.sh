#!/bin/bash
# shellcheck disable=SC1091,SC2086,SC2115

set -o errexit -o errtrace

ACCOUNTS=("gov1" "gov2" "gov3" "my-wallet" "user1" "validator")
ACCOUNTS_RECOVERY_KEYS=(
    "such field health riot cost kitten silly tube flash wrap festival portion imitate this make question host bitter puppy wait area glide soldier knee"
    "physical immune cargo feel crawl style fox require inhale law local glory cheese bring swear royal spy buyer diesel field when task spin alley"
    "tackle hen gap lady bike explain erode midnight marriage wide upset culture model select dial trial swim wood step scan intact what card symptom"
    "lumber shuffle lottery palm sense hollow swift drink lazy media bicycle neutral caught garbage link churn copper desert domain twin stereo expect air genius"
    "spike siege world rather ordinary upper napkin voice brush oppose junior route trim crush expire angry seminar anchor panther piano image pepper chest alone"
    "soap hub stick bomb dish index wing shield cruel board siren force glory assault rotate busy area topple resource okay clown wedding hint unhappy"
)
AMOUNT="1000000000000000000"
CURRENT_DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
RESET="$1"
UBLD_COIN="ubld"
VOTING_PERIOD="${VOTING_PERIOD:-1m}"

COINS=(
  "uist"
  "$UBLD_COIN"
  "ibc/toyusdc"                                                          # test_usdc
  "ibc/06362C6F7F4FB702B94C13CD2E7C03DEC357683FD978936340B43FBFBC5351EB" # test_atom
  "ibc/BA313C4A19DFBF943586C0387E6B11286F9E416B4DD27574E6909CABE0E342FA" # main_ATOM
  "ibc/295548A78785A1007F232DE286149A6FF512F180AF5657780FC89C009E2C348F"
  "ibc/6831292903487E58BF9A195FDDC8A2E626B3DF39B88F4E7F41C935CADBAF54AC" # main_usdc_grav
  "ibc/F2331645B9683116188EF36FC04A809C28BD36B54555E8705A37146D0182F045" # main_usdt_axl
  "ibc/386D09AE31DA7C0C93091BB45D08CB7A0730B1F697CD813F06A5446DCF02EEB2" # main_usdt_grv
  "ibc/3914BDEF46F429A26917E4D8D434620EC4817DC6B6E68FB327E190902F1E9242" # main_dai_axl
  "ibc/3D5291C23D776C3AA7A7ABB34C7B023193ECD2BC42EA19D3165B2CF9652117E7" # main_dai_grv
  "provisionpass"                                                        # for swingset provisioning
)
GENESIS_AMOUNT="50000000$UBLD_COIN"

set -o nounset

AGORIC_HOME=${AGORIC_HOME:-"/state/$CHAIN_ID"}

# Add some default accounts
add_default_wallets() {
    for i in "${!ACCOUNTS[@]}"
    do
        create_wallet "${ACCOUNTS[$i]}" "${ACCOUNTS_RECOVERY_KEYS[$i]}"
    done
}

# Add a genesis account with some default currencies
add_genesis_account() {
    local coins
    local address
    local key

    coins=$(IFS=','; echo "${COINS[*]/#/$AMOUNT}")
    key="validator"

    address="$(agd keys show "$key" --address --home "$AGORIC_HOME" --keyring-backend "test")"

    if [ ! "$(jq '.app_state.auth.accounts | any(.address == $address)' "$AGORIC_HOME/config/genesis.json" --arg address "$address" 2>&1)" == "true" ]
    then
        agd add-genesis-account "$key" "$coins" \
         --home "$AGORIC_HOME" --keyring-backend "test"
    fi
}

# Add a genesis transaction
add_genesis_transaction() {
    rm --force --recursive $AGORIC_HOME/config/gentx/*
    agd gentx validator "$GENESIS_AMOUNT" \
     --broadcast-mode "block" --chain-id "$CHAIN_ID" \
     --home "$AGORIC_HOME" --keyring-backend "test" > /dev/null 2>&1
}

# Create a wallet
create_wallet() {
    local key=$1
    local recovery_key=$2

    if ! agd keys show "$key" --address --home "$AGORIC_HOME" --keyring-backend "test" > /dev/null 2>&1
    then
        echo "$recovery_key" | \
        agd keys add "$key" \
         --home="$AGORIC_HOME" --keyring-backend=test \
         --recover > /dev/null 2>&1

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
    agoric set-defaults ag-chain-cosmos "$AGORIC_HOME"/config > /dev/null 2>&1
}

# Generate a genesis file from genesis transactions
generate_genesis_file_from_genesis_transaction() {
    if [ ! "$(jq '.app_state.genutil.gen_txs | length > 1' "$AGORIC_HOME/config/genesis.json" 2>&1)" == "true" ]
    then
        agd collect-gentxs --home "$AGORIC_HOME" > /dev/null 2>&1
    fi
}

# This will generate app.toml, config.toml and genesis.json config files
initiate() {
    test -f "$AGORIC_HOME/config/app.toml" || \
    agd init blockchain-node \
     --chain-id="$CHAIN_ID" --home "$AGORIC_HOME" > /dev/null 2>&1
}

# Clear any existing data
reset() {
    if test "$RESET" == "--reset"
    then
        echo "Resetting chain"
        rm --force --recursive $AGORIC_HOME/*
    fi
}

# start the chain
start_chain() {
    LOG_FILE="/state/app.log"
    CONTEXTUAL_SLOGFILE="/state/contextual_slogs.json"
    SLOGFILE="/state/slogs.json"

    if test "$RESET" == "--reset"
    then
        rm --force "$CONTEXTUAL_SLOGFILE" "$LOG_FILE" "$SLOGFILE"
    fi

    touch "$CONTEXTUAL_SLOGFILE" "$SLOGFILE"

    DEBUG="SwingSet:ls,SwingSet:vat" \
    CHAIN_BOOTSTRAP_VAT_CONFIG="@agoric/vm-config/decentral-demo-config.json" \
    CONTEXTUAL_SLOGFILE="$CONTEXTUAL_SLOGFILE" \
    SLOGFILE="$SLOGFILE" \
    SLOGSENDER="@agoric/telemetry/src/context-aware-slog-file.js" \
    ag-chain-cosmos start \
     --home "$AGORIC_HOME" --log_format "json" 2>&1 | \
    tee --append "$LOG_FILE"
}

# Update some configurations
update_configurations() {
    echo -E "$(
        jq \
        ".app_state.crisis.constant_fee.denom = \"$UBLD_COIN\" | .app_state.mint.params.inflation_max = \"0.000000000000000000\" | .app_state.gov.voting_params.voting_period = \"$VOTING_PERIOD\"" \
        "$AGORIC_HOME/config/genesis.json"
    )" > "$AGORIC_HOME/config/genesis.json"
    sed '/^\[api]/,/^\[/{s/^enable[[:space:]]*=.*/enable = true/}' "$AGORIC_HOME/config/app.toml" \
     --in-place
}

reset
source "$NVM_DIR/nvm.sh"
"$CURRENT_DIRECTORY_PATH/check-binaries.sh"
initiate
generate_defaults
add_default_wallets
add_genesis_account
add_genesis_transaction
generate_genesis_file_from_genesis_transaction
update_configurations
start_chain
