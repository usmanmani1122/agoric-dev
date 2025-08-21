#! /bin/bash
# shellcheck disable=SC1091,SC2086,SC2115

set -o errexit -o errtrace -o nounset -o pipefail

AGORIC_HOME="/state/$CHAIN_ID"
BUNDLES_CACHE_PATH="$HOME/.agoric/cache"
BUNDLES_DIRECTORY="bundles"
PROPOSAL_BUILD_LIST_PATH="$BUNDLES_DIRECTORY/bundle-list"
PROPOSAL_BUILD_PATH="$BUNDLES_DIRECTORY/bundle-proposal.js"
PROPOSAL_DEPLOY_SCRIPT_PATH="deployer-proposal.js"
PROPOSAL_FILES_PREFIX="proposal-file"
PROPOSAL_SOURCE_PATH="$(readlink --canonicalize "$1")"
SIGN_BROADCAST_OPTIONS="
 --broadcast-mode sync \
 --chain-id $CHAIN_ID \
 --from validator \
 --gas auto \
 --gas-adjustment 1.2 \
 --home $AGORIC_HOME \
 --keyring-backend test \
 --yes
"
VOID="/dev/null"

build_proposal() {
    print "Generating build ⏳"
    agoric run "$PROPOSAL_DEPLOY_SCRIPT_PATH" > "$VOID" 2>&1
    re_print "Generated builds ✅"
}

check_for_binaries() {
    if ! curl --silent "https://raw.githubusercontent.com/Agoric/agoric-sdk/refs/heads/master/scripts/smoketest-binaries.sh" | /bin/bash > "$VOID"; then
        exit 1
    fi
}

clean_up() {
    print "Cleaning up temporary files ⏳"
    find . -name "$PROPOSAL_FILES_PREFIX*" -type f -exec rm {} \;
    rm --recursive "$BUNDLES_DIRECTORY"
    rm $PROPOSAL_DEPLOY_SCRIPT_PATH
    re_print "Cleaned up temporary files ✅"
}

create_bundle_list() {
    print "Generating bundles list ⏳"
    ls --almost-all -1 "$BUNDLES_CACHE_PATH" >"$PROPOSAL_BUILD_LIST_PATH"
    re_print "Generated bundles list ✅"
}

create_temporary_scripts() {
    print "Creating temporary scripts ⏳"

    cat <<EOF >$PROPOSAL_DEPLOY_SCRIPT_PATH
import { makeHelpers } from '@agoric/deploy-script-support';
import { getManifest } from '$PROPOSAL_SOURCE_PATH';

export const proposalBuilder = async ({ publishRef, install }) =>
    harden({
        getManifestCall: [
            getManifest.name,
            {
                ref: publishRef(
                    install(
                        '$PROPOSAL_SOURCE_PATH',
                        '$PROPOSAL_BUILD_PATH',
                        {
                            persist: true,
                        },
                    ),
                ),
            },
        ],
        sourceSpec: '$PROPOSAL_SOURCE_PATH',
    });

export default async (homeP, endowments) => {
    const { writeCoreEval } = await makeHelpers(homeP, endowments);
    await writeCoreEval('$PROPOSAL_FILES_PREFIX', proposalBuilder);
};
EOF

    re_print "Created temporary scripts ✅"
}

get_node_status() {
    curl --fail --location --silent "http://0.0.0.0:26657/status" | jq '.result' --raw-output
}

get_transaction_data() {
    local transaction_hash="$1"

    agd query tx "$transaction_hash" --home "$AGORIC_HOME" --output "json" 2> "$VOID"
}

install_bundle() {
    local output=""

    print "Installing bundle $(basename "$1") ⏳"
    output="$(agd tx swingset install-bundle "@$1" $SIGN_BROADCAST_OPTIONS --compress --output "json" 2> "$VOID")"
    wait_for_transaction "$(echo "$output" | jq '.txhash' --raw-output)"
    re_print "Installed bundle $(basename "$1") ✅"
}

