// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {DiamondRootOval} from "../../DiamondRootOval.sol";
import {SnapshotSourceLib} from "../lib/SnapshotSourceLib.sol";
import {IOSM} from "../../interfaces/makerdao/IOSM.sol";

/**
 * @title OSMSourceAdapter contract to read data from MakerDAO OSM and standardize it for Oval.
 */
abstract contract OSMSourceAdapter is DiamondRootOval {
    IOSM public immutable osmSource;

    // MakerDAO performs decimal conversion in collateral adapter contracts, so all oracle prices are expected to have
    // 18 decimals and we can skip decimal conversion.
    uint8 public constant decimals = 18;

    SnapshotSourceLib.Snapshot[] public osmSnapshots; // Historical answer and timestamp snapshots.

    event SourceSet(address indexed sourceOracle);

    constructor(IOSM source) {
        osmSource = source;

        emit SourceSet(address(source));
    }

    /**
     * @notice Snapshot the current source data.
     */
    function snapshotData() public virtual override {
        (int256 latestAnswer, uint256 latestTimestamp) = OSMSourceAdapter.getLatestSourceData();
        SnapshotSourceLib.snapshotData(osmSnapshots, latestAnswer, latestTimestamp);
    }

    /**
     * @notice Returns the latest data from the source.
     * @return answer The latest answer in 18 decimals.
     * @return updatedAt The timestamp of the answer.
     */
    function getLatestSourceData() public view override returns (int256, uint256) {
        return (int256(uint256(osmSource.read())), osmSource.zzz());
    }

    /**
     * @notice Tries getting latest data as of requested timestamp. If this is not possible, returns the earliest data
     * available past the requested timestamp within provided traversal limitations.
     * @dev OSM does not support historical lookups so this uses SnapshotSourceLib to get historic data.
     * @param timestamp The timestamp to try getting latest data at.
     * @param maxTraversal The maximum number of rounds to traverse when looking for historical data.
     * @return answer The answer as of requested timestamp, or earliest available data if not available, in 18 decimals.
     * @return updatedAt The timestamp of the answer.
     */
    function tryLatestDataAt(uint256 timestamp, uint256 maxTraversal) public view override returns (int256, uint256) {
        (int256 latestAnswer, uint256 latestTimestamp) = OSMSourceAdapter.getLatestSourceData();
        SnapshotSourceLib.Snapshot memory snapshot =
            SnapshotSourceLib._tryLatestDataAt(osmSnapshots, latestAnswer, latestTimestamp, timestamp, maxTraversal);
        return (snapshot.answer, snapshot.timestamp);
    }
}
