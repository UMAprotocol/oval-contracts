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
import { TestedOval__factory } from "../../contract-types/factories/CompoundV2.Liquidation.sol/TestedOval__factory";

// Common constants.
const blockNumber = 18390940; // Latest as of writing this script.
const chainId = 1;
const cETHAddress = "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5";
const cUSDCAddress = "0x39AA39c021dfbaE8faC545936693aC917d5E7563";
const comptrollerAddress = "0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B";
const uniswapAnchoredViewSourceAddress =
  "0x50ce56A3239671Ab62f185704Caedf626352741e";
const collateralAmount = utils.parseEther("1"); // 1 ETH
const borrowAmount = utils.parseUnits("1000", 6); // 1000 USDC (should be below borrow limit)

// Used ABIs.
const cTokenAbi = [
  "function mint() payable",
  "function borrow(uint borrowAmount) returns (uint)",
];
const comptrollerAbi = [
  "function enterMarkets(address[] memory cTokens) returns (uint[] memory)",
  "function admin() returns (address)",
  "function _setPriceOracle(address newOracle) returns (uint)",
];
const accessControlledOffchainAggregatorAbi = [
  "function owner() returns (address)",
  "function addAccess(address)",
];

const mintAndBorrow = async (
  userAddress: string,
  forkTimestamp: number,
  forkId: string,
  rootId?: string // If not provided, the simulation starts off the fork initial state.
): Promise<TenderlySimulationResult> => {
  // Post collateral.
  let simulation: TenderlySimulationResult;
  const cTokenInterface = new utils.Interface(cTokenAbi);
  const mintInput = cTokenInterface.encodeFunctionData("mint");
  simulation = await simulateTenderlyTx({
    chainId,
    from: userAddress,
    to: cETHAddress,
    value: collateralAmount.toString(),
    input: mintInput,
    timestampOverride: forkTimestamp,
    fork: { id: forkId, root: rootId },
    description: "Deposit ETH",
  });

  // Enable collateral to be used for borrowing.
  const comptrollerInterface = new utils.Interface(comptrollerAbi);
  const enterMarketsInput = comptrollerInterface.encodeFunctionData(
    "enterMarkets",
    [[cETHAddress]]
  );
  simulation = await simulateTenderlyTx({
    chainId,
    from: userAddress,
    to: comptrollerAddress,
    input: enterMarketsInput,
    timestampOverride: forkTimestamp,
    fork: { id: forkId, root: simulation.id },
    description: "Enable ETH as collateral",
  });

  // Borrow USDC.
  const borrowInput = cTokenInterface.encodeFunctionData("borrow", [
    borrowAmount.toString(),
  ]);
  simulation = await simulateTenderlyTx({
    chainId,
    from: userAddress,
    to: cUSDCAddress,
    input: borrowInput,
    timestampOverride: forkTimestamp,
    fork: { id: forkId, root: simulation.id },
    description: "Borrow USDC",
  });

  return simulation;
};

const regularCompoundBorrow = async (): Promise<number> => {
  // Create and share new fork (delete the old one if it exists).
  const alias = "Regular Compound Borrow";
  const description =
    "Genereated: " + utils.keccak256(utils.toUtf8Bytes(alias));
  const existingFork = await findForkByDescription(description);
  if (existingFork) await deleteTenderlyFork(existingFork.id);
  const fork = await createTenderlyFork({
    chainId,
    alias,
    description,
    blockNumber,
  });
  const forkUrl = await shareTenderlyFork(fork.id);

  // Get provider, accounts and start time of the fork.
  const provider = new providers.StaticJsonRpcProvider(fork.rpcUrl);
  const [userAddress] = await provider.listAccounts(); // This should have 100 ETH balance.
  const forkTimestamp = (await provider.getBlock(blockNumber)).timestamp;

  // Open user position.
  const simulation = await mintAndBorrow(userAddress, forkTimestamp, fork.id); // Start off the initial fork state.

  console.log("Simulated " + alias + " in " + simulation.resultUrl.url);
  console.log("  Consumed gas: " + simulation.gasUsed);
  console.log("  Fork URL: " + forkUrl + "\n");

  return simulation.gasUsed;
};

