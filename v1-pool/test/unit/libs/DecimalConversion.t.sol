// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

import {DecimalConversion} from "src/libs/DecimalConversion.sol";

contract DecimalConversionTest is Test {
    /// forge-config: default.fuzz.runs = 20000
    function testFuzz_RoundTrip_Conversion(uint256 value, uint256 _decimals) public {
        value = bound(value, 0, type(uint96).max);
        uint8 decimals = uint8(bound(_decimals, 6, 18));
        assertEq(
            value,
            DecimalConversion.from18Decimals(DecimalConversion.to18Decimals(value, decimals), decimals),
            "Round trip conversion failed"
        );
    }

    function test_to18Decimals() public {
        assertEq(1e18, DecimalConversion.to18Decimals(1e6, 6), "to 18 decimals Conversion failed");
        assertEq(1e18, DecimalConversion.to18Decimals(1e3, 3), "to 18 decimals Conversion failed");
        assertEq(100 * 1e18, DecimalConversion.to18Decimals(100 * 1e6, 6), "to 18 decimals Conversion failed");
        assertEq(100 * 1e12, DecimalConversion.to18Decimals(100 * 1e12, 18), "to 18 decimals Conversion failed");
    }

    function test_from18Decimals() public {
        assertEq(1e6, DecimalConversion.from18Decimals(1e18, 6), "from 18 decimals Conversion failed");
        assertEq(1e10, DecimalConversion.from18Decimals(1e18, 10), "from 18 decimals Conversion failed");
        assertEq(100 * 1e12, DecimalConversion.from18Decimals(100 * 1e12, 18), "from 18 decimals Conversion failed");
    }
}
