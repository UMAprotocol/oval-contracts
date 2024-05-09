// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {DecimalLib} from "../lib/DecimalLib.sol";
import {IAggregatorV3Source} from "../../interfaces/chainlink/IAggregatorV3Source.sol";
import {DiamondRootOval} from "../../DiamondRootOval.sol";
import {console} from "forge-std/console.sol";

/**
 * @title CoinbaseOracleSourceAdapter contract to read data from CoinbaseOracle and standardize it for Oval.
 * @dev Can fetch information from CoinbaseOracle source at a desired timestamp for historic lookups.
 */

abstract contract CoinbaseOracleSourceAdapter is DiamondRootOval {
    IAggregatorV3Source public immutable COINBASE_SOURCE;
    uint8 private immutable SOURCE_DECIMALS;

    event SourceSet(address indexed sourceOracle, uint8 indexed sourceDecimals);

    constructor(IAggregatorV3Source source) {
        COINBASE_SOURCE = source;
        SOURCE_DECIMALS = source.decimals();

        emit SourceSet(address(source), SOURCE_DECIMALS);
    }

    /**
     * @notice Tries getting latest data as of requested timestamp. If this is not possible, returns the earliest data
     * available past the requested timestamp within provided traversal limitations.
     * @param timestamp The timestamp to try getting latest data at.
     * @param maxTraversal The maximum number of rounds to traverse when looking for historical data.
     * @return answer The answer as of requested timestamp, or earliest available data if not available, in 18 decimals.
     * @return updatedAt The timestamp of the answer.
     */
    function tryLatestDataAt(
        uint256 timestamp,
        uint256 maxTraversal
    ) public view virtual override returns (int256, uint256) {
        (int256 answer, uint256 updatedAt) = _tryLatestRoundDataAt(
            timestamp,
            maxTraversal
        );
        return (
            DecimalLib.convertDecimals(answer, SOURCE_DECIMALS, 18),
            updatedAt
        );
    }

    /**
     * @notice Initiate a snapshot of the source data. This is a no-op for Coinbase.
     */
    function snapshotData() public virtual override {}

    /**
     * @notice Returns the latest data from the source.
     * @return answer The latest answer in 18 decimals.
     * @return updatedAt The timestamp of the answer.
     */
    function getLatestSourceData()
        public
        view
        virtual
        override
        returns (int256, uint256)
    {
        (, int256 sourceAnswer, , uint256 updatedAt, ) = COINBASE_SOURCE
            .latestRoundData();
        return (
            DecimalLib.convertDecimals(sourceAnswer, SOURCE_DECIMALS, 18),
            updatedAt
        );
    }

    // Tries getting latest data as of requested timestamp. If this is not possible, returns the earliest data available
    // past the requested timestamp considering the maxTraversal limitations.
    function _tryLatestRoundDataAt(
        uint256 timestamp,
        uint256 maxTraversal
    ) internal view returns (int256, uint256) {
        (uint80 roundId, int256 answer, , uint256 updatedAt, ) = COINBASE_SOURCE
            .latestRoundData();

        // In the happy path there have been no source updates since requested time, so we can return the latest data.
        // We can use updatedAt property as it matches the block timestamp of the latest source transmission.
        if (updatedAt <= timestamp) return (answer, updatedAt);

        // Attempt traversing historical round data backwards from roundId. This might still be newer or uninitialized.
        (
            int256 historicalAnswer,
            uint256 historicalUpdatedAt
        ) = _searchRoundDataAt(timestamp, roundId, maxTraversal);

        // Validate returned data. If it is uninitialized we fallback to returning the current latest round data.
        if (historicalUpdatedAt > 0)
            return (historicalAnswer, historicalUpdatedAt);
        return (answer, updatedAt);
    }

    // Tries finding latest historical data (ignoring current roundId) not newer than requested timestamp. Might return
    // newer data than requested if exceeds traversal or hold uninitialized data that should be handled by the caller.
    function _searchRoundDataAt(
        uint256 timestamp,
        uint80 targetRoundId,
        uint256 maxTraversal
    ) internal view returns (int256, uint256) {
        int256 answer;
        uint256 updatedAt;
        uint80 traversedRounds = 1; // Start from 1 to avoid checking the current round.

        while (
            traversedRounds <= uint80(maxTraversal) &&
            targetRoundId >= traversedRounds
        ) {
            (, answer, , updatedAt, ) = COINBASE_SOURCE.getRoundData(
                targetRoundId - traversedRounds
            );
            if (updatedAt <= timestamp) return (answer, updatedAt);
            traversedRounds++;
        }

        return (answer, updatedAt); // Did not find requested round. Return earliest round or uninitialized data.
    }
}
