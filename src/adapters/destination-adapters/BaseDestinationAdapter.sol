// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {DiamondRootOval} from "../../DiamondRootOval.sol";

/**
 * @title BaseDestinationAdapter contract to expose Oval data via the standardized interface. Provides a base
 * implementation that consumers can connect with if they don't want to use an opinionated destination Adapter.
 *
 */

abstract contract BaseDestinationAdapter is DiamondRootOval {
    uint8 public constant decimals = 18;

    /**
     * @notice Returns the latest data from the source.
     * @return answer The latest answer in 18 decimals.
     */
    function latestAnswer() public view returns (int256) {
        (int256 answer,) = internalLatestData();
        return answer;
    }

    /**
     * @notice Returns the latest data timestamp from the source.
     * @return timestamp The timestamp of the most recent update.
     */
    function latestTimestamp() public view returns (uint256) {
        (, uint256 timestamp) = internalLatestData();
        return timestamp;
    }
}
