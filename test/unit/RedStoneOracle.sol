// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
import {RedstoneConsumerNumericBase} from "@redstone-finance/evm-connector/contracts/core/RedstoneConsumerNumericBase.sol";

import {CommonTest} from "../Common.sol";

import {BaseController} from "../../src/controllers/BaseController.sol";
import {ChainlinkSourceAdapter} from "../../src/adapters/source-adapters/ChainlinkSourceAdapter.sol";
import {DecimalLib} from "../../src/adapters/lib/DecimalLib.sol";
import {IAggregatorV3Source} from "../../src/interfaces/chainlink/IAggregatorV3Source.sol";
import {RedstonePriceFeedWithRounds} from "../../src/oracles/RedstonePriceFeedWithRounds.sol";

contract MockRedstonePayload is CommonTest {
    function getRedstonePayload(
        // dataFeedId:value:decimals
        string memory priceFeed
    ) public returns (bytes memory) {
        string[] memory args = new string[](3);
        args[0] = "node";
        args[1] = "./redstone/getRedstonePayload.js";
        args[2] = priceFeed;

        return vm.ffi(args);
    }
}

contract RedstoneOracleAdapterTest is
    CommonTest,
    MockRedstonePayload,
    RedstoneConsumerNumericBase
{
    RedstonePriceFeedWithRounds redstoneOracle;

    function setUp() public {
        redstoneOracle = new RedstonePriceFeedWithRounds(bytes32("BTC"));
    }

    function getAuthorisedSignerIndex(
        address signerAddress
    ) public view virtual override returns (uint8) {}

    function testPushPrice() public {
        bytes memory data = getRedstonePayload("BTC:120:8");

        (bytes memory redstonePayload, uint256 timestampMilliseconds) = abi
            .decode(data, (bytes, uint256));

        bytes32[] memory dataFeedIds = new bytes32[](1);
        dataFeedIds[0] = bytes32("BTC");

        // uint256[] memory values = getOracleNumericValuesFromTxMsg(dataFeedIds);

        bytes memory encodedFunction = abi.encodeWithSignature(
            "updateDataFeedsValues(uint256)",
            timestampMilliseconds
        );
        bytes memory encodedFunctionWithRedstonePayload = abi.encodePacked(
            encodedFunction,
            redstonePayload
        );

        (bool success, ) = address(redstoneOracle).call(
            encodedFunctionWithRedstonePayload
        );

        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = redstoneOracle.latestRoundData();

        assertEq(roundId, 1);
        assertEq(answer, 120 * 10 ** 8);
        // assertEq(startedAt, timestampMilliseconds);
        // assertEq(updatedAt, timestampMilliseconds);
        assertEq(answeredInRound, 1);
    }
}
