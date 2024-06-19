// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {CommonTest} from "../Common.sol";
import {MockSnapshotSourceAdapter} from "../mocks/MockSnapshotSourceAdapter.sol";
import {Oval} from "../../src/Oval.sol";
import {BaseController} from "../../src/controllers/BaseController.sol";
import {SnapshotSourceLib} from "../../src/adapters/lib/SnapshotSourceLib.sol";

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
        snapshotSource.mockSnapshots(0);

        // latestSnapshotData should return uninitialized data.
        SnapshotSourceLib.Snapshot memory snapshot = snapshotSource.latestSnapshotData();
        assertTrue(snapshot.answer == 0 && snapshot.timestamp == 0);
    }

    function testSnapshotValidSource() public {
        // Publish and snapshot source data.
        snapshotSource.publishSourceData(100, 1000);
        snapshotSource.snapshotData();

        // Verify snapshotted data.
        SnapshotSourceLib.Snapshot memory snapshot = snapshotSource.latestSnapshotData();
        assertTrue(snapshot.answer == 100 && snapshot.timestamp == 1000);
    }

    function testSnapshotLatestSource() public {
        // Publish multiple source updates and snapshot the latest.
        snapshotSource.publishSourceData(100, 1000);
        snapshotSource.publishSourceData(200, 2000);
        snapshotSource.snapshotData();

        // Verify the latest data got snapshotted.
        SnapshotSourceLib.Snapshot memory snapshot = snapshotSource.latestSnapshotData();
        assertTrue(snapshot.answer == 200 && snapshot.timestamp == 2000);
    }

    function testDoesNotSnapshotSameSourceTwice() public {
        // Publish and snapshot source data.
        snapshotSource.publishSourceData(100, 1000);
        snapshotSource.snapshotData();

        // Verify snapshotted data.
        SnapshotSourceLib.Snapshot memory snapshot = snapshotSource.latestSnapshotData();
        assertTrue(snapshot.answer == 100 && snapshot.timestamp == 1000);

        // The first snapshots element should match the latest snapshot data.
        (int256 snapshotAnswer, uint256 snapshotTimestamp) = snapshotSource.mockSnapshots(0);
        assertTrue(snapshotAnswer == 100 && snapshotTimestamp == 1000);

        // Publish and snapshot the same source data again.
        snapshotSource.publishSourceData(100, 1000);
        snapshotSource.snapshotData();

        // Verify that the snapshotting did not store any new data (snapshots array still holds one element).
        vm.expectRevert();
        snapshotSource.mockSnapshots(1);

        // latestSnapshotData should return the same data.
        snapshot = snapshotSource.latestSnapshotData();
        assertTrue(snapshot.answer == 100 && snapshot.timestamp == 1000);
    }

    function testMaxAgeIsRespected() public {
        // Set maxAge to 2000 for testing
        vm.warp(10000);
        snapshotSource.setMaxAge(2000);

        // Publish data at different timestamps
        vm.warp(11000);
        snapshotSource.publishSourceData(100, 11000);
        snapshotSource.snapshotData();

        vm.warp(12000);
        snapshotSource.publishSourceData(200, 12000);
        snapshotSource.snapshotData();

        vm.warp(13000);
        snapshotSource.publishSourceData(300, 13000);
        snapshotSource.snapshotData();

        vm.warp(14000);
        snapshotSource.publishSourceData(400, 14000);
        snapshotSource.snapshotData();

        // Verify behavior when requesting data within the maxAge limit
        (int256 answerAt14000, uint256 timestampAt14000,) = snapshotSource.tryLatestDataAt(14000, 10);
        assertTrue(answerAt14000 == 400 && timestampAt14000 == 14000);

        (int256 answerAt13000, uint256 timestampAt13000,) = snapshotSource.tryLatestDataAt(13000, 10);
        assertTrue(answerAt13000 == 300 && timestampAt13000 == 13000);

        // Request data at the limit of maxAge should still work.
        (int256 answerAt12000, uint256 timestampAt12000,) = snapshotSource.tryLatestDataAt(12000, 10);
        assertTrue(answerAt12000 == 200 && timestampAt12000 == 12000);

        // Request data older than maxAge (1000), should get the latest available data at 14000.
        (int256 answerAt11000, uint256 timestampAt11000,) = snapshotSource.tryLatestDataAt(11000, 10);
        assertTrue(answerAt11000 == 400 && timestampAt11000 == 14000);
    }
}
