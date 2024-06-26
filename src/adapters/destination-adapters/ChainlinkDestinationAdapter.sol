// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import {DecimalLib} from "../lib/DecimalLib.sol";
import {IAggregatorV3} from "../../interfaces/chainlink/IAggregatorV3.sol";
import {DiamondRootOval} from "../../DiamondRootOval.sol";

/**
 * @title ChainlinkDestinationAdapter contract to expose Oval data via the standard Chainlink Aggregator interface.
 */
abstract contract ChainlinkDestinationAdapter is DiamondRootOval, IAggregatorV3 {
    uint8 public immutable override decimals;

    event DecimalsSet(uint8 indexed decimals);

    constructor(uint8 _decimals) {
        decimals = _decimals;

        emit DecimalsSet(_decimals);
    }

    /**
     * @notice Returns the latest data from the source.
     * @return answer The latest answer in the configured number of decimals.
     */
    function latestAnswer() public view override returns (int256) {
        (int256 answer,,) = internalLatestData();
        return DecimalLib.convertDecimals(answer, 18, decimals);
    }

    /**
     * @notice Returns when the latest answer was updated.
     * @return timestamp The timestamp of the latest answer.
     */
    function latestTimestamp() public view override returns (uint256) {
        (, uint256 timestamp,) = internalLatestData();
        return timestamp;
    }

    /**
     * @notice Returns the latest Round data.
     * @return roundId The roundId of the latest answer (sources that do not support it hardcodes to 1).
     * @return answer The latest answer in the configured number of decimals.
     * @return startedAt The timestamp when the value was updated.
     * @return updatedAt The timestamp when the value was updated.
     * @return answeredInRound The roundId of the round in which the answer was computed (sources that do not support it
     * hardcodes to 1).
     */
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        (int256 answer, uint256 updatedAt, uint256 _roundId) = internalLatestData();
        uint80 roundId = SafeCast.toUint80(_roundId);
        return (roundId, DecimalLib.convertDecimals(answer, 18, decimals), updatedAt, updatedAt, roundId);
    }

    /**
     * @notice Returns the requested round data if available or uninitialized values then it is too recent.
     * @dev If the source does not support round data, always returns uninitialized answer and timestamp values.
     * @param _roundId The roundId to retrieve the round data for.
     * @return roundId The roundId of the latest answer (same as requested roundId).
     * @return answer The latest answer in the configured number of decimals.
     * @return startedAt The timestamp when the value was updated.
     * @return updatedAt The timestamp when the value was updated.
     * @return answeredInRound The roundId of the round in which the answer was computed (same as requested roundId).
     */
    function getRoundData(uint80 _roundId) external view returns (uint80, int256, uint256, uint256, uint80) {
        (int256 answer, uint256 updatedAt) = internalDataAtRound(_roundId);
        return (_roundId, DecimalLib.convertDecimals(answer, 18, decimals), updatedAt, updatedAt, _roundId);
    }
}
