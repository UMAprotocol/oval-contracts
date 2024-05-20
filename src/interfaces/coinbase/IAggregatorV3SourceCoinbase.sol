// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IAggregatorV3SourceCoinbase {
    function decimals() external view returns (uint8);

    function latestRoundData(string memory ticker)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function getRoundData(string memory ticker, uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
