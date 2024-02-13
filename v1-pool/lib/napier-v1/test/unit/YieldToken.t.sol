// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {CompleteFixture} from "../Fixtures.sol";

import {Math} from "@openzeppelin/contracts@4.9.3/utils/math/Math.sol";

import {ITranche} from "src/interfaces/ITranche.sol";
import {IYieldToken} from "src/interfaces/IYieldToken.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockAdapter} from "../mocks/MockAdapter.sol";
import {MAX_BPS} from "src/Constants.sol";

import {StringHelper} from "../utils/StringHelper.sol";

contract TestYieldToken is CompleteFixture {
    function setUp() public virtual override {
        _maturity = block.timestamp + 180 days;
        _tilt = 0;
        _issuanceFee = 100;

        super.setUp();

        initialBalance = 1000 * ONE_SCALE;
        // fund tokens
        deal(address(underlying), address(this), initialBalance, true);
        _approve(address(underlying), address(this), address(tranche), type(uint256).max);
    }

    function _deployAdapter() internal virtual override {
        underlying = new MockERC20("Underlying", "U", 18);
        target = new MockERC20("Target", "T", 18);
        adapter = new MockAdapter(address(underlying), address(target));
    }

    function testERC20Metadata() public {
        assertEq(yt.decimals(), underlying.decimals(), "decimals");
        assertTrue(StringHelper.isSubstring(yt.name(), "Napier Yield Token"), "name");
        assertTrue(StringHelper.isSubstring(yt.name(), target.name()), "name");
        assertTrue(StringHelper.isSubstring(yt.symbol(), "eY"), "symbol");
        assertTrue(StringHelper.isSubstring(yt.symbol(), target.symbol()), "symbol");
    }

    function testYieldTokenMetadata() public {
        assertEq(yt.maturity(), _maturity, "maturity");
        assertEq(yt.tranche(), address(tranche), "tranche");
        assertEq(yt.underlying(), address(underlying), "underlying token");
        assertEq(yt.target(), address(target), "target token");
        console2.log("name: %s", yt.name());
        console2.log("symbol: %s", yt.symbol());
    }

    function testMint_Ok() public {
        uint256 amount = 100;
        vm.prank(address(tranche));
        yt.mint(address(this), amount);
        assertEq(yt.balanceOf(address(this)), amount, "balanceOf");
        assertEq(yt.totalSupply(), amount, "totalSupply");
    }

    function testMint_RevertIfNotTranche() public {
        vm.expectRevert(IYieldToken.OnlyTranche.selector);
        yt.mint(address(this), 100);
    }

    function testBurn_Ok() public {
        deal(address(yt), address(this), 100, true);
        vm.prank(address(tranche));
        yt.burn(address(this), 100);
        assertEq(yt.balanceOf(address(this)), 0, "balanceOf");
        assertEq(yt.totalSupply(), 0, "totalSupply");
    }

    function testBurn_RevertIfNotTranche() public {
        vm.expectRevert(IYieldToken.OnlyTranche.selector);
        yt.burn(address(this), 100);
    }

    function testBurnFrom_WhenSpenderIsOwner_Ok() public {
        deal(address(yt), address(this), 100, true);

        vm.prank(address(tranche));
        yt.burnFrom(address(this), address(this), 100);

        assertEq(yt.balanceOf(address(this)), 0, "balanceOf");
        assertEq(yt.totalSupply(), 0, "totalSupply");
    }

    function testBurnFrom_WhenSpenderIsNotOwner_Ok() public {
        deal(address(yt), address(this), 100, true);

        _approve(address(yt), address(this), address(0xbabe), 100);

        vm.prank(address(tranche));
        yt.burnFrom(address(this), address(0xbabe), 10);

        assertEq(yt.balanceOf(address(this)), 90, "balanceOf");
        assertEq(yt.totalSupply(), 90, "totalSupply");
        assertEq(yt.allowance(address(this), address(0xbabe)), 90, "allowance");
    }

    function testBurnFrom_RevertIfInsuffficientAllowance() public {
        deal(address(yt), address(this), 100, true);

        _approve(address(yt), address(0xbabe), address(this), 14);

        vm.expectRevert("ERC20: insufficient allowance");
        vm.prank(address(tranche));
        yt.burnFrom(address(0xbabe), address(this), 15);
    }

    function testBurnFrom_RevertIfNotTranche() public {
        vm.expectRevert(IYieldToken.OnlyTranche.selector);
        yt.burnFrom(address(this), address(this), 100);
    }

    function testTransfer(uint256 amount, uint32 newTimestamp) public {
        amount = bound(amount, 1, initialBalance);
        // setup
        uint256 issued = _issueYT(address(this), address(this), amount);
        vm.warp(newTimestamp);
        uint256 ytSupply = yt.totalSupply();
        // execution
        yt.transfer(user, issued);
        // assertion
        assertEq(yt.totalSupply(), ytSupply, "totalSupply");
        assertEq(yt.balanceOf(address(this)), 0, "balanceOf this");
        assertEq(yt.balanceOf(user), issued, "balanceOf user");
    }

    function testTransferFrom(uint256 amount, uint32 newTimestamp) public {
        amount = bound(amount, 1, initialBalance);
        // setup
        uint256 issued = _issueYT(address(this), address(this), amount);
        vm.warp(newTimestamp);
        uint256 ytSupply = yt.totalSupply();
        // execution
        _approve(address(yt), address(this), user, issued);
        vm.prank(user);
        yt.transferFrom(address(this), address(0xcafe), issued);
        // assertion
        assertEq(yt.totalSupply(), ytSupply, "totalSupply");
        assertEq(yt.balanceOf(address(this)), 0, "balanceOf this");
        assertEq(yt.balanceOf(user), 0, "balanceOf user");
        assertEq(yt.balanceOf(address(0xcafe)), issued, "balanceOf 0xcafe");
    }

    function testTransfer_RevertIfZeroAddress(uint128 amount, uint32 newTimestamp) public {
        vm.assume(amount != 0);
        vm.warp(newTimestamp);
        // execution
        vm.expectRevert(ITranche.ZeroAddress.selector);
        yt.transfer(address(0), amount);
    }

    function testTransferFrom_RevertIfZeroAddress(uint128 amount, uint32 newTimestamp) public {
        vm.assume(amount != 0);
        vm.warp(newTimestamp);
        // execution
        vm.expectRevert(ITranche.ZeroAddress.selector);
        yt.transferFrom(address(0), user, amount);

        vm.expectRevert(ITranche.ZeroAddress.selector);
        yt.transferFrom(address(this), address(0), amount);
    }

    function _issueYT(address caller, address from, uint256 amount) internal returns (uint256 issued) {
        issued = _issue(from, from, amount);
        _approve(address(yt), from, caller, amount);
    }

    ///////////////////////////////////////////////////////////////////////
    // VIRTUAL FUNCTIONS
    ///////////////////////////////////////////////////////////////////////

    function _simulateScaleIncrease() internal override {}

    function _simulateScaleDecrease() internal override {}
}
