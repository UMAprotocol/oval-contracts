// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {DiamondRootOval} from "./DiamondRootOval.sol";

/**
 * @title Oval contract to provide permissioned updating at the execution of an MEV-share auction.
 * @dev This contract works by conditionally returning a stale value oracle price from the source adapter until a
 * permissioned actor calls the unlockLatestValue function. The call to unlockLatestValue is submitted via an MEV-share
 * auction and will be backrun by the winner of the auction. The backrunner has access to the most recent newly unlocked
 * source price. If someone tries to front-run the call to unlockLatestValue, the caller will receive a stale value. If
 * the permissioned actor does not call unlockLatestValue within the lockWindow, the latest value that is at least
 * lockWindow seconds old will be returned. This contract is intended to be used in conjunction with a Controller
 * contract that governs who can call unlockLatestValue.
 * @custom:security-contact bugs@umaproject.org
 */
abstract contract Oval is DiamondRootOval {
    uint256 public lastUnlockTime; // Timestamp of the latest unlock to Oval.

    /**
     * @notice Function called by permissioned actor to unlock the latest value as part of the MEV-share auction flow.
     * @dev The call to this function is expected to be sent to flashbots via eth_sendPrivateTransaction. This is the
     * transaction that is backrun by the winner of the auction. The backrunner has access to the most recent newly
     * unlocked source price as a result and therefore can extract the MEV associated with the unlock.
     */
    function unlockLatestValue() public {
        require(canUnlock(msg.sender, lastUnlockTime), "Controller blocked: canUnlock");

        snapshotData(); // If the source connected to this Oval needs to snapshot data, do it here. Else, no op.

        lastUnlockTime = block.timestamp;

        emit LatestValueUnlocked(block.timestamp);
    }

    /**
     * @notice Returns latest data from source, governed by lockWindow controlling if returned data is stale.
     * @return answer The latest answer in 18 decimals.
     * @return timestamp The timestamp of the answer.
     * @return roundId The roundId of the answer.
     */
    function internalLatestData() public view override returns (int256, uint256, uint256) {
        // Case work:
        //-> If unlockLatestValue has been called within lockWindow, then return most recent price as of unlockLatestValue call.
        //-> If unlockLatestValue has not been called in lockWindow, then return most recent value that is at least lockWindow old.
        return tryLatestDataAt(Math.max(lastUnlockTime, block.timestamp - lockWindow()), maxTraversal());
    }

    /**
     * @notice Returns the requested round data from the source. Depending on when Oval was last unlocked this might
     * also return uninitialized values to protect the OEV from being stolen by a front runner.
     * @dev If the source does not support rounds this would always return uninitialized data.
     * @param roundId The roundId to retrieve the round data for.
     * @return answer Round answer in 18 decimals.
     * @return updatedAt The timestamp of the answer.
     */
    function internalDataAtRound(uint256 roundId) public view override returns (int256, uint256) {
        (int256 answer, uint256 timestamp) = getSourceDataAtRound(roundId);

        // Return source data for the requested round only if it has been either explicitly or implicitly unlocked:
        //-> explicit unlock when source time is not newer than the time when last unlockLatestValue has been called, or
        //-> implicit unlock when source data is at least lockWindow old.
        uint256 latestUnlockedTimestamp = Math.max(lastUnlockTime, block.timestamp - lockWindow());
        if (timestamp <= latestUnlockedTimestamp) return (answer, timestamp);
        return (0, 0); // Source data is too recent, return uninitialized values.
    }
}
