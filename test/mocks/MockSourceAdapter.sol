// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {DiamondRootOval} from "../../src/DiamondRootOval.sol";

abstract contract MockSourceAdapter is DiamondRootOval {
    uint8 public sourceDecimals;

    struct RoundData {
        int256 answer;
        uint256 timestamp;
    }

    RoundData[] public rounds;

    constructor(uint8 decimals) {
        sourceDecimals = decimals;
    }

    function snapshotData() public override {}

    function publishRoundData(int256 answer, uint256 timestamp) public {
        rounds.push(RoundData(answer, timestamp));
    }

    function tryLatestDataAt(uint256 timestamp, uint256 maxTraversal)
        public
        view
        virtual
        override
        returns (int256, uint256)
    {
        RoundData memory latestData = _tryLatestDataAt(timestamp, maxTraversal);
        return (latestData.answer, latestData.timestamp);
    }

    function getLatestSourceData() public view virtual override returns (int256, uint256) {
        RoundData memory latestData = _latestRoundData();
        return (latestData.answer, latestData.timestamp);
    }

    function _latestRoundData() internal view returns (RoundData memory) {
        if (rounds.length > 0) return rounds[rounds.length - 1];
        return RoundData(0, 0);
    }

    function _tryLatestDataAt(uint256 timestamp, uint256 maxTraversal) internal view returns (RoundData memory) {
        RoundData memory latestData = _latestRoundData();
        if (latestData.timestamp <= timestamp) return latestData;

        RoundData memory historicalData = _searchDataAt(timestamp, maxTraversal);

        if (historicalData.timestamp > 0) return historicalData;
        return latestData;
    }

    function _searchDataAt(uint256 timestamp, uint256 maxTraversal) internal view returns (RoundData memory) {
        RoundData memory roundData;
        uint256 traversedRounds = 0;
        uint256 roundId = rounds.length;

        while (traversedRounds < maxTraversal && roundId > 0) {
            roundId--;
            roundData = rounds[roundId];
            if (roundData.timestamp <= timestamp) return roundData;
            traversedRounds++;
        }

        return roundData;
    }
}
