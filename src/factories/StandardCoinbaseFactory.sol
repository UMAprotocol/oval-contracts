// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {MutableUnlockersController} from "../controllers/MutableUnlockersController.sol";
import {CoinbaseSourceAdapter} from "../adapters/source-adapters/CoinbaseSourceAdapter.sol";
import {ChainlinkDestinationAdapter} from "../adapters/destination-adapters/ChainlinkDestinationAdapter.sol";
import {IAggregatorV3SourceCoinbase} from "../interfaces/coinbase/IAggregatorV3SourceCoinbase.sol";
import {BaseFactory} from "./BaseFactory.sol";

/**
 * @title OvalCoinbase is the recommended Oval Coinbase contract that allows Oval to extract OEV generated by
 * Coinbase usage.
 */
contract OvalCoinbase is MutableUnlockersController, CoinbaseSourceAdapter, ChainlinkDestinationAdapter {
    constructor(
        IAggregatorV3SourceCoinbase _source,
        string memory _ticker,
        address[] memory _unlockers,
        uint256 _lockWindow,
        uint256 _maxTraversal,
        uint256 _maxAge,
        address _owner
    )
        CoinbaseSourceAdapter(_source, _ticker)
        MutableUnlockersController(_lockWindow, _maxTraversal, _unlockers, _maxAge)
        ChainlinkDestinationAdapter(18)
    {
        _transferOwnership(_owner);
    }
}

/**
 * @title StandardCoinbaseFactory is the recommended factory for use cases that want a Coinbase source and Chainlink
 * interface.
 * @dev This is the best factory for most use cases, but there are other variants that may be needed if different
 * mutability choices are desired.
 */
contract StandardCoinbaseFactory is Ownable, BaseFactory {
    IAggregatorV3SourceCoinbase public immutable SOURCE;

    constructor(IAggregatorV3SourceCoinbase _source, uint256 _maxTraversal, address[] memory _defaultUnlockers)
        BaseFactory(_maxTraversal, _defaultUnlockers)
    {
        SOURCE = _source;
    }

    /**
     * @notice Creates the Coinbase Oval instance.
     * @param ticker the Coinbase oracle's ticker.
     * @param lockWindow the lockWindow used for this Oval instance. This is the length of the window
     * for the Oval auction to be run and, thus, the maximum time that prices will be delayed.
     * @param maxAge max age of a price that is used in place of the current price. If the only available price is
     * older than this, OEV is not captured and the current price is provided.
     * @return oval deployed oval address.
     */
    function create(string memory ticker, uint256 lockWindow, uint256 maxAge) external returns (address oval) {
        oval = address(new OvalCoinbase(SOURCE, ticker, defaultUnlockers, lockWindow, MAX_TRAVERSAL, maxAge, owner()));
        emit OvalDeployed(msg.sender, oval, lockWindow, MAX_TRAVERSAL, owner(), defaultUnlockers);
    }
}
