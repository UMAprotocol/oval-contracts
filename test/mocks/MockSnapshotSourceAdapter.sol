// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {SnapshotSource} from "../../src/adapters/source-adapters/SnapshotSource.sol";

abstract contract MockSnapshotSourceAdapter is SnapshotSource {
    struct SourceData {
        int256 answer;
        uint256 timestamp;
    }

    SourceData[] public sourceRounds;

    function publishSourceData(int256 answer, uint256 timestamp) public {
        sourceRounds.push(SourceData(answer, timestamp));
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
        returns (int256, uint256, uint256)
    {
        SnapshotSource.Snapshot memory latestData = _tryLatestDataAt(timestamp, maxTraversal);
        return (latestData.answer, latestData.timestamp, 1);
    }

    function _latestSourceData() internal view returns (SourceData memory) {
        if (sourceRounds.length > 0) return sourceRounds[sourceRounds.length - 1];
        return SourceData(0, 0);
    }
}
