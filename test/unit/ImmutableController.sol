// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {CommonTest} from "../Common.sol";
import {ImmutableController} from "../../src/controllers/ImmutableController.sol";
import {BaseDestinationAdapter} from "../../src/adapters/destination-adapters/BaseDestinationAdapter.sol";
import {MockSourceAdapter} from "../mocks/MockSourceAdapter.sol";

contract TestImmutableController is ImmutableController, MockSourceAdapter, BaseDestinationAdapter {
    constructor(
        uint8 decimals,
        uint256 _lockWindow,
        uint256 _maxTraversal,
        address[] memory _unlockers,
        uint256 _maxAge
    )
        MockSourceAdapter(decimals)
        ImmutableController(_lockWindow, _maxTraversal, _unlockers, _maxAge)
        BaseDestinationAdapter()
    {}
}

contract ImmutableControllerTest is CommonTest {
    uint8 decimals = 8;
    uint256 lockWindow = 60;
    uint256 maxTraversal = 10;
    address[] unlockers;
    uint256 maxAge = 86400;

    uint256 lastUnlockTime = 1690000000;

    TestImmutableController immutableController;

    function setUp() public {
        unlockers.push(permissionedUnlocker);

        vm.startPrank(owner);
        immutableController = new TestImmutableController(decimals, lockWindow, maxTraversal, unlockers, maxAge);
        vm.stopPrank();
    }

    function testPermissionedUnlockerCanUnlock() public {
        assertTrue(immutableController.canUnlock(permissionedUnlocker, lastUnlockTime));
    }

    function testRandomCannotUnlock() public {
        assertFalse(immutableController.canUnlock(random, lastUnlockTime));
    }

    function testLockWindowSetCorrectly() public {
        assertTrue(immutableController.lockWindow() == lockWindow);
    }

    function testMaxTraversalSetCorrectly() public {
        assertTrue(immutableController.maxTraversal() == maxTraversal);
    }
}
