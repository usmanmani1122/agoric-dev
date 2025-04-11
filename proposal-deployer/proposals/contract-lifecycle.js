import { E } from "@endo/far";
import { prepareExo } from "@agoric/vat-data";
import { M } from "@agoric/store";

const contractName = "contract-lifecycle";

/**
 * The first parameter will provide a `restoreRef` function which
 * will add a mapping of bundle ID + bundle label which can be
 * unwrapped to publish installations and consumed later
 *
 * @param {{
 *  restoreRef: (ref: manifestBundleRef) => {
 *      getBundle: () => Record<string, string>;
 *      getBundleLabel: () => string;
 *  }
 * }} _
 * @param {manifestBundleRef} __
 */
export const getManifest = ({ restoreRef }, { ref }) => ({
  installations: {
    [contractName]: restoreRef(ref),
  },
  manifest: {
    [proposal.name]: {
      consume: {
        chainTimerService: true,
        contractKits: true,
        startUpgradable: true,
      },
      installation: {
        consume: { [contractName]: true },
      },
      instance: {
        consume: { [contractName]: true },
        produce: { [contractName]: true },
      },
    },
  },
  options: { ref },
});

/**
 * First incarnation
 *
 * @param {{
 *  consume: {
 *      chainTimerService: Promise<import('@agoric/time').TimerService>;
 *  }
 * }} powers
 * @param {import('@agoric/vat-data').Baggage} __
 */
export const proposal = ({
  consume: { chainTimerService: chainTimerServicePromise, startUpgradable },
  installation: {
    consume: { [contractName]: installation },
  },
  instance: {
    produce: { [contractName]: produceInstance },
  },
}) =>
  chainTimerServicePromise.then((chainTimerService) =>
    E(startUpgradable)({
      installation,
      issuerKeywordRecord: {},
      terms: {},
      privateArgs: { chainTimerService },
      label: contractName,
    }).then(({ instance }) => produceInstance.resolve(instance))
  );

// /**
//  * Second incarnation
//  *
//  * @param {{
//  *  consume: {
//  *      chainTimerService: Promise<import('@agoric/time').TimerService>;
//  *  }
//  * }} powers
//  * @param {import('@agoric/vat-data').Baggage} __
//  */
// export const proposal = (
//   {
//     consume: {
//       chainTimerService: chainTimerServicePromise,
//       contractKits: contractKitsPromise,
//     },
//     instance: {
//       consume: { [contractName]: contractInstancePromise },
//     },
//   },
//   { options }
// ) =>
//   Promise.all([
//     chainTimerServicePromise,
//     contractInstancePromise,
//     contractKitsPromise,
//   ]).then(([chainTimerService, contractInstance, contractKits]) =>
//     E(contractKits)
//       .get(contractInstance)
//       .then(({ adminFacet }) =>
//         E(adminFacet).upgradeContract(options.ref.bundleID, {
//           chainTimerService,
//           message: "Second incarnation invoked",
//         })
//       )
//   );

// /**
//  * Termination
//  *
//  * @param {{
//  *  consume: {
//  *      chainTimerService: Promise<import('@agoric/time').TimerService>;
//  *  }
//  * }} powers
//  * @param {import('@agoric/vat-data').Baggage} __
//  */
// export const proposal = ({
//   consume: { contractKits: contractKitsPromise },
//   instance: {
//     consume: { [contractName]: contractInstancePromise },
//     produce: { [contractName]: produceInstance },
//   },
// }) =>
//   Promise.all([contractInstancePromise, contractKitsPromise])
//     .then(([contractInstance, contractKits]) =>
//       E(contractKits)
//         .get(contractInstance)
//         .then(({ adminFacet }) =>
//           E(adminFacet).terminateContract(Error("Terminate contract"))
//         )
//         .finally(() => E(contractKits).delete(contractInstance))
//     )
//     .finally(produceInstance.reset);

// /**
//  * First incarnation
//  *
//  * @param {any} _
//  * @param {{chainTimerService: import('@agoric/time').TimerService}} privateArgs
//  * @param {import('@agoric/vat-data').Baggage} baggage
//  */
// export const start = async (_, { chainTimerService, ...rest }, baggage) => {
//   assert(
//     !Object.keys(rest).length,
//     `Got unexpected parameters ${JSON.stringify(rest)}`
//   );
//   let logCount = 0;

//   return {
//     publicFacet: prepareExo(
//       baggage,
//       "Public Facet",
//       M.interface("Contract Life Cycle", {
//         log: M.call().returns(M.promise()),
//       }),
//       {
//         /**
//          * @type {(...args: string) => Promise<void>}
//          */
//         log: (...args) =>
//           E(chainTimerService)
//             .getCurrentTimestamp()
//             .then((time) =>
//               console.log(
//                 `First incarnation of contract invoked, time: "${Number(
//                   time.absValue
//                 )}", count: ${logCount++}, arguments: `,
//                 ...args
//               )
//             ),
//       }
//     ),
//   };
// };

/**
 * Second incarnation
 *
 * @param {any} _
 * @param {{
 *  chainTimerService: import('@agoric/time').TimerService;
 *  message: string;
 * }} privateArgs
 * @param {import('@agoric/vat-data').Baggage} baggage
 */
export const start = async (_, { chainTimerService, message }, baggage) => {
  assert(!!message, "Expected message parameter");
  let logCount = 0;

  return {
    publicFacet: prepareExo(
      baggage,
      "Public Facet",
      M.interface("Contract Life Cycle", {
        log: M.call().returns(M.promise()),
      }),
      {
        /**
         * @type {(...args: string) => Promise<void>}
         */
        log: (...args) =>
          E(chainTimerService)
            .getCurrentTimestamp()
            .then((time) =>
              console.log(
                `${message}, time: "${Number(
                  time.absValue
                )}", count: ${logCount++}, arguments: `,
                ...args
              )
            ),
      }
    ),
  };
};