const OvalCompoundBorrow = async (): Promise<number> => {
  // Create and share new fork (delete the old one if it exists).
  const alias = "Oval Compound Borrow";
  const description =
    "Genereated: " + utils.keccak256(utils.toUtf8Bytes(alias));
  const existingFork = await findForkByDescription(description);
  if (existingFork) await deleteTenderlyFork(existingFork.id);
  let fork = await createTenderlyFork({
    chainId,
    alias,
    description,
    blockNumber,
  });
  const forkUrl = await shareTenderlyFork(fork.id);

  // Get provider, accounts and start time of the fork.
  const provider = new providers.StaticJsonRpcProvider(fork.rpcUrl);
  const [ownerAddress, userAddress, unlockerAddress] =
    await provider.listAccounts(); // These should have 100 ETH balance.
  const ownerSigner = provider.getSigner(ownerAddress);
  const forkTimestamp = (await provider.getBlock(blockNumber)).timestamp;

  // Deploy UniswapAnchoredViewDestinationAdapter.
  const uavDestinationAdapterFactory =
    new UniswapAnchoredViewDestinationAdapter__factory(ownerSigner);
  const uavDestinationAdapter = await uavDestinationAdapterFactory.deploy(
    uniswapAnchoredViewSourceAddress
  );
  await uavDestinationAdapter.deployTransaction.wait();
  fork = await getTenderlyFork(fork.id); // Refresh to get head id since we submitted tx through RPC.
  if (!fork.headId) throw new Error("Fork head id not found.");
  await setForkSimulationDescription(
    fork.id,
    fork.headId,
    "Deploy UniswapAnchoredViewDestinationAdapter"
  );

  // Deploy Oval.
  const testedOvalFactory = new TestedOval__factory(ownerSigner);
  const testedOval = await testedOvalFactory.deploy(
    uniswapAnchoredViewSourceAddress,
    cETHAddress
  );
  await testedOval.deployTransaction.wait();
  fork = await getTenderlyFork(fork.id); // Refresh to get head id since we submitted tx through RPC.
  if (!fork.headId) throw new Error("Fork head id not found.");
  await setForkSimulationDescription(
    fork.id,
    fork.headId,
    "Deploy Oval"
  );

  // Set TestedOval on UniswapAnchoredViewDestinationAdapter.
  const setOvalInput =
    uavDestinationAdapterFactory.interface.encodeFunctionData("setOval", [
      cETHAddress,
      testedOval.address,
    ]);
  let simulation = await simulateTenderlyTx({
    chainId,
    from: ownerAddress,
    to: uavDestinationAdapter.address,
    input: setOvalInput,
    timestampOverride: forkTimestamp,
    fork: { id: fork.id, root: fork.headId },
    description: "Set Oval",
  });

  // Enable unlocker on TestedOval.
  const setUnlockerInput = testedOvalFactory.interface.encodeFunctionData(
    "setUnlocker",
    [unlockerAddress, true]
  );
  simulation = await simulateTenderlyTx({
    chainId,
    from: ownerAddress,
    to: testedOval.address,
    input: setUnlockerInput,
    timestampOverride: forkTimestamp,
    fork: { id: fork.id, root: simulation.id },
    description: "Enable unlocker on Oval",
  });

  // Whitelist TestedOval on chainlink
  const sourceChainlinkOracleAddress =
    await testedOval.callStatic.aggregator();
  const sourceChainlinkOracle = new Contract(
    sourceChainlinkOracleAddress,
    accessControlledOffchainAggregatorAbi,
    provider
  );
  const sourceChainlinkOracleOwner =
    await sourceChainlinkOracle.callStatic.owner();
  const addAccessInput = sourceChainlinkOracle.interface.encodeFunctionData(
    "addAccess",
    [testedOval.address]
  );
  simulation = await simulateTenderlyTx({
    chainId,
    from: sourceChainlinkOracleOwner,
    to: sourceChainlinkOracleAddress,
    input: addAccessInput,
    timestampOverride: forkTimestamp,
    fork: { id: fork.id, root: simulation.id },
    description: "Whitelist Oval on Chainlink",
  });

  // Point Comptroller to UniswapAnchoredViewDestinationAdapter.
  const comptroller = new Contract(
    comptrollerAddress,
    comptrollerAbi,
    provider
  );
  const comptrollerAdmin = await comptroller.callStatic.admin();
  const setPriceOracleInput = comptroller.interface.encodeFunctionData(
    "_setPriceOracle",
    [uavDestinationAdapter.address]
  );
  simulation = await simulateTenderlyTx({
    chainId,
    from: comptrollerAdmin,
    to: comptrollerAddress,
    input: setPriceOracleInput,
    timestampOverride: forkTimestamp,
    fork: { id: fork.id, root: simulation.id },
    description: "Switch Oracle on Comptroller",
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
  simulation = await mintAndBorrow(
    userAddress,
    forkTimestamp,
    fork.id,
    simulation.id
  );

  console.log("Simulated " + alias + " in " + simulation.resultUrl.url);
  console.log("  Consumed gas: " + simulation.gasUsed);
  console.log("  Fork URL: " + forkUrl + "\n");

  return simulation.gasUsed;
};

export const compoundBorrow = async () => {
  console.log("Compound Borrow gas comparison with unlock:\n");

  const regularCompoundBorrowGas = await regularCompoundBorrow();
  const OvalCompoundBorrowGas = await OvalCompoundBorrow();
  const gasDiff = OvalCompoundBorrowGas - regularCompoundBorrowGas;

  console.log("Gas difference: " + gasDiff);
};
