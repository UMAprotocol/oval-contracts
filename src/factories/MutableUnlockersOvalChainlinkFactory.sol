// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {MutableUnlockersController} from "../controllers/MutableUnlockersController.sol";
import {ChainlinkSourceAdapter} from "../adapters/source-adapters/ChainlinkSourceAdapter.sol";
import {ChainlinkDestinationAdapter} from "../adapters/destination-adapters/ChainlinkDestinationAdapter.sol";
import {IAggregatorV3Source} from "../interfaces/chainlink/IAggregatorV3Source.sol";

/**
 * @title OvalChainlinkMutableUnlocker, providing a mutable-unlocker controller for Oval wapped Chainlink.
 */
contract OvalChainlinkMutableUnlocker is
    MutableUnlockersController,
    ChainlinkSourceAdapter,
    ChainlinkDestinationAdapter
{
    constructor(
        IAggregatorV3Source source,
        address[] memory unlockers,
        uint256 _lockWindow,
        uint256 _maxTraversal,
        address owner
    )
        ChainlinkSourceAdapter(source)
        MutableUnlockersController(_lockWindow, _maxTraversal, unlockers)
        ChainlinkDestinationAdapter(source.decimals())
    {
        _transferOwnership(owner);
    }
}

/**
 * @title MutableUnlockersOvalChainlinkFactory
 * @dev Factory contract to create instances of OvalChainlinkMutableUnlocker. If Oval instances are deployed from this
 * factory then downstream contracts can be sure the inheretence structure is defined correctly.
 */
contract MutableUnlockersOvalChainlinkFactory {
    /**
     * @dev Creates an instance of OvalChainlinkMutableUnlocker.
     * @param source The Chainlink source aggregator. This is the address of the contract to be wrapped by Oval.
     * @param lockWindow The time window during which the unlockers can operate.
     * @param maxTraversal The maximum number of historical data points to traverse.
     * @param owner The address that will own the created OvalChainlinkMutableUnlocker instance.
     * @param unlockers Array of addresses that can unlock the controller.
     * @return The address of the newly created OvalChainlinkMutableUnlocker instance.
     */
    function createMutableUnlockerOvalChainlink(
        IAggregatorV3Source source,
        uint256 lockWindow,
        uint256 maxTraversal,
        address owner,
        address[] memory unlockers
    ) external returns (address) {
        return address(new OvalChainlinkMutableUnlocker(source, unlockers, lockWindow, maxTraversal, owner));
    }
}
