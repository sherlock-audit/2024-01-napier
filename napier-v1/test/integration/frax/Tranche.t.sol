// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {BaseTestTranche} from "../../shared/BaseTestTranche.t.sol";
import {SFrxETHFixture} from "./Fixture.sol";
import {CompleteFixture} from "./../../Fixtures.sol";

import {SFrxETHAdapter} from "src/adapters/frax/SFrxETHAdapter.sol";

import "src/Constants.sol" as Constants;

contract TestSFrxETHTranche is BaseTestTranche, SFrxETHFixture {
    using stdStorage for StdStorage;

    /// @dev Address of the whale
    address charlie = makeAddr("charlie");

    function setUp() public virtual override(CompleteFixture, SFrxETHFixture) {
        SFrxETHFixture.setUp();
        MIN_UNDERLYING_DEPOSIT = 1_000;
        MAX_UNDERLYING_DEPOSIT = 10_000 ether;
        _DELTA_ = 100;
    }

    function deal(
        address token,
        address to,
        uint256 give,
        bool adjust
    ) internal virtual override(StdCheats, SFrxETHFixture) {
        SFrxETHFixture.deal(token, to, give, adjust);
    }

    /// @notice Mint some sfrxETH and shares by depositing large amount of underlying.
    /// @dev This is a helper function for setting up the test environment.
    modifier setUpBuffer() {
        deal(address(underlying), charlie, 1_000_000 * ONE_SCALE, false); // 100x of the MAX_UNDERLYING_DEPOSIT
        vm.startPrank(charlie);
        underlying.transfer(address(adapter), 1_000_000 * ONE_SCALE);
        adapter.prefundedDeposit();
        vm.stopPrank();
        _;
    }

    /////////////////////////////////////////////////////////////////////
    /// REDEEM WITH YT
    /////////////////////////////////////////////////////////////////////

    /// @notice Test redeeming PT with YT
    ///         - PT+YT should be burned
    ///         - Accrued yield should be sent to user
    /// @param amountRedeem amount of PT+YT to redeem
    /// @param newTimestamp new timestamp to warp to
    function testRedeemWithYT_ScaleIncrease(uint256 amountRedeem, uint32 newTimestamp) public override setUpBuffer {
        uint256 amount = 100 * ONE_SCALE;
        uint256 issued = _issue(address(this), address(this), amount);
        amountRedeem = bound(amountRedeem, MIN_UNDERLYING_DEPOSIT, issued);
        newTimestamp = boundU32(newTimestamp, block.timestamp, _maturity + 365 days);
        // assert
        _testRedeemWithYT(issued, amountRedeem, _simulateScaleIncrease, newTimestamp);
    }

    /// @notice Test redeeming PT with YT
    ///         - PT+YT should be burned
    ///         - There should be no accrued yield
    /// @param amountRedeem amount of PT+YT to redeem
    /// @param newTimestamp new timestamp to warp to
    function testRedeemWithYT_ScaleDecrease(uint256 amountRedeem, uint32 newTimestamp) public override setUpBuffer {
        uint256 amount = 100 * ONE_SCALE;
        uint256 issued = _issue(address(this), address(this), amount);
        amountRedeem = bound(amountRedeem, MIN_UNDERLYING_DEPOSIT, issued);
        newTimestamp = boundU32(newTimestamp, block.timestamp, _maturity + 365 days);
        // assert
        _testRedeemWithYT(issued, amountRedeem, _simulateScaleDecrease, newTimestamp);
    }

    function testRedeemWithYT_AfterMaturity_AlreadySettle_LscaleNonZero() public override setUpBuffer {
        super.testRedeemWithYT_AfterMaturity_AlreadySettle_LscaleNonZero();
    }

    /// @inheritdoc BaseTestTranche
    function testRT_Issue_RedeemWithYT_Immediately(uint256 uDeposit) public override setUpBuffer {
        super.testRT_Issue_RedeemWithYT_Immediately(uDeposit);
    }

    function testRT_Issue_RedeemWithYT_ScaleIncrease(uint256 uDeposit) public override setUpBuffer {
        super.testRT_Issue_RedeemWithYT_ScaleIncrease(uDeposit);
    }

    /// @inheritdoc BaseTestTranche
    function testRT_Issue_RedeemWithYT_ScaleDecrease(uint256 uDeposit) public override setUpBuffer {
        super.testRT_Issue_RedeemWithYT_ScaleDecrease(uDeposit);
    }

    /////////////////////////////////////////////////////////////////////
    /// REDEEM
    /////////////////////////////////////////////////////////////////////

    /// @inheritdoc BaseTestTranche
    function testRedeem_WhenSunnyday(uint256 amountToRedeem) public override setUpBuffer {
        // setup
        uint256 amount = 100 * ONE_SCALE;
        uint256 issued = _issue(address(this), user, amount);
        vm.warp(_maturity + 7 days);
        amountToRedeem = bound(amountToRedeem, MIN_UNDERLYING_DEPOSIT, issued);
        // scale increases after issue
        _simulateScaleIncrease();
        // execution
        _testRedeem(amountToRedeem, user, user, user);
        assertEq(_isSunnyDay(), true, "sunnyday");
    }

    /// @inheritdoc BaseTestTranche
    function testRedeem_WhenNotSunnyday(uint256 amountToRedeem) public override setUpBuffer {
        // setup
        uint256 amount = 100 * ONE_SCALE;
        uint256 issued = _issue(address(this), user, amount);
        vm.warp(_maturity + 7 days);
        amountToRedeem = bound(amountToRedeem, MIN_UNDERLYING_DEPOSIT, issued);
        // scale increases after issue
        _simulateScaleDecrease();
        // execution
        uint256 underlyingWithdrawn = _testRedeem(amountToRedeem, user, user, user);
        // assert
        assertEq(_isSunnyDay(), false, "not sunnyday");
        // not sunnyday condition
        assertApproxEqRel(
            underlyingWithdrawn,
            _convertToUnderlying(((amountToRedeem * WAD) / tranche.getGlobalScales().maxscale), adapter.scale()),
            0.000_000_1 * 1e18,
            "underlying withdrawn"
        );
    }

    /////////////////////////////////////////////////////////////////////
    /// WITHDRAW
    /////////////////////////////////////////////////////////////////////

    /// @inheritdoc BaseTestTranche
    function testWithdraw_WhenSunnyday() public override setUpBuffer {
        super.testWithdraw_WhenSunnyday();
    }

    /// @inheritdoc BaseTestTranche
    function testWithdraw_WhenNotSunnyday() public override setUpBuffer {
        super.testWithdraw_WhenNotSunnyday();
    }

    /// @notice Test withdrawing underlying under sunnyday/ not sunnyday condition
    ///         - PT should be burned
    ///         - Target should be redeemed
    ///         - YT balance should not change
    ///         - Receiver should receive underlying
    function _testWithdraw(
        uint256 underlyingAmount,
        address to,
        address from,
        address caller
    ) internal override returns (uint256) {
        // pre-execution state
        uint256 balBefore = tranche.balanceOf(from);
        uint256 yBal = yt.balanceOf(from);
        uint256 tBal = target.balanceOf(address(tranche));

        uint256 cscale = adapter.scale();
        uint256 expectedBurned = tranche.convertToPrincipal(underlyingAmount);
        // execution
        _approve(address(tranche), from, caller, type(uint256).max);
        vm.prank(caller);
        uint256 ptRedeemed = tranche.withdraw(underlyingAmount, to, from);
        // assert
        assertApproxLeAbs(expectedBurned, ptRedeemed, 10, "underlying withdrawn");
        assertEq(tranche.balanceOf(from), balBefore - ptRedeemed, "balance");
        assertEq(yt.balanceOf(from), yBal, "yt balance shouldn't change");
        assertEq(target.balanceOf(address(adapter)), 0, "no funds left in adapter");
        // note: Precision loss occurs here.
        assertApproxEqAbs(underlying.balanceOf(to), underlyingAmount, 100, "balance ~= underlying withdrawn"); // diff should be 0 in theory.
        assertApproxEqAbs(
            target.balanceOf(address(tranche)),
            tBal - _convertToShares(underlyingAmount, cscale),
            _DELTA_,
            "target balance"
        );
        return ptRedeemed;
    }

    /////////////////////////////////////////////////////////////////////
    /// UPDATE UNCLAIMED YIELD FUZZ
    /////////////////////////////////////////////////////////////////////

    modifier boundUpdateUnclaimedYieldFuzzArgs(UpdateUnclaimedYieldFuzzArgs memory args) override {
        vm.assume(args.accounts[0] != address(0) && args.accounts[1] != address(0));
        vm.assume(accountsExcludedFromFuzzing[args.accounts[0]] == false);
        vm.assume(accountsExcludedFromFuzzing[args.accounts[1]] == false);
        args.cscale = bound(args.cscale, 1e10, RAY);
        args.uDeposits[0] = bound(args.uDeposits[0], MIN_UNDERLYING_DEPOSIT, MAX_UNDERLYING_DEPOSIT);
        args.uDeposits[1] = bound(args.uDeposits[1], MIN_UNDERLYING_DEPOSIT, MAX_UNDERLYING_DEPOSIT);
        args.unclaimedYields[0] = bound(args.unclaimedYields[0], 0, MAX_UNDERLYING_DEPOSIT);
        args.unclaimedYields[1] = bound(args.unclaimedYields[1], 0, MAX_UNDERLYING_DEPOSIT);
        args.yAmountTransfer = bound(args.yAmountTransfer, 0, args.uDeposits[0]);
        _;
    }

    /// @notice It'll take a long time to run this fuzz test. Run it with a small number of runs.
    /// forge-config: default.fuzz.runs = 100
    /// forge-config: deep_fuzz.fuzz.runs = 500
    /// @inheritdoc BaseTestTranche
    function testFuzz_UpdateUnclaimedYield_FromIsTo(
        UpdateUnclaimedYieldFuzzArgs memory args,
        uint32 newTimestamp
    ) public override {
        super.testFuzz_UpdateUnclaimedYield_FromIsTo(args, newTimestamp);
    }

    /// forge-config: default.fuzz.runs = 100
    /// forge-config: deep_fuzz.fuzz.runs = 500
    /// @inheritdoc BaseTestTranche
    function testFuzz_UpdateUnclaimedYield_FromIsNotTo_NonZeroTransfer_LscaleZero(
        UpdateUnclaimedYieldFuzzArgs memory args,
        uint32 newTimestamp
    ) public override {
        super.testFuzz_UpdateUnclaimedYield_FromIsNotTo_NonZeroTransfer_LscaleZero(args, newTimestamp);
    }

    /// forge-config: default.fuzz.runs = 100
    /// forge-config: deep_fuzz.fuzz.runs = 500
    /// @inheritdoc BaseTestTranche
    function testFuzz_UpdateUnclaimedYield_FromIsNotTo_NonZeroTransfer_LscaleNonZero(
        UpdateUnclaimedYieldFuzzArgs memory args,
        uint32 newTimestamp
    ) public override {
        super.testFuzz_UpdateUnclaimedYield_FromIsNotTo_NonZeroTransfer_LscaleNonZero(args, newTimestamp);
    }

    /// forge-config: default.fuzz.runs = 100
    /// forge-config: deep_fuzz.fuzz.runs = 500
    /// @inheritdoc BaseTestTranche
    function testFuzz_UpdateUnclaimedYield_FromIsNotTo_ZeroTransfer(
        UpdateUnclaimedYieldFuzzArgs memory args,
        uint32 newTimestamp
    ) public override {
        super.testFuzz_UpdateUnclaimedYield_FromIsNotTo_ZeroTransfer(args, newTimestamp);
    }

    /////////////////////////////////////////////////////////////////////
    /// COLLECT
    /////////////////////////////////////////////////////////////////////

    /// @inheritdoc BaseTestTranche
    function testCollect_BeforeMaturity_ScaleIncrease() public override setUpBuffer {
        super.testCollect_BeforeMaturity_ScaleIncrease();
    }

    /// @inheritdoc BaseTestTranche
    function testCollect_BeforeMaturity_ScaleDecrease() public override setUpBuffer {
        super.testCollect_BeforeMaturity_ScaleDecrease();
    }

    /// @inheritdoc BaseTestTranche
    function testCollect_AfterMaturity_ScaleIncrease_WhenSunnyday() public override setUpBuffer {
        super.testCollect_AfterMaturity_ScaleIncrease_WhenSunnyday();
    }

    /// @inheritdoc BaseTestTranche
    function testCollect_AfterMaturity_ScaleIncrease_WhenNotSunnyday() public override setUpBuffer {
        super.testCollect_AfterMaturity_ScaleIncrease_WhenNotSunnyday();
    }

    /// @inheritdoc BaseTestTranche
    function testCollect_AfterMaturity_ScaleDecrease_WhenSunnyday() public override setUpBuffer {
        super.testCollect_AfterMaturity_ScaleDecrease_WhenSunnyday();
    }

    /// @inheritdoc BaseTestTranche
    function testCollect_AfterMaturity_ScaleDecrease_WhenNotSunnyday_UnclaimedYieldZero() public override setUpBuffer {
        super.testCollect_AfterMaturity_ScaleDecrease_WhenNotSunnyday_UnclaimedYieldZero();
    }

    /// @inheritdoc BaseTestTranche
    function testCollect_AfterMaturity_ScaleDecrease_WhenNotSunnyday_UnclaimedYieldNonZero()
        public
        override
        setUpBuffer
    {
        super.testCollect_AfterMaturity_ScaleDecrease_WhenNotSunnyday_UnclaimedYieldNonZero();
    }

    /////////////////////////////////////////////////////////////////////
    /// COLLECT FUZZ
    /////////////////////////////////////////////////////////////////////

    modifier boundCollectFuzzArgs(CollectFuzzArgs memory args) override {
        vm.assume(args.caller != address(0));
        vm.assume(accountsExcludedFromFuzzing[args.caller] == false);
        args.cscale = bound(args.cscale, 1e16, 1e22);
        args.uDeposit = bound(args.uDeposit, MIN_UNDERLYING_DEPOSIT, MAX_UNDERLYING_DEPOSIT);
        _;
    }

    /// @dev It'll take a long time to run this fuzz test. Run it with a small number of runs.
    /// forge-config: default.fuzz.runs = 100
    /// forge-config: deep_fuzz.fuzz.runs = 500
    function testFuzz_Collect_BeforeMaturity(
        CollectFuzzArgs memory args,
        uint32 newTimestamp
    ) public override boundCollectFuzzArgs(args) setUpBuffer {
        super.testFuzz_Collect_BeforeMaturity(args, newTimestamp);
    }

    /// @dev It'll take a long time to run this fuzz test. Run it with a small number of runs.
    /// forge-config: default.fuzz.runs = 100
    /// forge-config: deep_fuzz.fuzz.runs = 500
    function testFuzz_Collect_AfterMaturity(
        CollectFuzzArgs memory args,
        uint32 newTimestamp
    ) public override setUpBuffer {
        super.testFuzz_Collect_AfterMaturity(args, newTimestamp);
    }

    /////////////////////////////////////////////////////////////////////
    /// PREVIEW REDEEM / PREVIEW WITHDRAW
    /////////////////////////////////////////////////////////////////////

    modifier boundPreviewFuncFuzzArgs(PreviewFuncFuzzArgs memory args) override {
        vm.assume(args.caller != address(0) && args.owner != address(0));
        vm.assume(accountsExcludedFromFuzzing[args.caller] == false);
        vm.assume(accountsExcludedFromFuzzing[args.owner] == false);
        args.uDeposit = bound(args.uDeposit, MIN_UNDERLYING_DEPOSIT, MAX_UNDERLYING_DEPOSIT);
        _;
    }

    /// forge-config: default.fuzz.runs = 100
    function testPreviewRedeem_AfterMaturity(
        PreviewFuncFuzzArgs memory args,
        uint32 newTimestamp
    ) public override setUpBuffer {
        super.testPreviewRedeem_AfterMaturity(args, newTimestamp);
    }

    /// forge-config: default.fuzz.runs = 100
    function testPreviewWithdraw_AfterMaturity(
        PreviewFuncFuzzArgs memory args,
        uint32 newTimestamp
    ) public override setUpBuffer {
        super.testPreviewWithdraw_AfterMaturity(args, newTimestamp);
    }
}
