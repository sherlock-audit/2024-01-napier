// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../shared/BaseTestTranche.t.sol";

import {ERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";

import {RETHFixture} from "./Fixture.sol";
import {RETHAdapter} from "src/adapters/rocketPool/RETHAdapter.sol";
import {RocketPoolHelper} from "../../utils/RocketPoolHelper.sol";

contract TestRETHTranche is BaseTestTranche, RETHFixture {
    using stdStorage for StdStorage;

    function setUp() public virtual override(CompleteFixture, RETHFixture) {
        RETHFixture.setUp();
    }

    //////////////////////////////////////////////////////////////////
    /// OVERRIDE
    //////////////////////////////////////////////////////////////////

    /// @notice Test first issuance of PT+YT
    function testIssue_Ok() public override {
        // setup
        uint256 amount = 100 * ONE_SCALE;
        uint256 cscale = adapter.scale();
        uint256 depositFee = RocketPoolHelper.getDepositFee(amount); // imposed by RocketPool
        uint256 shares = _convertToShares(amount - depositFee, cscale);
        uint256 fee = _getIssuanceFee(shares); // imposed by Napier
        // execution
        uint256 issued = tranche.issue(user, amount);
        // assert
        assertEq(tranche.balanceOf(user), issued, "user balance of pt");
        assertEq(yt.balanceOf(user), issued, "yt balance of pt");
        assertEq(tranche.totalSupply(), issued, "total supply");
        assertEq(tranche.issuanceFees(), fee, "accumulated fee");
        assertApproxEqAbs(
            ((amount - depositFee) * (MAX_BPS - _issuanceFee)) / MAX_BPS,
            issued,
            40,
            "issued amount should be reduced by fee"
        );
        assertApproxEqAbs(target.balanceOf(address(tranche)), shares, 40, "target balance of pt");
        assertEq(target.balanceOf(address(adapter)), 0, "zero target balance");
        uint256 cmaxscale = Math.max(cscale, tranche.getGlobalScales().maxscale);
        assertEq(tranche.lscales(user), cmaxscale, "lscale should be updated to max scale");
    }

    /// @notice Test issuance of PT+YT on top of existing PT+YT
    /// @dev when scale has increased since last issuance, accrued yield should be reinvested
    /// - issuance fee should be applied to the total amount (i.e. deposited + accrued yield)
    function testIssue_ReinvestIfScaleIncrease() public override {
        // setup
        uint256 amount = 100 * ONE_SCALE;
        uint256 issued1 = tranche.issue(address(this), amount);
        // pre-state
        uint256 preTargetBal = target.balanceOf(address(tranche));
        uint256 preFee = tranche.issuanceFees();
        uint256 preLscale = tranche.lscales(address(this));
        // execution
        _simulateScaleIncrease();
        uint256 issued2 = tranche.issue(address(this), amount);
        // post-state
        uint256 yieldInTarget = _calculateYieldRoundDown(issued1, preLscale, tranche.getGlobalScales().maxscale);
        uint256 depositFee = RocketPoolHelper.getDepositFee(amount); // imposed by RocketPool
        uint256 shares = _convertToShares(amount - depositFee, adapter.scale());
        // assert
        assertGt(issued2, issued1, "issued amount should greater than previous thanks to accrued yield");
        assertEq(tranche.balanceOf(address(this)), issued1 + issued2, "balance");
        assertEq(yt.balanceOf(address(this)), issued1 + issued2, "yt balance");
        assertEq(tranche.totalSupply(), issued1 + issued2, "total supply");
        assertApproxEqAbs(target.balanceOf(address(tranche)), preTargetBal + shares, _DELTA_ + 1, "target balance");
        assertApproxEqAbs(
            tranche.issuanceFees(),
            preFee + _getIssuanceFee(shares + yieldInTarget),
            _DELTA_ + 1,
            "accumulated fee"
        );
    }

    /// @notice Round trip test
    ///     Issue PT+YT and then redeem all PT+YT
    ///     - `underlyingWithdrawn` should be equal to `uDeposit` subtracted by fee
    function testRT_Issue_RedeemWithYT_Immediately(uint256 uDeposit) public override {
        uDeposit = bound(uDeposit, MIN_UNDERLYING_DEPOSIT, initialBalance);
        uint256 prevBalance = underlying.balanceOf(address(this));
        _testRT_Issue_RedeemWithYT(uDeposit, noop); // scale does not change
        assertApproxEqAbs(
            underlying.balanceOf(address(this)) + _getIssuanceFee(uDeposit) + RocketPoolHelper.getDepositFee(uDeposit),
            prevBalance,
            // in theory users can't get back more than uDeposit subtracted by fee.
            // the following should be true:
            // uWithdrawn ~= uDeposit - fee AND uWithdrawn - (uDeposit + fee) < 0
            2 * _DELTA_, // 2x tolerance
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
            underlying.balanceOf(address(this)) + _getIssuanceFee(uDeposit) + RocketPoolHelper.getDepositFee(uDeposit),
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
            underlying.balanceOf(address(this)) + _getIssuanceFee(uDeposit) + RocketPoolHelper.getDepositFee(uDeposit),
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
    ) internal virtual override(StdCheats, RETHFixture) {
        RETHFixture.deal(token, to, give, adjust);
    }
}
