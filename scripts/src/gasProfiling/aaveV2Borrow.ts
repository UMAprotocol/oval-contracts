import { providers, utils } from "ethers";
import {
  createTenderlyFork,
  deleteTenderlyFork,
  findForkByDescription,
  getTenderlyFork,
  setForkSimulationDescription,
  shareTenderlyFork,
} from "../TenderlyHelpers/TenderlyFork";
import {
  TenderlySimulationResult,
  simulateTenderlyTx,
} from "../TenderlyHelpers/TenderlySimulation";
// Have to import TestedOVAL manually since it is not unique.
import { TestedOVAL__factory } from "../../contract-types/factories/AaveV2.Liquidation.sol/TestedOVAL__factory";

// Common constants.
const blockNumber = 18426914;
const chainId = 1;

// Used ABIs.
const aaveOracleAbi = [
  "function setAssetSources(address[] memory assets, address[] memory sources)",
];

const borrowCall = async (
  forkTimestamp: number,
  forkId: string,
  rootId?: string // If not provided, the simulation starts off the fork initial state.
): Promise<TenderlySimulationResult> => {
  // Borrow tx
  // https://etherscan.io/tx/0x99751e7c2114bfc74d7effb6114a7d752c7573396a5d6456ee7b56497132d474
  let simulation: TenderlySimulationResult;
  simulation = await simulateTenderlyTx({
    chainId,
    from: "0x2a111934d990668e705c85da0e976db06281ef0a",
    to: "0x7d2768de32b0b80b7a3454c06bdac94a69ddc7a9",
    value: "0",
    input:
      "0xa415bcad000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec70000000000000000000000000000000000000000000000000000000077359400000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a111934d990668e705c85da0e976db06281ef0a",
    timestampOverride: forkTimestamp,
    fork: { id: forkId, root: rootId },
    description: "borrowCall",
  });

  return simulation;
};

const regularAaveV2Borrow = async (): Promise<number> => {
  // Create and share new fork (delete the old one if it exists).
  const alias = "Regular AAVE V2 Borrow";
  const description = "Generated: " + utils.keccak256(utils.toUtf8Bytes(alias));
  const existingFork = await findForkByDescription(description);
  if (existingFork) await deleteTenderlyFork(existingFork.id);
  const fork = await createTenderlyFork({
    chainId,
    alias,
    description,
    blockNumber,
    txIndex: 125,
  });
  const forkUrl = await shareTenderlyFork(fork.id);

  // Get provider, accounts and start time of the fork.
  const provider = new providers.StaticJsonRpcProvider(fork.rpcUrl);
  const forkTimestamp = (await provider.getBlock(blockNumber)).timestamp;

  // Open user position.
  const simulation = await borrowCall(forkTimestamp, fork.id); // Start off the initial fork state.

  console.log("Simulated " + alias + " in " + simulation.resultUrl.url);
  console.log("  Consumed gas: " + simulation.gasUsed);
  console.log("  Fork URL: " + forkUrl + "\n");

  return simulation.gasUsed;
};

const OVALAaveV2Borrow = async (): Promise<number> => {
  // Create and share new fork (delete the old one if it exists).
  const alias = "OVAL AAVE V2 Borrow";
  const description =
    "Genereated: " + utils.keccak256(utils.toUtf8Bytes(alias));
  const existingFork = await findForkByDescription(description);
  if (existingFork) await deleteTenderlyFork(existingFork.id);
  let fork = await createTenderlyFork({
    chainId,
    alias,
    description,
    blockNumber,
    txIndex: 125,
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
    "0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46",
    18
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
    [["0xdac17f958d2ee523a2206206994597c13d831ec7"], [testedOVAL.address]]
  );

  simulation = await simulateTenderlyTx({
    chainId,
    from: "0xEE56e2B3D491590B5b31738cC34d5232F378a8D5", //aaveOracle owner
    to: "0xA50ba011c48153De246E5192C8f9258A2ba79Ca9", //aaveOracle
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
  simulation = await borrowCall(forkTimestamp, fork.id, simulation.id);

  console.log("Simulated " + alias + " in " + simulation.resultUrl.url);
  console.log("  Consumed gas: " + simulation.gasUsed);
  console.log("  Fork URL: " + forkUrl + "\n");

  return simulation.gasUsed;
};

export const aaveV2Borrow = async () => {
  console.log("AAVE V2 Borrow gas comparison with unlock:\n");

  const regularAaveV2BorrowGas = await regularAaveV2Borrow();
  const OVALAaveV2BorrowGas = await OVALAaveV2Borrow();
  const gasDiff = OVALAaveV2BorrowGas - regularAaveV2BorrowGas;

  console.log("Gas difference: " + gasDiff);
};
