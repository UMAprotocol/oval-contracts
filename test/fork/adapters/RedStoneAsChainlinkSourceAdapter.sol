// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

// These tests show that we can treat redstone exactly as chainlink and use it within the Oval ecosystem without the
// need for a new adapter. This assumes the use of Redstone Classic.

import {CommonTest} from "../../Common.sol";
import {BaseController} from "../../../src/controllers/BaseController.sol";

import {DecimalLib} from "../../../src/adapters/lib/DecimalLib.sol";
import {ChainlinkSourceAdapter} from "../../../src/adapters/source-adapters/ChainlinkSourceAdapter.sol";

import {IAggregatorV3Source} from "../../../src/interfaces/chainlink/IAggregatorV3Source.sol";
import {MergedPriceFeedAdapterWithRounds} from
    "redstone-oracles-monorepo/packages/on-chain-relayer/contracts/price-feeds/with-rounds/MergedPriceFeedAdapterWithRounds.sol";

contract TestedSourceAdapter is ChainlinkSourceAdapter {
    constructor(IAggregatorV3Source source) ChainlinkSourceAdapter(source) {}

    function internalLatestData() public view override returns (int256, uint256, uint256) {}

    function internalDataAtRound(uint256 roundId) public view override returns (int256, uint256) {}

    function canUnlock(address caller, uint256 cachedLatestTimestamp) public view virtual override returns (bool) {}

    function lockWindow() public view virtual override returns (uint256) {}

    function maxTraversal() public view virtual override returns (uint256) {}
}

