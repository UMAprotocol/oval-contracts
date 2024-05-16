// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {CommonTest} from "../../Common.sol";

import {PythSourceAdapter} from "../../../src/adapters/source-adapters/PythSourceAdapter.sol";
import {IPyth} from "../../../src/interfaces/pyth/IPyth.sol";

contract TestedSourceAdapter is PythSourceAdapter {
    constructor(IPyth source, bytes32 priceId) PythSourceAdapter(source, priceId) {}

    function internalLatestData() public view override returns (int256, uint256) {}

    function canUnlock(address caller, uint256 cachedLatestTimestamp) public view virtual override returns (bool) {}

    function lockWindow() public view virtual override returns (uint256) {}

    function maxTraversal() public view virtual override returns (uint256) {}
}

contract PythSourceAdapterTest is CommonTest {
    uint256 targetBlock = 16125730; // Pyth ETH/USD received updates both before and after this block.

    uint256[] updateBlocks = [16125712, 16125717, 16125741]; // Known blocks where Pyth ETH/USD was updated.

    IPyth pyth;
    TestedSourceAdapter sourceAdapter;
    bytes32 priceId = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace; // ETH/USD

    function setUp() public {
        vm.createSelectFork("mainnet", targetBlock);
        pyth = IPyth(0x4305FB66699C3B2702D4d05CF36551390A4c69C6);
        sourceAdapter = new TestedSourceAdapter(pyth, priceId);
    }

    function testCorrectlyStandardizesOutputs() public {
        IPyth.Price memory pythPrice = pyth.getPriceUnsafe(priceId);
        (int256 latestSourceAnswer, uint256 latestSourceTimestamp) = sourceAdapter.getLatestSourceData();
        assertTrue(_scalePythTo18(pythPrice) == latestSourceAnswer);
        assertTrue(pythPrice.publishTime == latestSourceTimestamp);
    }

    function testReturnsLatestSourceDataNoSnapshot() public {
        uint256 targetTime = block.timestamp; // This should be bit before the latest known source update.

        // Fork 1 block past last known source update with persistent source adapter.
        vm.makePersistent(address(sourceAdapter));
        vm.createSelectFork("mainnet", updateBlocks[updateBlocks.length - 1] + 1);

        // Pyth should have updated in the meantime.
        IPyth.Price memory latestPythPrice = pyth.getPriceUnsafe(priceId);
        assertTrue(latestPythPrice.publishTime > targetTime);

        // Pyth does not support historical lookups so this should still return latest data without snapshotting.
        (int256 lookBackPrice, uint256 lookBackTimestamp) = sourceAdapter.tryLatestDataAt(targetTime, 100);
        assertTrue(_scalePythTo18(latestPythPrice) == lookBackPrice);
        assertTrue(latestPythPrice.publishTime == lookBackTimestamp);
    }

    function testCorrectlyLooksBackThroughSnapshots() public {
        (int256[] memory snapshotAnswers, uint256[] memory snapshotTimestamps) = _snapshotOnUpdateBlocks();

        for (uint256 i = 0; i < snapshotAnswers.length; i++) {
            // Lookback at exact snapshot timestamp should return the same answer and timestamp.
            (int256 lookBackPrice, uint256 lookBackTimestamp) = sourceAdapter.tryLatestDataAt(snapshotTimestamps[i], 10);
            assertTrue(snapshotAnswers[i] == lookBackPrice);
            assertTrue(snapshotTimestamps[i] == lookBackTimestamp);

            // Source updates were more than 1 minute apart, so lookback 1 minute later should return the same answer.
            (lookBackPrice, lookBackTimestamp) = sourceAdapter.tryLatestDataAt(snapshotTimestamps[i] + 60, 10);
            assertTrue(snapshotAnswers[i] == lookBackPrice);
            assertTrue(snapshotTimestamps[i] == lookBackTimestamp);

            // Source updates were more than 1 minute apart, so lookback 1 minute earlier should return the previous answer,
            // except for the first snapshot which should return the same answer as it does not have earlier data.
            (lookBackPrice, lookBackTimestamp) = sourceAdapter.tryLatestDataAt(snapshotTimestamps[i] - 60, 10);
            if (i > 0) {
                assertTrue(snapshotAnswers[i - 1] == lookBackPrice);
                assertTrue(snapshotTimestamps[i - 1] == lookBackTimestamp);
            } else {
                assertTrue(snapshotAnswers[i] == lookBackPrice);
                assertTrue(snapshotTimestamps[i] == lookBackTimestamp);
            }
        }
    }

    function testCorrectlyBoundsMaxLookBack() public {
        _snapshotOnUpdateBlocks();

        // If we limit how far we can lookback the source adapter snapshot should correctly return the oldest data it
        // can find, up to that limit. When searching for the earliest possible snapshot while limiting maximum snapshot
        // traversal to 1 we should still get the latest data.
        (int256 lookBackPrice, uint256 lookBackTimestamp) = sourceAdapter.tryLatestDataAt(0, 1);
        IPyth.Price memory latestPythPrice = pyth.getPriceUnsafe(priceId);
        assertTrue(_scalePythTo18(latestPythPrice) == lookBackPrice);
        assertTrue(latestPythPrice.publishTime == lookBackTimestamp);
    }

    function testPositiveExpo() public {
        _snapshotOnUpdateBlocks();

        IPyth.Price memory latestPythPrice = pyth.getPriceUnsafe(priceId);
        latestPythPrice.expo = 1;
        latestPythPrice.price = 1;

        vm.mockCall(
            0x4305FB66699C3B2702D4d05CF36551390A4c69C6,
            abi.encodeWithSelector(IPyth.getPriceUnsafe.selector, priceId),
            abi.encode(latestPythPrice)
        );

        (int256 latestSourceAnswer, uint256 latestSourceTimestamp) = sourceAdapter.getLatestSourceData();

        assertTrue(latestSourceAnswer == 10 ** 19);
        assertTrue(latestPythPrice.publishTime == latestSourceTimestamp);
    }

    function _scalePythTo18(IPyth.Price memory pythPrice) internal returns (int256) {
        assertTrue(pythPrice.expo <= 0);
        if (pythPrice.expo >= -18) {
            return pythPrice.price * int256(10 ** uint32(18 + pythPrice.expo));
        } else {
            return pythPrice.price / int256(10 ** uint32(-pythPrice.expo - 18));
        }
    }

    function _snapshotOnUpdateBlocks() internal returns (int256[] memory, uint256[] memory) {
        int256[] memory snapshotAnswers = new int256[](updateBlocks.length);
        uint256[] memory snapshotTimestamps = new uint256[](updateBlocks.length);

        // Fork forward with persistent source adapter and snapshot data at each update block.
        vm.makePersistent(address(sourceAdapter));
        for (uint256 i = 0; i < updateBlocks.length; i++) {
            vm.createSelectFork("mainnet", updateBlocks[i]);
            IPyth.Price memory pythPrice = pyth.getPriceUnsafe(priceId);
            snapshotAnswers[i] = _scalePythTo18(pythPrice);
            snapshotTimestamps[i] = pythPrice.publishTime;
            sourceAdapter.snapshotData();

            // Check that source oracle was updated on each update block.
            if (i > 0) {
                assertTrue(snapshotTimestamps[i] > snapshotTimestamps[i - 1]);
            }
        }

        return (snapshotAnswers, snapshotTimestamps);
    }
}
