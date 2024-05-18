// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {StandardPythFactory} from "../../src/factories/StandardPythFactory.sol";
import {OvalPyth} from "../../src/factories/StandardPythFactory.sol";
import {IPyth} from "../../src/interfaces/pyth/IPyth.sol";
import {CommonTest} from "../Common.sol";

contract StandardPythFactoryTest is CommonTest {
    StandardPythFactory factory;
    IPyth mockSource;
    address[] unlockers;
    uint256 lockWindow = 300;
    uint256 maxTraversal = 15;

    function setUp() public {
        mockSource = IPyth(address(0x456));
        unlockers.push(address(0x123));
        factory = new StandardPythFactory(mockSource, maxTraversal, unlockers);
    }

    function testCreateMutableUnlockerOvalPyth() public {
        address created = factory.create(
            bytes32(uint256(0x789)), lockWindow
        );

        assertTrue(created != address(0)); // Check if the address is set, non-zero.

        OvalPyth instance = OvalPyth(created);
        assertTrue(instance.lockWindow() == lockWindow);
        assertTrue(instance.maxTraversal() == maxTraversal);

        // Check if the unlockers are set correctly
        for (uint256 i = 0; i < unlockers.length; i++) {
            assertTrue(instance.canUnlock(unlockers[i], 0));
        }
        assertFalse(instance.canUnlock(address(0x456), 0)); // Check if a random address cannot unlock
    }

    function testOwnerCanChangeUnlockers() public {
        address created = factory.create(
            bytes32(uint256(0x789)), lockWindow
        );
        OvalPyth instance = OvalPyth(created);

        address newUnlocker = address(0x789);
        instance.setUnlocker(newUnlocker, true); // Correct method to add unlockers
        assertTrue(instance.canUnlock(newUnlocker, 0));

        instance.setUnlocker(address(0x123), false); // Correct method to remove unlockers
        assertFalse(instance.canUnlock(address(0x123), 0));
    }
}
