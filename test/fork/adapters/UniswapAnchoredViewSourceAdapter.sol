// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {CommonTest} from "../../Common.sol";

import {IValidatorProxyTest} from "../interfaces/compoundV2/IValidatorProxy.sol";
import {MockChainlinkV3Aggregator} from "../../mocks/MockChainlinkV3Aggregator.sol";
import {UniswapAnchoredViewSourceAdapter} from
    "../../../src/adapters/source-adapters/UniswapAnchoredViewSourceAdapter.sol";
import {IAccessControlledAggregatorV3} from "../../../src/interfaces/chainlink/IAccessControlledAggregatorV3.sol";
import {IUniswapAnchoredView} from "../../../src/interfaces/compound/IUniswapAnchoredView.sol";

contract TestedSourceAdapter is UniswapAnchoredViewSourceAdapter {
    constructor(IUniswapAnchoredView source, address cToken) UniswapAnchoredViewSourceAdapter(source, cToken) {}
    function internalLatestData() public view override returns (int256, uint256) {}
    function canUnlock(address caller, uint256 cachedLatestTimestamp) public view virtual override returns (bool) {}
    function lockWindow() public view virtual override returns (uint256) {}
    function maxTraversal() public view virtual override returns (uint256) {}
}

contract UniswapAnchoredViewSourceAdapterTest is CommonTest {
    uint256 targetBlock = 18141580;

    uint256[] transmissionBlocks = [18141754, 18142049, 18142275]; // Known blocks where Chainlink prices were transmitted.

    IUniswapAnchoredView uniswapAnchoredView;
    TestedSourceAdapter sourceAdapter;
    address cToken = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5; // cETH
    IAccessControlledAggregatorV3 aggregator;

    function setUp() public {
        vm.createSelectFork("mainnet", targetBlock);
        uniswapAnchoredView = IUniswapAnchoredView(0x50ce56A3239671Ab62f185704Caedf626352741e);
        sourceAdapter = new TestedSourceAdapter(uniswapAnchoredView, cToken);
        aggregator = IAccessControlledAggregatorV3(address(sourceAdapter.aggregator()));

        _whitelistOnAggregator();
    }

    function testCorrectlyReturnsLatestSourceData() public {
        uint256 latestUniswapAnchoredViewAnswer = uniswapAnchoredView.getUnderlyingPrice(cToken);
        uint256 latestAggregatorTimestamp = aggregator.latestTimestamp();
        (int256 latestSourceAnswer, uint256 latestSourceTimestamp) = sourceAdapter.getLatestSourceData();

        // ETH has 18 decimals, so source price feed is scaled at (36 - 18) = 18 decimals and no conversion is needed.
        assertTrue(int256(latestUniswapAnchoredViewAnswer) == latestSourceAnswer);
        assertTrue(latestAggregatorTimestamp == latestSourceTimestamp);
    }

    function testCorrectlyStandardizesOutputs() public {
        // Repeat the same test as above, but with cWBTC where underlying has 8 decimals.
        address cWBTC = 0xccF4429DB6322D5C611ee964527D42E5d685DD6a;
        sourceAdapter = new TestedSourceAdapter(uniswapAnchoredView, cWBTC);
        aggregator = IAccessControlledAggregatorV3(address(sourceAdapter.aggregator()));
        _whitelistOnAggregator();

        uint256 latestUniswapAnchoredViewAnswer = uniswapAnchoredView.getUnderlyingPrice(cWBTC);
        uint256 latestAggregatorTimestamp = aggregator.latestTimestamp();
        (int256 latestSourceAnswer, uint256 latestSourceTimestamp) = sourceAdapter.getLatestSourceData();

        // WBTC has 8 decimals, so source price feed is scaled at (36 - 8) = 28 decimals.
        uint256 standardizedAnswer = latestUniswapAnchoredViewAnswer / 10 ** (28 - 18);
        assertTrue(int256(standardizedAnswer) == latestSourceAnswer);
        assertTrue(latestAggregatorTimestamp == latestSourceTimestamp);
    }

    function testReturnsLatestSourceDataNoSnapshot() public {
        uint256 targetTime = block.timestamp;

        // Fork ~24 hours (7200 blocks on mainnet) forward with persistent source adapter.
        vm.makePersistent(address(sourceAdapter));
        vm.createSelectFork("mainnet", targetBlock + 7200);
        _whitelistOnAggregator(); // Re-whitelist on new fork.

        // UniswapAnchoredView should have updated in the meantime.
        uint256 latestUniswapAnchoredViewAnswer = uniswapAnchoredView.getUnderlyingPrice(cToken);
        uint256 latestAggregatorTimestamp = aggregator.latestTimestamp();
        assertTrue(latestAggregatorTimestamp > targetTime);

        // UniswapAnchoredView does not support historical lookups so this should still return latest data without snapshotting.
        (int256 lookBackPrice, uint256 lookBackTimestamp) = sourceAdapter.tryLatestDataAt(targetTime, 100);
        assertTrue(int256(latestUniswapAnchoredViewAnswer) == lookBackPrice);
        assertTrue(latestAggregatorTimestamp == lookBackTimestamp);
    }

    function testCorrectlyLooksBackThroughSnapshots() public {
        (uint256[] memory snapshotAnswers, uint256[] memory snapshotTimestamps) = _snapshotOnTransmissionBlocks();

        for (uint256 i = 0; i < snapshotAnswers.length; i++) {
            // Lookback at exact snapshot timestamp should return the same answer and timestamp.
            (int256 lookBackPrice, uint256 lookBackTimestamp) = sourceAdapter.tryLatestDataAt(snapshotTimestamps[i], 10);
            assertTrue(int256(snapshotAnswers[i]) == lookBackPrice);
            assertTrue(snapshotTimestamps[i] == lookBackTimestamp);

            // Source updates were more than 30 minutes apart, so lookback 30 minutes later should return the same answer.
            (lookBackPrice, lookBackTimestamp) = sourceAdapter.tryLatestDataAt(snapshotTimestamps[i] + 1800, 10);
            assertTrue(int256(snapshotAnswers[i]) == lookBackPrice);
            assertTrue(snapshotTimestamps[i] == lookBackTimestamp);

            // Source updates were more than 30 minutes apart, so lookback 30 minutes earlier should return the previous answer,
            // except for the first snapshot which should return the same answer as it does not have earlier data.
            (lookBackPrice, lookBackTimestamp) = sourceAdapter.tryLatestDataAt(snapshotTimestamps[i] - 1800, 10);
            if (i > 0) {
                assertTrue(int256(snapshotAnswers[i - 1]) == lookBackPrice);
                assertTrue(snapshotTimestamps[i - 1] == lookBackTimestamp);
            } else {
                assertTrue(int256(snapshotAnswers[i]) == lookBackPrice);
                assertTrue(snapshotTimestamps[i] == lookBackTimestamp);
            }
        }
    }

    function testCorrectlyBoundsMaxLookBack() public {
        _snapshotOnTransmissionBlocks();

        // If we limit how far we can lookback the source adapter snapshot should correctly return the oldest data it
        // can find, up to that limit. When searching for the earliest possible snapshot while limiting maximum snapshot
        // traversal to 1 we should still get the latest data.
        (int256 lookBackPrice, uint256 lookBackTimestamp) = sourceAdapter.tryLatestDataAt(0, 1);
        uint256 latestUniswapAnchoredViewAnswer = uniswapAnchoredView.getUnderlyingPrice(cToken);
        uint256 latestAggregatorTimestamp = aggregator.latestTimestamp();
        assertTrue(int256(latestUniswapAnchoredViewAnswer) == lookBackPrice);
        assertTrue(latestAggregatorTimestamp == lookBackTimestamp);
    }

    function testUpgradeAggregator() public {
        // Deploy mock aggregator.
        MockChainlinkV3Aggregator newAggregator = new MockChainlinkV3Aggregator(8, 0);

        // Upgrade aggregator to a new version.
        IUniswapAnchoredView.TokenConfig memory tokenConfig =
            uniswapAnchoredView.getTokenConfigByCToken(address(cToken));
        IValidatorProxyTest validatorProxy = IValidatorProxyTest(tokenConfig.reporter);
        vm.startPrank(validatorProxy.owner());
        validatorProxy.proposeNewAggregator(address(newAggregator));
        validatorProxy.upgradeAggregator();
        vm.stopPrank();

        // Sync aggregator on source adapter and verify that it was updated.
        sourceAdapter.syncAggregatorSource();
        assertTrue(address(newAggregator) == address(sourceAdapter.aggregator()));
    }

    function _whitelistOnAggregator() internal {
        vm.startPrank(aggregator.owner());
        aggregator.addAccess(address(sourceAdapter));
        aggregator.addAccess(address(this)); // So that we can read aggregator directly.
        vm.stopPrank();
    }

    function _snapshotOnTransmissionBlocks() internal returns (uint256[] memory, uint256[] memory) {
        uint256[] memory snapshotAnswers = new uint256[](transmissionBlocks.length);
        uint256[] memory snapshotTimestamps = new uint256[](transmissionBlocks.length);

        // Fork forward with persistent source adapter and snapshot data at each poke block.
        vm.makePersistent(address(sourceAdapter));
        for (uint256 i = 0; i < transmissionBlocks.length; i++) {
            vm.createSelectFork("mainnet", transmissionBlocks[i]);
            _whitelistOnAggregator(); // Re-whitelist on new fork.
            snapshotAnswers[i] = uniswapAnchoredView.getUnderlyingPrice(cToken);
            snapshotTimestamps[i] = aggregator.latestTimestamp();
            sourceAdapter.snapshotData();

            // Check that source oracle was updated on each poke block.
            if (i > 0) assertTrue(snapshotTimestamps[i] > snapshotTimestamps[i - 1]);
        }

        return (snapshotAnswers, snapshotTimestamps);
    }
}
