// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IOval {
    event LatestValueUnlocked(uint256 indexed timestamp);

    function internalLatestData() external view returns (int256 answer, uint256 timestamp, uint256 roundId);
}
