// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IMedian} from "../../interfaces/chronicle/IMedian.sol";
import {DiamondRootOval} from "../../DiamondRootOval.sol";

/**
 * @notice ChronicleMedianDestinationAdapter contract to expose Oval data via the standard Chronicle interface.
 */
abstract contract ChronicleMedianDestinationAdapter is IMedian, DiamondRootOval {
    constructor(address _sourceAdapter) {}

    uint8 public constant decimals = 18; // Chronicle price feeds have always have 18 decimals.

    /**
     * @notice Returns the latest data from the source.
     * @dev The standard chronicle implementation will revert if the latest answer is not valid when calling the read
     * function. This implementation will only revert if the latest answer is negative.
     * @return answer The latest answer in 18 decimals.
     */
    function read() public view override returns (uint256) {
        (int256 answer,,) = internalLatestData();
        require(answer > 0, "Median/invalid-price-feed");
        return uint256(answer);
    }

    /**
     * @notice Returns the latest data from the source and a bool indicating if the value is valid.
     * @return answer The latest answer in 18 decimals.
     * @return valid True if the value returned is valid.
     */
    function peek() public view override returns (uint256, bool) {
        (int256 answer,,) = internalLatestData();
        return (uint256(answer), answer > 0);
    }

    /**
     * @notice Returns the timestamp of the most recently updated data.
     * @return timestamp The timestamp of the most recent update.
     */
    function age() public view override returns (uint32) {
        (, uint256 timestamp,) = internalLatestData();
        return uint32(timestamp);
    }
}
