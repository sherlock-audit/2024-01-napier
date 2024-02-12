// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../Fixtures.sol";

import {IERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/IERC20.sol";
import {BaseAdapter} from "src/BaseAdapter.sol";

abstract contract BaseTestAdapter is AdapterFixture {
    function _deployAdapter() internal virtual override;

    function testSetUp_Ok() public virtual {
        assertEq(adapter.owner(), owner);
        assertEq(adapter.underlying(), address(underlying));
        assertEq(adapter.target(), address(target));
    }

    function testAdapterHasNoFundLeft() internal virtual;

    function testPrefundedDeposit_Zero() public virtual {
        (uint256 underlyingUsed, uint256 sharesMinted) = adapter.prefundedDeposit();
        assertEq(underlyingUsed, 0, "underlyingUsed !~= 0");
        assertEq(sharesMinted, 0, "sharesMinted !~= 0");
    }

    function testPrefundedRedeem_Zero() public virtual {
        (uint256 underlyingUsed, uint256 sharesMinted) = adapter.prefundedRedeem(user);
        assertEq(underlyingUsed, 0, "underlyingUsed !~= 0");
        assertEq(sharesMinted, 0, "sharesMinted !~= 0");
    }

    function testPrefundedDeposit() public virtual;

    function testPrefundedRedeem() public virtual;

    function testScale() public virtual;
}
