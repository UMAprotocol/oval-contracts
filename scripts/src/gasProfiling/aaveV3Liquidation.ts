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
// Have to import TestedOVAL manually since it is not unique.
import { TestedOVAL__factory } from "../../contract-types/factories/AaveV3.Liquidation.sol/TestedOVAL__factory";

// Common constants.
const blockNumber = 18018927;
const chainId = 1;

// Used ABIs.
const aaveOracleAbi = [
  "function setAssetSources(address[] memory assets, address[] memory sources)",
];

const liquidationCall = async (
  forkTimestamp: number,
  forkId: string,
  rootId?: string // If not provided, the simulation starts off the fork initial state.
): Promise<TenderlySimulationResult> => {
  let simulation: TenderlySimulationResult;
  // Original liquidation https://etherscan.io/tx/0x33ada9fb50abfbf29b59647328bd5fff5121ec04ec43a64f1540de0c898dfd6f
  simulation = await simulateTenderlyTx({
    chainId,
    from: "0x0177ffdf6b5c00ff8eab1a498ea10191ebc965db",
    to: "0x681d0d7196a036661b354fa2a7e3b73c2adc43ec",
    value: "0",
    input:
      "0x00000001283a64c5030288e6a0c2ddd26feeb64f039a2c41296fcb3f56400001f400c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000408a84a78ed977af000000000000000000000001c7e716ab0101004f011bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48b8618d9d13e2baa299bb726b413ff66418efbbd0000000000000000000000001c7e716ab0008000000000000000002e6fd523ca61a7d07000000000000000002c1a048a5db4c89",
    timestampOverride: forkTimestamp,
    fork: { id: forkId, root: rootId },
    description: "liquidationCall",
  });

  return simulation;
};

const regularAaveV3Liquidation = async (): Promise<number> => {
  // Create and share new fork (delete the old one if it exists).
  const alias = "Regular AAVE V3 Liquidation";
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

const OVALAaveV3Liquidation = async (): Promise<number> => {
  // Create and share new fork (delete the old one if it exists).
  const alias = "OVAL AAVE V3 Liquidation";
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

  // Deploy OVAL.
  const testedOVALFactory = new TestedOVAL__factory(ownerSigner);
  const testedOVAL = await testedOVALFactory.deploy(
    "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419",
    8
  );
  await testedOVAL.deployTransaction.wait();
  fork = await getTenderlyFork(fork.id); // Refresh to get head id since we submitted tx through RPC.
  if (!fork.headId) throw new Error("Fork head id not found.");
  await setForkSimulationDescription(fork.id, fork.headId, "Deploy OVAL");

  // Enable unlocker on TestedOVAL.
  const setUnlockerInput = testedOVALFactory.interface.encodeFunctionData(
    "setUnlocker",
    [unlockerAddress, true]
  );
  let simulation = await simulateTenderlyTx({
    chainId,
    from: ownerAddress,
    to: testedOVAL.address,
    input: setUnlockerInput,
    timestampOverride: forkTimestamp,
    fork: { id: fork.id, root: fork.headId },
    description: "Enable unlocker on OVAL",
  });

  // setOVALAsAaveSource
  const aaveOracleInterface = new utils.Interface(aaveOracleAbi);
  const aaveOracleCallData = aaveOracleInterface.encodeFunctionData(
    "setAssetSources",
    [["0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"], [testedOVAL.address]]
  );

  simulation = await simulateTenderlyTx({
    chainId,
    from: "0xEE56e2B3D491590B5b31738cC34d5232F378a8D5", //aaveOracle owner
    to: "0x54586bE62E3c3580375aE3723C145253060Ca0C2", //aaveOracle v3
    input: aaveOracleCallData,
    timestampOverride: forkTimestamp,
    fork: { id: fork.id, root: simulation.id },
    description: "Change OVAL as Aave source",
  });

  // Unlock latest value.
  const unlockLatestValueInput =
    testedOVALFactory.interface.encodeFunctionData("unlockLatestValue");
  simulation = await simulateTenderlyTx({
    chainId,
    from: unlockerAddress,
    to: testedOVAL.address,
    input: unlockLatestValueInput,
    timestampOverride: forkTimestamp,
    fork: { id: fork.id, root: simulation.id },
    description: "Unlock latest value on OVAL",
  });

  // Open user position.
  simulation = await liquidationCall(forkTimestamp, fork.id, simulation.id);

  console.log("Simulated " + alias + " in " + simulation.resultUrl.url);
  console.log("  Consumed gas: " + simulation.gasUsed);
  console.log("  Fork URL: " + forkUrl + "\n");

  return simulation.gasUsed;
};

export const aaveV3Liquidation = async () => {
  console.log("AAVE V3 Liquidation gas comparison with unlock:\n");

  const regularAaveV3LiquidationGas = await regularAaveV3Liquidation();
  const OVALAaveV3LiquidationGas = await OVALAaveV3Liquidation();
  const gasDiff = OVALAaveV3LiquidationGas - regularAaveV3LiquidationGas;

  console.log("Gas difference: " + gasDiff);
};
