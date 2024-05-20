// SPDX-License-Identifier: BUSL-1.1-only
pragma solidity 0.8.17;

import {IAggregatorV3Source} from "../../../src/interfaces/chainlink/IAggregatorV3Source.sol";
import {IMedian} from "../../../src/interfaces/chronicle/IMedian.sol";
import {IPyth} from "../../../src/interfaces/pyth/IPyth.sol";

import {BoundedUnionSourceAdapter} from "../../../src/adapters/source-adapters/BoundedUnionSourceAdapter.sol";
import {CommonTest} from "../../Common.sol";

contract TestBoundedUnionSource is BoundedUnionSourceAdapter {
    constructor(address chainlink)
        BoundedUnionSourceAdapter(
            IAggregatorV3Source(chainlink),
            IMedian(address(0)),
            IPyth(address(0)),
            bytes32(0),
            0.1e18 // boundingTolerance
        )
    {}

    function selectBoundedPrice(int256 cl, uint256 clT, int256 cr, uint256 crT, int256 py, uint256 pyT)
        public
        view
        returns (int256, uint256)
    {
        return _selectBoundedPrice(cl, clT, cr, crT, py, pyT);
    }

    function withinTolerance(int256 a, int256 b) public view returns (bool) {
        return _withinTolerance(a, b);
    }

    function internalLatestData() public view override returns (int256, uint256, uint256) {}

    function internalDataAtRound(uint256 roundId) public view override returns (int256, uint256) {}

    function canUnlock(address caller, uint256 cachedLatestTimestamp) public view virtual override returns (bool) {}

    function lockWindow() public view virtual override returns (uint256) {}
    function maxTraversal() public view virtual override returns (uint256) {}
}

contract MinimalChainlinkAdapter {
    function decimals() public view returns (uint8) {
        return 8;
    }
}

