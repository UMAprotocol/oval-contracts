pragma solidity 0.8.17;

import {CommonTest} from "../Common.sol";
import {MutableUnlockersController} from "../../src/controllers/MutableUnlockersController.sol";
import {MockSourceAdapter} from "../mocks/MockSourceAdapter.sol";
import {BaseDestinationAdapter} from "../../src/adapters/destination-adapters/BaseDestinationAdapter.sol";

contract TestMutableUnlockersController is MutableUnlockersController, MockSourceAdapter, BaseDestinationAdapter {
    constructor(address[] memory _unlockers)
        MutableUnlockersController(300, 15, _unlockers, 86400)
        MockSourceAdapter(18) // Assuming 18 decimals for the mock source adapter
        BaseDestinationAdapter()
    {}
}

contract MutableUnlockersControllerTest is CommonTest {
    TestMutableUnlockersController mutableController;
    address[] initialUnlockers;

    function setUp() public {
        initialUnlockers.push(permissionedUnlocker);
        vm.prank(owner);
        mutableController = new TestMutableUnlockersController(initialUnlockers);
    }

    function testInitialUnlockersCanUnlock() public {
        assertTrue(mutableController.canUnlock(initialUnlockers[0], 0));
    }

    function testNonInitialUnlockerCannotUnlock() public {
        assertFalse(mutableController.canUnlock(random, 0));
    }

    function testOwnerCanAddUnlocker() public {
        vm.prank(owner);
        mutableController.setUnlocker(random, true);
        assertTrue(mutableController.canUnlock(random, 0));
    }

    function testOwnerCanRemoveUnlocker() public {
        vm.prank(owner);
        mutableController.setUnlocker(permissionedUnlocker, false);
        assertFalse(mutableController.canUnlock(permissionedUnlocker, 0));
    }

    function testNonOwnerCannotAddUnlocker() public {
        vm.prank(random);
        vm.expectRevert("Ownable: caller is not the owner");
        mutableController.setUnlocker(random, true);
    }

    function testNonOwnerCannotRemoveUnlocker() public {
        vm.prank(random);
        vm.expectRevert("Ownable: caller is not the owner");
        mutableController.setUnlocker(permissionedUnlocker, false);
    }
}
