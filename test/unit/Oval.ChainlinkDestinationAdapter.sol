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

    uint256 latestPublishedRound;

    function setUp() public {
        vm.warp(initialTimestamp);

        vm.startPrank(owner);
        oval = new TestOval(sourceOracleDecimals);
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
        assertTrue(
            latestAnswer / internalDecimalsToSourceDecimals == oval.latestAnswer()
                && latestTimestamp == oval.latestTimestamp()
        );
        assertTrue(latestRoundId == latestPublishedRound);
    }

    function syncOvalWithOval() public {
        assertTrue(oval.canUnlock(permissionedUnlocker, oval.latestTimestamp()));
        vm.prank(permissionedUnlocker);
        oval.unlockLatestValue();
        verifyOvalMatchesOval();
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

    function testReturnUninitializedRoundData() public {
        // Advance time to within the lock window and update the source.
        uint256 beforeLockWindow = block.timestamp + oval.lockWindow() - 1;
        vm.warp(beforeLockWindow);
        publishRoundData(newAnswer, beforeLockWindow);

        // Before updating, uninitialized values would be returned.
        (int256 latestAnswer, uint256 latestTimestamp) = oval.internalDataAtRound(latestPublishedRound);
        assertTrue(latestAnswer == 0 && latestTimestamp == 0);
    }

    function testReturnUnlockedRoundData() public {
        // Advance time to within the lock window and update the source.
        uint256 beforeLockWindow = block.timestamp + oval.lockWindow() - 1;
        vm.warp(beforeLockWindow);
        publishRoundData(newAnswer, beforeLockWindow);

        // Unlock new round values.
        vm.prank(permissionedUnlocker);
        oval.unlockLatestValue();
        verifyOvalMatchesOval();

        // After unlock we should return the new values.
        (int256 latestAnswer, uint256 latestTimestamp) = oval.internalDataAtRound(latestPublishedRound);
        assertTrue(latestAnswer == newAnswer && latestTimestamp == beforeLockWindow);
    }
}