contract BoundedUnionSourceTest is CommonTest {
    TestBoundedUnionSource source;

    function setUp() public {
        source = new TestBoundedUnionSource(address(new MinimalChainlinkAdapter()));
    }

    // Fuzz test for _selectBoundedPrice function
    function ztestFuzzSelectBoundedPrice(int128 cl, uint128 clT, int128 cr, uint128 crT, int128 py, uint128 pyT)
        public
    {
        // Call the function with fuzzed inputs.
        (int256 selected, uint256 selectedT) = source.selectBoundedPrice(cl, clT, cr, crT, py, pyT);

        // Check if the selected price is the newest price.
        bool isMostRecent = (selected == py && selectedT == pyT && pyT >= crT && pyT >= clT)
            || (selected == cr && selectedT == crT && crT >= pyT && crT >= clT)
            || (selected == cl && selectedT == clT && clT >= pyT && clT >= crT);

        // Check if the selected price is the second most recent price. This means it must be newer than one, but older
        // than another.
        bool isSecondMostRecent = (
            selected == py && selectedT == pyT && (pyT <= crT && pyT >= clT || pyT <= clT && pyT >= crT)
        ) || (selected == cr && selectedT == crT && (crT <= pyT && crT >= clT || crT <= clT && crT >= pyT))
            || (selected == cl && selectedT == clT && (clT <= pyT && clT >= crT || clT <= crT && clT >= pyT));

        // Check if prices are within tolerance of each other. i.e compare the selected price to the other two.
        bool isWithinTolerance = (selected == py && (source.withinTolerance(py, cr) || source.withinTolerance(py, cl)))
            || (selected == cr && (source.withinTolerance(cr, py) || source.withinTolerance(cr, cl)))
            || (selected == cl && (source.withinTolerance(cl, py) || source.withinTolerance(cl, cr)));

        // Check if the selected price and time follow the logic of the function given the definition of:
        // a) Return the most recent price if it's within tolerance of at least one of the other two.
        // b) If not, return the second most recent price if it's within tolerance of at least one of the other two.
        // c) If neither a) nor b) is met, return chainlink. Here we ensure this by checking that the sources diverged.
        bool isValidPriceTimePair = (isMostRecent && isWithinTolerance)
            || (!isMostRecent && isSecondMostRecent && isWithinTolerance)
            || (selected == cl && selectedT == clT && !source.withinTolerance(cr, py));

        assertTrue(isValidPriceTimePair, "Invalid price-time pair selected");
    }

    function testHappyPathNoDivergence() public {
        int256 cl = 100;
        uint256 clT = 100001;
        int256 cr = 100;
        uint256 crT = 100002;
        int256 py = 100;
        uint256 pyT = 100003;

        (int256 selected, uint256 selectedT) = source.selectBoundedPrice(cl, clT, cr, crT, py, pyT);
        assertTrue(selected == py && selectedT == pyT);

        // now, make the newest be cr. we should now get cr.
        crT = 100003;
        pyT = 100002;
        (selected, selectedT) = source.selectBoundedPrice(cl, clT, cr, crT, py, pyT);
        assertTrue(selected == cr && selectedT == crT);

        // now, make the newest be cl. we should now get cl.
        clT = 100003;
        crT = 100001;
        (selected, selectedT) = source.selectBoundedPrice(cl, clT, cr, crT, py, pyT);
        assertTrue(selected == cl && selectedT == clT);
    }

    function testUnhappyPathOldestDiverged() public {
        int256 cl = 0; // consider chainlink is broken and the oldest.
        uint256 clT = 100001;
        int256 cr = 100;
        uint256 crT = 100002;
        int256 py = 100;
        uint256 pyT = 100003;

        (int256 selected, uint256 selectedT) = source.selectBoundedPrice(cl, clT, cr, crT, py, pyT);
        assertTrue(selected == py && selectedT == pyT);

        // now, make the oldest be cr which has diverged. we should still get py.
        cl = 100;
        cr = 0;
        clT = 100002; // cl is now the second oldest.
        crT = 100001; // cr is now the oldest.
        (selected, selectedT) = source.selectBoundedPrice(cl, clT, cr, crT, py, pyT);
        assertTrue(selected == py && selectedT == pyT);
    }

    function testUnhappyPathSecondOldestDiverged() public {
        int256 cl = 100;
        uint256 clT = 100001;
        int256 cr = 0; // consider chronicle is broken and the second oldest.
        uint256 crT = 100002;
        int256 py = 100;
        uint256 pyT = 100003;

        (int256 selected, uint256 selectedT) = source.selectBoundedPrice(cl, clT, cr, crT, py, pyT);
        assertTrue(selected == py && selectedT == pyT);
    }

    function testUnhappyPathNewestDiverged() public {
        int256 cl = 100;
        uint256 clT = 100001;
        int256 cr = 100;
        uint256 crT = 100002;
        int256 py = 0; // Pyth is both the newest and diverged.
        uint256 pyT = 100003;

        // In this case we should return cr.
        (int256 selected, uint256 selectedT) = source.selectBoundedPrice(cl, clT, cr, crT, py, pyT);
        assertTrue(selected == cr && selectedT == crT);

        // Now, make cl the second newest and cr the oldest. keep py diverged. Should see cl now returned.
        clT = 100002;
        crT = 100001;
        (selected, selectedT) = source.selectBoundedPrice(cl, clT, cr, crT, py, pyT);
        assertTrue(selected == cl && selectedT == clT);
    }

    function testUnhappyPathAllDiverged() public {
        // all values diverged. should get back chainlink.
        int256 cl = 0;
        uint256 clT = 100001;
        int256 cr = 50;
        uint256 crT = 100002;
        int256 py = 100;
        uint256 pyT = 100003;

        (int256 selected, uint256 selectedT) = source.selectBoundedPrice(cl, clT, cr, crT, py, pyT);
        assertTrue(selected == cl && selectedT == clT);
    }
}
