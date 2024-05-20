// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {CommonTest} from "../Common.sol";

import {BaseController} from "../../src/controllers/BaseController.sol";
import {CoinbaseSourceAdapter} from "../../src/adapters/source-adapters/CoinbaseSourceAdapter.sol";
import {DecimalLib} from "../../src/adapters/lib/DecimalLib.sol";
import {IAggregatorV3SourceCoinbase} from "../../src/interfaces/coinbase/IAggregatorV3SourceCoinbase.sol";
import {CoinbaseOracle} from "../../src/oracles/CoinbaseOracle.sol";

contract TestedSourceAdapter is CoinbaseSourceAdapter {
    constructor(IAggregatorV3SourceCoinbase source, string memory ticker) CoinbaseSourceAdapter(source, ticker) {}

    function internalLatestData() public view override returns (int256, uint256, uint256) {}

    function canUnlock(address caller, uint256 cachedLatestTimestamp) public view virtual override returns (bool) {}

    function lockWindow() public view virtual override returns (uint256) {}

    function maxTraversal() public view virtual override returns (uint256) {}

    function internalDataAtRound(uint256 roundId) public view override returns (int256, uint256) {}
}

contract CoinbaseSourceAdapterTest is CommonTest {
    CoinbaseOracle coinbase;
    TestedSourceAdapter sourceAdapter;

    address public reporter;
    uint256 public reporterPk;

    string public ticker = "ETH";
    uint256 public price = 3000e6;

    function pushPrice(string memory ticker, uint256 priceToPush, uint256 timestamp) public {
        string memory kind = "price";

        bytes memory encodedData = abi.encode(kind, timestamp, ticker, priceToPush);

        bytes32 hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(encodedData)));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(reporterPk, hash);

        bytes memory signature = abi.encode(r, s, v);

        coinbase.pushPrice(encodedData, signature);
    }

    function scaleCoinbaseTo18(int256 input) public pure returns (int256) {
        return (input * 10 ** 18) / 10 ** 6;
    }

    function setUp() public {
        (address _reporter, uint256 _reporterPk) = makeAddrAndKey("reporter");
        reporter = _reporter;
        reporterPk = _reporterPk;
        coinbase = new CoinbaseOracle(6, reporter);
        sourceAdapter = new TestedSourceAdapter(IAggregatorV3SourceCoinbase(address(coinbase)), ticker);

        // Push some prices to the oracle
        vm.warp(100000000);
        pushPrice(ticker, price, block.timestamp);
        vm.warp(block.timestamp + 1 hours);
        pushPrice(ticker, price - 500, block.timestamp);
        vm.warp(block.timestamp + 1 hours);
        pushPrice(ticker, price - 1000, block.timestamp);
        vm.warp(block.timestamp + 1 hours);
        pushPrice(ticker, price - 1500, block.timestamp);
    }

    function testCorrectlyStandardizesOutputs() public {
        (, int256 latestCoinbasePrice,, uint256 latestCoinbaseTimestamp,) = coinbase.latestRoundData(ticker);
        (int256 latestSourceAnswer, uint256 latestSourceTimestamp) = sourceAdapter.getLatestSourceData();

        assertTrue(scaleCoinbaseTo18(latestCoinbasePrice) == latestSourceAnswer);
        assertTrue(latestSourceTimestamp == latestCoinbaseTimestamp);
    }

    function testCorrectlyLooksBackThroughRounds() public {
        (uint80 latestRound, int256 latestAnswer,, uint256 latestUpdatedAt,) = coinbase.latestRoundData(ticker);
        assertTrue(uint256(latestAnswer) == price - 1500);

        uint256 targetTime = block.timestamp - 1 hours;
        (int256 lookBackPrice, uint256 lookBackTimestamp,) = sourceAdapter.tryLatestDataAt(targetTime, 10);
        (, int256 answer, uint256 startedAt,,) = coinbase.getRoundData(ticker, latestRound - 1);
        assertTrue(startedAt <= targetTime); // The time from the chainlink source is at least 1 hours old.
        assertTrue(scaleCoinbaseTo18(answer) == lookBackPrice);
        assertTrue(uint256(answer) == (price - 1000));
        assertTrue(startedAt == lookBackTimestamp);

        // Next, try looking back 2 hours. Equally, we should get the price from 2 rounds ago.
        targetTime = block.timestamp - 2 hours;
        (lookBackPrice, lookBackTimestamp,) = sourceAdapter.tryLatestDataAt(targetTime, 10);
        (, answer, startedAt,,) = coinbase.getRoundData(ticker, latestRound - 2);
        assertTrue(startedAt <= targetTime); // The time from the chainlink source is at least 2 hours old.
        assertTrue(scaleCoinbaseTo18(answer) == lookBackPrice);
        assertTrue(uint256(answer) == (price - 500));
        assertTrue(startedAt == lookBackTimestamp);

        // Now, try 4 hours old, this time we don't have data from 4 hours ago, so we should get the latest data available.
        targetTime = block.timestamp - 4 hours;
        (lookBackPrice, lookBackTimestamp,) = sourceAdapter.tryLatestDataAt(targetTime, 10);

        assertTrue(scaleCoinbaseTo18(latestAnswer) == lookBackPrice);
        assertTrue(latestUpdatedAt == lookBackTimestamp);
    }

    function testCorrectlyBoundsMaxLookBack() public {
        // If we limit how far we can lookback the source should correctly return the oldest data it can find, up to
        // that limit. From the previous tests we showed that looking back 2 hours should return the price from round 2.
        // If we try look back longer than this we should get the price from round 2, no matter how far we look back.
        uint256 targetTime = block.timestamp - 2 hours;
        (int256 lookBackPrice, uint256 lookBackTimestamp,) = sourceAdapter.tryLatestDataAt(targetTime, 2);
        (uint80 latestRound,,,,) = coinbase.latestRoundData(ticker);
        (, int256 answer, uint256 startedAt,,) = coinbase.getRoundData(ticker, latestRound - 2);

        assertTrue(scaleCoinbaseTo18(answer) == lookBackPrice);
        assertTrue(startedAt == lookBackTimestamp);

        // Now, lookback longer than 2 hours. should get the same value as before.
        targetTime = block.timestamp - 3 hours;
        (lookBackPrice, lookBackTimestamp,) = sourceAdapter.tryLatestDataAt(targetTime, 2);
        assertTrue(scaleCoinbaseTo18(answer) == lookBackPrice);
        assertTrue(startedAt == lookBackTimestamp);
        targetTime = block.timestamp - 10 hours;
        (lookBackPrice, lookBackTimestamp,) = sourceAdapter.tryLatestDataAt(targetTime, 2);
        assertTrue(scaleCoinbaseTo18(answer) == lookBackPrice);
        assertTrue(startedAt == lookBackTimestamp);
    }

    function testNonHistoricalData() public {
        coinbase = new CoinbaseOracle(6, reporter);
        sourceAdapter = new TestedSourceAdapter(IAggregatorV3SourceCoinbase(address(coinbase)), ticker);

        // Push only one price to the oracle
        vm.warp(100000000);
        pushPrice(ticker, price, block.timestamp);

        uint256 targetTime = block.timestamp - 1 hours;

        (, int256 answer,, uint256 updatedAt,) = coinbase.latestRoundData(ticker);

        (int256 lookBackPrice, uint256 lookBackTimestamp,) = sourceAdapter.tryLatestDataAt(targetTime, 0);
        assertEq(lookBackPrice, scaleCoinbaseTo18(answer));
        assertEq(lookBackTimestamp, updatedAt);
    }
}
