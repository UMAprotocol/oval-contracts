const { appendFileSync } = require("fs");
const {
  DataPackage,
  NumericDataPoint,
  RedstonePayload,
} = require("@redstone-finance/protocol");
const web3 = require("web3");
const sdk = require("@redstone-finance/sdk");
const args = process.argv.slice(2);

const exit = (code, message) => {
  process.stderr.write(message);
  appendFileSync("./getRedstonePayload.log.txt", message);
  process.exit(code);
};

const parsePrice = (value) => {
  const hexString = web3.utils.bytesToHex(value);
  const bigNumberPrice = BigInt(hexString);
  return Number(bigNumberPrice);
};

const main = async () => {
  if (args.length === 0) {
    exit(1, "You have to provide at least on dataFeed");
  }

  const dataFeeds = args[0].split(",");

  if (dataFeeds.length === 0) {
    exit(2, "You have to provide at least on dataFeed");
  }

  const timestampMilliseconds = Date.now();

  const PRIVATE_KEY_1 =
    "0x548e7c2fae09cc353ffe54ed40609d88a99fab24acfc81bfbf5cd9c11741643d";

  const dataPoints = dataFeeds.map((arg) => {
    const [dataFeedId, value, decimals] = arg.split(":");

    if (!dataFeedId || !value || !decimals) {
      exit(
        3,
        "Input should have format: dataFeedId:value:decimals (example: BTC:120:8)"
      );
    }

    return new NumericDataPoint({
      dataFeedId,
      value: parseInt(value),
      decimals: parseInt(decimals),
    });
  });

  // Prepare unsigned data package
  const dataPackage = new DataPackage(dataPoints, timestampMilliseconds);

  // Prepare signed data packages
  const signedDataPackages = [dataPackage.sign(PRIVATE_KEY_1)];

  const getLatestSignedPrice = await sdk.requestDataPackages({
    dataServiceId: "redstone-primary-prod",
    uniqueSignersCount: 3,
    dataFeeds: ["BTC"],
    urls: ["https://oracle-gateway-1.a.redstone.finance"],
  });

  // const payload = RedstonePayload.prepare(signedDataPackages, "");
  const payload = RedstonePayload.prepare(getLatestSignedPrice["BTC"], "");

  // process.stdout.write("0x" + payload)

  const timestampMS =
    getLatestSignedPrice["BTC"][0].dataPackage.timestampMilliseconds;

  const encodedData = web3.eth.abi.encodeParameters(
    ["bytes", "uint256", "uint256"],
    [
      "0x" + payload,
      timestampMS,
      parsePrice(
        getLatestSignedPrice["BTC"][0].dataPackage.dataPoints[0].value
      ),
    ]
  );

  process.stdout.write(encodedData);

  process.exit(0);
};

main().catch((error) => {
  exit(4, `An error occurred: ${error.message}`);
});
