// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {CommonTest} from "../../Common.sol";

import {OSMSourceAdapter} from "../../../src/adapters/source-adapters/OSMSourceAdapter.sol";
import {IOSM} from "../../../src/interfaces/makerdao/IOSM.sol";
import {IMedian} from "../../../src/interfaces/chronicle/IMedian.sol";

contract TestedSourceAdapter is OSMSourceAdapter {
    constructor(IOSM source) OSMSourceAdapter(source) {}
    function internalLatestData() public view override returns (int256, uint256, uint256) {}
    function internalDataAtRound(uint256 roundId) public view override returns (int256, uint256) {}
    function canUnlock(address caller, uint256 cachedLatestTimestamp) public view virtual override returns (bool) {}
    function lockWindow() public view virtual override returns (uint256) {}
    function maxTraversal() public view virtual override returns (uint256) {}
    function maxAge() public view virtual override returns (uint256) {}
}

contract OSMSourceAdapterTest is CommonTest {
    uint256 targetBlock = 18141580;

    uint256[] pokeBlocks = [18141778, 18142073, 18142367]; // Known blocks where OSM was poked.

    IOSM osm;
    TestedSourceAdapter sourceAdapter;

    function setUp() public {
        vm.createSelectFork("mainnet", targetBlock);
        osm = IOSM(0x81FE72B5A8d1A857d176C3E7d5Bd2679A9B85763); // MakerDAO ETH-A OSM.
        sourceAdapter = new TestedSourceAdapter(osm);

        _whitelistOnOSM();
    }

    function testCorrectlyReturnsLatestSourceData() public {
        bytes32 latestOSMAnswer = osm.read();
        uint64 latestOSMTimestamp = osm.zzz();
        (int256 latestSourceAnswer, uint256 latestSourceTimestamp) = sourceAdapter.getLatestSourceData();
        assertTrue(int256(uint256(latestOSMAnswer)) == latestSourceAnswer);
        assertTrue(latestOSMTimestamp == latestSourceTimestamp);
    }

    function testReturnsLatestSourceDataNoSnapshot() public {
        uint256 targetTime = block.timestamp;

        // Fork ~24 hours (7200 blocks on mainnet) forward with persistent source adapter.
        vm.makePersistent(address(sourceAdapter));
        vm.createSelectFork("mainnet", targetBlock + 7200);
        _whitelistOnOSM(); // Re-whitelist on new fork.

        // OSM should have updated in the meantime.
        bytes32 latestOSMAnswer = osm.read();
        uint64 latestOSMTimestamp = osm.zzz();
        assertTrue(latestOSMTimestamp > targetTime);

        // OSM does not support historical lookups so this should still return latest data without snapshotting.
        (int256 lookBackPrice, uint256 lookBackTimestamp, uint256 lookBackRoundId) =
            sourceAdapter.tryLatestDataAt(targetTime, 100);
        assertTrue(int256(uint256(latestOSMAnswer)) == lookBackPrice);
        assertTrue(latestOSMTimestamp == lookBackTimestamp);
        assertTrue(lookBackRoundId == 1); // roundId not supported, hardcoded to 1.
    }

    function testCorrectlyLooksBackThroughSnapshots() public {
        (uint256[] memory snapshotAnswers, uint256[] memory snapshotTimestamps) = _snapshotOnPokeBlocks();

        for (uint256 i = 0; i < snapshotAnswers.length; i++) {
            // Lookback at exact snapshot timestamp should return the same answer and timestamp.
            (int256 lookBackPrice, uint256 lookBackTimestamp, uint256 lookBackRoundId) =
                sourceAdapter.tryLatestDataAt(snapshotTimestamps[i], 10);
            assertTrue(int256(snapshotAnswers[i]) == lookBackPrice);
            assertTrue(snapshotTimestamps[i] == lookBackTimestamp);
            assertTrue(lookBackRoundId == 1); // roundId not supported, hardcoded to 1.

            // Source updates were ~1 hour apart, so lookback 10 minutes later should return the same answer.
            (lookBackPrice, lookBackTimestamp, lookBackRoundId) =
                sourceAdapter.tryLatestDataAt(snapshotTimestamps[i] + 600, 10);
            assertTrue(int256(snapshotAnswers[i]) == lookBackPrice);
            assertTrue(snapshotTimestamps[i] == lookBackTimestamp);
            assertTrue(lookBackRoundId == 1); // roundId not supported, hardcoded to 1.

            // Source updates were ~1 hour apart, so lookback 10 minutes earlier should return the previous answer,
            // except for the first snapshot which should return the same answer as it does not have earlier data.
            (lookBackPrice, lookBackTimestamp, lookBackRoundId) =
                sourceAdapter.tryLatestDataAt(snapshotTimestamps[i] - 600, 10);
            assertTrue(lookBackRoundId == 1); // roundId not supported, hardcoded to 1.
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
        (int256 lookBackPrice, uint256 lookBackTimestamp, uint256 lookBackRoundId) = sourceAdapter.tryLatestDataAt(0, 1);
        bytes32 latestOSMAnswer = osm.read();
        uint64 latestOSMTimestamp = osm.zzz();
        assertTrue(int256(uint256(latestOSMAnswer)) == lookBackPrice);
        assertTrue(latestOSMTimestamp == lookBackTimestamp);
        assertTrue(lookBackRoundId == 1); // roundId not supported, hardcoded to 1.
    }

    function _whitelistOnOSM() internal {
        vm.startPrank(0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB); // DSPause that is a ward (can add kiss to OSM)
        IMedian(address(osm)).kiss(address(sourceAdapter));
        IMedian(address(osm)).kiss(address(this)); // So that we can read OSM directly.
        vm.stopPrank();
    }

    function _snapshotOnPokeBlocks() internal returns (uint256[] memory, uint256[] memory) {
        uint256[] memory snapshotAnswers = new uint256[](pokeBlocks.length);
        uint256[] memory snapshotTimestamps = new uint256[](pokeBlocks.length);

        // Fork forward with persistent source adapter and snapshot data at each poke block.
        vm.makePersistent(address(sourceAdapter));
        for (uint256 i = 0; i < pokeBlocks.length; i++) {
            vm.createSelectFork("mainnet", pokeBlocks[i]);
            _whitelistOnOSM(); // Re-whitelist on new fork.
            snapshotAnswers[i] = uint256(osm.read());
            snapshotTimestamps[i] = osm.zzz();
            sourceAdapter.snapshotData();

            // Check that source oracle was updated on each poke block.
            if (i > 0) assertTrue(snapshotTimestamps[i] > snapshotTimestamps[i - 1]);
        }

        return (snapshotAnswers, snapshotTimestamps);
    }
}
