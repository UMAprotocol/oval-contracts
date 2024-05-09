// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {Oval} from "../../src/Oval.sol";
import {BaseDestinationAdapter} from "../../src/adapters/destination-adapters/BaseDestinationAdapter.sol";
import {ChainlinkDestinationAdapter} from "../../src/adapters/destination-adapters/ChainlinkDestinationAdapter.sol";
import {BaseController} from "../../src/controllers/BaseController.sol";
import {CommonTest} from "../Common.sol";
import {MockSourceAdapter} from "../mocks/MockSourceAdapter.sol";

contract TestOval is BaseController, MockSourceAdapter, ChainlinkDestinationAdapter {
    constructor(uint8 decimals) BaseController() MockSourceAdapter(decimals) ChainlinkDestinationAdapter(decimals) {}
}

contract OvalChainlinkDestinationAdapter is CommonTest {
    int256 initialPrice = 1895 * 1e18;
    uint256 initialTimestamp = 1690000000;

    int256 newAnswer = 1900 * 1e18;
    uint256 newTimestamp = initialTimestamp + 1;

    uint8 sourceOracleDecimals = 8;

    int256 internalDecimalsToSourceDecimals = 1e10;

    TestOval oval;

    function setUp() public {
        vm.warp(initialTimestamp);

        vm.startPrank(owner);
        oval = new TestOval(sourceOracleDecimals);
        oval.setUnlocker(permissionedUnlocker, true);
        vm.stopPrank();

        oval.publishRoundData(initialPrice, initialTimestamp);
    }

    function verifyOvalMatchesOval() public {
        (int256 latestAnswer, uint256 latestTimestamp,) = oval.internalLatestData();
        assertTrue(
            latestAnswer / internalDecimalsToSourceDecimals == oval.latestAnswer()
                && latestTimestamp == oval.latestTimestamp()
        );
    }

    function syncOvalWithOval() public {
        assertTrue(oval.canUnlock(permissionedUnlocker, oval.latestTimestamp()));
        vm.prank(permissionedUnlocker);
        oval.unlockLatestValue();
        verifyOvalMatchesOval();
    }

    function testUpdatesWithinLockWindow() public {
        // Publish an update to the mock source adapter.
        oval.publishRoundData(newAnswer, newTimestamp);

        syncOvalWithOval();
        assertTrue(oval.lastUnlockTime() == block.timestamp);

        // Apply an unlock with no diff in source adapter.
        uint256 unlockTimestamp = block.timestamp + 1 minutes;
        vm.warp(unlockTimestamp);
        vm.prank(permissionedUnlocker);
        oval.unlockLatestValue();

        // Check that the update timestamp was unlocked and that the answer and timestamp are unchanged.
        assertTrue(oval.lastUnlockTime() == unlockTimestamp);
        verifyOvalMatchesOval();

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oval.latestRoundData();

        // Check that Oval return the correct values scaled to the source oracle decimals.
        assertTrue(roundId == 2); // We published twice and roundId starts at 1.
        assertTrue(answer == newAnswer / internalDecimalsToSourceDecimals);
        assertTrue(startedAt == newTimestamp);
        assertTrue(updatedAt == newTimestamp);
        assertTrue(answeredInRound == 2); // We published twice and roundId starts at 1.
    }
}
