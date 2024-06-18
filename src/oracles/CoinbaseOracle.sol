// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IAggregatorV3SourceCoinbase} from "../interfaces/coinbase/IAggregatorV3SourceCoinbase.sol";

/**
 * @title CoinbaseOracle
 * @notice A smart contract that serves as an oracle for price data reported by a designated reporter.
 */
contract CoinbaseOracle is IAggregatorV3SourceCoinbase {
    address public immutable REPORTER = 0xfCEAdAFab14d46e20144F48824d0C09B1a03F2BC;
    uint8 public immutable DECIMALS = 6;
    bytes32 public immutable KIND_HASH = keccak256(abi.encodePacked("prices"));

    struct RoundData {
        int256 answer;
        uint256 timestamp;
    }

    struct PriceData {
        uint80 lastRoundId;
        mapping(uint80 => RoundData) rounds;
    }

    mapping(string => PriceData) internal prices;

    event PricePushed(string indexed ticker, uint80 indexed roundId, int256 price, uint256 timestamp);

    /**
     * @notice Returns the number of decimals used by the oracle.
     * @return The number of decimals used by the oracle.
     */
    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    /**
     * @notice Returns the address of the reporter.
     * @return The address of the reporter.
     */
    function reporter() public view virtual returns (address) {
        return REPORTER;
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

        require(keccak256(abi.encodePacked(kind)) == KIND_HASH, "Invalid kind.");

        PriceData storage priceDataStruct = prices[ticker];
        uint256 latestTimestamp = priceDataStruct.rounds[priceDataStruct.lastRoundId].timestamp;

        require(timestamp > latestTimestamp, "Invalid timestamp.");
        require(recoverSigner(priceData, signature) == reporter(), "Invalid signature.");
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
