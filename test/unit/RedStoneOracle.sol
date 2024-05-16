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
    ) public view virtual override returns (uint8) {
        if (signerAddress == 0x71d00abE308806A3bF66cE05CF205186B0059503) {
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

    function testPushPrice() public {
        bytes memory data = getRedstonePayload("BTC:120:8");

        (
            bytes memory redstonePayload,
            uint256 timestampMilliseconds
        ) = abi.decode(data, (bytes, uint256));

        bytes32[] memory dataFeedIds = new bytes32[](1);
        dataFeedIds[0] = bytes32("BTC");

        // getOracleNumericValuesFromTxMsg()
        // uint256[] memory values = getOracleNumericValuesFromTxMsg(dataFeedIds);

        bytes memory encodedFunction = abi.encodeWithSignature(
            "updateDataFeedsValues(uint256)",
            timestampMilliseconds
        );
        bytes memory encodedFunctionWithRedstonePayload = abi.encodePacked(
            encodedFunction,
            redstonePayload
        );

        // // Securely getting oracle value
        (bool success, ) = address(redstoneOracle).call(
            encodedFunctionWithRedstonePayload
        );

        // redstoneOracle.updateDataFeedsValues();
    }
}
