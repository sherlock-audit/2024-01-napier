// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../../shared/BaseTestTranche.t.sol";

import {ERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";

import {CETHFixture} from "./Fixture.sol";
import {WrappedCETHAdapter} from "src/adapters/compoundV2/WrappedCETHAdapter.sol";

contract TestCompoundTranche is BaseTestTranche, CETHFixture {
    using stdStorage for StdStorage;

    function setUp() public virtual override(CompleteFixture, CETHFixture) {
        CETHFixture.setUp();
    }

    //////////////////////////////////////////////////////////////////
    /// OVERRIDE
    //////////////////////////////////////////////////////////////////

    /// @notice Test first issuance of PT+YT
    /// @dev when call assertApproxEqAbs(), max_delta should be reset for CompoundV2
    /// underlying decimals(18) != target decimals(8), this means if target amount delta is one,
    /// underlying amount delta can be 10^10 at most.  this delta should be affected only in CompoundV2.
    function testIssue_Ok() public override {
        // setup
        uint256 amount = 100 * ONE_SCALE;
        uint256 cscale = adapter.scale();
        uint256 shares = _convertToShares(amount, cscale);
        uint256 fee = _getIssuanceFee(shares); // imposed by Napier
        // execution
        uint256 issued = tranche.issue(user, amount);
        // assert
        assertEq(tranche.balanceOf(user), issued, "user balance of pt");
        assertEq(yt.balanceOf(user), issued, "yt balance of pt");
        assertEq(tranche.totalSupply(), issued, "total supply");
        assertEq(tranche.issuanceFees(), fee, "accumulated fee");
        assertApproxEqRel(
            (amount * (MAX_BPS - _issuanceFee)) / MAX_BPS,
            issued,
            0.000_000_000_1 * 1e18,
            "issued amount should be reduced by fee"
        );
        assertApproxEqRel(target.balanceOf(address(tranche)), shares, 0.000_000_000_1 * 1e18, "target balance of pt");
        assertEq(target.balanceOf(address(adapter)), 0, "zero target balance");
        uint256 cmaxscale = Math.max(cscale, tranche.getGlobalScales().maxscale);
        assertEq(tranche.lscales(user), cmaxscale, "lscale should be updated to max scale");
    }

    /// @notice Round trip test
    ///     Issue PT+YT and then redeem all PT+YT
    ///     - `underlyingWithdrawn` should be equal to `uDeposit` subtracted by fee
    function testRT_Issue_RedeemWithYT_Immediately(uint256 uDeposit) public override {
        uDeposit = bound(uDeposit, MIN_UNDERLYING_DEPOSIT, initialBalance);
        uint256 prevBalance = underlying.balanceOf(address(this));
        _testRT_Issue_RedeemWithYT(uDeposit, noop); // scale does not change
        assertApproxEqRel(
            underlying.balanceOf(address(this)) + _getIssuanceFee(uDeposit),
            prevBalance,
            0.000_000_000_1 * 1e18,
            "underlying withdrawn should be equal to uDeposit subtracted by fee"
        );
    }

    /// @notice Round trip test with scale increase
    ///     Issue PT+YT and then redeem all PT+YT
    /// @param uDeposit amount of underlying to deposit
    function testRT_Issue_RedeemWithYT_ScaleIncrease(uint256 uDeposit) public override {
        uDeposit = bound(uDeposit, MIN_UNDERLYING_DEPOSIT, initialBalance); // 100 is the minimum deposit to make sure accrued yield is not 0
        uint256 prevBalance = underlying.balanceOf(address(this));
        _testRT_Issue_RedeemWithYT(uDeposit, _simulateScaleIncrease);
        assertGt(
            underlying.balanceOf(address(this)) + _getIssuanceFee(uDeposit),
            prevBalance,
            "underlying withdrawn should be greater than uDeposit subtracted by fee"
        );
    }

    /// @notice Round trip test with scale decrease
    ///     Issue PT+YT and then redeem all PT+YT
    /// @param uDeposit amount of underlying to deposit
    function testRT_Issue_RedeemWithYT_ScaleDecrease(uint256 uDeposit) public override {
        uDeposit = bound(uDeposit, MIN_UNDERLYING_DEPOSIT, initialBalance);
        uint256 prevBalance = underlying.balanceOf(address(this));
        _testRT_Issue_RedeemWithYT(uDeposit, _simulateScaleDecrease);
        assertLt(
            underlying.balanceOf(address(this)) + _getIssuanceFee(uDeposit),
            prevBalance,
            "underlying withdrawn should be less than uDeposit subtracted by fee"
        );
    }

    /////////////////////////////////////////////////////////////////
    /// MODIFIERS
    /////////////////////////////////////////////////////////////////
    // The modifiers below are used to bound the fuzz args.
    // NOTE: address type is bounded to `user` or `address(this)` instead of random addresses.
    // because it will run out of rpc resources and very slow if we use random addresses.

    /// @dev Bound fuzz args for `testUpdateUnclaimedYield`.
    modifier boundUpdateUnclaimedYieldFuzzArgs(UpdateUnclaimedYieldFuzzArgs memory args) override {
        vm.assume(args.accounts[0] != address(0) && args.accounts[1] != address(0));
        args.accounts[0] = address(this);
        args.accounts[1] = user;
        args.cscale = bound(args.cscale, (ONE_TARGET * 8) / 10, ONE_TARGET * 2);
        args.uDeposits[0] = bound(args.uDeposits[0], MIN_UNDERLYING_DEPOSIT, FUZZ_UNDERLYING_DEPOSIT_CAP);
        args.uDeposits[1] = bound(args.uDeposits[1], MIN_UNDERLYING_DEPOSIT, FUZZ_UNDERLYING_DEPOSIT_CAP);
        args.unclaimedYields[0] = bound(args.unclaimedYields[0], 0, FUZZ_UNDERLYING_DEPOSIT_CAP);
        args.unclaimedYields[1] = bound(args.unclaimedYields[1], 0, FUZZ_UNDERLYING_DEPOSIT_CAP);
        args.yAmountTransfer = bound(args.yAmountTransfer, 0, args.uDeposits[0]);
        _;
    }

    /// @dev Bound fuzz args for `testCollect`.
    modifier boundCollectFuzzArgs(CollectFuzzArgs memory args) override {
        vm.assume(args.caller != address(0));
        args.caller = address(this);
        args.cscale = bound(args.cscale, (ONE_TARGET * 8) / 10, ONE_TARGET * 2);
        args.uDeposit = bound(args.uDeposit, MIN_UNDERLYING_DEPOSIT, FUZZ_UNDERLYING_DEPOSIT_CAP);
        _;
    }

    /// @dev Bound fuzz args for `testPreview**` and `testMax**`.
    modifier boundPreviewFuncFuzzArgs(PreviewFuncFuzzArgs memory args) override {
        vm.assume(args.caller != address(0) && args.owner != address(0));
        args.caller = address(this);
        args.owner = user;
        args.uDeposit = bound(args.uDeposit, MIN_UNDERLYING_DEPOSIT, FUZZ_UNDERLYING_DEPOSIT_CAP);
        _;
    }

    function deal(
        address token,
        address to,
        uint256 give,
        bool adjust
    ) internal virtual override(StdCheats, CETHFixture) {
        CETHFixture.deal(token, to, give, adjust);
    }
}
