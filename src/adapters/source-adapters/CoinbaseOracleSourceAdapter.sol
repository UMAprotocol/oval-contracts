// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {DecimalLib} from "../lib/DecimalLib.sol";
import {IAggregatorV3Source} from "../../interfaces/chainlink/IAggregatorV3Source.sol";
import {DiamondRootOval} from "../../DiamondRootOval.sol";

/**
 * @title CoinbaseOracleSourceAdapter
 * @notice A contract to read data from CoinbaseOracle and standardize it for Oval.
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
     * @notice Tries getting the latest data as of the requested timestamp.
     * If this is not possible, returns the earliest data available past the requested timestamp within provided traversal limitations.
     * @param timestamp The timestamp to try getting the latest data at.
     * @param maxTraversal The maximum number of rounds to traverse when looking for historical data.
     * @return answer The answer as of the requested timestamp, or the earliest available data if not available, in 18 decimals.
     * @return updatedAt The timestamp of the answer.
     */
    function tryLatestDataAt(uint256 timestamp, uint256 maxTraversal)
        public
        view
        virtual
        override
        returns (int256, uint256)
    {
        (int256 answer, uint256 updatedAt) = _tryLatestRoundDataAt(timestamp, maxTraversal);
        return (DecimalLib.convertDecimals(answer, SOURCE_DECIMALS, 18), updatedAt);
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
    function getLatestSourceData() public view virtual override returns (int256, uint256) {
        (, int256 sourceAnswer,, uint256 updatedAt,) = COINBASE_SOURCE.latestRoundData();
        return (DecimalLib.convertDecimals(sourceAnswer, SOURCE_DECIMALS, 18), updatedAt);
    }

    // Tries getting the latest data as of the requested timestamp. If this is not possible,
    // returns the earliest data available past the requested timestamp considering the maxTraversal limitations.
    function _tryLatestRoundDataAt(uint256 timestamp, uint256 maxTraversal) internal view returns (int256, uint256) {
        (uint80 roundId, int256 answer,, uint256 updatedAt,) = COINBASE_SOURCE.latestRoundData();

        // If the latest update is older than or equal to the requested timestamp, return the latest data.
        if (updatedAt <= timestamp) {
            return (answer, updatedAt);
        }

        // Attempt traversing historical round data backwards from roundId.
        (int256 historicalAnswer, uint256 historicalUpdatedAt) = _searchRoundDataAt(timestamp, roundId, maxTraversal);

        // Validate returned data. If it is uninitialized, fall back to returning the current latest round data.
        if (historicalUpdatedAt > 0) {
            return (historicalAnswer, historicalUpdatedAt);
        }

        return (answer, updatedAt);
    }

    // Searches for the latest historical data not newer than the requested timestamp.
    // Returns newer data than requested if it exceeds traversal limits or holds uninitialized data that should be handled by the caller.
    function _searchRoundDataAt(uint256 timestamp, uint80 latestRoundId, uint256 maxTraversal)
        internal
        view
        returns (int256, uint256)
    {
        int256 answer;
        uint256 updatedAt;
        for (uint80 i = 1; i <= maxTraversal && latestRoundId >= i; i++) {
            (, answer,, updatedAt,) = COINBASE_SOURCE.getRoundData(latestRoundId - i);
            if (updatedAt <= timestamp) {
                return (answer, updatedAt);
            }
        }

        return (answer, updatedAt); // Did not find requested round. Return earliest round or uninitialized data.
    }
}
