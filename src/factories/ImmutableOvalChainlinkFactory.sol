// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {ImmutableController} from "../controllers/ImmutableController.sol";
import {ChainlinkSourceAdapter} from "../adapters/source-adapters/ChainlinkSourceAdapter.sol";
import {ChainlinkDestinationAdapter} from "../adapters/destination-adapters/ChainlinkDestinationAdapter.sol";
import {IAggregatorV3Source} from "../interfaces/chainlink/IAggregatorV3Source.sol";

contract OvalChainlinkImmutable is ImmutableController, ChainlinkSourceAdapter, ChainlinkDestinationAdapter {
    constructor(
        IAggregatorV3Source source,
        address[] memory unlockers,
        uint256 _lockWindow,
        uint256 _maxTraversal,
        address owner
    )
        ChainlinkSourceAdapter(source)
        ImmutableController(_lockWindow, _maxTraversal, unlockers)
        ChainlinkDestinationAdapter(source.decimals())
    {}
}

contract MutableUnlockersOvalChainlinkFactory {
    function createImmutableOvalChainlink(
        IAggregatorV3Source source,
        uint256 lockWindow,
        uint256 maxTraversal,
        address owner,
        address[] memory unlockers
    ) external returns (address) {
        return address(new OvalChainlinkImmutable(source, unlockers, lockWindow, maxTraversal, owner));
    }
}
