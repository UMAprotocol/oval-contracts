// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {Oval} from "../../src/Oval.sol";
import {BaseDestinationAdapter} from "../../src/adapters/destination-adapters/BaseDestinationAdapter.sol";
import {PythDestinationAdapter} from "../../src/adapters/destination-adapters/PythDestinationAdapter.sol";
import {IPyth} from "../../src/interfaces/pyth/IPyth.sol";
import {IOval} from "../../src/interfaces/IOval.sol";
import {BaseController} from "../../src/controllers/BaseController.sol";
import {CommonTest} from "../Common.sol";
import {MockSourceAdapter} from "../mocks/MockSourceAdapter.sol";

contract TestOval is BaseController, MockSourceAdapter, PythDestinationAdapter {
    constructor(uint8 decimals, IPyth _basePythProvider)
        BaseController()
        MockSourceAdapter(decimals)
        PythDestinationAdapter(_basePythProvider)
    {}
}

contract OvalChronicleMedianDestinationAdapter is CommonTest {
    int256 initialPrice = 1895 * 1e18;
    uint256 initialTimestamp = 1690000000;

    int256 newAnswer = 1900 * 1e18;
    uint256 newTimestamp = initialTimestamp + 1;

    bytes32 testId = keccak256("testId");
    uint8 testDecimals = 8;
    uint256 testValidTimePeriod = 3600;

    address OvalAddress = makeAddr("OvalAddress");
    address basePythProviderAddress = makeAddr("basePythProviderAddress");

    PythDestinationAdapter destinationAdapter;

    function setUp() public {
        vm.clearMockedCalls();
        destinationAdapter = new PythDestinationAdapter(IPyth(basePythProviderAddress));
    }

    function testSetOval() public {
        destinationAdapter.setOval(testId, testDecimals, testValidTimePeriod, IOval(OvalAddress));
        assertEq(address(destinationAdapter.idToOval(testId)), address(OvalAddress));
        assertEq(destinationAdapter.idToDecimal(testId), testDecimals);
        assertEq(destinationAdapter.idToValidTimePeriod(testId), testValidTimePeriod);
    }

    function testGetPriceUnsafe() public {
        destinationAdapter.setOval(testId, testDecimals, testValidTimePeriod, IOval(OvalAddress));
        vm.mockCall(
            OvalAddress, abi.encodeWithSelector(IOval.internalLatestData.selector), abi.encode(newAnswer, newTimestamp)
        );

        IPyth.Price memory price = destinationAdapter.getPriceUnsafe(testId);

        assertEq(price.price, newAnswer / 10 ** 10);
        assertEq(price.expo, -int32(uint32(testDecimals)));
        assertEq(price.publishTime, newTimestamp);
    }

    function testGetPrice() public {
        destinationAdapter.setOval(testId, testDecimals, testValidTimePeriod, IOval(OvalAddress));
        uint256 timestamp = block.timestamp;
        vm.mockCall(
            OvalAddress, abi.encodeWithSelector(IOval.internalLatestData.selector), abi.encode(newAnswer, timestamp)
        );

        IPyth.Price memory price = destinationAdapter.getPrice(testId);

        assertEq(price.price, newAnswer / 10 ** 10);
        assertEq(price.expo, -int32(uint32(testDecimals)));
        assertEq(price.publishTime, timestamp);
    }

    function testNotWithinValidWindow() public {
        destinationAdapter.setOval(testId, testDecimals, testValidTimePeriod, IOval(OvalAddress));
        vm.warp(newTimestamp + testValidTimePeriod + 1); // Warp to after the valid time period.

        vm.mockCall(
            OvalAddress, abi.encodeWithSelector(IOval.internalLatestData.selector), abi.encode(newAnswer, newTimestamp)
        );

        vm.expectRevert("Not within valid window");
        destinationAdapter.getPrice(testId);
    }

    function testFutureTimestamp() public {
        destinationAdapter.setOval(testId, testDecimals, testValidTimePeriod, IOval(OvalAddress));
        vm.warp(newTimestamp - 1); // Warp to before publish time.

        vm.mockCall(
            OvalAddress, abi.encodeWithSelector(IOval.internalLatestData.selector), abi.encode(newAnswer, newTimestamp)
        );

        IPyth.Price memory price = destinationAdapter.getPrice(testId);

        assertEq(price.price, newAnswer / 10 ** 10);
        assertEq(price.expo, -int32(uint32(testDecimals)));
        assertEq(price.publishTime, newTimestamp);
    }

    function testUnsupportedIdentifier() public {
        // We don't set an Oval for testId, so it should return the price from the source.
        assert(address(destinationAdapter.idToOval(testId)) == address(0));

        vm.mockCall(
            basePythProviderAddress,
            abi.encodeWithSelector(IPyth.getPriceUnsafe.selector, testId),
            abi.encode(IPyth.Price({price: 1, conf: 0, expo: -int32(uint32(testDecimals)), publishTime: 1000}))
        );

        IPyth.Price memory price = destinationAdapter.getPriceUnsafe(testId);

        assertEq(price.price, 1);
        assertEq(price.expo, -int32(uint32(testDecimals)));
        assertEq(price.publishTime, 1000);
    }
}
