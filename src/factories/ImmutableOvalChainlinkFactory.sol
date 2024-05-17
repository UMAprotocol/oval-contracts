// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {ImmutableController} from "../controllers/ImmutableController.sol";
import {ChainlinkSourceAdapter} from "../adapters/source-adapters/ChainlinkSourceAdapter.sol";
import {ChainlinkDestinationAdapter} from "../adapters/destination-adapters/ChainlinkDestinationAdapter.sol";
import {IAggregatorV3Source} from "../interfaces/chainlink/IAggregatorV3Source.sol";

/**
 * @title OvalChainlinkImmutable, providing an immutable controller for Oval wapped Chainlink.
 */
contract OvalChainlinkImmutable is ImmutableController, ChainlinkSourceAdapter, ChainlinkDestinationAdapter {
    constructor(IAggregatorV3Source source, address[] memory unlockers, uint256 _lockWindow, uint256 _maxTraversal)
        ChainlinkSourceAdapter(source)
        ImmutableController(_lockWindow, _maxTraversal, unlockers)
        ChainlinkDestinationAdapter(source.decimals())
    {}
}

/**
 * @title ImmutableUnlockersOvalChainlinkFactory
 * @dev Factory contract to create instances of OvalChainlinkImmutable. If Oval instances are deployed from this factory
 * then downstream contracts can be sure the inheretence structure is defined correctly.
 */
contract ImmutableUnlockersOvalChainlinkFactory {
    /**
     * @dev Creates an instance of OvalChainlinkImmutable.
     * @param source The Chainlink source aggregator. This is the address of the contract to be wrapped by Oval.
     * @param lockWindow The time window during which the unlockers can operate.
     * @param maxTraversal The maximum number of historical data points to traverse.
     * @param unlockers Array of addresses that can unlock the controller.
     * @return The address of the newly created OvalChainlinkImmutable instance.
     */
    function createImmutableOvalChainlink(
        IAggregatorV3Source source,
        uint256 lockWindow,
        uint256 maxTraversal,
        address[] memory unlockers
    ) external returns (address) {
        return address(new OvalChainlinkImmutable(source, unlockers, lockWindow, maxTraversal));
    }
}
