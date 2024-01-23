// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {CommonTest} from "../Common.sol";
import {DecimalLib} from "../../src/adapters/lib/DecimalLib.sol";

// Wrapper contract to test DecimalLib functions, needed only for coverage to work.
contract TestDecimalConverter {
    function convertDecimals(int256 answer, uint8 iDecimals, uint8 oDecimals) public pure returns (int256) {
        return DecimalLib.convertDecimals(answer, iDecimals, oDecimals);
    }

    function convertDecimals(uint256 answer, uint8 iDecimals, uint8 oDecimals) public pure returns (uint256) {
        return DecimalLib.convertDecimals(answer, iDecimals, oDecimals);
    }

    function deriveDecimals(uint256 scalingFactor) public pure returns (uint8) {
        return DecimalLib.deriveDecimals(scalingFactor);
    }
}

contract DecimalLibTest is CommonTest {
    TestDecimalConverter converter;

    function setUp() public {
        converter = new TestDecimalConverter();
    }

    function testConvertEqualDecimals() public {
        uint256 input = 10000;
        uint8 iDecimals = 18;
        uint8 oDecimals = 18;
        uint256 result = converter.convertDecimals(input, iDecimals, oDecimals);
        int256 resultInt = converter.convertDecimals(-int256(input), iDecimals, oDecimals);
        assertTrue(result == input);
        assertTrue(resultInt == -int256(input));
    }

    function testUpscaleDecimals() public {
        uint256 input = 10;
        uint8 iDecimals = 15;
        uint8 oDecimals = 18;
        uint256 result = converter.convertDecimals(input, iDecimals, oDecimals);
        int256 resultInt = converter.convertDecimals(-int256(input), iDecimals, oDecimals);
        uint256 expected = 10000;
        assertTrue(result == expected);
        assertTrue(resultInt == -int256(expected));
    }

    function testDownscaleDecimals() public {
        uint256 input = 10999;
        uint8 iDecimals = 18;
        uint8 oDecimals = 15;
        uint256 result = converter.convertDecimals(input, iDecimals, oDecimals);
        int256 resultInt = converter.convertDecimals(-int256(input), iDecimals, oDecimals);
        uint256 expected = 10; // We expect loosing precision here.
        assertTrue(result == expected);
        assertTrue(resultInt == -int256(expected));
    }

    function testDeriveDecimals() public {
        uint256 scalingFactor = 1000000000000000000; // Corresponds to 10^18
        uint8 result = converter.deriveDecimals(scalingFactor);
        uint8 expected = 18;
        assertTrue(uint256(result) == uint256(expected));
    }

    function testDeriveDecimalsInvalidScaling() public {
        uint256 scalingFactor = 1000000000000000001; // Corresponds to 10^18 + 1
        vm.expectRevert("Invalid scalingFactor");
        converter.deriveDecimals(scalingFactor);
    }
}
