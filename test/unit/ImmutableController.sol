// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {CommonTest} from "../Common.sol";
import {ImmutableController} from "../../src/controllers/ImmutableController.sol";
import {BaseDestinationAdapter} from "../../src/adapters/destination-adapters/BaseDestinationAdapter.sol";
import {MockSourceAdapter} from "../mocks/MockSourceAdapter.sol";

contract TestImmutableController is ImmutableController, MockSourceAdapter, BaseDestinationAdapter {
    constructor(uint8 decimals, uint256 _lockWindow, uint256 _maxTraversal, address[] memory _unlockers)
        MockSourceAdapter(decimals)
        ImmutableController(_lockWindow, _maxTraversal, _unlockers)
        BaseDestinationAdapter()
    {}
}

contract OvalUnlockLatestValue is CommonTest {
    uint8 decimals = 8;
    uint256 lockWindow = 60;
    uint256 maxTraversal = 10;
    address[] unlockers;

    uint256 lastUnlockTime = 1690000000;

    TestImmutableController immutableController;

    function setUp() public {
        unlockers.push(permissionedUnlocker);

        vm.startPrank(owner);
        immutableController = new TestImmutableController(decimals, lockWindow, maxTraversal, unlockers);
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

    function testCannotSetUnlocker() public {
        bytes4 selector = bytes4(keccak256("setUnlocker(address,bool)"));
        bytes memory data = abi.encodeWithSelector(selector, random, true);
        vm.prank(owner);
        (bool success,) = address(immutableController).call(data);
        assertFalse(success);
    }

    function testCannotSetLockWindow() public {
        bytes4 selector = bytes4(keccak256("setLockWindow(uint256)"));
        bytes memory data = abi.encodeWithSelector(selector, lockWindow + 1);
        vm.prank(owner);
        (bool success,) = address(immutableController).call(data);
        assertFalse(success);
    }

    function testCannotSetMaxTraversal() public {
        bytes4 selector = bytes4(keccak256("setMaxTraversal(uint256)"));
        bytes memory data = abi.encodeWithSelector(selector, maxTraversal + 1);
        vm.prank(owner);
        (bool success,) = address(immutableController).call(data);
        assertFalse(success);
    }
}
