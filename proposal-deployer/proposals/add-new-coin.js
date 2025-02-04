/**
 * @typedef {{ ref: { bundleID: string } }} manifestBundleRef
 */

const AMOUNT = "1000000";
const DESTINATION_ACCOUNT = "agoric1megzytg65cyrgzs6fvzxgrcqvwwl7ugpt62346";
const MESSAGE_TYPE = "VBANK_GIVE";
const MY_DENOM = "utah";
const VBANK_PORT_NAME = "bank";

export const proposal = ({ devices: { bridge }, vatPowers: { D } }) =>
  D(bridge).callOutbound(VBANK_PORT_NAME, {
    amount: AMOUNT,
    denom: MY_DENOM,
    recipient: DESTINATION_ACCOUNT,
    type: MESSAGE_TYPE,
  });

/**
 * @param {{
 *  restoreRef: (ref: manifestBundleRef) => {
 *      getBundle: () => Record<string, string>;
 *      getBundleLabel: () => string;
 *  }
 * }} _
 * @param {manifestBundleRef} __
 */
export const getManifest = (_, __) => ({
  manifest: {
    [proposal.name]: {
      devices: { bridge: true },
      vatPowers: { D: true },
    },
  },
});
