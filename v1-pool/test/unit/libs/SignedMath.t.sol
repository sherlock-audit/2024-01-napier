// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import {SignedMath} from "src/libs/SignedMath.sol";

contract SignedMathTest is Test {
    function test_mulDivDown() public {
        assertEq(SignedMath.mulDivDown(2, 3, 1), 6);
        assertEq(SignedMath.mulDivDown(10, 5, 2), 25);
    }

    function test_subNoNeg() public {
        assertEq(SignedMath.subNoNeg(5, 3), 2);
    }

    function testFuzz_subNoNeg(int256 a, int256 b) public {
        b = bound(b, -1e36 * 1e18, 1e36 * 1e18);
        a = bound(a, -1e36 * 1e18, 1e36 * 1e18);
        vm.assume(a >= b);
        assertEq(SignedMath.subNoNeg(a, b), a - b);
    }

    function testFuzz_RevertIf_Negative_subNoNeg(int256 a, int256 b) public {
        vm.assume(a < b);
        vm.expectRevert("negative");
        SignedMath.subNoNeg(a, b); // This should fail
    }

    function test_mulWadDown() public {
        assertEq(SignedMath.mulWadDown(2 * 1e18, 3 * 1e18), 6 * 1e18);
    }

    function test_divWadDown() public {
        assertEq(SignedMath.divWadDown(6 * 1e18, 2 * 1e18), 3 * 1e18);
    }

    function test_neg() public {
        assertEq(SignedMath.neg(uint256(5)), -5);
        assertEq(SignedMath.neg(-5), 5);
    }
}
