// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {CommonTest} from "../../Common.sol";

import {BaseController} from "../../../src/controllers/BaseController.sol";
import {ChainlinkSourceAdapter} from "../../../src/adapters/source-adapters/ChainlinkSourceAdapter.sol";
import {DecimalLib} from "../../../src/adapters/lib/DecimalLib.sol";
import {IAggregatorV3Source} from "../../../src/interfaces/chainlink/IAggregatorV3Source.sol";

contract TestedSourceAdapter is ChainlinkSourceAdapter {
    constructor(IAggregatorV3Source source) ChainlinkSourceAdapter(source) {}

    function internalLatestData() public view override returns (int256, uint256, uint256) {}

    function canUnlock(address caller, uint256 cachedLatestTimestamp) public view virtual override returns (bool) {}

    function lockWindow() public view virtual override returns (uint256) {}

    function maxTraversal() public view virtual override returns (uint256) {}
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

    function testCorrectlyLooksBackThroughRounds() public {
        // Try fetching the price an hour before. At the sample data block there was not a lot of price action and one
        // hour ago is simply the previous round (there was only one update in that interval due to chainlink heartbeat)
        uint256 targetTime = block.timestamp - 1 hours;
        (uint80 latestRound,,,,) = chainlink.latestRoundData();
        (int256 lookBackPrice, uint256 lookBackTimestamp,) = sourceAdapter.tryLatestDataAt(targetTime, 10);
        (, int256 answer, uint256 startedAt,,) = chainlink.getRoundData(latestRound - 1);
        assertTrue(startedAt <= targetTime); // The time from the chainlink source is at least 1 hours old.
        assertTrue(scaleChainlinkTo18(answer) == lookBackPrice);
        assertTrue(startedAt == lookBackTimestamp);

        // Next, try looking back 2 hours. Equally, we should get the price from 2 rounds ago.
        targetTime = block.timestamp - 2 hours;
        (lookBackPrice, lookBackTimestamp,) = sourceAdapter.tryLatestDataAt(targetTime, 10);
        (, answer, startedAt,,) = chainlink.getRoundData(latestRound - 2);
        assertTrue(startedAt <= targetTime); // The time from the chainlink source is at least 2 hours old.
        assertTrue(scaleChainlinkTo18(answer) == lookBackPrice);
        assertTrue(startedAt == lookBackTimestamp);

        // Now, try 3 hours old. again, The value should be at least 3 hours old. However, for this lookback the chainlink
        // souce was updated 2x in the interval. Therefore, we should get the price from 4 rounds ago.
        targetTime = block.timestamp - 3 hours;
        (lookBackPrice, lookBackTimestamp,) = sourceAdapter.tryLatestDataAt(targetTime, 10);
        (, answer, startedAt,,) = chainlink.getRoundData(latestRound - 4);
        assertTrue(startedAt <= block.timestamp - 3 hours); // The time from the chainlink source is at least 3 hours old.
        assertTrue(startedAt > block.timestamp - 4 hours); // Time from chainlink source is at not more than 4 hours.
    }

    function testCorrectlyBoundsMaxLookBack() public {
        // If we limit how far we can lookback the source should correctly return the oldest data it can find, up to
        // that limit. From the previous tests we showed that looking back 2 hours should return the price from round 2.
        // If we try look back longer than this we should get the price from round 2, no matter how far we look back.
        uint256 targetTime = block.timestamp - 2 hours;
        (int256 lookBackPrice, uint256 lookBackTimestamp,) = sourceAdapter.tryLatestDataAt(targetTime, 2);
        (uint80 latestRound,,,,) = chainlink.latestRoundData();
        (, int256 answer, uint256 startedAt,,) = chainlink.getRoundData(latestRound - 2);
        assertTrue(scaleChainlinkTo18(answer) == lookBackPrice);
        assertTrue(startedAt == lookBackTimestamp);

        // Now, lookback longer than 2 hours. should get the same value as before.
        targetTime = block.timestamp - 3 hours;
        (lookBackPrice, lookBackTimestamp,) = sourceAdapter.tryLatestDataAt(targetTime, 2);
        assertTrue(scaleChainlinkTo18(answer) == lookBackPrice);
        assertTrue(startedAt == lookBackTimestamp);
        targetTime = block.timestamp - 10 hours;
        (lookBackPrice, lookBackTimestamp,) = sourceAdapter.tryLatestDataAt(targetTime, 2);
        assertTrue(scaleChainlinkTo18(answer) == lookBackPrice);
        assertTrue(startedAt == lookBackTimestamp);
    }

    function testNonHistoricalData() public {
        uint256 targetTime = block.timestamp - 1 hours;

        (, int256 answer,, uint256 updatedAt,) = chainlink.latestRoundData();

        (int256 lookBackPrice, uint256 lookBackTimestamp,) = sourceAdapter.tryLatestDataAt(targetTime, 0);
        assertEq(lookBackPrice / 10 ** 10, answer);
        assertEq(lookBackTimestamp, updatedAt);
    }

    function testMismatchedRoundId() public {
        sourceAdapter.snapshotData();
        (uint80 latestRound,,,,) = chainlink.latestRoundData();
        vm.mockCall(
            address(chainlink),
            abi.encodeWithSelector(chainlink.getRoundData.selector, latestRound - 1),
            abi.encode(latestRound, 1000, block.timestamp - 5 days, block.timestamp, latestRound)
        );

        (int256 resultPrice, uint256 resultTimestamp,) = sourceAdapter.tryLatestDataAt(block.timestamp - 2 hours, 10);

        (, int256 latestAnswer,, uint256 latestUpdatedAt,) = chainlink.latestRoundData();

        // Check if the return value matches the latest round data, given the fallback logic in _tryLatestRoundDataAt
        assertTrue(resultPrice == DecimalLib.convertDecimals(latestAnswer, 8, 18));
        assertTrue(resultTimestamp == latestUpdatedAt);
    }

    function scaleChainlinkTo18(int256 input) public pure returns (int256) {
        return (input * 10 ** 18) / 10 ** 8;
    }
}