install_bundles() {
    [ -s "$PROPOSAL_BUILD_LIST_PATH" ] || exit 1
    wait_for_block 2

    while IFS= read -r bundle; do
        install_bundle "$BUNDLES_CACHE_PATH/$bundle"
    done <"$PROPOSAL_BUILD_LIST_PATH"
}

print() {
    echo -n "$1"
}

re_print() {
    echo -en "\r\033[K"
    echo "$1"
}

reset() {
    print "Resetting cache paths ⏳"
    rm --force --recursive $BUNDLES_CACHE_PATH/* "$PROPOSAL_BUILD_LIST_PATH" "$PROPOSAL_DEPLOY_SCRIPT_PATH"
    re_print "Resetted cache paths ✅"
}

submit_proposal() {
    local output=""

    print "Submitting proposal ⏳"
    output="$(
        agd tx gov submit-proposal swingset-core-eval "${PROPOSAL_FILES_PREFIX}-permit.json" "${PROPOSAL_FILES_PREFIX}.js" \
        $SIGN_BROADCAST_OPTIONS \
        --deposit "10000000ubld" \
        --description "Evaluate script" \
        --output "json" \
        --title "Core Eval" 2> "$VOID"
    )"
    wait_for_transaction "$(echo "$output" | jq '.txhash' --raw-output)"
    re_print "Submitted proposal ✅"
}

vote_for_proposal_and_wait() {
    local json=""
    local proposal_id=""
    local proposal_status=""

    print "Voting for proposal to pass ⏳"

    wait_for_block
    proposal_id="$(
        agd query gov proposals --output "json" |
            jq --raw-output '.proposals | last | if .proposal_id == null then .id else .proposal_id end'
    )"
    wait_for_block

    agd tx gov deposit "$proposal_id" "50000000ubld" $SIGN_BROADCAST_OPTIONS > "$VOID" 2>&1
    wait_for_block

    agd tx gov vote "$proposal_id" yes $SIGN_BROADCAST_OPTIONS > "$VOID" 2>&1
    wait_for_block

    while true; do
        json="$(agd query gov proposal "$proposal_id" --output "json")"
        proposal_status="$(echo "$json" | jq --raw-output 'if .proposal then .proposal.status else .status end')"

        case $proposal_status in
        PROPOSAL_STATUS_PASSED)
            break
            ;;
        PROPOSAL_STATUS_REJECTED | PROPOSAL_STATUS_FAILED)
            echo "Proposal did not pass ❌"
            echo "$json" | jq .
            exit 1
            ;;
        *)
            sleep 1
            ;;
        esac
    done

    re_print "Proposal passed ✅"
}

wait_for_block() (
    local first_unique_block_height=""
    local second_unique_block_height=""
    local times="${1:-"1"}"

    for ((i = 1; i <= times; i++)); do
        first_unique_block_height="$(wait_for_bootstrap)"
        while true; do
            second_unique_block_height="$(wait_for_bootstrap)"
            if test "$first_unique_block_height" != "$second_unique_block_height"; then
                break
            fi
            sleep 1
        done
    done
)

wait_for_bootstrap() {
    while true; do
        json="$(get_node_status 2> "$VOID")"
        if last_height="$(echo "$json" | jq --raw-output '.sync_info.latest_block_height')"; then
            echo "$last_height"
            if test "$last_height" != "1"; then
                return
            fi
        fi
        sleep 2
    done
}

wait_for_transaction() {
    local transaction_hash="$1"

    while true; do
        if get_transaction_data "$transaction_hash" > "$VOID"; then
            break
        fi
        sleep 2
    done
}

reset
check_for_binaries
source "$NVM_DIR/nvm.sh"
create_temporary_scripts
build_proposal
create_bundle_list
install_bundles
submit_proposal
vote_for_proposal_and_wait
wait_for_block 2
clean_up
