// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Oval} from "../Oval.sol";

/**
 * @title MutableUnlockersController is a controller that only allows unlockers to be change, but other params are immutable.
 */
abstract contract MutableUnlockersController is Ownable, Oval {
    // these don't need to be public since they can be accessed via the accessor functions below.
    uint256 private immutable LOCK_WINDOW; // The lockWindow in seconds.
    uint256 private immutable MAX_TRAVERSAL; // The maximum number of rounds to traverse when looking for historical data.
    uint256 private immutable MAX_AGE; // Max age for a historical price used by Oval instead of the current price.

    mapping(address => bool) public unlockers;

    constructor(uint256 _lockWindow, uint256 _maxTraversal, address[] memory _unlockers, uint256 _maxAge) {
        require(_maxAge > _lockWindow, "Max age not above lock window");
        require(_maxTraversal > 0, "Max traversal must be > 0");

        LOCK_WINDOW = _lockWindow;
        MAX_TRAVERSAL = _maxTraversal;
        MAX_AGE = _maxAge;

        for (uint256 i = 0; i < _unlockers.length; i++) {
            setUnlocker(_unlockers[i], true);
        }

        emit LockWindowSet(_lockWindow);
        emit MaxTraversalSet(_maxTraversal);
        emit MaxAgeSet(_maxAge);
    }

    /**
     * @notice Enables the owner to set the unlocker status of an address. Once set, the address can unlock Oval
     * and by calling unlockLatestValue as part of an MEV-share auction.
     * @param unlocker The address to set the unlocker status of.
     * @param allowed The unlocker status to set.
     */
    function setUnlocker(address unlocker, bool allowed) public onlyOwner {
        unlockers[unlocker] = allowed;

        emit UnlockerSet(unlocker, allowed);
    }

    /**
     * @notice Returns true if the caller is allowed to unlock Oval.
     * @dev This implementation simply checks if the caller is in the unlockers mapping. Custom Controllers can override
     * this function to provide more granular control over who can unlock Oval.
     * @param caller The address to check.
     * @param _lastUnlockTime The timestamp of the latest unlock to Oval. Might be useful in verification.
     */
    function canUnlock(address caller, uint256 _lastUnlockTime) public view override returns (bool) {
        return unlockers[caller];
    }

    /**
     * @notice Time window that bounds how long the permissioned actor has to call the unlockLatestValue function after
     * a new source update is posted. If the permissioned actor does not call unlockLatestValue within this window of a
     * new source price, the latest value will be made available to everyone without going through an MEV-Share auction.
     * @return lockWindow time in seconds.
     */
    function lockWindow() public view override returns (uint256) {
        return LOCK_WINDOW;
    }

    /**
     * @notice Max number of historical source updates to traverse when looking for a historic value in the past.
     * @return maxTraversal max number of historical source updates to traverse.
     */
    function maxTraversal() public view override returns (uint256) {
        return MAX_TRAVERSAL;
    }

    /**
     * @notice Max age of a historical price that can be used instead of the current price.
     */
    function maxAge() public view override returns (uint256) {
        return MAX_AGE;
    }
}
