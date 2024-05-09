// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {BaseDestinationAdapter} from "../../src/adapters/destination-adapters/BaseDestinationAdapter.sol";
import {UniswapAnchoredViewDestinationAdapter} from
    "../../src/adapters/destination-adapters/UniswapAnchoredViewDestinationAdapter.sol";
import {IUniswapAnchoredView} from "../../src/interfaces/compound/IUniswapAnchoredView.sol";
import {IOval} from "../../src/interfaces/IOval.sol";
import {CommonTest} from "../Common.sol";

contract OvalUniswapAnchoredViewDestinationAdapter is CommonTest {
    int256 newAnswer = 1900 * 1e18;
    uint256 newTimestamp = 1690000000;
    uint256 roundId = 1; // UniswapAnchoredView does not support roundId and has it hardcoded to 1.

    int256 internalDecimalsToSourceDecimals = 1e10;

    address sourceAddress = makeAddr("sourceAddress");
    address OvalAddress = makeAddr("OvalAddress");
    address cTokenAddress = makeAddr("cTokenAddress");
    uint8 underlyingDecimals = 8;

    UniswapAnchoredViewDestinationAdapter destinationAdapter;

    function setUp() public {
        vm.clearMockedCalls();
        destinationAdapter = new UniswapAnchoredViewDestinationAdapter(IUniswapAnchoredView(sourceAddress));
    }

    function testSetOval() public {
        vm.mockCall(
            sourceAddress,
            abi.encodeWithSelector(IUniswapAnchoredView.getTokenConfigByCToken.selector, cTokenAddress),
            abi.encode(
                IUniswapAnchoredView.TokenConfig({
                    cToken: cTokenAddress,
                    underlying: makeAddr("underlying"),
                    symbolHash: keccak256("symbol"),
                    baseUnit: 10 ** underlyingDecimals,
                    priceSource: IUniswapAnchoredView.PriceSource.REPORTER,
                    fixedPrice: 1,
                    uniswapMarket: makeAddr("uniswapMarket"),
                    reporter: makeAddr("reporter"),
                    reporterMultiplier: 1,
                    isUniswapReversed: false
                })
            )
        );
        destinationAdapter.setOval(cTokenAddress, OvalAddress);

        assertEq(destinationAdapter.cTokenToOval(cTokenAddress), OvalAddress);
        assertEq(destinationAdapter.cTokenToDecimal(cTokenAddress), 36 - underlyingDecimals);
    }

    function testGetUnderlyingPrice() public {
        vm.mockCall(
            sourceAddress,
            abi.encodeWithSelector(IUniswapAnchoredView.getTokenConfigByCToken.selector, cTokenAddress),
            abi.encode(
                IUniswapAnchoredView.TokenConfig({
                    cToken: cTokenAddress,
                    underlying: makeAddr("underlying"),
                    symbolHash: keccak256("symbol"),
                    baseUnit: 10 ** underlyingDecimals,
                    priceSource: IUniswapAnchoredView.PriceSource.REPORTER,
                    fixedPrice: 1,
                    uniswapMarket: makeAddr("uniswapMarket"),
                    reporter: makeAddr("reporter"),
                    reporterMultiplier: 1,
                    isUniswapReversed: false
                })
            )
        );
        destinationAdapter.setOval(cTokenAddress, OvalAddress);

        vm.mockCall(
            OvalAddress,
            abi.encodeWithSelector(IOval.internalLatestData.selector),
            abi.encode(newAnswer, newTimestamp, roundId)
        );
        uint256 underlyingPrice = destinationAdapter.getUnderlyingPrice(cTokenAddress);

        assertEq(underlyingPrice, uint256((newAnswer * 10 ** (36 - 8)) / 10 ** 18));
    }

    function testUnsupportedCToken() public {
        // We don't set an Oval for this cToken, so it should return the price from the source.
        assert(destinationAdapter.cTokenToOval(cTokenAddress) == address(0));

        vm.mockCall(
            sourceAddress,
            abi.encodeWithSelector(IUniswapAnchoredView.getUnderlyingPrice.selector, cTokenAddress),
            abi.encode(uint256(1))
        );
        uint256 underlyingPrice = destinationAdapter.getUnderlyingPrice(cTokenAddress);

        assertEq(underlyingPrice, uint256(1));
    }

    function testGetTokenConfigByCToken() public {
        vm.expectRevert("Not supported");
        destinationAdapter.getTokenConfigByCToken(address(1));
    }
}
