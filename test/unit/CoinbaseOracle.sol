// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {CommonTest} from "../Common.sol";

import {BaseController} from "../../src/controllers/BaseController.sol";
import {CoinbaseOracleSourceAdapter} from "../../src/adapters/source-adapters/CoinbaseOracleSourceAdapter.sol";
import {DecimalLib} from "../../src/adapters/lib/DecimalLib.sol";
import {IAggregatorV3Source} from "../../src/interfaces/chainlink/IAggregatorV3Source.sol";
import {CoinbaseOracle} from "../../src/oracles/CoinbaseOracle.sol";

contract CoinbaseSourceAdapterTest is CommonTest {
    CoinbaseOracle coinbaseOracle;

    address public reporter;
    uint256 public reporterPk;

    function setUp() public {
        (address _reporter, uint256 _reporterPk) = makeAddrAndKey("reporter");
        reporter = _reporter;
        reporterPk = _reporterPk;
        coinbaseOracle = new CoinbaseOracle("ETH", 6, reporter);
    }

    function testPushPrice() public {
        string memory kind = "price";
        uint256 timestamp = block.timestamp;
        string memory ticker = "ETH";
        uint256 price = 10e6;

        bytes memory encodedData = abi.encode(kind, timestamp, ticker, price);

        bytes32 hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(encodedData)));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(reporterPk, hash);

        bytes memory signature = abi.encode(r, s, v);

        coinbaseOracle.pushPrice(encodedData, signature);

        (, int256 answer, uint256 updatedAt,,) = coinbaseOracle.latestRoundData();

        assertEq(uint256(answer), price);
        assertEq(updatedAt, timestamp);
    }
}