contract RedstoneAsChainlinkSourceAdapterTest is CommonTest {
    uint256 targetBlock = 19889008;

    MergedPriceFeedAdapterWithRounds redstone;
    TestedSourceAdapter sourceAdapter;

    function setUp() public {
        vm.createSelectFork("mainnet", targetBlock);
        redstone = MergedPriceFeedAdapterWithRounds(0xdDb6F90fFb4d3257dd666b69178e5B3c5Bf41136); // Redstone weETH
        sourceAdapter = new TestedSourceAdapter(IAggregatorV3Source(address(redstone)));
    }

    function testCorrectlyStandardizesOutputs() public {
        (, int256 latestRedstoneAnswer,, uint256 latestRedstoneTimestamp,) = redstone.latestRoundData();
        (int256 latestSourceAnswer, uint256 latestSourceTimestamp) = sourceAdapter.getLatestSourceData();
        assertTrue(scaleRedstoneTo18(latestRedstoneAnswer) == latestSourceAnswer);
        assertTrue(latestSourceTimestamp == latestRedstoneTimestamp);
    }

    function testCanApplyRedstoneUpdateToSource() public {
        (uint80 roundId, int256 latestAnswer, uint256 latestTimestamp,,) = redstone.latestRoundData();
        // Values read from the contract at block before applying the update.
        assertTrue(roundId == 2009);
        assertTrue(latestAnswer == 316882263951);
        assertTrue(latestTimestamp == 1715934227);
        applyKnownRedstoneUpdate();
        (roundId, latestAnswer, latestTimestamp,,) = redstone.latestRoundData();
        assertTrue(roundId == 2010);
        assertTrue(latestAnswer == 313659742144);
        assertTrue(latestTimestamp == block.timestamp);
    }

    function testCorrectlyLooksBackThroughRounds() public {
        // Try fetching the price from some periods in the past and make sure it returns the corespending value for
        // given historic lookback. By looking at the contract history on-chain around the blocknumber, we can see
        // how many rounds back we expect to look. Looking 1 hour back shows no updates were applied in that interval.
        // we should be able to query one hour ago and get the latest round data from both the redstone source and the
        // adapter.
        uint256 targetTime = block.timestamp - 1 hours;
        (uint80 latestRound,,,,) = redstone.latestRoundData();

        (int256 lookBackPrice, uint256 lookBackTimestamp, uint256 roundId) =
            sourceAdapter.tryLatestDataAt(targetTime, 10);
        (, int256 answer,, uint256 updatedAt,) = redstone.getRoundData(latestRound);
        assertTrue(roundId == latestRound);
        assertTrue(updatedAt <= targetTime);
        assertTrue(scaleRedstoneTo18(answer) == lookBackPrice);
        assertTrue(updatedAt == lookBackTimestamp);

        // Next, try looking back 2 hours. by looking on-chain we can see only one update was applied. Therefore we
        // should get the values from latestRound -1 (one update applied relative to the "latest" round).
        targetTime = block.timestamp - 2 hours;
        (lookBackPrice, lookBackTimestamp,) = sourceAdapter.tryLatestDataAt(targetTime, 10);
        (, answer,, updatedAt,) = redstone.getRoundData(latestRound - 1);
        assertTrue(updatedAt <= targetTime);
        assertTrue(scaleRedstoneTo18(answer) == lookBackPrice);
        assertTrue(updatedAt == lookBackTimestamp);

        // Next, try land at 2 rounds ago. Again, by looking on-chain, we can see this is ~2 23 mins before the current
        // fork timestamp. We should be able to show the value is the oldest value within this interval.
        targetTime = block.timestamp - 2 hours - 23 minutes;
        (lookBackPrice, lookBackTimestamp,) = sourceAdapter.tryLatestDataAt(targetTime, 10);
        (, answer,, updatedAt,) = redstone.getRoundData(latestRound - 2);
        assertTrue(updatedAt <= targetTime);
        assertTrue(scaleRedstoneTo18(answer) == lookBackPrice);
        assertTrue(updatedAt == lookBackTimestamp);

        // Now, try 3 hours old. On-chain there were 5 updates in this interval. we should be able to show the value is
        // the oldest value within this interval.
        targetTime = block.timestamp - 3 hours;
        (lookBackPrice, lookBackTimestamp,) = sourceAdapter.tryLatestDataAt(targetTime, 10);
        (, answer,, updatedAt,) = redstone.getRoundData(latestRound - 5);
        assertTrue(updatedAt <= targetTime);
        assertTrue(scaleRedstoneTo18(answer) == lookBackPrice);
        assertTrue(updatedAt == lookBackTimestamp);
    }

    function testCorrectlyBoundsMaxLookBack() public {
        // If we limit how far we can lookback the source should correctly return the oldest data it can find, up to
        // that limit. From the previous tests we showed that looking back 2 hours 23 hours returns the price from round
        // 2. If we try look back longer than this we should get the price from round 2, no matter how far we look back,
        // if we bound the maximum lookback to 2 rounds.
        uint256 targetTime = block.timestamp - 2 hours - 23 minutes;
        (int256 lookBackPrice, uint256 lookBackTimestamp,) = sourceAdapter.tryLatestDataAt(targetTime, 2);
        (uint80 latestRound,,,,) = redstone.latestRoundData();
        (, int256 answer,, uint256 updatedAt,) = redstone.getRoundData(latestRound - 2);
        assertTrue(scaleRedstoneTo18(answer) == lookBackPrice);
        assertTrue(updatedAt == lookBackTimestamp);

        // Now, lookback longer than 2 hours. should get the same value as before.
        targetTime = block.timestamp - 3 hours;
        (lookBackPrice, lookBackTimestamp,) = sourceAdapter.tryLatestDataAt(targetTime, 2);
        assertTrue(scaleRedstoneTo18(answer) == lookBackPrice);
        assertTrue(updatedAt == lookBackTimestamp);
        targetTime = block.timestamp - 10 hours;
        (lookBackPrice, lookBackTimestamp,) = sourceAdapter.tryLatestDataAt(targetTime, 2);
        assertTrue(scaleRedstoneTo18(answer) == lookBackPrice);
        assertTrue(updatedAt == lookBackTimestamp);
    }

    function testNonHistoricalData() public {
        uint256 targetTime = block.timestamp - 1 hours;

        (, int256 answer,, uint256 updatedAt,) = redstone.latestRoundData();

        (int256 lookBackPrice, uint256 lookBackTimestamp,) = sourceAdapter.tryLatestDataAt(targetTime, 0);
        assertEq(lookBackPrice / 10 ** 10, answer);
        assertEq(lookBackTimestamp, updatedAt);
    }

    function applyKnownRedstoneUpdate() internal {
        // Update payload taken from: https://etherscan.io/tx/0xbcde8a894337a7e1f29dcad1f78cb0246c1b29305b5c62e43cf0e1801acc11c9
        bytes memory updatePayload =
            hex"c14c92040000000000000000000000000000000000000000000000000000018f86086c107765455448000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000490793d7c0018f86086c1000000020000001f6c1ccae51e44aa9e5f57431f59cbd228c190ba072e1eb0af683fef58e02ac0b7f6432b819356ed51210945643f7362871371344395bf48df443663ee525dcef1c7765455448000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000490793d7c0018f86086c100000002000000180353e157cebadd3ba9a25140b95360e0deb02f23274d275301e53680c135c7c0033dcf794366503d9d500d9003842d03abe812bc9535b644e1b5f0cee72845f1c00023137313539343036363233373123302e332e3623646174612d7061636b616765732d77726170706572000029000002ed57011e0000";
        vm.prank(0x517a67D809549093bD3Ef7C6195546B8BDF24C04); // Permissioned Redstone updater.

        (bool success,) = address(redstone).call(updatePayload);
        require(success, "Failed to update Redstone data");
    }

    function scaleRedstoneTo18(int256 input) public pure returns (int256) {
        return (input * 10 ** 18) / 10 ** 8;
    }
}
