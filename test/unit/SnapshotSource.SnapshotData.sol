// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {CommonTest} from "../Common.sol";
import {MockSnapshotSourceAdapter} from "../mocks/MockSnapshotSourceAdapter.sol";
import {Oval} from "../../src/Oval.sol";
import {BaseController} from "../../src/controllers/BaseController.sol";
import "forge-std/console.sol";

contract TestSnapshotSource is MockSnapshotSourceAdapter, Oval, BaseController {}

contract SnapshotSourceSnapshotDataTest is CommonTest {
    TestSnapshotSource snapshotSource;

    function setUp() public {
        snapshotSource = new TestSnapshotSource();
    }

    function testDoesNotSnapshotInvalidSource() public {
        // We don't have any source data published, so the snapshotting should not store any data.
        snapshotSource.snapshotData();

        // Verify that the snapshotting did not store any data (snapshots array is empty).
        vm.expectRevert();
        snapshotSource.snapshots(0);

        // latestSnapshotData should return uninitialized data.
        MockSnapshotSourceAdapter.Snapshot memory snapshot = snapshotSource.latestSnapshotData();
        assertTrue(snapshot.answer == 0 && snapshot.timestamp == 0);
    }

    function testSnapshotValidSource() public {
        // Publish and snapshot source data.
        snapshotSource.publishSourceData(100, 1000);
        snapshotSource.snapshotData();

        // Verify snapshotted data.
        MockSnapshotSourceAdapter.Snapshot memory snapshot = snapshotSource.latestSnapshotData();
        assertTrue(snapshot.answer == 100 && snapshot.timestamp == 1000);
    }

    function testSnapshotLatestSource() public {
        // Publish multiple source updates and snapshot the latest.
        snapshotSource.publishSourceData(100, 1000);
        snapshotSource.publishSourceData(200, 2000);
        snapshotSource.snapshotData();

        // Verify the latest data got snapshotted.
        MockSnapshotSourceAdapter.Snapshot memory snapshot = snapshotSource.latestSnapshotData();
        assertTrue(snapshot.answer == 200 && snapshot.timestamp == 2000);
    }

    function testDoesNotSnapshotSameSourceTwice() public {
        // Publish and snapshot source data.
        snapshotSource.publishSourceData(100, 1000);
        snapshotSource.snapshotData();

        // Verify snapshotted data.
        MockSnapshotSourceAdapter.Snapshot memory snapshot = snapshotSource.latestSnapshotData();
        assertTrue(snapshot.answer == 100 && snapshot.timestamp == 1000);

        // The first snapshots element should match the latest snapshot data.
        (int256 snapshotAnswer, uint256 snapshotTimestamp) = snapshotSource.snapshots(0);
        assertTrue(snapshotAnswer == 100 && snapshotTimestamp == 1000);

        // Publish and snapshot the same source data again.
        snapshotSource.publishSourceData(100, 1000);
        snapshotSource.snapshotData();

        // Verify that the snapshotting did not store any new data (snapshots array still holds one element).
        vm.expectRevert();
        snapshotSource.snapshots(1);

        // latestSnapshotData should return the same data.
        snapshot = snapshotSource.latestSnapshotData();
        assertTrue(snapshot.answer == 100 && snapshot.timestamp == 1000);
    }

    function testMaxAgeIsRespected() public {
        // Set maxAge to 2000 for testing
        snapshotSource.setMaxAge(2000);

        // Publish data at different timestamps
        vm.warp(1000);
        snapshotSource.publishSourceData(100, 1000);
        snapshotSource.snapshotData();

        vm.warp(2000);
        snapshotSource.publishSourceData(200, 2000);
        snapshotSource.snapshotData();

        vm.warp(3000);
        snapshotSource.publishSourceData(300, 3000);
        snapshotSource.snapshotData();

        vm.warp(4000);
        snapshotSource.publishSourceData(400, 4000);
        snapshotSource.snapshotData();

        // Verify behavior when requesting data within the maxAge limit
        (int256 answerAt4000, uint256 timestampAt4000,) = snapshotSource.tryLatestDataAt(4000, 10);
        assertTrue(answerAt4000 == 400 && timestampAt4000 == 4000);

        (int256 answerAt3000, uint256 timestampAt3000,) = snapshotSource.tryLatestDataAt(3000, 10);
        assertTrue(answerAt3000 == 300 && timestampAt3000 == 3000);

        // Request data at the limit of maxAge should still work.
        (int256 answerAt2000, uint256 timestampAt2000,) = snapshotSource.tryLatestDataAt(2000, 10);
        assertTrue(answerAt2000 == 200 && timestampAt2000 == 2000);

        // Request data older than maxAge (1000), should get the latest available data at 4000.
        (int256 answerAt1000, uint256 timestampAt1000,) = snapshotSource.tryLatestDataAt(1000, 10);
        assertTrue(answerAt1000 == 400 && timestampAt1000 == 4000);
    }
}
