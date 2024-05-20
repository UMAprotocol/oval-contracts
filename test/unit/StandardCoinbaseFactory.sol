// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {StandardCoinbaseFactory} from "../../src/factories/StandardCoinbaseFactory.sol";
import {OvalCoinbase} from "../../src/factories/StandardCoinbaseFactory.sol";
import {IAggregatorV3SourceCoinbase} from "../../src/interfaces/coinbase/IAggregatorV3SourceCoinbase.sol";
import {MockChainlinkV3Aggregator} from "../mocks/MockChainlinkV3Aggregator.sol";
import {CommonTest} from "../Common.sol";

contract StandardCoinbaseFactoryTest is CommonTest {
    StandardCoinbaseFactory factory;
    IAggregatorV3SourceCoinbase mockSource;
    address[] unlockers;
    uint256 lockWindow = 300;
    uint256 maxTraversal = 15;
    string ticker = "test ticker";
    uint256 maxAge = 86400;

    function setUp() public {
        mockSource = IAggregatorV3SourceCoinbase(address(new MockChainlinkV3Aggregator(8, 420)));
        unlockers.push(address(0x123));
        factory = new StandardCoinbaseFactory(mockSource, maxTraversal, unlockers);
    }

    function testCreateMutableUnlockerOvalCoinbase() public {
        address created = factory.create(ticker, lockWindow, maxAge);

        assertTrue(created != address(0)); // Check if the address is set, non-zero.

        OvalCoinbase instance = OvalCoinbase(created);
        assertTrue(instance.lockWindow() == lockWindow);
        assertTrue(instance.maxTraversal() == maxTraversal);

        // Check if the unlockers are set correctly
        for (uint256 i = 0; i < unlockers.length; i++) {
            assertTrue(instance.canUnlock(unlockers[i], 0));
        }
        assertFalse(instance.canUnlock(address(0x456), 0)); // Check if a random address cannot unlock
    }

    function testOwnerCanChangeUnlockers() public {
        address created = factory.create(ticker, lockWindow, maxAge);
        OvalCoinbase instance = OvalCoinbase(created);

        address newUnlocker = address(0x789);
        instance.setUnlocker(newUnlocker, true); // Correct method to add unlockers
        assertTrue(instance.canUnlock(newUnlocker, 0));

        instance.setUnlocker(address(0x123), false); // Correct method to remove unlockers
        assertFalse(instance.canUnlock(address(0x123), 0));
    }
}
