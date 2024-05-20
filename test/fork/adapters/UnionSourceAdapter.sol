// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {CommonTest} from "../../Common.sol";

import {BaseController} from "../../../src/controllers/BaseController.sol";
import {UnionSourceAdapter} from "../../../src/adapters/source-adapters/UnionSourceAdapter.sol";
import {IAggregatorV3Source} from "../../../src/interfaces/chainlink/IAggregatorV3Source.sol";
import {IMedian} from "../../../src/interfaces/chronicle/IMedian.sol";
import {IPyth} from "../../../src/interfaces/pyth/IPyth.sol";
import {DecimalLib} from "../../../src/adapters/lib/DecimalLib.sol";

contract TestedSourceAdapter is UnionSourceAdapter, BaseController {
    constructor(IAggregatorV3Source chainlink, IMedian chronicle, IPyth pyth, bytes32 pythPriceId)
        UnionSourceAdapter(chainlink, chronicle, pyth, pythPriceId)
    {}
}

contract UnionSourceAdapterTest is CommonTest {
    struct OracleData {
        int256 answer;
        uint256 timestamp;
    }

    struct SourceData {
        OracleData chainlink;
        OracleData chronicle;
        OracleData pyth;
        OracleData union;
    }

    uint256 targetChainlinkBlock = 18141580; // Known block where Chainlink was the newest.
    uint256 targetChronicleBlock = 18153212; // Known block where Chronicle was the newest.
    uint256 targetPythBlock = 16125718; // Known block where Pyth was the newest.

    uint256 lastPythUpdateBlock = 16125741; // Known block where Pyth was last updated.

    IAggregatorV3Source chainlink = IAggregatorV3Source(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    IMedian chronicle = IMedian(0x64DE91F5A373Cd4c28de3600cB34C7C6cE410C85);
    IPyth pyth = IPyth(0x4305FB66699C3B2702D4d05CF36551390A4c69C6);
    bytes32 pythPriceId = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;

    TestedSourceAdapter sourceAdapter;

    function setUp() public {
        vm.createSelectFork("mainnet", targetChainlinkBlock);
        sourceAdapter = new TestedSourceAdapter(chainlink, chronicle, pyth, pythPriceId);
        vm.makePersistent(address(sourceAdapter));
    }

    function testGetLatestSourceDataChainlink() public {
        vm.createSelectFork("mainnet", targetChainlinkBlock + 1);
        _whitelistOnChronicle();

        // Latest answer should be the newest of the three sources. At this known block number chainlink was the newest.
        // We can verify this to be the case and ensure that the Union adapter returned this value.

        SourceData memory latest = _getLatestData();

        assertTrue(latest.union.answer == latest.chainlink.answer);
        assertTrue(latest.union.timestamp == latest.chainlink.timestamp);
        assertTrue(latest.union.answer != latest.chronicle.answer);
        assertTrue(latest.union.answer != latest.pyth.answer);
        assertTrue(latest.chainlink.timestamp > latest.chronicle.timestamp); // Verify chainlink was indeed the newest.
        assertTrue(latest.chainlink.timestamp > latest.pyth.timestamp);
    }

    function testGetLatestSourceDataChronicle() public {
        vm.createSelectFork("mainnet", targetChronicleBlock);
        _whitelistOnChronicle();

        // Latest answer should be the newest of the three sources. At this known block number chronicle was the newest.
        // We can verify this to be the case and ensure that the Union adapter returned this value.

        SourceData memory latest = _getLatestData();

        assertTrue(latest.union.answer == latest.chronicle.answer);
        assertTrue(latest.union.timestamp == latest.chronicle.timestamp);
        assertTrue(latest.union.answer != latest.chainlink.answer);
        assertTrue(latest.union.answer != latest.pyth.answer);
        assertTrue(latest.chronicle.timestamp > latest.chainlink.timestamp); // Verify chronicle was indeed the newest.
        assertTrue(latest.chronicle.timestamp > latest.pyth.timestamp);
    }

    function testGetLatestSourceDataPyth() public {
        vm.createSelectFork("mainnet", targetPythBlock);
        _whitelistOnChronicle();

        // Latest answer should be the newest of the three sources. At this known block number pyth was the newest.
        // We can verify this to be the case and ensure that the Union adapter returned this value.

        SourceData memory latest = _getLatestData();

        assertTrue(latest.union.answer == latest.pyth.answer);
        assertTrue(latest.union.timestamp == latest.pyth.timestamp);
        assertTrue(latest.union.answer != latest.chainlink.answer);
        assertTrue(latest.union.answer != latest.chronicle.answer);
        assertTrue(latest.pyth.timestamp > latest.chainlink.timestamp); // Verify pyth was indeed the newest.
        assertTrue(latest.pyth.timestamp > latest.chronicle.timestamp);
    }

    function testLookbackChainlink() public {
        vm.createSelectFork("mainnet", targetChainlinkBlock + 1);
        uint256 targetTimestamp = block.timestamp;
        _whitelistOnChronicle();

        // Snapshotting union adapter should not affect historical lookups, but we do it just to prove it does not interfere.
        sourceAdapter.snapshotData();

        // Grab the latest data as of target block and check that chainlink was the newest.
        SourceData memory historic = _getLatestData();
        assertTrue(historic.chainlink.timestamp > historic.chronicle.timestamp);
        assertTrue(historic.chainlink.timestamp > historic.pyth.timestamp);

        // Move ~1 minute forward for the lookback test.
        vm.createSelectFork("mainnet", targetChainlinkBlock + 5);
        _whitelistOnChronicle();

        // We don't expect any of sources updated in the last minute.
        SourceData memory latest = _getLatestData();
        assertTrue(latest.chainlink.timestamp == historic.chainlink.timestamp);
        assertTrue(latest.chronicle.timestamp == historic.chronicle.timestamp);
        assertTrue(latest.pyth.timestamp == historic.pyth.timestamp);

        // As no sources had updated we still expect historic union to match chainlink.
        (int256 lookbackUnionAnswer, uint256 lookbackUnionTimestamp, uint256 lookBackRoundId) =
            sourceAdapter.tryLatestDataAt(targetTimestamp, 10);
        assertTrue(lookbackUnionAnswer == historic.chainlink.answer);
        assertTrue(lookbackUnionTimestamp == historic.chainlink.timestamp);
        assertTrue(lookBackRoundId == 1); // roundId not supported, hardcoded to 1.
    }

    function testLookbackChronicle() public {
        // Fork to a block where chronicle was the newest.
        vm.createSelectFork("mainnet", targetChronicleBlock);
        uint256 targetTimestamp = block.timestamp;
        _whitelistOnChronicle();

        // Snapshotting union adapter should not affect historical lookups, but we do it just to prove it does not interfere.
        sourceAdapter.snapshotData();

        // Grab the latest data as of target block and check that chronicle was the newest.
        SourceData memory historic = _getLatestData();
        assertTrue(historic.chronicle.timestamp > historic.chainlink.timestamp);
        assertTrue(historic.chronicle.timestamp > historic.pyth.timestamp);

        // Move ~1 minute forward for the lookback test.
        vm.createSelectFork("mainnet", targetChronicleBlock + 5);
        _whitelistOnChronicle();

        // We don't expect any of sources updated in the last minute.
        SourceData memory latest = _getLatestData();
        assertTrue(latest.chainlink.timestamp == historic.chainlink.timestamp);
        assertTrue(latest.chronicle.timestamp == historic.chronicle.timestamp);
        assertTrue(latest.pyth.timestamp == historic.pyth.timestamp);

        // As no sources had updated we still expect historic union to match chronicle.
        (int256 lookbackUnionAnswer, uint256 lookbackUnionTimestamp, uint256 lookBackRoundId) =
            sourceAdapter.tryLatestDataAt(targetTimestamp, 10);
        assertTrue(lookbackUnionAnswer == historic.chronicle.answer);
        assertTrue(lookbackUnionTimestamp == historic.chronicle.timestamp);
        assertTrue(lookBackRoundId == 1); // roundId not supported, hardcoded to 1.
    }

    function testLookbackDropChronicle() public {
        // Fork to a block where chronicle was the newest.
        vm.createSelectFork("mainnet", targetChronicleBlock);
        uint256 targetTimestamp = block.timestamp;
        sourceAdapter.setMaxAge(2 days); // Set max age to 2 days to disable this logic for the test.
        _whitelistOnChronicle();

        // Snapshotting union adapter should not affect historical lookups, but we do it just to prove it does not interfere.
        sourceAdapter.snapshotData();

        // Grab the latest data as of target block and check that chronicle was the newest.
        SourceData memory historic = _getLatestData();
        assertTrue(historic.chronicle.timestamp > historic.chainlink.timestamp);
        assertTrue(historic.chronicle.timestamp > historic.pyth.timestamp);

        // Move ~24 hours forward for the lookback test.
        vm.createSelectFork("mainnet", targetChronicleBlock + 7200);
        _whitelistOnChronicle();

        // Chronicle should have updated in the meantime.
        SourceData memory latest = _getLatestData();
        assertTrue(latest.chronicle.timestamp > historic.chronicle.timestamp);

        // We cannot lookback to the historic timestamp as chronicle does not support historical lookups.
        // So we expect union lookback to fallback to chainlink.
        (int256 lookbackUnionAnswer, uint256 lookbackUnionTimestamp, uint256 lookBackRoundId) =
            sourceAdapter.tryLatestDataAt(targetTimestamp, 100);
        assertTrue(lookbackUnionAnswer == historic.chainlink.answer);
        assertTrue(lookbackUnionTimestamp == historic.chainlink.timestamp);
        assertTrue(lookBackRoundId == 1); // roundId not supported, hardcoded to 1.
    }

    function testLookbackPyth() public {
        // Fork to a block where pyth was the newest.
        vm.createSelectFork("mainnet", targetPythBlock);
        uint256 targetTimestamp = block.timestamp;
        _whitelistOnChronicle();

        // Snapshotting union adapter should not affect historical lookups, but we do it just to prove it does not interfere.
        sourceAdapter.snapshotData();

        // Grab the latest data as of target block and check that pyth was the newest.
        SourceData memory historic = _getLatestData();
        assertTrue(historic.pyth.timestamp > historic.chainlink.timestamp);
        assertTrue(historic.pyth.timestamp > historic.chronicle.timestamp);

        // Move ~1 minute forward for the lookback test.
        vm.createSelectFork("mainnet", targetPythBlock + 5);
        _whitelistOnChronicle();

        // We don't expect any of sources updated in the last minute.
        SourceData memory latest = _getLatestData();
        assertTrue(latest.chainlink.timestamp == historic.chainlink.timestamp);
        assertTrue(latest.chronicle.timestamp == historic.chronicle.timestamp);
        assertTrue(latest.pyth.timestamp == historic.pyth.timestamp);

        // As no sources had updated we still expect historic union to match pyth.
        (int256 lookbackUnionAnswer, uint256 lookbackUnionTimestamp, uint256 lookBackRoundId) =
            sourceAdapter.tryLatestDataAt(targetTimestamp, 10);
        assertTrue(lookbackUnionAnswer == historic.pyth.answer);
        assertTrue(lookbackUnionTimestamp == historic.pyth.timestamp);
        assertTrue(lookBackRoundId == 1); // roundId not supported, hardcoded to 1.
    }

    function testLookbackDropPyth() public {
        // Fork to a block where pyth was the newest.
        vm.createSelectFork("mainnet", targetPythBlock);
        uint256 targetTimestamp = block.timestamp;
        _whitelistOnChronicle();

        // Snapshotting union adapter should not affect historical lookups, but we do it just to prove it does not interfere.
        sourceAdapter.snapshotData();

        // Grab the latest data as of target block and check that pyth was the newest.
        SourceData memory historic = _getLatestData();
        assertTrue(historic.pyth.timestamp > historic.chainlink.timestamp);
        assertTrue(historic.pyth.timestamp > historic.chronicle.timestamp);

        // Move forward after the last known pyth update for the lookback test.
        vm.createSelectFork("mainnet", lastPythUpdateBlock);
        _whitelistOnChronicle();

        // Pyth should have updated.
        SourceData memory latest = _getLatestData();
        assertTrue(latest.pyth.timestamp > historic.pyth.timestamp);

        // We cannot lookback to the historic timestamp as pyth does not support historical lookups.
        // So we expect union lookback to fallback to chainlink.
        (int256 lookbackUnionAnswer, uint256 lookbackUnionTimestamp, uint256 lookBackRoundId) =
            sourceAdapter.tryLatestDataAt(targetTimestamp, 100);
        assertTrue(lookbackUnionAnswer == historic.chainlink.answer);
        assertTrue(lookbackUnionTimestamp == historic.chainlink.timestamp);
        assertTrue(lookBackRoundId == 1); // roundId not supported, hardcoded to 1.
    }

    function _convertDecimalsWithExponent(int256 answer, int32 expo) internal pure returns (int256) {
        if (expo <= 0) {
            return DecimalLib.convertDecimals(answer, uint8(uint32(-expo)), 18);
        } else {
            return DecimalLib.convertDecimals(answer, 0, 18 + uint8(uint32(expo)));
        }
    }

    function _whitelistOnChronicle() internal {
        vm.startPrank(0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB); // DSPause that is a ward (can add kiss to chronicle)
        chronicle.kiss(address(sourceAdapter));
        chronicle.kiss(address(this)); // So that we can read Chronicle directly.
        vm.stopPrank();
    }

    function _getLatestData() internal view returns (SourceData memory) {
        SourceData memory latest;
        (, int256 latestAnswer,, uint256 latestTimestamp,) = chainlink.latestRoundData();
        latest.chainlink.answer = DecimalLib.convertDecimals(latestAnswer, 8, 18);
        latest.chainlink.timestamp = latestTimestamp;

        latest.chronicle.answer = int256(chronicle.read());
        latest.chronicle.timestamp = chronicle.age();

        IPyth.Price memory pythPrice = pyth.getPriceUnsafe(pythPriceId);
        latest.pyth.answer = _convertDecimalsWithExponent(pythPrice.price, pythPrice.expo);
        latest.pyth.timestamp = pythPrice.publishTime;

        (latest.union.answer, latest.union.timestamp) = sourceAdapter.getLatestSourceData();

        return latest;
    }
}
