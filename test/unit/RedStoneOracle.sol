// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
// import {RedstoneConsumerNumericBase} from "@redstone-finance/evm-connector/contracts/core/RedstoneConsumerNumericBase.sol";

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
        args[1] = "./test/unit/getRedstonePayload.js";
        args[2] = priceFeed;

        return vm.ffi(args);
    }
}

contract RedstoneOracleAdapterTest is CommonTest, MockRedstonePayload {
    RedstonePriceFeedWithRounds redstoneOracle;

    function setUp() public {
        redstoneOracle = new RedstonePriceFeedWithRounds(bytes32("BTC"));
    }

    function testPushPrice() public {

        bytes memory redstonePayload = getRedstonePayload("BTC:120:8");



        // redstoneOracle.updateDataFeedsValues();
    }
}
