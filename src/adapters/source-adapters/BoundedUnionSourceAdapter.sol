// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";

import {IAggregatorV3Source} from "../../interfaces/chainlink/IAggregatorV3Source.sol";
import {IMedian} from "../../interfaces/chronicle/IMedian.sol";
import {IPyth} from "../../interfaces/pyth/IPyth.sol";
import {SnapshotSourceLib} from "../lib/SnapshotSourceLib.sol";
import {ChainlinkSourceAdapter} from "./ChainlinkSourceAdapter.sol";
import {ChronicleMedianSourceAdapter} from "./ChronicleMedianSourceAdapter.sol";
import {PythSourceAdapter} from "./PythSourceAdapter.sol";

/**
 * @title BoundedUnionSourceAdapter contract to read data from multiple sources and return the newest, contingent on it
 * being within a certain tolerance of the other sources. The return logic operates as follows:
 *   a) Return the most recent price if it's within tolerance of at least one of the other two.
 *   b) If not, return the second most recent price if it's within tolerance of at least one of the other two.
 *   c) If neither a) nor b) is met, return the chainlink price.
 * @dev This adapter only works with Chainlink, Chronicle and Pyth adapters. If alternative adapter configs are desired
 * then a new adapter should be created.
 */
abstract contract BoundedUnionSourceAdapter is
    ChainlinkSourceAdapter,
    ChronicleMedianSourceAdapter,
    PythSourceAdapter
{
    // Pack all source data into a struct to avoid stack too deep errors.
    struct AllSourceData {
        int256 clAnswer;
        uint256 clTimestamp;
        int256 crAnswer;
        uint256 crTimestamp;
        int256 pyAnswer;
        uint256 pyTimestamp;
    }

    uint256 public immutable BOUNDING_TOLERANCE;

    SnapshotSourceLib.Snapshot[] public boundedUnionSnapshots; // Historical answer and timestamp snapshots.

    constructor(
        IAggregatorV3Source chainlink,
        IMedian chronicle,
        IPyth pyth,
        bytes32 pythPriceId,
        uint256 boundingTolerance
    ) ChainlinkSourceAdapter(chainlink) ChronicleMedianSourceAdapter(chronicle) PythSourceAdapter(pyth, pythPriceId) {
        BOUNDING_TOLERANCE = boundingTolerance;
    }

    /**
     * @notice Returns the latest data from the source, contingent on it being within a tolerance of the other sources.
     * @return answer The latest answer in 18 decimals.
     * @return timestamp The timestamp of the answer.
     */
    function getLatestSourceData()
        public
        view
        override(ChainlinkSourceAdapter, ChronicleMedianSourceAdapter, PythSourceAdapter)
        returns (int256 answer, uint256 timestamp)
    {
        AllSourceData memory data = _getAllLatestSourceData();
        return _selectBoundedPrice(data);
    }

    /**
     * @notice Returns the requested round data from the source.
     * @dev Not all aggregated adapters support this, so this returns uninitialized data.
     * @return answer Round answer in 18 decimals.
     * @return updatedAt The timestamp of the answer.
     */
    function getSourceDataAtRound(uint256 /* roundId */ )
        public
        view
        virtual
        override(ChainlinkSourceAdapter, ChronicleMedianSourceAdapter, PythSourceAdapter)
        returns (int256, uint256)
    {
        return (0, 0);
    }

    /**
     * @notice Snapshot the current bounded union source data.
     */
    function snapshotData() public override(ChainlinkSourceAdapter, ChronicleMedianSourceAdapter, PythSourceAdapter) {
        (int256 latestAnswer, uint256 latestTimestamp) = BoundedUnionSourceAdapter.getLatestSourceData();
        SnapshotSourceLib.snapshotData(boundedUnionSnapshots, latestAnswer, latestTimestamp);
    }

    /**
     * @notice Tries getting latest data as of requested timestamp.
     * @param timestamp The timestamp to try getting latest data at.
     * @param maxTraversal The maximum number of rounds to traverse when looking for historical data.
     * @return answer The answer as of requested timestamp, or earliest available data if not available, in 18 decimals.
     * @return updatedAt The timestamp of the answer.
     * @return roundId The roundId of the answer (hardcoded to 1 as not all aggregated adapters support it).
     */
    function tryLatestDataAt(uint256 timestamp, uint256 maxTraversal)
        public
        view
        override(ChainlinkSourceAdapter, ChronicleMedianSourceAdapter, PythSourceAdapter)
        returns (int256, uint256, uint256)
    {
        // In the happy path there have been no source updates since requested time, so we can return the latest data.
        AllSourceData memory data = _getAllLatestSourceData();
        (int256 boundedAnswer, uint256 boundedTimestamp) = _selectBoundedPrice(data);
        if (boundedTimestamp <= timestamp) return (boundedAnswer, boundedTimestamp, 1);

        // Chainlink has price history, so use tryLatestDataAt to pull the most recent price that satisfies the timestamp constraint.
        (data.clAnswer, data.clTimestamp,) = ChainlinkSourceAdapter.tryLatestDataAt(timestamp, maxTraversal);

        // "Drop" Chronicle and/or Pyth by setting their timestamps to 0 (as old as possible) if they are too recent.
        // This means that they will never be used if either or both are 0.
        if (data.crTimestamp > timestamp) data.crTimestamp = 0;
        if (data.pyTimestamp > timestamp) data.pyTimestamp = 0;

        // Bounded union prices could have been captured at snapshot that satisfies time constraint.
        SnapshotSourceLib.Snapshot memory snapshot = SnapshotSourceLib._tryLatestDataAt(
            boundedUnionSnapshots, boundedAnswer, boundedTimestamp, timestamp, maxTraversal
        );

        // Update bounded data with constrained source data.
        (boundedAnswer, boundedTimestamp) = _selectBoundedPrice(data);

        // Return bounded data unless there is a newer snapshotted data that still satisfies time constraint.
        if (boundedTimestamp > snapshot.timestamp || snapshot.timestamp > timestamp) {
            return (boundedAnswer, boundedTimestamp, 1);
        }
        return (snapshot.answer, snapshot.timestamp, 1);
    }

    // Internal helper to get the latest data from all sources.
    function _getAllLatestSourceData() internal view returns (AllSourceData memory) {
        AllSourceData memory data;
        (data.clAnswer, data.clTimestamp) = ChainlinkSourceAdapter.getLatestSourceData();
        (data.crAnswer, data.crTimestamp) = ChronicleMedianSourceAdapter.getLatestSourceData();
        (data.pyAnswer, data.pyTimestamp) = PythSourceAdapter.getLatestSourceData();

        return data;
    }

    // Selects the appropriate price from the three sources based on the bounding tolerance and logic.
    function _selectBoundedPrice(AllSourceData memory data) internal view returns (int256, uint256) {
        int256 newestVal = 0;
        uint256 newestT = 0;

        // Unpack the data to short named variables for better code readability below.
        (int256 cl, uint256 clT, int256 cr, uint256 crT, int256 py, uint256 pyT) =
            (data.clAnswer, data.clTimestamp, data.crAnswer, data.crTimestamp, data.pyAnswer, data.pyTimestamp);

        // For each price, check if it is within tolerance of the other two. If so, check if it is the newest.
        if (pyT > newestT && (_withinTolerance(py, cr) || _withinTolerance(py, cl))) (newestVal, newestT) = (py, pyT);
        if (crT > newestT && (_withinTolerance(cr, py) || _withinTolerance(cr, cl))) (newestVal, newestT) = (cr, crT);
        if (clT > newestT && (_withinTolerance(cl, py) || _withinTolerance(cl, cr))) (newestVal, newestT) = (cl, clT);

        if (newestT == 0) return (cl, clT); // If no valid price was found, default to returning chainlink.

        return (newestVal, newestT);
    }

    // Checks if value a is within tolerance of value b.
    function _withinTolerance(int256 a, int256 b) internal view returns (bool) {
        uint256 diff = SignedMath.abs(a - b);
        uint256 maxDiff = SignedMath.abs(b) * BOUNDING_TOLERANCE / 1e18;
        return diff <= maxDiff;
    }
}
