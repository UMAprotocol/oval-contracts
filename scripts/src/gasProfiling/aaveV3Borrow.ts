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
import { TestedOVAL__factory } from "../../contract-types/factories/AaveV3.Liquidation.sol/TestedOVAL__factory";

// Common constants.
const blockNumber = 18427678;
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
  let simulation: TenderlySimulationResult;
  // Original borrow https://etherscan.io/tx/0x20092fee7e5574443f19fc2fd0e2aaa4b73226252e428e11e068e2a1930b9a67
  simulation = await simulateTenderlyTx({
    chainId,
    from: "0xec4a9460200017cf196da530a8b2ad5904e54796",
    to: "0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2",
    value: "0",
    input:
      "0xa415bcad000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000000000000000000000000000000000012a05f20000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ec4a9460200017cf196da530a8b2ad5904e54796",
    timestampOverride: forkTimestamp,
    fork: { id: forkId, root: rootId },
    description: "borrowCall",
  });

  return simulation;
};

const regularAaveV3Borrow = async (): Promise<number> => {
  // Create and share new fork (delete the old one if it exists).
  const alias = "Regular AAVE V3 Borrow";
  const description = "Generated: " + utils.keccak256(utils.toUtf8Bytes(alias));
  const existingFork = await findForkByDescription(description);
  if (existingFork) await deleteTenderlyFork(existingFork.id);
  const fork = await createTenderlyFork({
    chainId,
    alias,
    description,
    blockNumber,
    txIndex: 104,
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

const OVALAaveV3Borrow = async (): Promise<number> => {
  // Create and share new fork (delete the old one if it exists).
  const alias = "OVAL AAVE V3 Borrow";
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
    "0x3E7d1eAB13ad0104d2750B8863b489D65364e32D",
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
    [["0xdac17f958d2ee523a2206206994597c13d831ec7"], [testedOVAL.address]]
  );

  simulation = await simulateTenderlyTx({
    chainId,
    from: "0xEE56e2B3D491590B5b31738cC34d5232F378a8D5", //aaveOracle owner
    to: "0x54586be62e3c3580375ae3723c145253060ca0c2", //aaveOracle v3
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

export const aaveV3Borrow = async () => {
  console.log("AAVE V3 Borrow gas comparison with unlock:\n");

  const regularAaveV3BorrowGas = await regularAaveV3Borrow();
  const OVALAaveV3BorrowGas = await OVALAaveV3Borrow();
  const gasDiff = OVALAaveV3BorrowGas - regularAaveV3BorrowGas;

  console.log("Gas difference: " + gasDiff);
};
