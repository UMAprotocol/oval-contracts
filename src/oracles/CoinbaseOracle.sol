// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IAggregatorV3Source} from "../interfaces/chainlink/IAggregatorV3Source.sol";

/**
 * @title CoinbaseOracle
 * @notice A smart contract that serves as an oracle for price data reported by a designated reporter.
 */
contract CoinbaseOracle is IAggregatorV3Source {
    address immutable reporter;

    uint8 public immutable decimals;

    string public symbol;

    uint80 public lastRoundId;

    mapping(uint80 => int256) public roundAnswers;
    mapping(uint80 => uint256) public roundTimestamps;

    /**
     * @notice Emitted when a new price is pushed.
     * @param roundId The round ID of the new price.
     * @param price The price that was pushed.
     * @param timestamp The timestamp at which the price was pushed.
     */
    event PricePushed(uint80 indexed roundId, int256 price, uint256 timestamp);

    /**
     * @notice Constructor to initialize the CoinbaseOracle contract.
     * @param _symbol The symbol of the asset being reported.
     * @param _decimals The number of decimals in the reported price.
     * @param _reporter The address of the reporter allowed to push price data.
     */
    constructor(string memory _symbol, uint8 _decimals, address _reporter) {
        symbol = _symbol;
        decimals = _decimals;
        reporter = _reporter;
    }

    /**
     * @notice Returns the latest round data.
     * @return roundId The ID of the latest round.
     * @return answer The latest price.
     * @return startedAt The timestamp when the round started.
     * @return updatedAt The timestamp when the round was updated.
     * @return answeredInRound The round ID in which the answer was computed.
     */
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

    /**
     * @notice Returns the data for a specific round.
     * @param _roundId The round ID to retrieve the data for.
     * @return roundId The ID of the round.
     * @return answer The price of the round.
     * @return startedAt The timestamp when the round started.
     * @return updatedAt The timestamp when the round was updated.
     * @return answeredInRound The round ID in which the answer was computed.
     */
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

    /**
     * @notice Pushes a new price to the oracle.
     * @param priceData The encoded price data.
     * @param signature The signature to verify the authenticity of the data.
     */
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

        emit PricePushed(lastRoundId, int256(price), timestamp);
    }

    /**
     * @notice Internal function to recover the signer of a message.
     * @param message The message that was signed.
     * @param signature The signature to recover the signer from.
     * @return The address of the signer.
     */
    function recoverSigner(bytes memory message, bytes memory signature) internal pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = abi.decode(signature, (bytes32, bytes32, uint8));
        bytes32 hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(message)));
        return ecrecover(hash, v, r, s);
    }
}
