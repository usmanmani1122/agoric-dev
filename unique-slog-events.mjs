#! /usr/bin/env node

import { open } from "node:fs/promises";
import { createInterface } from "node:readline/promises";

const main = async () => {
  const [, , slogFilePath] = process.argv;
  if (!slogFilePath) throw Error("Missing slog file path");

  const slogFileHandler = await open(slogFilePath, "r");
  const readStream = slogFileHandler.createReadStream({
    autoClose: false,
    encoding: "utf-8",
  });
  const reader = createInterface({
    crlfDelay: Infinity,
    input: readStream,
  });

  reader.addListener("close", () => readStream.close());
  readStream.addListener("close", () => slogFileHandler.close());

  /** @type {Set<string>} */
  const uniqueTypes = new Set();

  for await (const data of reader) {
    /** @type {string} */
    const type = JSON.parse(data).type;

    if (!type) console.error(`"type" key not present in slog ${data}`);
    else uniqueTypes.add(type);
  }

  reader.close();

  return Array.from(uniqueTypes);
};

main().then((slogEvents) => console.log(JSON.stringify(slogEvents)));
