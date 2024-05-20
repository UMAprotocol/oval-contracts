const { appendFileSync } = require("fs");
const { RedstonePayload } = require("@redstone-finance/protocol");
const ethers = require("ethers");
const sdk = require("@redstone-finance/sdk");
const args = process.argv.slice(2);

const exit = (code, message) => {
  process.stderr.write(message);
  appendFileSync("./getRedstonePayload.log.txt", message);
  process.exit(code);
};

const parsePrice = (value) => {
  const hexString = ethers.utils.hexlify(value);
  const bigNumberPrice = ethers.BigNumber.from(hexString);
  return bigNumberPrice.toNumber();
};

const pickMedian = (arr) => {
  if (arr.length === 0) {
    throw new Error("Cannot pick median of empty array");
  }
  arr.sort((a, b) => a - b);
  const middleIndex = Math.floor(arr.length / 2);
  if (arr.length % 2 === 0) {
    return (arr[middleIndex - 1] + arr[middleIndex]) / 2;
  } else {
    return arr[middleIndex];
  }
};

const main = async () => {
  if (args.length === 0) {
    exit(1, "You have to provide a data Feed");
  }

  const dataFeed = args[0];

  const getLatestSignedPrice = await sdk.requestDataPackages({
    dataServiceId: "redstone-primary-prod",
    uniqueSignersCount: 3,
    dataFeeds: [dataFeed],
    urls: ["https://oracle-gateway-1.a.redstone.finance"],
  });

  const prices = getLatestSignedPrice[dataFeed].map((dataPackage) =>
    parsePrice(dataPackage.dataPackage.dataPoints[0].value)
  );

  const medianPrice = pickMedian(prices);

  const payload = RedstonePayload.prepare(getLatestSignedPrice[dataFeed], "");

  const timestampMS =
    getLatestSignedPrice[dataFeed][0].dataPackage.timestampMilliseconds;

  const encodedData = ethers.utils.defaultAbiCoder.encode(
    ["bytes", "uint256", "uint256"],
    ["0x" + payload, timestampMS, medianPrice]
  );

  process.stdout.write(encodedData);

  process.exit(0);
};

main().catch((error) => {
  exit(4, `An error occurred: ${error.message}`);
});
