import { E, Far } from "@endo/far";

/**
 * @typedef {{ ref: { bundleID: string } }} manifestBundleRef
 */

export const proposal = ({ consume: { provisionBridgeManager } }) =>
  E(provisionBridgeManager).setHandler(
    Far("No Provisioning Handler", {
      fromBridge: async (obj) => {
        throw Error(
          `Rejecting provisioning for payload: ${JSON.stringify(obj)}`
        );
      },
    })
  );

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
      consume: {
        provisionBridgeManager: true,
      },
    },
  },
});
