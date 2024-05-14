// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IAggregatorV3Source} from "../interfaces/chainlink/IAggregatorV3Source.sol";

contract CoinbaseOracle is IAggregatorV3Source {
    address immutable reporter;

    uint8 public immutable decimals;

    string public symbol;

    uint80 public lastRoundId;

    mapping(uint80 => int256) public roundAnswers;
    mapping(uint80 => uint256) public roundTimestamps;

    constructor(string memory _symbol, uint8 _decimals, address _reporter) {
        symbol = _symbol;
        decimals = _decimals;
        reporter = _reporter;
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        int256 latestAnswer = roundAnswers[lastRoundId];
        uint256 latestTimestamp = roundTimestamps[lastRoundId];
        return (lastRoundId, latestAnswer, latestTimestamp, latestTimestamp, lastRoundId);
    }

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        int256 latestAnswer = roundAnswers[_roundId];
        uint256 latestTimestamp = roundTimestamps[_roundId];
        return (_roundId, latestAnswer, latestTimestamp, latestTimestamp, _roundId);
    }

    function pushPrice(bytes memory priceData, bytes memory signature) external {
        (
            string memory kind, // e.g. "price"
            uint256 timestamp, // e.g. 1629350000
            string memory ticker, // e.g. "BTC"
            uint256 price // 6 decimals
        ) = abi.decode(priceData, (string, uint256, string, uint256));

        uint256 latestTimestamp = roundTimestamps[lastRoundId];

        require(keccak256(abi.encodePacked(kind)) == keccak256(abi.encodePacked("price")), "Invalid kind.");
        require(price < uint256(type(int256).max), "Price exceeds max value.");
        require(timestamp > latestTimestamp, "Invalid timestamp.");
        require(keccak256(abi.encodePacked(ticker)) == keccak256(abi.encodePacked(symbol)), "Invalid ticker.");
        require(recoverSigner(priceData, signature) == reporter, "Invalid signature.");

        lastRoundId++;
        roundAnswers[lastRoundId] = int256(price);
        roundTimestamps[lastRoundId] = timestamp;
    }

    // Internal function to recover the signer of a message
    function recoverSigner(bytes memory message, bytes memory signature) public pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = abi.decode(signature, (bytes32, bytes32, uint8));
        bytes32 hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(message)));
        return ecrecover(hash, v, r, s);
    }
}
