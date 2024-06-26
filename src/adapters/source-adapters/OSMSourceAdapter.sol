// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {SnapshotSource} from "./SnapshotSource.sol";
import {IOSM} from "../../interfaces/makerdao/IOSM.sol";

/**
 * @title OSMSourceAdapter contract to read data from MakerDAO OSM and standardize it for Oval.
 */
abstract contract OSMSourceAdapter is SnapshotSource {
    IOSM public immutable osmSource;

    // MakerDAO performs decimal conversion in collateral adapter contracts, so all oracle prices are expected to have
    // 18 decimals and we can skip decimal conversion.
    uint8 public constant decimals = 18;

    event SourceSet(address indexed sourceOracle);

    constructor(IOSM source) {
        osmSource = source;

        emit SourceSet(address(source));
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
     * @notice Returns the requested round data from the source.
     * @dev OSM does not support this and returns uninitialized data.
     * @return answer Round answer in 18 decimals.
     * @return updatedAt The timestamp of the answer.
     */
    function getSourceDataAtRound(uint256 /* roundId */ ) public view virtual override returns (int256, uint256) {
        return (0, 0);
    }

    /**
     * @notice Tries getting latest data as of requested timestamp. If this is not possible, returns the earliest data
     * available past the requested timestamp within provided traversal limitations.
     * @dev OSM does not support historical lookups so this uses SnapshotSource to get historic data.
     * @param timestamp The timestamp to try getting latest data at.
     * @param maxTraversal The maximum number of rounds to traverse when looking for historical data.
     * @return answer The answer as of requested timestamp, or earliest available data if not available, in 18 decimals.
     * @return updatedAt The timestamp of the answer.
     * @return roundId The roundId of the answer (hardcoded to 1 as OSM does not support it).
     */
    function tryLatestDataAt(uint256 timestamp, uint256 maxTraversal)
        public
        view
        override
        returns (int256, uint256, uint256)
    {
        Snapshot memory snapshot = _tryLatestDataAt(timestamp, maxTraversal);
        return (snapshot.answer, snapshot.timestamp, 1);
    }
}
