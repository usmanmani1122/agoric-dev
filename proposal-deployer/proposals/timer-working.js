import { Far } from "@endo/far";

/**
 * @typedef {{ ref: { bundleID: string } }} manifestBundleRef
 * @typedef {bigint} TimestampValue
 *
 * @typedef {{
 *  getLastPolled: () => TimestampValue;
 *  setWakeup: (time: TimestampValue, handler: {wake: (time: TimestampValue) => void }) => void;
 * }} TimerDevice
 */

/**
 * @param {Object} powers
 * @param {Object} powers.devices
 * @param {TimerDevice} powers.devices.timer
 */
export const proposal = ({ devices: { timer }, vatPowers: { D } }) => {
  const lastBlockTime = D(timer).getLastPolled();
  const wakeUpTime = lastBlockTime + 20n;
  const repeaterInterval = 10n;
  const repeaterStartTime = lastBlockTime + 30n;

  const wakeUpHandler = (time) =>
    console.log(
      `Wake up Time is ${time} and last block time is ${D(
        timer
      ).getLastPolled()}`
    );

  const handler = Far("root", {
    wake: (time) => {
      wakeUpHandler(time);
      D(timer).removeWakeup(handler);
    },
  });

  console.log("Last Block Time in proposal: ", lastBlockTime);
  console.log("Scheduling wakeup time for: ", wakeUpTime);

  D(timer).setWakeup(wakeUpTime, handler);

  const repeaterIndex = D(timer).makeRepeater(
    repeaterStartTime,
    repeaterInterval
  );
  D(timer).schedule(
    repeaterIndex,
    Far("root", {
      wake: wakeUpHandler,
    })
  );
};

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
      devices: { timer: true },
      vatPowers: { D: true },
    },
  },
});
