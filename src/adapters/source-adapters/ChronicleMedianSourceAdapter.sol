// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {DiamondRootOval} from "../../DiamondRootOval.sol";
import {SnapshotSourceLib} from "../lib/SnapshotSourceLib.sol";
import {IMedian} from "../../interfaces/chronicle/IMedian.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

/**
 * @title ChronicleMedianSourceAdapter contract to read data from Chronicle and standardize it for Oval.
 */
abstract contract ChronicleMedianSourceAdapter is DiamondRootOval {
    IMedian public immutable CHRONICLE_SOURCE;

    SnapshotSourceLib.Snapshot[] public chronicleMedianSnapshots; // Historical answer and timestamp snapshots.

    event SourceSet(address indexed sourceOracle);

    constructor(IMedian _chronicleSource) {
        CHRONICLE_SOURCE = _chronicleSource;

        emit SourceSet(address(_chronicleSource));
    }

    /**
     * @notice Snapshot the current source data.
     */
    function snapshotData() public virtual override {
        (int256 latestAnswer, uint256 latestTimestamp) = ChronicleMedianSourceAdapter.getLatestSourceData();
        SnapshotSourceLib.snapshotData(chronicleMedianSnapshots, latestAnswer, latestTimestamp);
    }

    /**
     * @notice Returns the latest data from the source.
     * @dev The standard chronicle implementation will revert if the latest answer is not valid when calling the read
     * function. Additionally, chronicle returns the answer in 18 decimals, so no conversion is needed.
     * @return answer The latest answer in 18 decimals.
     * @return updatedAt The timestamp of the answer.
     */
    function getLatestSourceData() public view virtual override returns (int256, uint256) {
        return (SafeCast.toInt256(CHRONICLE_SOURCE.read()), CHRONICLE_SOURCE.age());
    }

    /**
     * @notice Returns the requested round data from the source.
     * @dev Chronicle Median does not support this and returns uninitialized data.
     * @return answer Round answer in 18 decimals.
     * @return updatedAt The timestamp of the answer.
     */
    function getSourceDataAtRound(uint256 /* roundId */ ) public view virtual override returns (int256, uint256) {
        return (0, 0);
    }

    /**
     * @notice Tries getting latest data as of requested timestamp. If this is not possible, returns the earliest data
     * available past the requested timestamp within provided traversal limitations.
     * @dev Chronicle does not support historical lookups so this uses SnapshotSourceLib to get historic data.
     * @param timestamp The timestamp to try getting latest data at.
     * @param maxTraversal The maximum number of rounds to traverse when looking for historical data.
     * @return answer The answer as of requested timestamp, or earliest available data if not available, in 18 decimals.
     * @return updatedAt The timestamp of the answer.
     * @return roundId The roundId of the answer (hardcoded to 1 as Chronicle Median does not support it).
     */
    function tryLatestDataAt(uint256 timestamp, uint256 maxTraversal)
        public
        view
        virtual
        override
        returns (int256, uint256, uint256)
    {
        (int256 latestAnswer, uint256 latestTimestamp) = ChronicleMedianSourceAdapter.getLatestSourceData();
        SnapshotSourceLib.Snapshot memory snapshot = SnapshotSourceLib._tryLatestDataAt(
            chronicleMedianSnapshots, latestAnswer, latestTimestamp, timestamp, maxTraversal, maxAge()
        );
        return (snapshot.answer, snapshot.timestamp, 1);
    }
}
