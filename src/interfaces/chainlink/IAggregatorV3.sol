// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IAggregatorV3 {
    function latestAnswer() external view returns (int256);

    function latestTimestamp() external view returns (uint256);

    function decimals() external view returns (uint8);

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    // Other Chainlink functions we don't need.

    // function latestRound() external view returns (uint256);

    // function getAnswer(uint256 roundId) external view returns (int256);

    // function getTimestamp(uint256 roundId) external view returns (uint256);

    // function description() external view returns (string memory);

    // function version() external view returns (uint256);

    // event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);

    // event NewRound(uint256 indexed roundId, address indexed startedBy, uint256 startedAt);
}
