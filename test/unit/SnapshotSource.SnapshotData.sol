// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {CommonTest} from "../Common.sol";
import {MockSnapshotSourceAdapter} from "../mocks/MockSnapshotSourceAdapter.sol";
import {OVAL} from "../../src/Oval.sol";
import {BaseController} from "../../src/controllers/BaseController.sol";

contract TestSnapshotSource is MockSnapshotSourceAdapter, OVAL, BaseController {}

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
}
