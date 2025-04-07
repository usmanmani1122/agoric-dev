#! /usr/bin/env node

import { unlink, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { execSync } from "node:child_process";

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
 * @param {string} contractInstanceName
 * @returns {Promise<[string, string]>}
 */
const getContractInstance = async (contractInstanceName) => {
  const response = await fetch(RPC_URL, {
    body: JSON.stringify({
      id: 1,
      jsonrpc: "2.0",
      method: "abci_query",
      params: {
        path: "/custom/vstorage/data/published.agoricNames.instance",
      },
    }),
    method: "POST",
  });

  if (!response.ok)
    throw Error(`Query failed due to error: ${await response.text()}`);

  /**
   * @type {{
   *    id: number;
   *    jsonrpc: string;
   *    result: {
   *        response:{
   *            code: number;
   *            codespace: string;
   *            height: string;
   *            index: string;
   *            info: string;
   *            key: string;
   *            log: string;
   *            value: string;
   *        }
   *    }
   * }}
   */
  const data = await response.json();

  if (data.result.response.code !== 0)
    throw Error(`Query failed with response: ${JSON.stringify(data)}`);

  /**
   * @type {{
   *    value: {
   *        blockHeight: number;
   *        values: Array<{
   *            body: Array<[string, string]>;
   *            slots: Array<string>;
   *        }>;
   *    }
   * }}
   */
  const json = cleanJSON(
    JSON.parse(Buffer.from(data.result.response.value, "base64").toString())
  );

  /**
   * @type {string}
   */
  let boardSlot;
  /**
   * @type {string}
   */
  let contractInstanceHandle;

  for (const { body, slots } of json.value.values) {
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
  const [, , contractInstanceName, publicInvitationMaker, walletAddress] =
    process.argv;
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
    )}\",\"publicInvitationMaker\":\"${publicInvitationMaker}\",\"source\":\"contract\"},\"proposal\":{}}}`,
    slots: [boardSlot],
  };
  await writeFile(OFFER_FILE, JSON.stringify(offerContent));

  // TODO: Move to agd tx swingset to be able to support `RPC_URL`
  execSync(
    [
      "agoric",
      "wallet",
      "send",
      `--home "/state/${process.env.CHAIN_ID}"`,
      `--keyring-backend "test"`,
      `--from "${walletAddress}"`,
      `--offer "${OFFER_FILE}"`,
    ].join(" "),
    {
      stdio: ["ignore", "pipe", "pipe"],
    }
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
