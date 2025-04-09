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
        zoe: true,
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
  consume: { chainTimerService: chainTimerServicePromise, zoe },
  installation: {
    consume: { [contractName]: installation },
  },
  instance: {
    produce: { [contractName]: produceInstance },
  },
}) =>
  chainTimerServicePromise.then((chainTimerService) =>
    E(zoe)
      .startInstance(installation, {}, {}, { chainTimerService }, contractName)
      .then((instance) => produceInstance.resolve(instance))
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
//     consume: { chainTimerService: chainTimerServicePromise },
//     instance: {
//       consume: { [contractName]: contractInstancePromise },
//     },
//   },
//   { options }
// ) =>
//   Promise.all([chainTimerServicePromise, contractInstancePromise]).then(
//     ([chainTimerService, { adminFacet }]) =>
//       E(adminFacet).upgradeContract(options.ref.bundleID, {
//         chainTimerService,
//         message: "Second incarnation invoked at time",
//       })
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
//   instance: {
//     consume: { [contractName]: contractInstancePromise },
//   },
// }) =>
//   contractInstancePromise.then(({ adminFacet }) =>
//     E(adminFacet).terminateContract(Error("Terminate contract"))
//   );

/**
 * First incarnation
 *
 * @param {any} _
 * @param {{chainTimerService: import('@agoric/time').TimerService}} privateArgs
 * @param {import('@agoric/vat-data').Baggage} baggage
 */
export const start = async (_, { chainTimerService, ...rest }, baggage) => {
  assert(
    !Object.keys(rest).length,
    `Got unexpected parameters ${JSON.stringify(rest)}`
  );

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
                `First incarnation invoked at time "${Number(
                  time.absValue
                )}" with arguments: `,
                ...args
              )
            ),
      }
    ),
  };
};

// /**
//  * Second incarnation
//  *
//  * @param {any} _
//  * @param {{
//  *  chainTimerService: import('@agoric/time').TimerService;
//  *  message: string;
//  * }} privateArgs
//  * @param {import('@agoric/vat-data').Baggage} baggage
//  */
// export const start = async (_, { chainTimerService, message }, baggage) => {
//   assert(!!message, "Expected message parameter");

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
//                 `${message} "${Number(time.absValue)}" with arguments: `,
//                 ...args
//               )
//             ),
//       }
//     ),
//   };
// };
