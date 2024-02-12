// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

import {Create2TrancheLib} from "src/Create2TrancheLib.sol";

contract TestCreate2TrancheLib is Test {
    function setUp() public {
        vm.label(address(Create2TrancheLib), "Create2TrancheLib");
    }

    function testFuzz_RevertIfUpperBitsAreDirty(address adapter, uint256 maturity, uint256 random) public {
        vm.assume(random != 0 && adapter != address(0) && maturity != 0);

        uint256 _adapter = (random << 160) | uint256(uint160(adapter));
        vm.expectRevert();
        (bool s, ) = address(Create2TrancheLib).delegatecall(
            abi.encodeWithSelector(Create2TrancheLib.deploy.selector, _adapter, maturity)
        );
        s; // Silence compiler warning "Return value of low-level calls not used."
    }
}
