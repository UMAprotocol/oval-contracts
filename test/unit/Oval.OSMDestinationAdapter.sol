// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {Oval} from "../../src/Oval.sol";
import {BaseDestinationAdapter} from "../../src/adapters/destination-adapters/BaseDestinationAdapter.sol";
import {OSMDestinationAdapter} from "../../src/adapters/destination-adapters/OSMDestinationAdapter.sol";
import {BaseController} from "../../src/controllers/BaseController.sol";
import {CommonTest} from "../Common.sol";
import {MockSourceAdapter} from "../mocks/MockSourceAdapter.sol";

contract TestOval is BaseController, MockSourceAdapter, OSMDestinationAdapter {
    constructor(uint8 decimals) BaseController() MockSourceAdapter(decimals) OSMDestinationAdapter() {}
}

contract OvalChronicleMedianDestinationAdapter is CommonTest {
    int256 initialPrice = 1895 * 1e18;
    uint256 initialTimestamp = 1690000000;

    int256 newAnswer = 1900 * 1e18;
    uint256 newTimestamp = initialTimestamp + 1;

    TestOval oval;

    function setUp() public {
        vm.warp(initialTimestamp);

        vm.startPrank(owner);
        oval = new TestOval(18);
        oval.setUnlocker(permissionedUnlocker, true);
        vm.stopPrank();

        oval.publishRoundData(initialPrice, initialTimestamp);
    }

    function verifyOvalOracleMatchesOvalOracle() public {
        (int256 latestAnswer, uint256 latestTimestamp,) = oval.internalLatestData();

        (, bool sourceValid) = oval.peek();
        assertTrue(sourceValid);
        assertTrue(bytes32(uint256(latestAnswer)) == oval.read() && uint64(latestTimestamp) == oval.zzz());
    }

    function syncOvalOracleWithOvalOracle() public {
        assertTrue(oval.canUnlock(permissionedUnlocker, oval.zzz()));
        vm.prank(permissionedUnlocker);
        oval.unlockLatestValue();
        verifyOvalOracleMatchesOvalOracle();
    }

    function testUpdatesWithinLockWindow() public {
        // Publish an update to the mock source adapter.
        oval.publishRoundData(newAnswer, newTimestamp);

        syncOvalOracleWithOvalOracle();
        assertTrue(oval.lastUnlockTime() == block.timestamp);

        // Apply an update with no diff in source adapter.
        uint256 updateTimestamp = block.timestamp + 1 minutes;
        vm.warp(updateTimestamp);
        vm.prank(permissionedUnlocker);
        oval.unlockLatestValue();

        // Check that the update timestamp was updated and that the answer and timestamp are unchanged.
        assertTrue(oval.lastUnlockTime() == updateTimestamp);
        verifyOvalOracleMatchesOvalOracle();
    }
}
