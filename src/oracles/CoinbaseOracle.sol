// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IAggregatorV3SourceCoinbase} from "../interfaces/coinbase/IAggregatorV3SourceCoinbase.sol";

/**
 * @title CoinbaseOracle
 * @notice A smart contract that serves as an oracle for price data reported by a designated reporter.
 */
contract CoinbaseOracle is IAggregatorV3SourceCoinbase {
    address immutable reporter;
    uint8 public immutable decimals;
    string public dataKind;

    struct RoundData {
        int256 answer;
        uint256 timestamp;
    }

    struct PriceData {
        uint80 lastRoundId;
        mapping(uint80 => RoundData) rounds;
    }

    mapping(string => PriceData) private prices;

    event PricePushed(string indexed ticker, uint80 indexed roundId, int256 price, uint256 timestamp);

    /**
     * @notice Constructor to initialize the CoinbaseOracle contract.
     * @param _decimals The number of decimals in the reported price.
     * @param _dataKind The kind of data that the oracle will report, expected to be "prices" but open for changes.
     * @param _reporter The address of the reporter allowed to push price data.
     */
    constructor(uint8 _decimals, string memory _dataKind, address _reporter) {
        decimals = _decimals;
        reporter = _reporter;
        dataKind = _dataKind;
    }

    /**
     * @notice Returns the latest round data for a given ticker.
     * @param ticker The ticker symbol to retrieve the data for.
     * @return roundId The ID of the latest round.
     * @return answer The latest price.
     * @return updatedAt The timestamp when the price was updated.
     */
    function latestRoundData(string memory ticker)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 updatedAt)
    {
        PriceData storage priceData = prices[ticker];
        RoundData storage latestRound = priceData.rounds[priceData.lastRoundId];
        return (priceData.lastRoundId, latestRound.answer, latestRound.timestamp);
    }

    /**
     * @notice Returns the data for a specific round for a given ticker.
     * @param ticker The ticker symbol to retrieve the data for.
     * @param roundId The round ID to retrieve the data for.
     * @return roundId The ID of the round.
     * @return answer The price of the round.
     * @return updatedAt The timestamp when the round was updated.
     */
    function getRoundData(string memory ticker, uint80 roundId)
        external
        view
        returns (uint80, int256 answer, uint256 updatedAt)
    {
        PriceData storage priceData = prices[ticker];
        RoundData memory round = priceData.rounds[roundId];
        return (roundId, round.answer, round.timestamp);
    }

    /**
     * @notice Pushes a new price to the oracle for a given ticker.
     * @dev Only the designated reporter can push price data.
     * @param priceData The encoded price data, which contains the following fields:
     * - kind: A string representing the kind of data (e.g., "prices").
     * - timestamp: A uint256 representing the timestamp when the price was reported (e.g., 1629350000).
     * - ticker: A string representing the ticker symbol of the asset (e.g., "BTC").
     * - price: A uint256 representing the price of the asset (with 6 decimals).
     * @param signature The signature to verify the authenticity of the data.
     */
    function pushPrice(bytes memory priceData, bytes memory signature) external {
        (
            string memory kind, // e.g. "prices"
            uint256 timestamp, // e.g. 1629350000
            string memory ticker, // e.g. "BTC"
            uint256 price // 6 decimals
        ) = abi.decode(priceData, (string, uint256, string, uint256));

        require(keccak256(abi.encodePacked(kind)) == keccak256(abi.encodePacked(dataKind)), "Invalid kind.");

        PriceData storage priceDataStruct = prices[ticker];
        uint256 latestTimestamp = priceDataStruct.rounds[priceDataStruct.lastRoundId].timestamp;

        require(timestamp > latestTimestamp, "Invalid timestamp.");
        require(recoverSigner(priceData, signature) == reporter, "Invalid signature.");
        require(price <= uint256(type(int256).max), "Price exceeds max value.");

        priceDataStruct.lastRoundId++;
        priceDataStruct.rounds[priceDataStruct.lastRoundId] = RoundData(int256(price), timestamp);

        emit PricePushed(ticker, priceDataStruct.lastRoundId, int256(price), timestamp);
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
