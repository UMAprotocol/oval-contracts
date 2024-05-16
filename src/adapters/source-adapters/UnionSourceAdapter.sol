// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {IAggregatorV3Source} from "../../interfaces/chainlink/IAggregatorV3Source.sol";
import {IMedian} from "../../interfaces/chronicle/IMedian.sol";
import {IPyth} from "../../interfaces/pyth/IPyth.sol";
import {ChainlinkSourceAdapter} from "./ChainlinkSourceAdapter.sol";
import {ChronicleMedianSourceAdapter} from "./ChronicleMedianSourceAdapter.sol";
import {PythSourceAdapter} from "./PythSourceAdapter.sol";
import {SnapshotSource} from "./SnapshotSource.sol";

/**
 * @title UnionSourceAdapter contract to read data from multiple sources and return the newest.
 * @dev This adapter only works with Chainlink, Chronicle and Pyth adapters. If alternative adapter configs are desired
 * then a new adapter should be created.
 */

abstract contract UnionSourceAdapter is ChainlinkSourceAdapter, ChronicleMedianSourceAdapter, PythSourceAdapter {
    constructor(IAggregatorV3Source chainlink, IMedian chronicle, IPyth pyth, bytes32 pythPriceId)
        ChainlinkSourceAdapter(chainlink)
        ChronicleMedianSourceAdapter(chronicle)
        PythSourceAdapter(pyth, pythPriceId)
    {}

    /**
     * @notice Returns the latest data from the source. As this source is the union of multiple sources, it will return
     * the most recent data from the set of sources.
     * @return answer The latest answer in 18 decimals.
     * @return timestamp The timestamp of the answer.
     */
    function getLatestSourceData()
        public
        view
        override(ChainlinkSourceAdapter, ChronicleMedianSourceAdapter, PythSourceAdapter)
        returns (int256, uint256)
    {
        (int256 clAnswer, uint256 clTimestamp) = ChainlinkSourceAdapter.getLatestSourceData();
        (int256 crAnswer, uint256 crTimestamp) = ChronicleMedianSourceAdapter.getLatestSourceData();
        (int256 pyAnswer, uint256 pyTimestamp) = PythSourceAdapter.getLatestSourceData();

        if (clTimestamp >= crTimestamp && clTimestamp >= pyTimestamp) return (clAnswer, clTimestamp);
        else if (crTimestamp >= pyTimestamp) return (crAnswer, crTimestamp);
        else return (pyAnswer, pyTimestamp);
    }

    /**
     * @notice Snapshots data from all sources that require it.
     */
    function snapshotData() public override(ChainlinkSourceAdapter, SnapshotSource) {
        SnapshotSource.snapshotData();
    }

    /**
     * @notice Tries getting latest data as of requested timestamp. Note that for all historic lookups we simply return
     * the chainlink data as this is the only supported source that has historical data.
     * @param timestamp The timestamp to try getting latest data at.
     * @param maxTraversal The maximum number of rounds to traverse when looking for historical data.
     * @return answer The answer as of requested timestamp, or earliest available data if not available, in 18 decimals.
     * @return updatedAt The timestamp of the answer.
     */
    function tryLatestDataAt(uint256 timestamp, uint256 maxTraversal)
        public
        view
        override(ChainlinkSourceAdapter, ChronicleMedianSourceAdapter, PythSourceAdapter)
        returns (int256, uint256)
    {
        // Chainlink has price history, so just use tryLatestDataAt to pull the most recent price that satisfies the timestamp constraint.
        (int256 clAnswer, uint256 clTimestamp) = ChainlinkSourceAdapter.tryLatestDataAt(timestamp, maxTraversal);

        // For Chronicle and Pyth, just pull the most recent prices and drop them if they don't satisfy the constraint.
        (int256 crAnswer, uint256 crTimestamp) = ChronicleMedianSourceAdapter.getLatestSourceData();
        (int256 pyAnswer, uint256 pyTimestamp) = PythSourceAdapter.getLatestSourceData();

        // To "drop" Chronicle and Pyth, we set their timestamps to 0 (as old as possible) if they are too recent.
        // This means that they will never be used if either or both are 0.
        if (crTimestamp > timestamp) crTimestamp = 0;
        if (pyTimestamp > timestamp) pyTimestamp = 0;

        // This if/else block matches the one in getLatestSourceData, since it is now just looking for the most recent
        // timestamp, as all prices that violate the input constraint have had their timestamps set to 0.
        if (clTimestamp >= crTimestamp && clTimestamp >= pyTimestamp) return (clAnswer, clTimestamp);
        else if (crTimestamp >= pyTimestamp) return (crAnswer, crTimestamp);
        else return (pyAnswer, pyTimestamp);
    }
}
