// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {CommonTest} from "../../Common.sol";

import {BaseController} from "../../../src/controllers/BaseController.sol";
import {BoundedUnionSourceAdapter} from "../../../src/adapters/source-adapters/BoundedUnionSourceAdapter.sol";
import {IAggregatorV3Source} from "../../../src/interfaces/chainlink/IAggregatorV3Source.sol";
import {IMedian} from "../../../src/interfaces/chronicle/IMedian.sol";
import {IPyth} from "../../../src/interfaces/pyth/IPyth.sol";
import {MockPyth} from "../../mocks/MockPyth.sol";
import {MockChronicleMedianSource} from "../../mocks/MockChronicleMedianSource.sol";

contract TestedSourceAdapter is BoundedUnionSourceAdapter, BaseController {
    constructor(
        IAggregatorV3Source chainlink,
        IMedian chronicle,
        IPyth pyth,
        bytes32 pythPriceId,
        uint256 boundingTolerance
    ) BoundedUnionSourceAdapter(chainlink, chronicle, pyth, pythPriceId, boundingTolerance) {}
}

contract BoundedUnionSourceAdapterTest is CommonTest {
    uint256 targetBlock = 18419040;

    IAggregatorV3Source chainlink = IAggregatorV3Source(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    MockChronicleMedianSource chronicle;
    MockPyth pyth;
    bytes32 pythPriceId = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    uint256 boundingTolerance = 0.1e18;

    uint256 lockWindow = 60;
    uint256 maxTraversal = 10;

    TestedSourceAdapter sourceAdapter;

    function setUp() public {
        vm.createSelectFork("mainnet", targetBlock);
        chronicle = new MockChronicleMedianSource();
        pyth = new MockPyth();
        sourceAdapter = new TestedSourceAdapter(chainlink, chronicle, pyth, pythPriceId, boundingTolerance);
        vm.makePersistent(address(sourceAdapter));
    }

    function testLookbackDoesNotFlipBackward() public {
        // Set initial Pyth price 1% above current Chainlink price at current timestamp.
        (, int256 chainlinkPrice,, uint256 chainlinkTime,) = chainlink.latestRoundData();
        int64 pythPrice = int64(chainlinkPrice) * 101 / 100;
        pyth.setLatestPrice(pythPrice, 0, -8, block.timestamp);

        // Check that the locked price (lockWindow ago) is the same as the latest Chainlink price.
        (int256 lockedAnswer, uint256 lockedTimestamp, uint256 lockedRoundId) =
            sourceAdapter.tryLatestDataAt(block.timestamp - lockWindow, maxTraversal);
        int256 standardizedChainlinkAnswer = chainlinkPrice * 10 ** (18 - 8);
        assertTrue(lockedAnswer == standardizedChainlinkAnswer);
        assertTrue(lockedTimestamp == chainlinkTime);
        assertTrue(lockedRoundId == 1); // roundId not supported, hardcoded to 1.

        // Simulate unlock by snapshotting the current data and checking the price matches the latest Pyth price.
        sourceAdapter.snapshotData(); // In Oval this should get automatically called via unlockLatestValue.
        (int256 unlockedAnswer, uint256 unlockedTimestamp, uint256 unlockedRoundId) =
            sourceAdapter.tryLatestDataAt(block.timestamp, maxTraversal);
        int256 standardizedPythAnswer = int256(pythPrice) * 10 ** (18 - 8);
        assertTrue(unlockedAnswer == standardizedPythAnswer);
        assertTrue(unlockedTimestamp == block.timestamp);
        assertTrue(unlockedRoundId == 1); // roundId not supported, hardcoded to 1.

        // Update Pyth price by additional 1% after 10 minutes.
        skip(600);
        int64 nextPythPrice = pythPrice * 101 / 100;
        pyth.setLatestPrice(nextPythPrice, 0, -8, block.timestamp);

        // Check that the locked price (lockWindow ago) is the same as the prior Pyth price and not flipping back to the
        // old Chainlink price.
        (int256 nextLockedAnswer, uint256 nextLockedTimestamp, uint256 nextLockedRoundId) =
            sourceAdapter.tryLatestDataAt(block.timestamp - lockWindow, maxTraversal);
        assertTrue(nextLockedAnswer == standardizedPythAnswer);
        assertTrue(nextLockedTimestamp == unlockedTimestamp);
        assertTrue(nextLockedTimestamp > chainlinkTime);
        assertTrue(nextLockedRoundId == 1); // roundId not supported, hardcoded to 1.
    }
}
