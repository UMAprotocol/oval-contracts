// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Oval} from "../Oval.sol";

/**
 * @title BaseController providing the simplest possible controller logic to govern who can unlock Oval.
 * @dev Custom Controllers can be created to provide more granular control over who can unlock Oval.
 */
abstract contract BaseController is Ownable, Oval {
    // these don't need to be public since they can be accessed via the accessor functions below.
    uint256 private lockWindow_ = 60; // The lockWindow in seconds.
    uint256 private maxTraversal_ = 10; // The maximum number of rounds to traverse when looking for historical data.
    uint256 private maxAge_ = 1 days; // Default 1 day.

    mapping(address => bool) public unlockers;

    /**
     * @notice Enables the owner to set the unlocker status of an address. Once set, the address can unlock Oval
     * and by calling unlockLatestValue as part of an MEV-share auction.
     * @param unlocker The address to set the unlocker status of.
     * @param allowed The unlocker status to set.
     */
    function setUnlocker(address unlocker, bool allowed) public onlyOwner {
        require(unlockers[unlocker] != allowed, "Unlocker not changed");

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
     * @notice Enables the owner to set the lockWindow.
     * @dev If changing the lockWindow would cause Oval to return different data the permissioned actor must first
     * call unlockLatestValue through flashbots via eth_sendPrivateTransaction.
     * @param newLockWindow The lockWindow to set.
     */
    function setLockWindow(uint256 newLockWindow) public onlyOwner {
        require(maxAge() > newLockWindow, "Max age not above lock window");

        (int256 currentAnswer, uint256 currentTimestamp,) = internalLatestData();

        lockWindow_ = newLockWindow;

        _checkDataNotChanged(currentAnswer, currentTimestamp);

        emit LockWindowSet(newLockWindow);
    }

    /**
     * @notice Enables the owner to set the maxTraversal.
     * @param newMaxTraversal The maxTraversal to set.
     */
    function setMaxTraversal(uint256 newMaxTraversal) public onlyOwner {
        require(newMaxTraversal > 0, "Max traversal must be > 0");

        (int256 currentAnswer, uint256 currentTimestamp,) = internalLatestData();

        maxTraversal_ = newMaxTraversal;

        _checkDataNotChanged(currentAnswer, currentTimestamp);

        emit MaxTraversalSet(newMaxTraversal);
    }

    /**
     * @notice Enables the owner to set the maxAge.
     * @param newMaxAge The maxAge to set
     */
    function setMaxAge(uint256 newMaxAge) public onlyOwner {
        require(newMaxAge > lockWindow(), "Max age not above lock window");

        (int256 currentAnswer, uint256 currentTimestamp,) = internalLatestData();

        maxAge_ = newMaxAge;

        _checkDataNotChanged(currentAnswer, currentTimestamp);

        emit MaxAgeSet(newMaxAge);
    }

    /**
     * @notice Time window that bounds how long the permissioned actor has to call the unlockLatestValue function after
     * a new source update is posted. If the permissioned actor does not call unlockLatestValue within this window of a
     * new source price, the latest value will be made available to everyone without going through an MEV-Share auction.
     * @return lockWindow time in seconds.
     */
    function lockWindow() public view override returns (uint256) {
        return lockWindow_;
    }

    /**
     * @notice Max number of historical source updates to traverse when looking for a historic value in the past.
     * @return maxTraversal max number of historical source updates to traverse.
     */
    function maxTraversal() public view override returns (uint256) {
        return maxTraversal_;
    }

    /**
     * @notice Max age of a historical price that can be used instead of the current price.
     */
    function maxAge() public view override returns (uint256) {
        return maxAge_;
    }

    // Helper function to ensure that changing controller parameters does not change the returned data.
    function _checkDataNotChanged(int256 currentAnswer, uint256 currentTimestamp) internal view {
        (int256 newAnswer, uint256 newTimestamp,) = internalLatestData();
        require(currentAnswer == newAnswer && currentTimestamp == newTimestamp, "Must unlock first");
    }
}
