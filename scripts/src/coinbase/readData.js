require("dotenv").config(); // Load environment variables from .env file
const web3 = require("web3");
const fs = require("fs");
const path = require("path");

async function main(symbol) {
  try {
    if (!symbol) {
      console.error("Error: No symbol argument provided");
      process.exit(1);
    }

    const filePath = path.join(__dirname, "data.json");

    const file = fs.readFileSync(filePath);
    const data = JSON.parse(file);
    const tickerData = data[symbol];

    if (!tickerData) {
      console.error("Error: Symbol not found");
      process.exit(1);
    }

    const encodedData = web3.eth.abi.encodeParameters(
      ["bytes", "bytes"],
      [tickerData.message, tickerData.signature]
    );

    process.stdout.write(encodedData);
  } catch (error) {
    console.error("An error occurred:", error.message);
    process.exit(1);
  }
}

const symbolArg = process.argv[2];
main(symbolArg);
