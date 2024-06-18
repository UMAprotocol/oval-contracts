require("dotenv").config(); // Add dotenv package to load environment variables
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const web3 = require("web3");

const { COINBASE_API_KEY, COINBASE_API_SECRET, COINBASE_API_PASSPHRASE } =
  process.env;
if (!COINBASE_API_KEY || !COINBASE_API_SECRET || !COINBASE_API_PASSPHRASE) {
  console.log(
    "error: missing one or more of COINBASE_API_KEY, COINBASE_API_SECRET, COINBASE_API_PASSPHRASE environment variables"
  );
  process.exit(1);
}

const API_URL = "https://api.exchange.coinbase.com";

async function main() {
  const timestamp = (new Date().getTime() / 1000).toString();
  const message = timestamp + "GET" + "/oracle";
  const hmac = crypto
    .createHmac("sha256", Buffer.from(COINBASE_API_SECRET, "base64"))
    .update(message);
  const signature = hmac.digest("base64");

  const headers = {
    "CB-ACCESS-SIGN": signature,
    "CB-ACCESS-TIMESTAMP": timestamp,
    "CB-ACCESS-KEY": COINBASE_API_KEY,
    "CB-ACCESS-PASSPHRASE": COINBASE_API_PASSPHRASE,
  };

  const res = await fetch(API_URL + "/oracle", { method: "GET", headers });

  const { messages, signatures } = await res.json();

  const output = {};
  for (let i = 0; i < messages.length; ++i) {
    const record = Object.values(
      web3.eth.abi.decodeParameters(
        ["string", "uint", "string", "uint"],
        messages[i]
      )
    ).slice(0, -1);

    const adr = web3.eth.accounts.recover(
      web3.utils.keccak256(messages[i]),
      signatures[i]
    );

    if (adr !== "0xfCEAdAFab14d46e20144F48824d0C09B1a03F2BC")
      throw new Error("Invalid signature");

    output[record[2]] = {
      message: messages[i],
      signature: signatures[i],
    };
  }

  const filePath = path.join(__dirname, "data.json");

  fs.mkdirSync(path.dirname(filePath), { recursive: true });

  fs.writeFileSync(filePath, JSON.stringify(output, null, 2));
}

main();
