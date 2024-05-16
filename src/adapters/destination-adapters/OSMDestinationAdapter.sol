// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {IOSM} from "../../interfaces/makerdao/IOSM.sol";
import {DiamondRootOval} from "../../DiamondRootOval.sol";

/**
 * @title OSMDestinationAdapter contract to expose Oval data via the standard MakerDAO OSM interface.
 */

abstract contract OSMDestinationAdapter is IOSM, DiamondRootOval {
    constructor() {}

    /**
     * @notice Returns the latest data from the source, formatted for the OSM interface as a bytes32.
     * @dev The standard OSM implementation will revert if the latest answer is not valid when calling the read function.
     * This implementation will only revert if the latest answer is negative.
     * @return answer The latest answer as a bytes32.
     */
    function read() public view override returns (bytes32) {
        // MakerDAO performs decimal conversion in collateral adapter contracts, so all oracle prices are expected to
        // have 18 decimals, the same as returned by the internalLatestData().answer.
        (int256 answer,) = internalLatestData();
        return bytes32(uint256(answer));
    }

    /**
     * @notice Returns the latest data from the source and a bool indicating if the value is valid.
     * @return answer The latest answer as a bytes32.
     * @return valid True if the value returned is valid.
     */
    function peek() public view override returns (bytes32, bool) {
        (int256 answer,) = internalLatestData();
        // This might be required for MakerDAO when voiding Oracle sources.
        return (bytes32(uint256(answer)), answer > 0);
    }

    /**
     * @notice Returns the timestamp of the most recently updated data.
     * @return timestamp The timestamp of the most recent update.
     */
    function zzz() public view override returns (uint64) {
        (, uint256 timestamp) = internalLatestData();
        return uint64(timestamp);
    }
}
