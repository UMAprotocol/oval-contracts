// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {StandardChronicleFactory} from "../../src/factories/StandardChronicleFactory.sol";
import {OvalChronicle} from "../../src/factories/StandardChronicleFactory.sol";
import {IMedian} from "../../src/interfaces/chronicle/IMedian.sol";
import {CommonTest} from "../Common.sol";

contract StandardChronicleFactoryTest is CommonTest {
    StandardChronicleFactory factory;
    IMedian mockSource;
    address[] unlockers;
    uint256 lockWindow = 300;
    uint256 maxTraversal = 15;

    function setUp() public {
        mockSource = IMedian(address(0x456));
        unlockers.push(address(0x123));
        factory = new StandardChronicleFactory(maxTraversal, unlockers);
    }

    function testCreateMutableUnlockerOvalChronicle() public {
        address created = factory.create(mockSource, lockWindow);

        assertTrue(created != address(0)); // Check if the address is set, non-zero.

        OvalChronicle instance = OvalChronicle(created);
        assertTrue(instance.lockWindow() == lockWindow);
        assertTrue(instance.maxTraversal() == maxTraversal);

        // Check if the unlockers are set correctly
        for (uint256 i = 0; i < unlockers.length; i++) {
            assertTrue(instance.canUnlock(unlockers[i], 0));
        }
        assertFalse(instance.canUnlock(address(0x456), 0)); // Check if a random address cannot unlock
    }

    function testOwnerCanChangeUnlockers() public {
        address created = factory.create(mockSource, lockWindow);
        OvalChronicle instance = OvalChronicle(created);

        address newUnlocker = address(0x789);
        instance.setUnlocker(newUnlocker, true); // Correct method to add unlockers
        assertTrue(instance.canUnlock(newUnlocker, 0));

        instance.setUnlocker(address(0x123), false); // Correct method to remove unlockers
        assertFalse(instance.canUnlock(address(0x123), 0));
    }
}
