// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {RedstoneConsumerNumericBase} from "@redstone-finance/evm-connector/contracts/core/RedstoneConsumerNumericBase.sol";

import {CommonTest} from "../Common.sol";

import {BaseController} from "../../src/controllers/BaseController.sol";
import {ChainlinkSourceAdapter} from "../../src/adapters/source-adapters/ChainlinkSourceAdapter.sol";
import {DecimalLib} from "../../src/adapters/lib/DecimalLib.sol";
import {IAggregatorV3Source} from "../../src/interfaces/chainlink/IAggregatorV3Source.sol";
import {RedstonePriceFeedWithRounds} from "../../src/oracles/RedstonePriceFeedWithRounds.sol";

import {IAggregatorV3Source} from "../../src/interfaces/chainlink/IAggregatorV3Source.sol";

import {TestedSourceAdapter} from "../fork/adapters/ChainlinkSourceAdapter.sol";

import "forge-std/console.sol";

contract MockRedstonePayload is CommonTest {
    function getRedstonePayload(
        string memory priceFeed
    ) public returns (bytes memory) {
        string[] memory args = new string[](4);
        args[0] = "node";
        args[1] = "--no-warnings";
        args[2] = "./scripts/src/RedstoneHelpers/getRedstonePayload.js";
        args[3] = priceFeed;

        return vm.ffi(args);
    }
}

contract RedstoneOracleAdapterTest is CommonTest, MockRedstonePayload {
    RedstonePriceFeedWithRounds redstoneOracle;
    TestedSourceAdapter sourceAdapter;

    function setUp() public {
        redstoneOracle = new RedstonePriceFeedWithRounds(bytes32("BTC"));
        sourceAdapter = new TestedSourceAdapter(
            IAggregatorV3Source(address(redstoneOracle))
        );
    }

    function pushPrice() internal returns (uint256, uint256) {
        bytes memory data = getRedstonePayload("BTC");

        (
            bytes memory redstonePayload,
            uint256 timestampMilliseconds,
            uint256 updatePrice
        ) = abi.decode(data, (bytes, uint256, uint256));

        uint256 timestampSeconds = timestampMilliseconds / 1000;

        vm.warp(timestampSeconds);
        bytes memory encodedFunction = abi.encodeWithSignature(
            "updateDataFeedsValues(uint256)",
            timestampMilliseconds
        );
        bytes memory encodedFunctionWithRedstonePayload = abi.encodePacked(
            encodedFunction,
            redstonePayload
        );

        address(redstoneOracle).call(encodedFunctionWithRedstonePayload);

        return (updatePrice, timestampSeconds);
    }

    function testPushPrice() public {
        (uint256 updatePrice, uint256 updateTimestamp) = pushPrice();
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = redstoneOracle.latestRoundData();

        assertEq(roundId, 1);
        assertEq(uint256(answer), updatePrice);
        assertEq(startedAt, updateTimestamp);
        assertEq(updatedAt, updateTimestamp);
        assertEq(answeredInRound, 1);
    }

    function testCorrectlyStandardizesOutputs() public {
        (uint256 pushedPrice, ) = pushPrice();
        (
            ,
            int256 latestChainlinkAnswer,
            ,
            uint256 latestChainlinkTimestamp,

        ) = redstoneOracle.latestRoundData();
        (
            int256 latestSourceAnswer,
            uint256 latestSourceTimestamp
        ) = sourceAdapter.getLatestSourceData();
        assertTrue(
            scaleChainlinkTo18(latestChainlinkAnswer) == latestSourceAnswer
        );
        assertTrue(pushedPrice == uint256(latestChainlinkAnswer));
        assertTrue(latestSourceTimestamp == latestChainlinkTimestamp);
    }

    function scaleChainlinkTo18(int256 input) public pure returns (int256) {
        return (input * 10 ** 18) / 10 ** 8;
    }
}
