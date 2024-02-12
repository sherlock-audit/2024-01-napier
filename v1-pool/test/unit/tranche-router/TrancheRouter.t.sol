// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Base} from "../../Base.t.sol";

import {TrancheRouter} from "src/TrancheRouter.sol";
import {IERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/IERC20.sol";

import {ITranche} from "@napier/napier-v1/src/interfaces/ITranche.sol";
import {Tranche} from "@napier/napier-v1/src/Tranche.sol";
import {TrancheFactory} from "@napier/napier-v1/src/TrancheFactory.sol";
import {YieldToken} from "@napier/napier-v1/src/YieldToken.sol";
import {MockERC20} from "@napier/napier-v1/test/mocks/MockERC20.sol";
import {MockAdapter} from "@napier/napier-v1/test/mocks/MockAdapter.sol";

contract TrancheRouterTest_ERC20 is Base {
    address caller = address(0xCAFE);
    address receiver = address(0xBEEF);

    function setUp() public virtual {
        _deployWETH();
        _deployAdaptersAndPrincipalTokens();
        _deployCurveV2Pool();
        _deployNapierPool();
        _deployNapierRouter();
        _deployTrancheRouter();

        deal(address(underlying), address(caller), 1 ether, false);
        _label();
    }

    /////////////////////////////////////////////////////////////////////
    /// ISSUE
    /////////////////////////////////////////////////////////////////////

    /// @notice Should revert if maturity has passed or is equal to current timestamp
    function testIssue_RevertIfMatured() public virtual {
        vm.warp(maturity);
        address underlying = ITranche(pts[0]).underlying();

        _approve(IERC20(underlying), caller, address(trancheRouter), 1 ether);
        vm.startPrank(caller);
        vm.expectRevert(ITranche.TimestampAfterMaturity.selector);
        trancheRouter.issue(address(adapters[0]), maturity, 1 ether, receiver);
        vm.stopPrank();
    }

    function testIssue_RevertIfInsufficientAllowance() public virtual {
        address underlying = ITranche(pts[0]).underlying();

        _approve(IERC20(underlying), caller, address(trancheRouter), 0.5 ether);
        vm.startPrank(caller);
        vm.expectRevert("ERC20: insufficient allowance");
        trancheRouter.issue(address(adapters[0]), maturity, 1 ether, receiver);
        vm.stopPrank();
    }

    function testIssue_RevertIfNotWETHUnderlying() public virtual {
        startHoax(caller);
        vm.expectRevert("ERC20: insufficient allowance");
        trancheRouter.issue{value: 1 ether}(address(adapters[0]), maturity, 1 ether, receiver);
        vm.stopPrank();
    }

    function testIssue_Ok() public virtual {
        address underlying = ITranche(pts[0]).underlying();

        _approve(IERC20(underlying), caller, address(trancheRouter), 1 ether);
        vm.startPrank(caller);
        uint256 issuedAmount = trancheRouter.issue(address(adapters[0]), maturity, 1 ether, receiver);
        assertGt(issuedAmount, 0, "issuedAmount should be greater than zero");
        vm.stopPrank();
    }

    //////////////////////////////////////////////////////////////////////
    /// REDEEM_WITH_YT
    //////////////////////////////////////////////////////////////////////

    function testRedeemWithYT_RevertIfZeroYieldAccrued() public virtual {
        vm.warp(maturity);
        vm.expectRevert(ITranche.NoAccruedYield.selector);
        trancheRouter.redeemWithYT(address(adapters[0]), maturity, 0, receiver);
    }

    /// @notice Same amount of YT should be burned as PT
    function testRedeemWithYT_RevertIfInsufficientYieldTokenBalance() public virtual {
        address underlying = ITranche(pts[0]).underlying();

        _approve(IERC20(underlying), caller, address(trancheRouter), 1 ether);
        vm.prank(caller);
        uint256 issuedAmount = trancheRouter.issue(address(adapters[0]), maturity, 1 ether, caller);
        vm.warp(maturity + 10 days);
        _approve(IERC20(address(pts[0])), caller, address(trancheRouter), issuedAmount);
        _approve(IERC20(address(yts[0])), caller, address(trancheRouter), issuedAmount);
        vm.startPrank(caller);
        IERC20(address(yts[0])).transfer(address(0xABCD), 1);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        trancheRouter.redeemWithYT(address(adapters[0]), maturity, issuedAmount, receiver);
        vm.stopPrank();
    }

    /// @notice  TrancheRouter should be approve to transfer PT and YT
    function testRedeemWithYT_RevertIfInsufficientAllowance() public virtual {
        address underlying = ITranche(pts[0]).underlying();

        _approve(IERC20(underlying), caller, address(trancheRouter), 1 ether);
        vm.startPrank(caller);
        uint256 issuedAmount = trancheRouter.issue(address(adapters[0]), maturity, 1 ether, caller);
        vm.warp(maturity + 10 days);
        vm.expectRevert("ERC20: insufficient allowance");
        trancheRouter.redeemWithYT(address(adapters[0]), maturity, issuedAmount, receiver);
        vm.stopPrank();
    }

    function test_RedeemWithYT_Ok() public virtual {
        address underlying = ITranche(pts[0]).underlying();

        _approve(IERC20(underlying), caller, address(trancheRouter), 1 ether);
        vm.prank(caller);
        uint256 issuedAmount = trancheRouter.issue(address(adapters[0]), maturity, 1 ether, caller);
        vm.warp(maturity + 10 days);
        adapters[0].setScale(adapters[0].scale() * 2);
        _approve(IERC20(address(pts[0])), caller, address(trancheRouter), issuedAmount);
        _approve(IERC20(address(yts[0])), caller, address(trancheRouter), issuedAmount);
        vm.prank(caller);
        trancheRouter.redeemWithYT(address(adapters[0]), maturity, issuedAmount, receiver);
        assertApproxEqAbs(
            IERC20(underlying).balanceOf(receiver), issuedAmount * 2, 10, "target balance of underlying Token"
        );
    }

    //////////////////////////////////////////////////////////////////////
    /// REDEEM
    //////////////////////////////////////////////////////////////////////

    /// @notice Redeem PT can be done after maturity
    function testRedeem_RevertIfNotMaturedYet() public virtual {
        vm.expectRevert(ITranche.TimestampBeforeMaturity.selector);
        trancheRouter.redeem(address(adapters[0]), maturity, 0, receiver);
    }

    /// @notice Redeeming should revert if not enough allowance
    function testRedeem_RevertIfInsufficientAllowance() public virtual {
        address underlying = ITranche(pts[0]).underlying();

        _approve(IERC20(underlying), caller, address(trancheRouter), 1 ether);
        vm.prank(caller);
        uint256 issuedAmount = trancheRouter.issue(address(adapters[0]), maturity, 1 ether, caller);
        vm.warp(maturity + 10 days);
        _approve(IERC20(address(pts[0])), caller, address(trancheRouter), 10);

        vm.expectRevert("ERC20: insufficient allowance");
        vm.prank(caller);
        trancheRouter.redeem(address(adapters[0]), maturity, issuedAmount / 2, receiver);
    }

    function testRedeem_Ok() public virtual {
        address underlying = ITranche(pts[0]).underlying();

        _approve(IERC20(underlying), caller, address(trancheRouter), 1 ether);
        vm.prank(caller);
        uint256 issuedAmount = trancheRouter.issue(address(adapters[0]), maturity, 1 ether, caller);

        vm.warp(maturity + 10 days);
        adapters[0].setScale(adapters[0].scale() * 2);
        _approve(IERC20(address(pts[0])), caller, address(trancheRouter), issuedAmount);
        vm.prank(caller);
        trancheRouter.redeem(address(adapters[0]), maturity, issuedAmount, receiver);

        assertApproxEqAbs(
            IERC20(underlying).balanceOf(receiver), issuedAmount, 10, "target balance of underlying Token"
        );
    }

    //////////////////////////////////////////////////////////////////////
    /// WITHDRAW
    //////////////////////////////////////////////////////////////////////

    /// @notice Withdrawing should revert if not matured yet
    function testWithdraw_RevertIfNotMaturedYet() public virtual {
        vm.expectRevert(ITranche.TimestampBeforeMaturity.selector);
        trancheRouter.withdraw(address(adapters[0]), maturity, 0, receiver);
    }

    /// @notice Withdrawing should revert if not enough allowance
    function testWithdraw_RevertIfInsufficientAllowance() public virtual {
        address underlying = ITranche(pts[0]).underlying();

        _approve(IERC20(underlying), caller, address(trancheRouter), 1 ether);
        vm.prank(caller);
        uint256 issuedAmount = trancheRouter.issue(address(adapters[0]), maturity, 1 ether, caller);
        vm.warp(maturity + 10 days);
        _approve(IERC20(address(pts[0])), caller, address(trancheRouter), 10);
        vm.expectRevert("ERC20: insufficient allowance");
        vm.prank(caller);
        trancheRouter.withdraw(address(adapters[0]), maturity, issuedAmount / 2, receiver);
    }

    function testWithdraw_Ok() public virtual {
        address underlying = ITranche(pts[0]).underlying();

        _approve(IERC20(underlying), caller, address(trancheRouter), 1 ether);
        vm.prank(caller);
        uint256 issuedAmount = trancheRouter.issue(address(adapters[0]), maturity, 1 ether, caller);
        vm.warp(maturity + 10 days);
        adapters[0].setScale(adapters[0].scale() * 2);
        _approve(IERC20(address(pts[0])), caller, address(trancheRouter), issuedAmount);
        vm.prank(caller);
        trancheRouter.withdraw(address(adapters[0]), maturity, issuedAmount, receiver);
        assertApproxEqAbs(
            IERC20(underlying).balanceOf(receiver), issuedAmount, 10, "target balance of underlying Token"
        );
    }
}

contract TrancheRouterTest_ETH is TrancheRouterTest_ERC20 {
    address callerWithETH = address(0xAABB);

    function setUp() public override {
        super.setUp();
        deal(callerWithETH, 1 ether);
        deal(address(weth), address(caller), 1 ether, false);
    }

    function _deployUnderlying() internal override {
        require(address(weth) != address(0), "WETH not deployed");
        underlying = weth;
        uDecimals = 18;
        ONE_UNDERLYING = 1e18;
    }

    /////////////////////////////////////////////////////////////////////
    /// ISSUE
    /////////////////////////////////////////////////////////////////////

    /// @notice Should revert if maturity has passed or is equal to current timestamp
    function testIssue_RevertIfMatured() public override {
        vm.warp(maturity);

        vm.startPrank(callerWithETH);

        vm.expectRevert(ITranche.TimestampAfterMaturity.selector);
        trancheRouter.issue{value: 1 ether}(address(adapters[0]), maturity, 1 ether, receiver);
        vm.stopPrank();
    }

    function testIssue_RevertIfInsufficientAllowance() public override {
        vm.startPrank(callerWithETH);
        vm.expectRevert("ERC20: insufficient allowance");
        trancheRouter.issue{value: 0.5 ether}(address(adapters[0]), maturity, 1 ether, receiver);
        vm.stopPrank();
    }

    function testIssue_RevertIfNotWETHUnderlying() public override {
        // Note: this test is not applicable for ETH
    }

    function testIssue_Ok() public override {
        vm.startPrank(callerWithETH);
        uint256 issuedAmount = trancheRouter.issue{value: 1 ether}(address(adapters[0]), maturity, 1 ether, receiver);
        assertGt(issuedAmount, 0, "issuedAmount should be greater than zero");
        vm.stopPrank();
    }

    //////////////////////////////////////////////////////////////////////
    /// REDEEM_WITH_YT
    //////////////////////////////////////////////////////////////////////

    /// @notice  TrancheRouter should be approve to transfer PT and YT
    function testRedeemWithYT_RevertIfInsufficientAllowance() public override {
        address underlying = ITranche(pts[0]).underlying();

        _approve(IERC20(underlying), caller, address(trancheRouter), 1 ether);
        vm.startPrank(caller);
        uint256 issuedAmount = trancheRouter.issue(address(adapters[0]), maturity, 1 ether, caller);
        vm.warp(maturity + 10 days);
        vm.expectRevert("ERC20: insufficient allowance");

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(
            trancheRouter.redeemWithYT.selector, adapters[0], maturity, issuedAmount, address(trancheRouter)
        );
        data[1] = abi.encodeWithSelector(trancheRouter.unwrapWETH9.selector, 0, receiver);
        trancheRouter.multicall(data);
        vm.stopPrank();
    }

    /// @notice Same amount of YT should be burned as PT
    function testRedeemWithYT_RevertIfInsufficientYieldTokenBalance() public override {
        address underlying = ITranche(pts[0]).underlying();

        _approve(IERC20(underlying), caller, address(trancheRouter), 1 ether);
        vm.prank(caller);
        uint256 issuedAmount = trancheRouter.issue(address(adapters[0]), maturity, 1 ether, caller);
        vm.warp(maturity + 10 days);
        _approve(IERC20(address(pts[0])), caller, address(trancheRouter), issuedAmount);
        _approve(IERC20(address(yts[0])), caller, address(trancheRouter), issuedAmount);
        vm.startPrank(caller);
        IERC20(address(yts[0])).transfer(address(0xABCD), 1);
        vm.expectRevert("ERC20: burn amount exceeds balance");

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(
            trancheRouter.redeemWithYT.selector, adapters[0], maturity, issuedAmount, address(trancheRouter)
        );
        data[1] = abi.encodeWithSelector(trancheRouter.unwrapWETH9.selector, 0, receiver);
        trancheRouter.multicall(data);
        vm.stopPrank();
    }

    function test_RedeemWithYT_Ok() public override {
        address underlying = ITranche(pts[0]).underlying();

        _approve(IERC20(underlying), caller, address(trancheRouter), 1 ether);
        vm.prank(caller);
        uint256 issuedAmount = trancheRouter.issue(address(adapters[0]), maturity, 1 ether, caller);

        vm.warp(maturity + 10 days);
        adapters[0].setScale(adapters[0].scale() * 2);

        _approve(IERC20(address(pts[0])), caller, address(trancheRouter), issuedAmount);
        _approve(IERC20(address(yts[0])), caller, address(trancheRouter), issuedAmount);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(
            trancheRouter.redeemWithYT.selector, adapters[0], maturity, issuedAmount, address(trancheRouter)
        );
        data[1] = abi.encodeWithSelector(trancheRouter.unwrapWETH9.selector, 0, receiver);
        vm.prank(caller);
        trancheRouter.multicall(data);

        assertApproxEqAbs(receiver.balance, issuedAmount * 2, 10, "target balance of native ETH");
    }

    //////////////////////////////////////////////////////////////////////
    /// REDEEM
    //////////////////////////////////////////////////////////////////////

    /// @notice Redeeming should revert if not enough allowance
    function testRedeem_RevertIfInsufficientAllowance() public override {
        address underlying = ITranche(pts[0]).underlying();

        _approve(IERC20(underlying), caller, address(trancheRouter), 1 ether);
        vm.prank(caller);
        uint256 issuedAmount = trancheRouter.issue(address(adapters[0]), maturity, 1 ether, caller);
        vm.warp(maturity + 10 days);
        _approve(IERC20(address(pts[0])), caller, address(trancheRouter), 10);
        vm.expectRevert("ERC20: insufficient allowance");
        vm.prank(caller);
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(
            trancheRouter.redeem.selector, adapters[0], maturity, issuedAmount / 2, address(trancheRouter)
        );
        data[1] = abi.encodeWithSelector(trancheRouter.unwrapWETH9.selector, 0, receiver);
        trancheRouter.multicall(data);
    }

    function testRedeem_Ok() public override {
        address underlying = ITranche(pts[0]).underlying();

        _approve(IERC20(underlying), caller, address(trancheRouter), 1 ether);
        vm.prank(caller);
        uint256 issuedAmount = trancheRouter.issue(address(adapters[0]), maturity, 1 ether, caller);

        vm.warp(maturity + 10 days);
        adapters[0].setScale(adapters[0].scale() * 2);
        _approve(IERC20(address(pts[0])), caller, address(trancheRouter), issuedAmount);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(
            trancheRouter.redeem.selector, adapters[0], maturity, issuedAmount, address(trancheRouter)
        );
        data[1] = abi.encodeWithSelector(trancheRouter.unwrapWETH9.selector, 0, receiver);
        vm.prank(caller);
        trancheRouter.multicall(data);
        assertApproxEqAbs(receiver.balance, issuedAmount, 10, "target balance of native ETH");
    }

    //////////////////////////////////////////////////////////////////////
    /// WITHDRAW
    //////////////////////////////////////////////////////////////////////

    /// @notice Withdrawing should revert if not enough allowance
    function testWithdraw_RevertIfInsufficientAllowance() public override {
        address underlying = ITranche(pts[0]).underlying();

        _approve(IERC20(underlying), caller, address(trancheRouter), 1 ether);
        vm.prank(caller);
        uint256 issuedAmount = trancheRouter.issue(address(adapters[0]), maturity, 1 ether, caller);
        vm.warp(maturity + 10 days);
        _approve(IERC20(address(pts[0])), caller, address(trancheRouter), 10);
        vm.expectRevert("ERC20: insufficient allowance");
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(
            trancheRouter.withdraw.selector, adapters[0], maturity, issuedAmount / 2, address(trancheRouter)
        );
        data[1] = abi.encodeWithSelector(trancheRouter.unwrapWETH9.selector, 0, receiver);
        vm.prank(caller);
        trancheRouter.multicall(data);
    }

    function testWithdraw_Ok() public override {
        address underlying = ITranche(pts[0]).underlying();

        _approve(IERC20(underlying), caller, address(trancheRouter), 1 ether);
        vm.prank(caller);
        uint256 issuedAmount = trancheRouter.issue(address(adapters[0]), maturity, 1 ether, caller);
        vm.warp(maturity + 10 days);
        adapters[0].setScale(adapters[0].scale() * 2);

        _approve(IERC20(address(pts[0])), caller, address(trancheRouter), issuedAmount);
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(
            trancheRouter.withdraw.selector, adapters[0], maturity, issuedAmount, address(trancheRouter)
        );
        data[1] = abi.encodeWithSelector(trancheRouter.unwrapWETH9.selector, 0, receiver);
        vm.prank(caller);
        trancheRouter.multicall(data);
        assertApproxEqAbs(receiver.balance, issuedAmount, 10, "target balance of native ETH");
    }
}
