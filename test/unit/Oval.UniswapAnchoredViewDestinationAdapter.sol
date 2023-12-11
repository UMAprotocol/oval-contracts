// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {BaseDestinationAdapter} from "../../src/adapters/destination-adapters/BaseDestinationAdapter.sol";
import {UniswapAnchoredViewDestinationAdapter} from
    "../../src/adapters/destination-adapters/UniswapAnchoredViewDestinationAdapter.sol";
import {IUniswapAnchoredView} from "../../src/interfaces/compound/IUniswapAnchoredView.sol";
import {IOVAL} from "../../src/interfaces/IOval.sol";
import {CommonTest} from "../Common.sol";

contract OVALUniswapAnchoredViewDestinationAdapter is CommonTest {
    int256 newAnswer = 1900 * 1e18;
    uint256 newTimestamp = 1690000000;

    int256 internalDecimalsToSourceDecimals = 1e10;

    address sourceAddress = makeAddr("sourceAddress");
    address OVALAddress = makeAddr("OVALAddress");
    address cTokenAddress = makeAddr("cTokenAddress");
    uint8 underlyingDecimals = 8;

    UniswapAnchoredViewDestinationAdapter destinationAdapter;

    function setUp() public {
        vm.clearMockedCalls();
        destinationAdapter = new UniswapAnchoredViewDestinationAdapter(IUniswapAnchoredView(sourceAddress));
    }

    function testSetOVAL() public {
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
        destinationAdapter.setOVAL(cTokenAddress, OVALAddress);

        assertEq(destinationAdapter.cTokenToOVAL(cTokenAddress), OVALAddress);
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
        destinationAdapter.setOVAL(cTokenAddress, OVALAddress);

        vm.mockCall(
            OVALAddress, abi.encodeWithSelector(IOVAL.internalLatestData.selector), abi.encode(newAnswer, newTimestamp)
        );
        uint256 underlyingPrice = destinationAdapter.getUnderlyingPrice(cTokenAddress);

        assertEq(underlyingPrice, uint256((newAnswer * 10 ** (36 - 8)) / 10 ** 18));
    }

    function testUnsupportedCToken() public {
        // We don't set an OVAL for this cToken, so it should return the price from the source.
        assert(destinationAdapter.cTokenToOVAL(cTokenAddress) == address(0));

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
