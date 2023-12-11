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
import { TestedOVAL__factory } from "../../contract-types/factories/CompoundV2.Liquidation.sol/TestedOVAL__factory";

// Common constants.
// Compound liquidation https://etherscan.io/tx/0xb955a078b9b2a73e111033a3e77142b5768f5729285279d56eff641e43060555
const blockNumber = 18115157;
const chainId = 1;
const cETHAddress = "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5";
const comptrollerAddress = "0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B";
const uniswapAnchoredViewSourceAddress =
  "0x50ce56A3239671Ab62f185704Caedf626352741e";

// Used ABIs.
const cTokenAbi = [
  "function mint() payable",
  "function borrow(uint borrowAmount) returns (uint)",
  "function liquidateBorrow(address borrower, uint256 repayAmount, address cTokenCollateral) returns (uint256)",
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

const liquidateBorrow = async (
  forkTimestamp: number,
  forkId: string,
  rootId?: string // If not provided, the simulation starts off the fork initial state.
): Promise<TenderlySimulationResult> => {
  // Post collateral.
  let simulation: TenderlySimulationResult;
  const cTokenInterface = new utils.Interface(cTokenAbi);
  const liquidateInput = cTokenInterface.encodeFunctionData("liquidateBorrow", [
    "0xFeECA8db8b5f4Efdb16BA43d3D06ad2F568a52E3",
    "14528113530",
    cETHAddress,
  ]);
  simulation = await simulateTenderlyTx({
    chainId,
    from: "0x50A77BA863dBaA84269133e5625EF80072f1884a",
    to: "0x39aa39c021dfbae8fac545936693ac917d5e7563",
    value: "0",
    input: liquidateInput,
    timestampOverride: forkTimestamp,
    fork: { id: forkId, root: rootId },
    description: "Liquidate Borrow",
  });

  return simulation;
};

const regularCompoundLiquidation = async (): Promise<number> => {
  // Create and share new fork (delete the old one if it exists).
  const alias = "Regular Compound Liquidation";
  const description = "Generated: " + utils.keccak256(utils.toUtf8Bytes(alias));
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
  const forkTimestamp = (await provider.getBlock(blockNumber)).timestamp;

  // Open user position.
  const simulation = await liquidateBorrow(forkTimestamp, fork.id); // Start off the initial fork state.

  console.log("Simulated " + alias + " in " + simulation.resultUrl.url);
  console.log("  Consumed gas: " + simulation.gasUsed);
  console.log("  Fork URL: " + forkUrl + "\n");

  return simulation.gasUsed;
};

const OVALCompoundLiquidation = async (): Promise<number> => {
  // Create and share new fork (delete the old one if it exists).
  const alias = "OVAL Compound Liquidation";
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

  // Deploy OVAL.
  const testedOVALFactory = new TestedOVAL__factory(ownerSigner);
  const testedOVAL = await testedOVALFactory.deploy(
    uniswapAnchoredViewSourceAddress,
    cETHAddress
  );
  await testedOVAL.deployTransaction.wait();
  fork = await getTenderlyFork(fork.id); // Refresh to get head id since we submitted tx through RPC.
  if (!fork.headId) throw new Error("Fork head id not found.");
  await setForkSimulationDescription(fork.id, fork.headId, "Deploy OVAL");

  // Set TestedOVAL on UniswapAnchoredViewDestinationAdapter.
  const setOVALInput =
    uavDestinationAdapterFactory.interface.encodeFunctionData("setOVAL", [
      cETHAddress,
      testedOVAL.address,
    ]);
  let simulation = await simulateTenderlyTx({
    chainId,
    from: ownerAddress,
    to: uavDestinationAdapter.address,
    input: setOVALInput,
    timestampOverride: forkTimestamp,
    fork: { id: fork.id, root: fork.headId },
    description: "Set OVAL",
  });

  // Enable unlocker on TestedOVAL.
  const setUnlockerInput = testedOVALFactory.interface.encodeFunctionData(
    "setUnlocker",
    [unlockerAddress, true]
  );
  simulation = await simulateTenderlyTx({
    chainId,
    from: ownerAddress,
    to: testedOVAL.address,
    input: setUnlockerInput,
    timestampOverride: forkTimestamp,
    fork: { id: fork.id, root: simulation.id },
    description: "Enable unlocker on OVAL",
  });

  // Whitelist TestedOVAL on chainlink
  const sourceChainlinkOracleAddress =
    await testedOVAL.callStatic.aggregator();
  const sourceChainlinkOracle = new Contract(
    sourceChainlinkOracleAddress,
    accessControlledOffchainAggregatorAbi,
    provider
  );
  const sourceChainlinkOracleOwner =
    await sourceChainlinkOracle.callStatic.owner();
  const addAccessInput = sourceChainlinkOracle.interface.encodeFunctionData(
    "addAccess",
    [testedOVAL.address]
  );
  simulation = await simulateTenderlyTx({
    chainId,
    from: sourceChainlinkOracleOwner,
    to: sourceChainlinkOracleAddress,
    input: addAccessInput,
    timestampOverride: forkTimestamp,
    fork: { id: fork.id, root: simulation.id },
    description: "Whitelist OVAL on Chainlink",
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
  simulation = await liquidateBorrow(forkTimestamp, fork.id, simulation.id);

  console.log("Simulated " + alias + " in " + simulation.resultUrl.url);
  console.log("  Consumed gas: " + simulation.gasUsed);
  console.log("  Fork URL: " + forkUrl + "\n");

  return simulation.gasUsed;
};

export const compoundLiquidation = async () => {
  console.log("Compound Liquidation gas comparison with unlock:\n");

  const regularCompoundBorrowGas = await regularCompoundLiquidation();
  const OVALCompoundBorrowGas = await OVALCompoundLiquidation();
  const gasDiff = OVALCompoundBorrowGas - regularCompoundBorrowGas;

  console.log("Gas difference: " + gasDiff);
};
