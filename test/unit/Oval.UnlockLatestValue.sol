// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {CommonTest} from "../Common.sol";
import {BaseController} from "../../src/controllers/BaseController.sol";
import {Oval} from "../../src/Oval.sol";
import {BaseDestinationAdapter} from "../../src/adapters/destination-adapters/BaseDestinationAdapter.sol";
import {MockSourceAdapter} from "../mocks/MockSourceAdapter.sol";

contract TestOval is BaseController, MockSourceAdapter, BaseDestinationAdapter {
    constructor(uint8 decimals) MockSourceAdapter(decimals) BaseController() BaseDestinationAdapter() {}
}

contract OvalUnlockLatestValue is CommonTest {
    int256 initialPrice = 1895 * 1e18;
    uint256 initialTimestamp = 1690000000;

    int256 newAnswer = 1900 * 1e18;
    uint256 newTimestamp = initialTimestamp + 1;

    TestOval oval;

    uint256 latestPublishedRound;

    function setUp() public {
        vm.warp(initialTimestamp);

        vm.startPrank(owner);
        oval = new TestOval(18);
        oval.setUnlocker(permissionedUnlocker, true);
        vm.stopPrank();

        publishRoundData(initialPrice, initialTimestamp);
    }

    function publishRoundData(int256 answer, uint256 timestamp) public {
        oval.publishRoundData(answer, timestamp);
        ++latestPublishedRound;
    }

    function verifyOvalMatchesOval() public {
        (int256 latestAnswer, uint256 latestTimestamp, uint256 latestRoundId) = oval.internalLatestData();
        assertTrue(latestAnswer == oval.latestAnswer() && latestTimestamp == oval.latestTimestamp());
        assertTrue(latestRoundId == latestPublishedRound);
    }

    function syncOvalWithOval() public {
        assertTrue(oval.canUnlock(permissionedUnlocker, oval.latestTimestamp()));
        vm.prank(permissionedUnlocker);
        oval.unlockLatestValue();
        verifyOvalMatchesOval();
    }

    function testUnlockWithNoDiffUpdatesUnlockTimestamp() public {
        syncOvalWithOval();
        assertTrue(oval.lastUnlockTime() == block.timestamp);

        // Apply an unlock with no diff in source adapter.
        uint256 unlockTimestamp = block.timestamp + 1 minutes;
        vm.warp(unlockTimestamp);
        vm.prank(permissionedUnlocker);
        oval.unlockLatestValue();

        // Check that the unlock timestamp was updated and that the answer and timestamp are unchanged.
        assertTrue(oval.lastUnlockTime() == unlockTimestamp);
        verifyOvalMatchesOval();
    }

    function testUnlockerCanUnlockLatestValue() public {
        syncOvalWithOval();

        publishRoundData(newAnswer, newTimestamp);
        vm.warp(newTimestamp);

        vm.prank(permissionedUnlocker);
        oval.unlockLatestValue();
        verifyOvalMatchesOval();
        (int256 latestAnswer, uint256 latestTimestamp,) = oval.internalLatestData();
        assertTrue(latestAnswer == newAnswer && latestTimestamp == newTimestamp);

        // Advance time. Add a diff to the source adapter and verify that it is applied.
        vm.warp(newTimestamp + 2);
        publishRoundData(newAnswer + 1, newTimestamp + 2);
        vm.prank(permissionedUnlocker);
        oval.unlockLatestValue();
        verifyOvalMatchesOval();
    }

    function testNonUnlockerCannotUnlockLatestValue() public {
        syncOvalWithOval();

        publishRoundData(newAnswer, newTimestamp);
        vm.warp(newTimestamp);

        vm.expectRevert("Controller blocked: canUnlock");
        vm.prank(random);
        oval.unlockLatestValue();

        (int256 latestAnswer, uint256 latestTimestamp, uint256 latestRoundId) = oval.internalLatestData();
        assertTrue(latestAnswer == initialPrice && latestTimestamp == initialTimestamp);
        assertTrue(latestRoundId == latestPublishedRound - 1);
    }

    function testUpdatesWithinLockWindow() public {
        syncOvalWithOval();

        // Advance time to within the lock window and update the source.
        uint256 beforeLockWindow = block.timestamp + oval.lockWindow() - 1;
        vm.warp(beforeLockWindow);
        publishRoundData(newAnswer, beforeLockWindow);

        // Before updating, initial values from cache would be returned.
        (int256 latestAnswer, uint256 latestTimestamp, uint256 latestRoundId) = oval.internalLatestData();
        assertTrue(latestAnswer == initialPrice && latestTimestamp == initialTimestamp);
        assertTrue(latestRoundId == latestPublishedRound - 1);

        // After updating we should return the new values.
        vm.prank(permissionedUnlocker);
        oval.unlockLatestValue();
        verifyOvalMatchesOval();
    }

    function testNoUpdatesPastLockWindow() public {
        syncOvalWithOval();
        uint256 unlockTimestamp = block.timestamp;

        uint256 beforeOEVLockWindow = unlockTimestamp + 59; // Default lock window is 10 minutes.
        vm.warp(beforeOEVLockWindow); // Advance before the end of the lock window.
        publishRoundData(newAnswer, beforeOEVLockWindow); // Update the source.

        // Within original lock window (after OEV unlock), initial values from cache would be returned.
        (int256 latestAnswer, uint256 latestTimestamp, uint256 latestRoundId) = oval.internalLatestData();
        assertTrue(latestAnswer == initialPrice && latestTimestamp == initialTimestamp, "1");
        assertTrue(latestRoundId == latestPublishedRound - 1);

        // Advancing time past the original lock window but before new lock window since source update
        // should not yet pass through source values.
        uint256 pastOEVLockWindow = beforeOEVLockWindow + 2;
        vm.warp(pastOEVLockWindow);
        (latestAnswer, latestTimestamp, latestRoundId) = oval.internalLatestData();
        assertTrue(latestAnswer == initialPrice && latestTimestamp == initialTimestamp);
        assertTrue(latestRoundId == latestPublishedRound - 1);

        // Advancing time past the new lock window should pass through source values.
        uint256 pastSourceLockWindow = beforeOEVLockWindow + 69;
        vm.warp(pastSourceLockWindow);
        verifyOvalMatchesOval();
    }

    function testRepeatedUpdates() public {
        syncOvalWithOval();

        // Advance time to within the lock window and update the source.
        uint256 beforeLockWindow = block.timestamp + oval.lockWindow() - 1;
        vm.warp(beforeLockWindow);
        publishRoundData(newAnswer, beforeLockWindow);

        // Before updating, initial values from cache would be returned.
        (int256 latestAnswer, uint256 latestTimestamp, uint256 latestRoundId) = oval.internalLatestData();
        assertTrue(latestAnswer == initialPrice && latestTimestamp == initialTimestamp);
        assertTrue(latestRoundId == latestPublishedRound - 1);

        // Sync and verify updated values.
        syncOvalWithOval();

        // Advance time to within the lock window and update the source.
        uint256 nextBeforeLockWindow = block.timestamp + oval.lockWindow() - 1;
        vm.warp(nextBeforeLockWindow);
        int256 nextNewAnswer = newAnswer + 1e18;
        publishRoundData(nextNewAnswer, nextBeforeLockWindow);

        // Within lock window, values from previous update would be returned.
        (latestAnswer, latestTimestamp, latestRoundId) = oval.internalLatestData();
        assertTrue(latestAnswer == newAnswer && latestTimestamp == beforeLockWindow);
        assertTrue(latestRoundId == latestPublishedRound - 1);
    }
}
