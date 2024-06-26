// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {CommonTest} from "../../Common.sol";

import {BaseController} from "../../../src/controllers/BaseController.sol";
import {ChainlinkSourceAdapter} from "../../../src/adapters/source-adapters/ChainlinkSourceAdapter.sol";
import {DecimalLib} from "../../../src/adapters/lib/DecimalLib.sol";
import {IAggregatorV3Source} from "../../../src/interfaces/chainlink/IAggregatorV3Source.sol";

contract TestedSourceAdapter is ChainlinkSourceAdapter, BaseController {
    constructor(IAggregatorV3Source source) ChainlinkSourceAdapter(source) {}
}

contract ChainlinkSourceAdapterTest is CommonTest {
    uint256 targetBlock = 18141580;

    IAggregatorV3Source chainlink;
    TestedSourceAdapter sourceAdapter;

    function setUp() public {
        vm.createSelectFork("mainnet", targetBlock);
        chainlink = IAggregatorV3Source(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419); // Chainlink ETH/USD
        sourceAdapter = new TestedSourceAdapter(chainlink);
    }

    function testCorrectlyStandardizesOutputs() public {
        (, int256 latestChainlinkAnswer,, uint256 latestChainlinkTimestamp,) = chainlink.latestRoundData();
        (int256 latestSourceAnswer, uint256 latestSourceTimestamp) = sourceAdapter.getLatestSourceData();
        assertTrue(scaleChainlinkTo18(latestChainlinkAnswer) == latestSourceAnswer);
        assertTrue(latestSourceTimestamp == latestChainlinkTimestamp);
    }

    function testCorrectlyStandardizesRoundOutputs() public {
        (uint80 latestRound,,,,) = chainlink.latestRoundData();
        (, int256 chainlinkAnswer,, uint256 chainlinkTimestamp,) = chainlink.getRoundData(latestRound);
        (int256 sourceAnswer, uint256 sourceTimestamp) = sourceAdapter.getSourceDataAtRound(latestRound);
        assertTrue(scaleChainlinkTo18(chainlinkAnswer) == sourceAnswer);
        assertTrue(sourceTimestamp == chainlinkTimestamp);
    }

    function testCorrectlyLooksBackThroughRounds() public {
        // Try fetching the price an hour before. At the sample data block there was not a lot of price action and one
        // hour ago is simply the previous round (there was only one update in that interval due to chainlink heartbeat)
        uint256 targetTime = block.timestamp - 1 hours;
        (uint80 latestRound,,,,) = chainlink.latestRoundData();
        (int256 lookBackPrice, uint256 lookBackTimestamp, uint256 lookBackRoundId) =
            sourceAdapter.tryLatestDataAt(targetTime, 10);
        (uint80 roundId, int256 answer, uint256 startedAt,,) = chainlink.getRoundData(latestRound - 1);
        assertTrue(startedAt <= targetTime); // The time from the chainlink source is at least 1 hours old.
        assertTrue(scaleChainlinkTo18(answer) == lookBackPrice);
        assertTrue(startedAt == lookBackTimestamp);
        assertTrue(uint256(roundId) == lookBackRoundId);

        // Next, try looking back 2 hours. Equally, we should get the price from 2 rounds ago.
        targetTime = block.timestamp - 2 hours;
        (lookBackPrice, lookBackTimestamp, lookBackRoundId) = sourceAdapter.tryLatestDataAt(targetTime, 10);
        (roundId, answer, startedAt,,) = chainlink.getRoundData(latestRound - 2);
        assertTrue(startedAt <= targetTime); // The time from the chainlink source is at least 2 hours old.
        assertTrue(scaleChainlinkTo18(answer) == lookBackPrice);
        assertTrue(startedAt == lookBackTimestamp);
        assertTrue(uint256(roundId) == lookBackRoundId);

        // Now, try 3 hours old. again, The value should be at least 3 hours old. However, for this lookback the chainlink
        // souce was updated 2x in the interval. Therefore, we should get the price from 4 rounds ago.
        targetTime = block.timestamp - 3 hours;
        (lookBackPrice, lookBackTimestamp, lookBackRoundId) = sourceAdapter.tryLatestDataAt(targetTime, 10);
        (roundId, answer, startedAt,,) = chainlink.getRoundData(latestRound - 4);
        assertTrue(startedAt <= block.timestamp - 3 hours); // The time from the chainlink source is at least 3 hours old.
        assertTrue(startedAt > block.timestamp - 4 hours); // Time from chainlink source is at not more than 4 hours.
        assertTrue(uint256(roundId) == lookBackRoundId);
    }

    function testCorrectlyBoundsMaxLookBack() public {
        // If we limit how far we can lookback the source should correctly return the oldest data it can find, up to
        // that limit. From the previous tests we showed that looking back 2 hours should return the price from round 2.
        // If we try look back longer than this we should get the price from round 2, no matter how far we look back.
        uint256 targetTime = block.timestamp - 2 hours;
        (int256 lookBackPrice, uint256 lookBackTimestamp, uint256 lookBackRoundId) =
            sourceAdapter.tryLatestDataAt(targetTime, 2);
        (uint80 latestRound,,,,) = chainlink.latestRoundData();
        (uint80 roundId, int256 answer, uint256 startedAt,,) = chainlink.getRoundData(latestRound - 2);
        assertTrue(scaleChainlinkTo18(answer) == lookBackPrice);
        assertTrue(startedAt == lookBackTimestamp);
        assertTrue(uint256(roundId) == lookBackRoundId);

        // Now, lookback longer than 2 hours. should get the same value as before.
        targetTime = block.timestamp - 3 hours;
        (lookBackPrice, lookBackTimestamp, lookBackRoundId) = sourceAdapter.tryLatestDataAt(targetTime, 2);
        assertTrue(scaleChainlinkTo18(answer) == lookBackPrice);
        assertTrue(startedAt == lookBackTimestamp);
        assertTrue(uint256(roundId) == lookBackRoundId);
        targetTime = block.timestamp - 10 hours;
        (lookBackPrice, lookBackTimestamp, lookBackRoundId) = sourceAdapter.tryLatestDataAt(targetTime, 2);
        assertTrue(scaleChainlinkTo18(answer) == lookBackPrice);
        assertTrue(startedAt == lookBackTimestamp);
        assertTrue(uint256(roundId) == lookBackRoundId);
    }

    function testCorrectlyBoundsMaxLooBackByMaxAge() public {
        // Value returned at 2 days should be the same as the value returned at 1 day as the max age is 1 day.
        assertTrue(sourceAdapter.maxAge() == 1 days);
        (int256 lookBackPricePastWindow, uint256 lookBackTimestampPastWindow, uint256 lookBackRoundIdPastWindow) =
            sourceAdapter.tryLatestDataAt(block.timestamp - 2 days, 50);

        (int256 lookBackPriceAtLimit, uint256 lookBackTimestampAtLimit, uint256 lookBackRoundIdAtLimit) =
            sourceAdapter.tryLatestDataAt(block.timestamp - 1 days, 50);

        assertTrue(lookBackPricePastWindow == lookBackPriceAtLimit);
        assertTrue(lookBackTimestampPastWindow == lookBackTimestampAtLimit);
        assertTrue(lookBackRoundIdPastWindow == lookBackRoundIdAtLimit);
    }

    function testExtendingMaxAgeCorrectlyExtendsWindowOfReturnedValue() public {
        sourceAdapter.setMaxAge(2 days);
        (int256 lookBackPricePastWindow, uint256 lookBackTimestampPastWindow, uint256 lookBackRoundIdPastWindow) =
            sourceAdapter.tryLatestDataAt(block.timestamp - 3 days, 50);

        (int256 lookBackPriceAtLimit, uint256 lookBackTimestampAtLimit, uint256 lookBackRoundIdAtLimit) =
            sourceAdapter.tryLatestDataAt(block.timestamp - 2 days, 50);

        assertTrue(lookBackPricePastWindow == lookBackPriceAtLimit);
        assertTrue(lookBackTimestampPastWindow == lookBackTimestampAtLimit);
        assertTrue(lookBackRoundIdPastWindow == lookBackRoundIdAtLimit);
    }

    function testNonHistoricalData() public {
        uint256 targetTime = block.timestamp - 1 hours;

        (uint80 roundId, int256 answer,, uint256 updatedAt,) = chainlink.latestRoundData();

        (int256 lookBackPrice, uint256 lookBackTimestamp, uint256 lookBackRoundId) =
            sourceAdapter.tryLatestDataAt(targetTime, 0);
        assertEq(lookBackPrice / 10 ** 10, answer);
        assertEq(lookBackTimestamp, updatedAt);
        assertEq(uint256(roundId), lookBackRoundId);
    }

    function testMismatchedRoundId() public {
        sourceAdapter.snapshotData();
        (uint80 latestRound,,,,) = chainlink.latestRoundData();
        vm.mockCall(
            address(chainlink),
            abi.encodeWithSelector(chainlink.getRoundData.selector, latestRound - 1),
            abi.encode(latestRound, 1000, block.timestamp - 5 days, block.timestamp, latestRound)
        );

        (int256 resultPrice, uint256 resultTimestamp, uint256 lookBackRoundId) =
            sourceAdapter.tryLatestDataAt(block.timestamp - 2 hours, 10);

        (, int256 latestAnswer,, uint256 latestUpdatedAt,) = chainlink.latestRoundData();

        // Check if the return value matches the latest round data, given the fallback logic in _tryLatestRoundDataAt
        assertTrue(resultPrice == DecimalLib.convertDecimals(latestAnswer, 8, 18));
        assertTrue(resultTimestamp == latestUpdatedAt);
        assertTrue(uint256(latestRound) == lookBackRoundId);
    }

    function testNonExistentRoundData() public {
        (uint80 latestRound,,,,) = chainlink.latestRoundData();
        (int256 sourceAnswer, uint256 sourceTimestamp) = sourceAdapter.getSourceDataAtRound(latestRound + 1);
        assertTrue(sourceAnswer == 0);
        assertTrue(sourceTimestamp == 0);
    }

    function scaleChainlinkTo18(int256 input) public pure returns (int256) {
        return (input * 10 ** 18) / 10 ** 8;
    }
}
