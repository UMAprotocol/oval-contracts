import { Contract, providers, utils } from "ethers";
import {
  createTenderlyFork,
  deleteTenderlyFork,
  findForkByDescription,
  getTenderlyFork,
  setForkSimulationDescription,
  shareTenderlyFork,
} from "../TenderlyHelpers/TenderlyFork";
import {
  simulateTenderlyTx,
  TenderlySimulationResult,
} from "../TenderlyHelpers/TenderlySimulation";
import { UniswapAnchoredViewDestinationAdapter__factory } from "../../contract-types";
// Have to import TestedOval manually since it is not unique.
import { TestedOval__factory } from "../../contract-types/factories/AaveV2.Liquidation.sol/TestedOval__factory";

// Common constants.
const blockNumber = 17937311;
const chainId = 1;

// Used ABIs.
const aaveV2LendingPoolAbi = [
  "function liquidationCall(address collateralAsset, address debtAsset, address user, uint256 debtToCover, bool receiveAToken)",
  "function getReserveData(address asset) returns (uint256 totalLiquidity, uint256 availableLiquidity, uint256 totalBorrowsStable, uint256 totalBorrowsVariable, uint256 liquidityRate, uint256 variableBorrowRate, uint256 stableBorrowRate, uint256 averageStableBorrowRate, uint256 utilizationRate, uint256 liquidityIndex, uint256 variableBorrowIndex, address aTokenAddress, uint40 lastUpdateTimestamp)",
  "function getUserAccountData(address user) returns (uint256 totalCollateralETH, uint256 totalDebtETH, uint256 availableBorrowsETH, uint256 currentLiquidationThreshold, uint256 ltv, uint256 healthFactor)",
];

const aaveOracleAbi = [
  "function setAssetSources(address[] memory assets, address[] memory sources)",
];

const liquidationCall = async (
  forkTimestamp: number,
  forkId: string,
  rootId?: string // If not provided, the simulation starts off the fork initial state.
): Promise<TenderlySimulationResult> => {
  // Post collateral.
  let simulation: TenderlySimulationResult;
  const lendingPoolInterface = new utils.Interface(aaveV2LendingPoolAbi);
  const liquidationCallData = lendingPoolInterface.encodeFunctionData(
    "liquidationCall",
    [
      "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
      "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
      "0x6e3aa85db95bba36276a37ed93b12b7ab0782afb",
      "148912478614",
      true,
    ]
  );
  simulation = await simulateTenderlyTx({
    chainId,
    from: "0x796d37daf7cdc455e023be793d0daa6240707069",
    to: "0x7d2768de32b0b80b7a3454c06bdac94a69ddc7a9",
    value: "0",
    input: liquidationCallData,
    timestampOverride: forkTimestamp,
    fork: { id: forkId, root: rootId },
    description: "liquidationCall",
  });

  return simulation;
};

const regularAaveV2Liquidation = async (): Promise<number> => {
  // Create and share new fork (delete the old one if it exists).
  const alias = "Regular AaveV2 Liquidation";
  const description = "Generated: " + utils.keccak256(utils.toUtf8Bytes(alias));
  const existingFork = await findForkByDescription(description);
  if (existingFork) await deleteTenderlyFork(existingFork.id);
  const fork = await createTenderlyFork({
    chainId,
    alias,
    description,
    blockNumber,
    txIndex: 1,
  });
  const forkUrl = await shareTenderlyFork(fork.id);

  // Get provider, accounts and start time of the fork.
  const provider = new providers.StaticJsonRpcProvider(fork.rpcUrl);
  const forkTimestamp = (await provider.getBlock(blockNumber)).timestamp;

  // Open user position.
  const simulation = await liquidationCall(forkTimestamp, fork.id); // Start off the initial fork state.

  console.log("Simulated " + alias + " in " + simulation.resultUrl.url);
  console.log("  Consumed gas: " + simulation.gasUsed);
  console.log("  Fork URL: " + forkUrl + "\n");

  return simulation.gasUsed;
};

const OvalAaveV2Liquidation = async (): Promise<number> => {
  // Create and share new fork (delete the old one if it exists).
  const alias = "Oval AAVE V2 Liquidation";
  const description =
    "Genereated: " + utils.keccak256(utils.toUtf8Bytes(alias));
  const existingFork = await findForkByDescription(description);
  if (existingFork) await deleteTenderlyFork(existingFork.id);
  let fork = await createTenderlyFork({
    chainId,
    alias,
    description,
    blockNumber,
    txIndex: 1,
  });
  const forkUrl = await shareTenderlyFork(fork.id);

  // Get provider, accounts and start time of the fork.
  const provider = new providers.StaticJsonRpcProvider(fork.rpcUrl);
  const [ownerAddress, userAddress, unlockerAddress] =
    await provider.listAccounts(); // These should have 100 ETH balance.
  const ownerSigner = provider.getSigner(ownerAddress);
  const forkTimestamp = (await provider.getBlock(blockNumber)).timestamp;

  // Deploy Oval.
  const testedOvalFactory = new TestedOval__factory(ownerSigner);
  const testedOval = await testedOvalFactory.deploy(
    "0x8e0b7e6062272B5eF4524250bFFF8e5Bd3497757",
    18,
    [unlockerAddress]
  );
  await testedOval.deployTransaction.wait();
  fork = await getTenderlyFork(fork.id); // Refresh to get head id since we submitted tx through RPC.
  if (!fork.headId) throw new Error("Fork head id not found.");
  await setForkSimulationDescription(fork.id, fork.headId, "Deploy Oval");

  // setOvalAsAaveSource
  const aaveOracleInterface = new utils.Interface(aaveOracleAbi);
  const aaveOracleCallData = aaveOracleInterface.encodeFunctionData(
    "setAssetSources",
    [["0x57Ab1ec28D129707052df4dF418D58a2D46d5f51"], [testedOval.address]]
  );

  let simulation = await simulateTenderlyTx({
    chainId,
    from: "0xEE56e2B3D491590B5b31738cC34d5232F378a8D5", //aaveOracle owner
    to: "0xA50ba011c48153De246E5192C8f9258A2ba79Ca9", //aaveOracle
    input: aaveOracleCallData,
    timestampOverride: forkTimestamp,
    fork: { id: fork.id, root: fork.headId },
    description: "Change Oval as Aave source",
  });

  // Unlock latest value.
  const unlockLatestValueInput =
    testedOvalFactory.interface.encodeFunctionData("unlockLatestValue");
  simulation = await simulateTenderlyTx({
    chainId,
    from: unlockerAddress,
    to: testedOval.address,
    input: unlockLatestValueInput,
    timestampOverride: forkTimestamp,
    fork: { id: fork.id, root: simulation.id },
    description: "Unlock latest value on Oval",
  });

  // Open user position.
  simulation = await liquidationCall(forkTimestamp, fork.id, simulation.id);

  console.log("Simulated " + alias + " in " + simulation.resultUrl.url);
  console.log("  Consumed gas: " + simulation.gasUsed);
  console.log("  Fork URL: " + forkUrl + "\n");

  return simulation.gasUsed;
};

export const aaveV2Liquidation = async () => {
  console.log("AAVE V2 Liquidation gas comparison with unlock:\n");

  const regularAaveV2LiquidationGas = await regularAaveV2Liquidation();
  const OvalAaveV2LiquidationGas = await OvalAaveV2Liquidation();
  const gasDiff = OvalAaveV2LiquidationGas - regularAaveV2LiquidationGas;

  console.log("Gas difference: " + gasDiff);
};
