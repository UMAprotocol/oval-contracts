// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {SnapshotSourceLib} from "../../src/adapters/lib/SnapshotSourceLib.sol";
import {DiamondRootOval} from "../../src/DiamondRootOval.sol";

abstract contract MockSnapshotSourceAdapter is DiamondRootOval {
    struct SourceData {
        int256 answer;
        uint256 timestamp;
    }

    SourceData[] public sourceRounds;

    SnapshotSourceLib.Snapshot[] public mockSnapshots;

    function publishSourceData(int256 answer, uint256 timestamp) public {
        sourceRounds.push(SourceData(answer, timestamp));
    }

    function snapshotData() public virtual override {
        (int256 latestAnswer, uint256 latestTimestamp) = MockSnapshotSourceAdapter.getLatestSourceData();
        SnapshotSourceLib.snapshotData(mockSnapshots, latestAnswer, latestTimestamp);
    }

    function getLatestSourceData() public view virtual override returns (int256, uint256) {
        SourceData memory latestData = _latestSourceData();
        return (latestData.answer, latestData.timestamp);
    }

    function tryLatestDataAt(uint256 timestamp, uint256 maxTraversal)
        public
        view
        virtual
        override
        returns (int256, uint256)
    {
        (int256 latestAnswer, uint256 latestTimestamp) = MockSnapshotSourceAdapter.getLatestSourceData();
        SnapshotSourceLib.Snapshot memory latestData =
            SnapshotSourceLib._tryLatestDataAt(mockSnapshots, latestAnswer, latestTimestamp, timestamp, maxTraversal);
        return (latestData.answer, latestData.timestamp);
    }

    function latestSnapshotData() public view returns (SnapshotSourceLib.Snapshot memory) {
        if (mockSnapshots.length > 0) return mockSnapshots[mockSnapshots.length - 1];
        return SnapshotSourceLib.Snapshot(0, 0);
    }

    function _latestSourceData() internal view returns (SourceData memory) {
        if (sourceRounds.length > 0) return sourceRounds[sourceRounds.length - 1];
        return SourceData(0, 0);
    }
}
