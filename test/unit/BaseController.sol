// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {CommonTest} from "../Common.sol";
import {BaseController} from "../../src/controllers/BaseController.sol";
import {BaseDestinationAdapter} from "../../src/adapters/destination-adapters/BaseDestinationAdapter.sol";
import {MockSourceAdapter} from "../mocks/MockSourceAdapter.sol";

contract TestBaseController is BaseController, MockSourceAdapter, BaseDestinationAdapter {
    constructor(uint8 decimals) MockSourceAdapter(decimals) BaseController() BaseDestinationAdapter() {}
}

contract OVALUnlockLatestValue is CommonTest {
    uint256 lastUnlockTime = 1690000000;

    TestBaseController baseController;

    function setUp() public {
        vm.startPrank(owner);
        baseController = new TestBaseController(18);
        baseController.setUnlocker(permissionedUnlocker, true);
        vm.stopPrank();
    }

    function testOwnerCanAddUnlocker() public {
        vm.prank(owner);
        baseController.setUnlocker(random, true);
        assertTrue(baseController.canUnlock(random, lastUnlockTime));
    }

    function testOwnerCanRemoveUnlocker() public {
        vm.prank(owner);
        baseController.setUnlocker(permissionedUnlocker, false);
        assertTrue(!baseController.canUnlock(permissionedUnlocker, lastUnlockTime));
    }

    function testNonOwnerCannotSetUnlocker() public {
        vm.prank(random);
        vm.expectRevert("Ownable: caller is not the owner");
        baseController.setUnlocker(random, true);
    }

    function testOwnerCanSetLockWindow() public {
        vm.warp(block.timestamp + 3600);
        vm.prank(owner);
        vm.warp(block.timestamp + 3600);
        baseController.setLockWindow(3600);
        assertTrue(baseController.lockWindow() == 3600);
    }

    function testNonOwnerCannotSetLockWindow() public {
        vm.prank(random);
        vm.expectRevert("Ownable: caller is not the owner");
        baseController.setLockWindow(3600);
    }

    function testOwnerCanSetMaxTraversal() public {
        vm.prank(owner);
        baseController.setMaxTraversal(100);
        assertTrue(baseController.maxTraversal() == 100);
    }

    function testNonOwnerCannotSetMaxTraversal() public {
        vm.prank(random);
        vm.expectRevert("Ownable: caller is not the owner");
        baseController.setMaxTraversal(100);
    }
}
