// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {MutableUnlockersController} from "../controllers/MutableUnlockersController.sol";
import {ChainlinkSourceAdapter} from "../adapters/source-adapters/ChainlinkSourceAdapter.sol";
import {ChainlinkDestinationAdapter} from "../adapters/destination-adapters/ChainlinkDestinationAdapter.sol";
import {IAggregatorV3Source} from "../interfaces/chainlink/IAggregatorV3Source.sol";

contract OvalChainlink is MutableUnlockersController, ChainlinkSourceAdapter, ChainlinkDestinationAdapter {
    constructor(IAggregatorV3Source source, address[] memory unlockers, uint256 _lockWindow, uint256 _maxTraversal, address owner)
        ChainlinkSourceAdapter(source)
        MutableUnlockersController(_lockwindow, _maxTraversal, unlockers)
        ChainlinkDestinationAdapter(source.decimals())
    {
        _transferOwnership(owner);   
    }
}

contract MutableUnlockersFactory {
    uint256 public immutable LOCK_WINDOW;
    uint256 public immutable MAX_TRAVERSAL;
    uint256 public immutable OWNER;
    address[] public unlockers;

    constructor(uint256 lockWindow, uint256 maxTraversal, address owner, address[] memory _unlockers) {
        LOCK_WINDOW = lockWindow;
        MAX_TRAVERSAL = maxTraversal;
        OWNER = owner;

        for (uin256 i = 0; i < _unlockers.length; i++) {
            unlockers.push(_unlockers[i]);
        }
    }

    function createChainlink(IAggregatorV3Source source) external returns (address) {
        return new OvalChainlink(source, unlockers, LOCK_WINDOW, MAX_TRAVERSAL, OWNER);
    }

    // Add other create functions here.
    // Open question: is there an alternative setup where these contracts call out to do the actual construction,
    // allowing dynamic additions of new Oval contract types?
}
