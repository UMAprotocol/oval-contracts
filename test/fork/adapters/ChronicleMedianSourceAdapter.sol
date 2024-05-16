// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {CommonTest} from "../../Common.sol";

import {ChronicleMedianSourceAdapter} from "../../../src/adapters/source-adapters/ChronicleMedianSourceAdapter.sol";
import {IMedian} from "../../../src/interfaces/chronicle/IMedian.sol";

contract TestedSourceAdapter is ChronicleMedianSourceAdapter {
    constructor(IMedian source) ChronicleMedianSourceAdapter(source) {}
    function internalLatestData() public view override returns (int256, uint256) {}
    function canUnlock(address caller, uint256 cachedLatestTimestamp) public view virtual override returns (bool) {}
    function lockWindow() public view virtual override returns (uint256) {}
    function maxTraversal() public view virtual override returns (uint256) {}
}

contract ChronicleMedianSourceAdapterTest is CommonTest {
    uint256 targetBlock = 18141580;

    uint256[] pokeBlocks = [18141853, 18142932, 18144016]; // Known blocks where Chronicle was poked.

    IMedian chronicle;
    TestedSourceAdapter sourceAdapter;

    function setUp() public {
        vm.createSelectFork("mainnet", targetBlock);
        chronicle = IMedian(0x64DE91F5A373Cd4c28de3600cB34C7C6cE410C85); // Chronicle MedianETHUSD
        sourceAdapter = new TestedSourceAdapter(chronicle);

        _whitelistOnChronicle();
    }

    function testCorrectlyReturnsLatestSourceData() public {
        uint256 latestChronicleAnswer = chronicle.read();
        uint256 latestChronicleTimestamp = chronicle.age();
        (int256 latestSourceAnswer, uint256 latestSourceTimestamp) = sourceAdapter.getLatestSourceData();
        assertTrue(int256(latestChronicleAnswer) == latestSourceAnswer);
        assertTrue(latestSourceTimestamp == latestChronicleTimestamp);
    }

    function testReturnsLatestSourceDataNoSnapshot() public {
        uint256 targetTime = block.timestamp;

        // Fork ~24 hours (7200 blocks on mainnet) forward with persistent source adapter.
        vm.makePersistent(address(sourceAdapter));
        vm.createSelectFork("mainnet", targetBlock + 7200);
        _whitelistOnChronicle(); // Re-whitelist on new fork.

        // Chronicle should have updated in the meantime.
        uint256 latestChronicleAnswer = chronicle.read();
        uint256 latestChronicleTimestamp = chronicle.age();
        assertTrue(latestChronicleTimestamp > targetTime);

        // Chronicle does not support historical lookups so this should still return latest data without snapshotting.
        (int256 lookBackPrice, uint256 lookBackTimestamp) = sourceAdapter.tryLatestDataAt(targetTime, 100);
        assertTrue(int256(latestChronicleAnswer) == lookBackPrice);
        assertTrue(latestChronicleTimestamp == lookBackTimestamp);
    }

    function testCorrectlyLooksBackThroughSnapshots() public {
        (uint256[] memory snapshotAnswers, uint256[] memory snapshotTimestamps) = _snapshotOnPokeBlocks();

        for (uint256 i = 0; i < snapshotAnswers.length; i++) {
            // Lookback at exact snapshot timestamp should return the same answer and timestamp.
            (int256 lookBackPrice, uint256 lookBackTimestamp) = sourceAdapter.tryLatestDataAt(snapshotTimestamps[i], 10);
            assertTrue(int256(snapshotAnswers[i]) == lookBackPrice);
            assertTrue(snapshotTimestamps[i] == lookBackTimestamp);

            // Source updates were more than 1 hour apart, so lookback 1 hour later should return the same answer.
            (lookBackPrice, lookBackTimestamp) = sourceAdapter.tryLatestDataAt(snapshotTimestamps[i] + 3600, 10);
            assertTrue(int256(snapshotAnswers[i]) == lookBackPrice);
            assertTrue(snapshotTimestamps[i] == lookBackTimestamp);

            // Source updates were more than 1 hour apart, so lookback 1 hour earlier should return the previous answer,
            // except for the first snapshot which should return the same answer as it does not have earlier data.
            (lookBackPrice, lookBackTimestamp) = sourceAdapter.tryLatestDataAt(snapshotTimestamps[i] - 3600, 10);
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
        _snapshotOnPokeBlocks();

        // If we limit how far we can lookback the source adapter snapshot should correctly return the oldest data it
        // can find, up to that limit. When searching for the earliest possible snapshot while limiting maximum snapshot
        // traversal to 1 we should still get the latest data.
        (int256 lookBackPrice, uint256 lookBackTimestamp) = sourceAdapter.tryLatestDataAt(0, 1);
        uint256 latestChronicleAnswer = chronicle.read();
        uint256 latestChronicleTimestamp = chronicle.age();
        assertTrue(int256(latestChronicleAnswer) == lookBackPrice);
        assertTrue(latestChronicleTimestamp == lookBackTimestamp);
    }

    function _whitelistOnChronicle() internal {
        vm.startPrank(0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB); // DSPause that is a ward (can add kiss to chronicle)
        chronicle.kiss(address(sourceAdapter));
        chronicle.kiss(address(this)); // So that we can read Chronicle directly.
        vm.stopPrank();
    }

    function _snapshotOnPokeBlocks() internal returns (uint256[] memory, uint256[] memory) {
        uint256[] memory snapshotAnswers = new uint256[](pokeBlocks.length);
        uint256[] memory snapshotTimestamps = new uint256[](pokeBlocks.length);

        // Fork forward with persistent source adapter and snapshot data at each poke block.
        vm.makePersistent(address(sourceAdapter));
        for (uint256 i = 0; i < pokeBlocks.length; i++) {
            vm.createSelectFork("mainnet", pokeBlocks[i]);
            _whitelistOnChronicle(); // Re-whitelist on new fork.
            snapshotAnswers[i] = chronicle.read();
            snapshotTimestamps[i] = chronicle.age();
            sourceAdapter.snapshotData();

            // Check that source oracle was updated on each poke block.
            if (i > 0) assertTrue(snapshotTimestamps[i] > snapshotTimestamps[i - 1]);
        }

        return (snapshotAnswers, snapshotTimestamps);
    }
}
