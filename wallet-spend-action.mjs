#! /usr/bin/env node

import { unlink, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { exec } from "node:child_process";

const OFFER_FILE = "/tmp/offer.json";
const RPC_URL = process.env.RPC_URL || "http://localhost:26657";

const cleanJSON = (input) =>
  typeof input !== "object" || !input
    ? input
    : Array.isArray(input)
    ? input.map((_) => cleanJSON(typeof _ === "string" ? parseString(_) : _))
    : Object.entries(input).reduce(
        (acc, [key, value]) => ({
          ...acc,
          [key]: cleanJSON(
            typeof value === "string" ? parseString(value) : value
          ),
        }),
        {}
      );

/**
 * @param {string} command
 */
const executeCommand = (command) =>
  /** @type {Promise<string>} */ (
    new Promise((resolve, reject) =>
      exec(command, { encoding: "utf-8" }, (err, stdout, stderr) =>
        err ? reject(Error(err.toString())) : resolve(stdout + stderr)
      )
    )
  );

/**
 * @param {string} contractInstanceName
 * @returns {[string, string]}
 */
const getContractInstance = async (contractInstanceName) => {
  const response = await executeCommand(
    [
      "agd",
      "query",
      "vstorage",
      "data",
      "published.agoricNames.instance",
      `--chain-id "${process.env.CHAIN_ID}"`,
      `--home "/state/${process.env.CHAIN_ID}"`,
      `--node ${RPC_URL}`,
      `--output json`,
    ].join(" ")
  );

  /**
   * @type {{
   *  blockHeight: number;
   *  values: Array<{
   *    body: Array<[string, string]>;
   *    slots: Array<string>;
   *  }>;
   * }}
   */
  const json = cleanJSON(JSON.parse(JSON.parse(response).value));

  /**
   * @type {string}
   */
  let boardSlot;
  /**
   * @type {string}
   */
  let contractInstanceHandle;

  for (const { body, slots } of json.values) {
    let index = 0;

    for (const [_contractInstanceName, _contractInstanceHandle] of body) {
      if (_contractInstanceName === contractInstanceName) {
        contractInstanceHandle = _contractInstanceHandle;
        boardSlot = slots[index];
        break;
      }
      index++;
    }

    if (contractInstanceHandle) break;
  }

  if (!contractInstanceHandle)
    throw Error(`No contract instance found for ${contractInstanceName}`);

  return [boardSlot, contractInstanceHandle];
};

const main = async () => {
  const [
    ,
    ,
    contractInstanceName,
    publicInvitationMaker,
    walletAddress,
    ...args
  ] = process.argv;
  if (!(contractInstanceName && publicInvitationMaker && walletAddress))
    throw Error(
      "Need contractInstanceName, publicInvitationMaker and walletAddress"
    );

  const [boardSlot, contractInstanceHandle] = await getContractInstance(
    contractInstanceName
  );

  const offerContent = {
    body: `#{\"method\":\"executeOffer\",\"offer\":{\"id\":\"wa-${new Date().getTime()}\",\"invitationSpec\":{\"instance\":\"${contractInstanceHandle.replace(
      /^\$\d+/,
      "$0"
    )}\",\"invitationArgs\": [${args
      .map((arg) => `"${arg}"`)
      .join(
        ", "
      )}],\"publicInvitationMaker\":\"${publicInvitationMaker}\",\"source\":\"contract\"},\"proposal\":{}}}`,
    slots: [boardSlot],
  };

  await writeFile(OFFER_FILE, JSON.stringify(offerContent));

  // TODO: Move to agd tx swingset to be able to support `RPC_URL`
  await executeCommand(
    [
      "agoric",
      "wallet",
      "send",
      `--home "/state/${process.env.CHAIN_ID}"`,
      `--keyring-backend "test"`,
      `--from "${walletAddress}"`,
      `--offer "${OFFER_FILE}"`,
    ].join(" ")
  );
};

/**
 * @param {string} str
 */
const parseString = (str) => {
  try {
    return JSON.parse(str.startsWith("#") ? str.slice(1) : str);
  } catch (error) {
    return str;
  }
};

main().finally(() => existsSync(OFFER_FILE) && unlink(OFFER_FILE));
