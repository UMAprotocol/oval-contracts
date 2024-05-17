// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {CommonTest} from "../Common.sol";
import {BaseController} from "../../src/controllers/BaseController.sol";
import {CoinbaseSourceAdapter} from "../../src/adapters/source-adapters/CoinbaseSourceAdapter.sol";
import {DecimalLib} from "../../src/adapters/lib/DecimalLib.sol";
import {IAggregatorV3SourceCoinbase} from "../../src/interfaces/coinbase/IAggregatorV3SourceCoinbase.sol";
import {CoinbaseOracle} from "../../src/oracles/CoinbaseOracle.sol";

contract CoinbaseSourceAdapterTest is CommonTest {
    CoinbaseOracle coinbaseOracle;

    address public reporter;
    uint256 public reporterPk;
    string public constant ethTicker = "ETH";
    string public constant btcTicker = "BTC";

    function setUp() public {
        (address _reporter, uint256 _reporterPk) = makeAddrAndKey("reporter");
        reporter = _reporter;
        reporterPk = _reporterPk;
        coinbaseOracle = new CoinbaseOracle(6, reporter);
    }

    function testPushPriceETH() public {
        _testPushPrice(ethTicker, 10e6);
    }

    function testPushPriceBTC() public {
        _testPushPrice(btcTicker, 20e6);
    }

    function testPushPriceBothTickers() public {
        _testPushPrice(ethTicker, 10e6);
        vm.warp(block.timestamp + 1);
        _testPushPrice(btcTicker, 20e6);
    }

    function _testPushPrice(string memory ticker, uint256 price) internal {
        string memory kind = "price";
        uint256 timestamp = block.timestamp;

        bytes memory encodedData = abi.encode(kind, timestamp, ticker, price);

        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(encodedData)
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(reporterPk, hash);

        bytes memory signature = abi.encode(r, s, v);

        coinbaseOracle.pushPrice(encodedData, signature);

        (, int256 answer, uint256 updatedAt, , ) = coinbaseOracle
            .latestRoundData(ticker);

        assertEq(uint256(answer), price);
        assertEq(updatedAt, timestamp);
    }
}
