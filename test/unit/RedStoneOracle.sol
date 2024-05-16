// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
import {RedstoneConsumerNumericBase} from "@redstone-finance/evm-connector/contracts/core/RedstoneConsumerNumericBase.sol";

import {CommonTest} from "../Common.sol";

import {BaseController} from "../../src/controllers/BaseController.sol";
import {ChainlinkSourceAdapter} from "../../src/adapters/source-adapters/ChainlinkSourceAdapter.sol";
import {DecimalLib} from "../../src/adapters/lib/DecimalLib.sol";
import {IAggregatorV3Source} from "../../src/interfaces/chainlink/IAggregatorV3Source.sol";
import {RedstonePriceFeedWithRounds} from "../../src/oracles/RedstonePriceFeedWithRounds.sol";

import "forge-std/console.sol";

contract MockRedstonePayload is CommonTest {
    function getRedstonePayload(
        // dataFeedId:value:decimals
        string memory priceFeed
    ) public returns (bytes memory) {
        string[] memory args = new string[](4);
        args[0] = "node";
        args[1] = "--no-warnings";
        args[2] = "./redstone/getRedstonePayload.js";
        args[3] = priceFeed;

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

    function testPushPrice() public {
        bytes memory data = getRedstonePayload("BTC:120:8");

        (bytes memory redstonePayload, uint256 timestampMilliseconds, uint256 updatePrice) = abi
            .decode(data, (bytes, uint256,uint256));

        bytes memory encodedFunctionNumericValues = abi.encodeWithSignature(
            "getOracleNumericValueFromTxMsg(bytes32)",
            bytes32("BTC")
        );

        bytes memory encodedFunctionNumericWithRedstonePayload = abi
            .encodePacked(encodedFunctionNumericValues, redstonePayload);

        (bool success2, bytes memory dataa) = address(redstoneOracle).call(
            encodedFunctionNumericWithRedstonePayload
        );

        uint256 oracleValue;
        if (success2) {
            oracleValue = abi.decode(dataa, (uint256));
        }

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
        // (bool success3, ) = address(redstoneOracle).call(
        //     encodedFunctionWithRedstonePayload
        // );

        assert(success);
        // assert(success3);

        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = redstoneOracle.latestRoundData();

        console.logInt(answer);
        console.logUint(oracleValue);
        console.logBytes(dataa);

        // assertEq(roundId, 1);
        assertEq(uint256(answer), updatePrice);
        // // assertEq(startedAt, timestampMilliseconds);
        // // assertEq(updatedAt, timestampMilliseconds);
        // assertEq(answeredInRound, 1);
    }

    function getAuthorisedSignerIndex(
        address signerAddress
    ) public view virtual override returns (uint8) {
        if (signerAddress == 0x8BB8F32Df04c8b654987DAaeD53D6B6091e3B774) {
            return 0;
        } else if (
            signerAddress == 0xdEB22f54738d54976C4c0fe5ce6d408E40d88499
        ) {
            return 1;
        } else if (
            signerAddress == 0x51Ce04Be4b3E32572C4Ec9135221d0691Ba7d202
        ) {
            return 2;
        } else if (
            signerAddress == 0xDD682daEC5A90dD295d14DA4b0bec9281017b5bE
        ) {
            return 3;
        } else if (
            signerAddress == 0x9c5AE89C4Af6aA32cE58588DBaF90d18a855B6de
        ) {
            return 4;
        } else {
            revert SignerNotAuthorised(signerAddress);
        }
    }
}
