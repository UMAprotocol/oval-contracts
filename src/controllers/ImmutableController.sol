// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {OVAL} from "../Oval.sol";

/**
 * @title ImmutableController providing an immutable controller.
 * @dev The benefit of this controller is two-fold:
 * 1. Permissioning and parameters _cannot_ be updated after deployment. Ownership doesn't exist.
 * 2. Because LOCK_WINDOW and MAX_TRAVERSAL are immutable, the read costs are much lower in the "hot" path (end
 *    oracle users).
 */

abstract contract ImmutableController is OVAL {
    uint256 private immutable LOCK_WINDOW; // The lockWindow in seconds.
    uint256 private immutable MAX_TRAVERSAL; // The maximum number of rounds to traverse when looking for historical data.

    mapping(address => bool) public unlockers;

    constructor(uint256 _lockWindow, uint256 _maxTraversal, address[] memory _unlockers) {
        LOCK_WINDOW = _lockWindow;
        MAX_TRAVERSAL = _maxTraversal;
        for (uint256 i = 0; i < _unlockers.length; i++) {
            unlockers[_unlockers[i]] = true;

            emit UnlockerSet(_unlockers[i], true);
        }

        emit LockWindowSet(_lockWindow);
        emit MaxTraversalSet(_maxTraversal);
    }

    /**
     * @notice Returns true if the caller is allowed to unlock the OVAL.
     * @dev This implementation simply checks if the caller is in the unlockers mapping. Custom Controllers can override
     * this function to provide more granular control over who can unlock the OVAL.
     * @param caller The address to check.
     * @param _lastUnlockTime The timestamp of the latest unlock to the OVAL. Might be useful in verification.
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
}
