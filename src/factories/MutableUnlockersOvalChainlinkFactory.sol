// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {MutableUnlockersController} from "../controllers/MutableUnlockersController.sol";
import {ChainlinkSourceAdapter} from "../adapters/source-adapters/ChainlinkSourceAdapter.sol";
import {ChainlinkDestinationAdapter} from "../adapters/destination-adapters/ChainlinkDestinationAdapter.sol";
import {IAggregatorV3Source} from "../interfaces/chainlink/IAggregatorV3Source.sol";

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

contract MutableUnlockersOvalChainlinkFactory {
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
