// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../shared/BaseTestTranche.t.sol";

import {MorphoFixture} from "./Fixture.sol";

contract TestMorphoTranche is BaseTestTranche, MorphoFixture {
    using stdStorage for StdStorage;

    function setUp() public virtual override(CompleteFixture, MorphoFixture) {
        MorphoFixture.setUp();
    }

    //////////////////////////////////////////////////////////////////
    /// OVERRIDE
    //////////////////////////////////////////////////////////////////

    /// @notice Test first issuance of PT+YT
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
        assertApproxEqAbs(
            (amount * (MAX_BPS - _issuanceFee)) / MAX_BPS,
            issued,
            40,
            "issued amount should be reduced by fee"
        );
        assertApproxEqAbs(target.balanceOf(address(tranche)), shares, 40, "target balance of pt");
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
        assertApproxEqAbs(
            underlying.balanceOf(address(this)) + _getIssuanceFee(uDeposit),
            prevBalance,
            40,
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

    function testFuzz_Collect_AfterMaturity(
        CollectFuzzArgs memory args,
        uint32 newTimestamp
    ) public override boundCollectFuzzArgs(args) {
        deal(address(underlying), args.caller, args.uDeposit);
        _issue(args.caller, args.caller, args.uDeposit);
        // Aave may revert with error code 50 `BORROW_CAP_EXCEEDED` if the timestamp is too large.
        // so we bound the timestamp to be less than 300 days after maturity.
        // https://github.com/aave/aave-v3-core/blob/6070e82d962d9b12835c88e68210d0e63f08d035/contracts/protocol/libraries/helpers/Errors.sol#L58C72-L58C80
        // https://github.com/aave/aave-v3-core/blob/6070e82d962d9b12835c88e68210d0e63f08d035/contracts/protocol/libraries/logic/ValidationLogic.sol#L192C22-L192C31
        newTimestamp = boundU32(newTimestamp, _maturity, _maturity + 300 days);
        vm.warp(newTimestamp);
        _testFuzz_Collect(args);
    }

    /// @notice Test redeeming PT under sunnyday condition
    ///         - PT should be burned
    ///         - Target should be redeemed based on not sunnyday condition
    /// @param amountToRedeem amount of PT to redeem (less than issued amount)
    function testRedeem_WhenNotSunnyday(uint256 amountToRedeem) public override {
        // setup
        uint256 amount = 100 * ONE_SCALE;
        uint256 issued = _issue(address(this), user, amount);
        vm.warp(_maturity + 7 days);
        amountToRedeem = bound(amountToRedeem, 100, issued);
        // scale increases after issue
        _simulateScaleDecrease();
        // before that, save the value of adapter.scale()
        uint256 scale = adapter.scale();
        // execution
        uint256 underlyingWithdrawn = _testRedeem(amountToRedeem, user, user, user);
        // assert
        assertEq(_isSunnyDay(), false, "not sunnyday");
        assertApproxEqRel(
            underlyingWithdrawn,
            _convertToUnderlying(((amountToRedeem * WAD) / tranche.getGlobalScales().maxscale), scale),
            0.000_000_1 * 1e18,
            "underlying withdrawn"
        );
    }

    /////////////////////////////////////////////////////////////////////
    /// REDEEM WITH YT FUZZ
    /////////////////////////////////////////////////////////////////////

    /// @notice Test redeeming PT with YT
    ///         - PT+YT should be burned
    ///         - Accrued yield should be sent to user
    /// @param amountRedeem amount of PT+YT to redeem
    /// @param newTimestamp new timestamp to warp to
    function testRedeemWithYT_ScaleIncrease(uint256 amountRedeem, uint32 newTimestamp) public override {
        uint256 amount = 100 * ONE_SCALE;
        uint256 issued = _issue(address(this), address(this), amount);
        amountRedeem = bound(amountRedeem, 100, issued);
        // if newTimestamp < block.timestamp, can't get atoken balance
        // if the new Timestamp is too large, the scale would be much greater than the previous one.
        // so when we withdraw asset from Morpho, it could be reverted.
        newTimestamp = boundU32(newTimestamp, block.timestamp, _maturity * 2);
        _testRedeemWithYT(issued, amountRedeem, _simulateScaleIncrease, newTimestamp);
    }

    /// @notice Test redeeming PT with YT
    ///         - PT+YT should be burned
    ///         - There should be no accrued yield
    /// @param amountRedeem amount of PT+YT to redeem
    /// @param newTimestamp new timestamp to warp to
    function testRedeemWithYT_ScaleDecrease(uint256 amountRedeem, uint32 newTimestamp) public override {
        uint256 amount = 100 * ONE_SCALE;
        uint256 issued = _issue(address(this), address(this), amount);
        // adapter.scale() can decrease to scale()/10, so if amountRedeem is smaller than 10, redeemed amount would be 0.
        // Aave doesn't allow zero-value minting. It'll revert with `INVALID_MINT_AMOUNT` error.
        // https://docs.aave.com/developers/v/2.0/guides/troubleshooting-errors
        amountRedeem = bound(amountRedeem, 100, issued);
        // if newTimestamp < block.timestamp, can't get atoken balance.
        // if the new Timestamp is too large, the scale would be much greater than the previous one.
        // so when we withdraw asset from Morpho, it could be reverted.
        newTimestamp = boundU32(newTimestamp, block.timestamp, _maturity * 2);
        _testRedeemWithYT(issued, amountRedeem, _simulateScaleDecrease, newTimestamp);
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
    ) internal virtual override(StdCheats, MorphoFixture) {
        MorphoFixture.deal(token, to, give, adjust);
    }
}
