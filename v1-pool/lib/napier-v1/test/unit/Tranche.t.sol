// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../shared/BaseTestTranche.t.sol";
import {Math} from "@openzeppelin/contracts@4.9.3/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts@4.9.3/utils/math/SafeCast.sol";

import {BaseAdapter} from "src/BaseAdapter.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockAdapter} from "../mocks/MockAdapter.sol";
import {MAX_BPS} from "src/Constants.sol";

/// @notice Helper contract to test the Tranche contract
contract TrancheHarness is Tranche {
    function setGlobalScales(GlobalScales memory _gscales) public {
        gscales = _gscales;
    }

    function burnFrom(address _account, uint256 _amount) public {
        _burnFrom(_account, _amount);
    }

    function updateGlobalScales() public {
        GlobalScales memory _gscales = gscales;
        _updateGlobalScalesCache(_gscales);
        gscales = _gscales;
    }

    function computeSharesRedeemed(
        GlobalScales memory _gscales,
        uint256 _principalAmount
    ) public view returns (uint256) {
        return _computeSharesRedeemed(_gscales, _principalAmount);
    }

    function computePrincipalTokenRedeemed(
        GlobalScales memory _gscales,
        uint256 _shares
    ) public view returns (uint256) {
        return _computePrincipalTokenRedeemed(_gscales, _shares);
    }

    function computeAccruedInterestInTarget(
        uint256 _maxscale,
        uint256 _lscale,
        uint256 _yBal
    ) public pure returns (uint256 accruedInTarget) {
        accruedInTarget = _computeAccruedInterestInTarget(_maxscale, _lscale, _yBal);
    }
}

/// @notice Mock factory that allows to set the init args
contract MockFactoryCallbackReceiver is TrancheFactory {
    constructor(address _management) TrancheFactory(_management) {}

    function setArgs(TrancheInitArgs memory _args) external {
        _tempArgs = _args;
    }
}

contract TestTranche is BaseTestTranche {
    using Cast for *;
    using SafeCast for uint256;

    function setUp() public virtual override {
        vm.warp(365 days);
        _maturity = block.timestamp + 90 days;
        _tilt = 10;
        _issuanceFee = 100;
        _DELTA_ = 2;

        super.setUp();

        initialBalance = 1000 * ONE_SCALE;
        MAX_UNDERLYING_DEPOSIT = 1e9 * ONE_SCALE; // 1B

        // fund tokens
        deal(address(underlying), address(this), initialBalance, true);
        _approve(address(underlying), address(this), address(tranche), type(uint256).max);
    }

    function _deployTranche() internal override {
        // deploy factory
        factory = new MockFactoryCallbackReceiver(management);
        bytes32 salt = keccak256(abi.encodePacked(adapter, _maturity));
        address create2Addr = computeCreate2Address(
            salt,
            hashInitCode(type(TrancheHarness).creationCode),
            address(factory)
        );
        address underlying = adapter.underlying();
        // deploy yield token
        yt = new YieldToken(address(create2Addr), underlying, address(target), _maturity);
        // prepare init args
        factory.asMock().setArgs(
            ITrancheFactory.TrancheInitArgs({
                adapter: address(adapter),
                maturity: uint32(_maturity),
                tilt: uint16(_tilt),
                issuanceFee: uint16(_issuanceFee),
                yt: address(yt),
                management: management
            })
        );
        // deploy tranche from factory
        vm.prank(address(factory));
        tranche = new TrancheHarness{salt: salt}();
        require(address(tranche) == create2Addr, "Tranche address mismatch");
    }

    function _deployAdapter() internal override {
        // USDC mock
        underlying = new MockERC20("Underlying", "U", 6);
        target = new MockERC20("Target", "T", 6);

        adapter = new MockAdapter(address(underlying), address(target));

        accountsExcludedFromFuzzing[address(adapter.asMock().lendingProtocol())] = true;
    }

    /////////////////////////////////////////////////////////////////////
    /// ERC20
    /////////////////////////////////////////////////////////////////////

    function testBurnFrom_WhenFromIsOwner() public virtual {
        //setUp
        uint256 amount = 100;
        deal(address(tranche), address(this), amount, true);
        uint256 totalSupply = tranche.totalSupply();
        //execution
        vm.prank(address(this));
        tranche.asHarness().burnFrom(address(this), amount);
        //assert
        assertEq(tranche.balanceOf(address(this)), 0, "burnFrom should burn tokens");
        assertEq(tranche.totalSupply(), totalSupply - amount, "totalSupply should decrease");
    }

    function testBurnFrom_WhenFromIsNotOwner_Ok() public virtual {
        //setUp
        uint256 amount = 100;
        deal(address(tranche), address(this), amount, true);
        uint256 totalSupply = tranche.totalSupply();
        //execution
        _approve(address(tranche), address(this), user, amount);
        vm.prank(user);
        tranche.asHarness().burnFrom(address(this), amount);
        //assert
        assertEq(tranche.balanceOf(address(this)), 0, "burnFrom should burn tokens");
        assertEq(tranche.totalSupply(), totalSupply - amount, "totalSupply should decrease");
        assertEq(tranche.allowance(address(this), user), 0, "allowance should decrease");
    }

    function testBurnFrom_WhenFromIsNotOwner_RevertIfInsufficientAllowance() public virtual {
        //setUp
        uint256 amount = 100;
        deal(address(tranche), address(this), amount, true);
        //execution & assert
        vm.expectRevert("ERC20: insufficient allowance");
        vm.prank(user);
        tranche.asHarness().burnFrom(address(this), amount);
    }

    /////////////////////////////////////////////////////////////////////
    /// INTERNAL FUNCTIONS
    /////////////////////////////////////////////////////////////////////

    /// @dev maxscale should be updated if current scale is larger than last maxscale.
    ///      mscale (scale at maturity)
    function testFuzz_UpdateScales_BeforeMaturity_Ok(uint128 scale, uint32 newTimestamp) public virtual {
        vm.warp(newTimestamp);
        vm.assume(!_isMatured() && scale > 0);
        uint128 maxscale = gscalesCache.maxscale;
        _testFuzz_UpdateScales(0, scale);
        // assert
        if (scale > maxscale) {
            assertEq(tranche.getGlobalScales().maxscale, scale, "maxscale should be updated");
        } else {
            assertEq(tranche.getGlobalScales().maxscale, maxscale, "maxscale should not change");
        }
        assertEq(tranche.getGlobalScales().mscale, 0, "mscale zero");
    }

    function testFuzz_UpdateScales_AfterMaturity_NotSettled_Ok(uint128 scale, uint32 newTimestamp) public virtual {
        vm.warp(newTimestamp);
        vm.assume(_isMatured() && scale > 0);
        uint128 maxscale = gscalesCache.maxscale;
        _testFuzz_UpdateScales(0, scale);
        // assert
        if (scale > maxscale) {
            assertEq(tranche.getGlobalScales().maxscale, scale, "maxscale should be updated");
        } else {
            assertEq(tranche.getGlobalScales().maxscale, maxscale, "maxscale should not change");
        }
        assertEq(tranche.getGlobalScales().mscale, scale, "mscale is updated");
    }

    function testFuzz_UpdateScales_AfterMaturity_AlreadySettled_Ok(
        uint128 mscale,
        uint128 scale,
        uint32 newTimestamp
    ) public virtual {
        vm.warp(newTimestamp);
        vm.assume(_isMatured() && scale > 0 && mscale > 0);
        uint128 maxscale = gscalesCache.maxscale;
        _testFuzz_UpdateScales(mscale, scale);
        assertEq(tranche.getGlobalScales().maxscale, maxscale, "maxscale should be updated");
        assertEq(tranche.getGlobalScales().mscale, mscale, "mscale should not be updated");
    }

    function _testFuzz_UpdateScales(uint128 mscale, uint128 cscale) internal {
        gscalesCache.mscale = mscale;
        tranche.asHarness().setGlobalScales(gscalesCache);
        vm.mockCall(address(adapter), abi.encodeWithSelector(IBaseAdapter.scale.selector), abi.encode(cscale));
        // execution
        tranche.asHarness().updateGlobalScales();
        vm.clearMockedCalls();
    }

    /////////////////////////////////////////////////////////////////////
    /// round trip properties
    /////////////////////////////////////////////////////////////////////

    // computeSharesRedeemed(computePrincipalTokenRedeemed(x)) <=~ x
    function testRT_ComputeShares_ComputePrincipal(
        uint128 mscale,
        uint128 maxscale,
        uint128 principalAmount
    ) public virtual {
        mscale = bound(mscale, 1, RAY).toUint128();
        maxscale = bound(maxscale, 1, RAY).toUint128();
        gscalesCache.mscale = mscale;
        gscalesCache.maxscale = maxscale;

        uint256 shares = tranche.asHarness().computeSharesRedeemed(gscalesCache, principalAmount);
        uint256 principal_ = tranche.asHarness().computePrincipalTokenRedeemed(gscalesCache, shares);
        assertApproxLeAbs(principal_, principalAmount, 3, "prop/shares->principal->shares");
    }

    // computePrincipalTokenRedeemed(computeSharesRedeemed(s)) <=~ s
    function testRT_ComputePrincipal_ComputeShares(uint128 mscale, uint128 maxscale, uint128 shares) public virtual {
        mscale = bound(mscale, 1, RAY).toUint128();
        maxscale = bound(maxscale, 1, RAY).toUint128();
        gscalesCache.mscale = mscale;
        gscalesCache.maxscale = maxscale;

        uint256 principal = tranche.asHarness().computePrincipalTokenRedeemed(gscalesCache, shares);
        uint256 shares_ = tranche.asHarness().computeSharesRedeemed(gscalesCache, principal);
        assertApproxLeAbs(shares_, shares, 3, "prop/principal->shares->principal");
    }

    function testComputeSharesRedeemed_WhenSunnyday() public virtual {}

    function testComputeSharesRedeemed_WhenNotSunnyday() public virtual {}

    function testComputePrincipalTokenRedeemed_WhenSunnyday() public virtual {}

    function testComputePrincipalTokenRedeemed_WhenNotSunnyday() public virtual {}

    function testComputeaccruedInterestInTarget_Zero(uint256 maxscale) public virtual {
        maxscale = bound(maxscale, 1, RAY);
        uint256 yBal = 1000 * ONE_SCALE; // 1000 YT
        uint256 lscale = (ONE_SCALE * 12) / 10;
        vm.assume(maxscale <= lscale);
        uint256 accruedInterest = tranche.asHarness().computeAccruedInterestInTarget(maxscale, lscale, yBal);
        assertEq(accruedInterest, 0, "accruedInterest should be zero");
    }

    function testComputeaccruedInterestInTarget_NonZero() public virtual {
        uint256 yBal = 1000 * ONE_SCALE; // 1000 YT
        uint256 lscale = (ONE_SCALE * 12) / 10;
        uint256 maxscale = (ONE_SCALE * 15) / 10;
        uint256 accrued = tranche.asHarness().computeAccruedInterestInTarget(maxscale, lscale, yBal);
        // 1.2 underlying per Target -> 1.5 underlying per Target
        // 1000/1.2 = 833.3333 initial Target equivalent to 1000 underlying
        // => now 833.3333 * 1.5 = 1250 underlying
        // == 250 underlying accrued
        assertApproxEqRel((accrued * maxscale) / WAD, 250 * ONE_SCALE, 0.000_000_1 * 1e18, "equivalent underlying"); // 1e18 == 100%
    }

    /////////////////////////////////////////////////////////////////////
    /// CONVERT TO UNDERLYING / CONVERT TO PRINCIPAL
    /////////////////////////////////////////////////////////////////////

    function testConvertToUnderlying_BeforeSettlement(uint256 principal, uint256 cscale) public virtual {
        cscale = bound(cscale, 1, RAY);
        principal = bound(principal, 0, MAX_UINT128);
        // setup
        vm.mockCall(address(adapter), abi.encodeWithSelector(IBaseAdapter.scale.selector), abi.encode(cscale));
        // simulate the settlement as if it is settled now
        gscalesCache.mscale = cscale.toUint128();
        gscalesCache.maxscale = Math.max(cscale, gscalesCache.maxscale).toUint128();
        uint256 shares = tranche.asHarness().computeSharesRedeemed(gscalesCache, principal);
        // execution
        uint256 res = tranche.convertToUnderlying(principal);
        assertApproxEqAbs(res, (shares * cscale) / WAD, _DELTA_, "convertToUnderlying before settlement");
        vm.clearMockedCalls();
    }

    function testConvertToUnderlying_AfterSettlement(uint256 principal, uint256 cscale) public virtual {
        cscale = bound(cscale, 1, RAY);
        principal = bound(principal, 0, MAX_UINT128);
        vm.warp(_maturity + 7 days);
        // setup
        vm.mockCall(address(adapter), abi.encodeWithSelector(IBaseAdapter.scale.selector), abi.encode(cscale));
        vm.mockCall(address(adapter), abi.encodeWithSelector(IBaseAdapter.scale.selector), abi.encode(cscale));
        // settle
        tranche.asHarness().updateGlobalScales();
        assertEq(tranche.getGlobalScales().mscale, cscale, "mscale should be updated to cscale");
        uint256 shares = tranche.asHarness().computeSharesRedeemed(tranche.getGlobalScales(), principal);
        // execution
        uint256 res = tranche.convertToUnderlying(principal);
        // assert
        assertApproxEqAbs(res, (shares * cscale) / WAD, _DELTA_, "convertToUnderlying after settlement");
        vm.clearMockedCalls();
    }

    function testConvertToPrincipal_BeforeSettlement(uint256 underlyingAmount, uint256 cscale) public virtual {
        cscale = bound(cscale, 1, RAY);
        underlyingAmount = bound(underlyingAmount, 0, MAX_UINT128);
        // setup
        vm.mockCall(address(adapter), abi.encodeWithSelector(IBaseAdapter.scale.selector), abi.encode(cscale));
        // simulate the settlement as if it is settled now
        gscalesCache.mscale = cscale.toUint128();
        gscalesCache.maxscale = Math.max(cscale, gscalesCache.maxscale).toUint128();
        uint256 principal = tranche.asHarness().computePrincipalTokenRedeemed(
            gscalesCache,
            (underlyingAmount * WAD) / cscale
        );
        // execution
        uint256 res = tranche.convertToPrincipal(underlyingAmount);
        // assert
        assertApproxEqAbs(res, principal, _DELTA_, "convertToPrincipal before settlement");
        vm.clearMockedCalls();
    }

    function testConvertToPrincipal_AfterSettlement(uint256 underlyingAmount, uint256 cscale) public virtual {
        cscale = bound(cscale, 1, RAY);
        underlyingAmount = bound(underlyingAmount, 0, MAX_UINT128);
        vm.warp(_maturity + 7 days);
        // setup
        vm.mockCall(address(adapter), abi.encodeWithSelector(IBaseAdapter.scale.selector), abi.encode(cscale));
        vm.mockCall(address(adapter), abi.encodeWithSelector(IBaseAdapter.scale.selector), abi.encode(cscale));
        // settle
        tranche.asHarness().updateGlobalScales();
        assertEq(tranche.getGlobalScales().mscale, cscale, "mscale should be updated to cscale");
        uint256 principal = tranche.asHarness().computePrincipalTokenRedeemed(
            tranche.getGlobalScales(),
            (underlyingAmount * WAD) / cscale
        );
        // execution
        uint256 res = tranche.convertToPrincipal(underlyingAmount);
        // assert
        assertApproxEqAbs(res, principal, _DELTA_, "convertToPrincipal after settlement");
        vm.clearMockedCalls();
    }

    /////////////////////////////////////////////////////////////////////
    /// ISSUE
    /////////////////////////////////////////////////////////////////////

    /// @notice Should revert if maturity has passed or is equal to current timestamp
    function testIssue_RevertIfMatured() public virtual {
        vm.warp(_maturity);
        vm.expectRevert(ITranche.TimestampAfterMaturity.selector);
        tranche.issue(user, 100 * ONE_SCALE);
    }

    /////////////////////////////////////////////////////////////////////
    /// UPDATE UNCLAIMED YIELD
    /////////////////////////////////////////////////////////////////////

    function testUpdateUnclaimedYield_RevertIfNotYT() public virtual {
        vm.expectRevert(ITranche.OnlyYT.selector);
        tranche.updateUnclaimedYield(address(this), user, 10 * ONE_SCALE);
    }

    function testUpdateUnclaimedYield_RevertIfZeroAddress() public virtual {
        uint256 yAmountTransfer = 10;
        // from: non-zero, to: zero
        {
            address[2] memory accounts = [address(0xcafe), address(0)];
            _expectRevertWithZeroAddress(accounts, yAmountTransfer);
        }
        // from: zero, to: non-zero
        {
            address[2] memory accounts = [address(0), address(0xbabe)];
            _expectRevertWithZeroAddress(accounts, yAmountTransfer);
        }
        // from: zero, to: zero
        {
            address[2] memory accounts = [address(0), address(0)];
            _expectRevertWithZeroAddress(accounts, yAmountTransfer);
        }
    }

    function _expectRevertWithZeroAddress(address[2] memory accounts, uint256 yAmountTransfer) internal {
        vm.expectRevert(ITranche.ZeroAddress.selector);
        vm.prank(address(yt));
        tranche.updateUnclaimedYield(accounts[0], accounts[1], yAmountTransfer);
    }

    //////////////////////////////////////////////////////////////////////
    /// REDEEM
    //////////////////////////////////////////////////////////////////////

    /// @notice Redeem PT can be done after maturity
    function testRedeem_RevertIfNotMaturedYet() public virtual {
        vm.expectRevert(ITranche.TimestampBeforeMaturity.selector);
        tranche.redeem(100 * ONE_SCALE, user, address(this));
    }

    function testRedeem_RevertIfInsufficientAllowance() public virtual {
        _issue(address(this), user, 100 * ONE_SCALE);
        _approve(address(tranche), user, address(this), 10);
        vm.warp(_maturity + 7 days);
        vm.expectRevert("ERC20: insufficient allowance");
        tranche.redeem(10 * ONE_SCALE, user, user);
    }

    //////////////////////////////////////////////////////////////////////
    /// WITHDRAW
    //////////////////////////////////////////////////////////////////////

    /// @notice Withdrawing should revert if not matured yet
    function testWithdraw_RevertIfNotMaturedYet() public virtual {
        vm.expectRevert(ITranche.TimestampBeforeMaturity.selector);
        tranche.withdraw(100 * ONE_SCALE, user, address(this));
    }

    /// @notice Withdrawing should revert if not enough allowance
    function testWithdraw_RevertIfInsufficientAllowance() public virtual {
        _issue(address(this), user, 100 * ONE_SCALE);
        _approve(address(tranche), user, address(this), 10);
        vm.warp(_maturity + 7 days);
        vm.expectRevert("ERC20: insufficient allowance");
        tranche.withdraw(10 * ONE_SCALE, user, user);
    }

    //////////////////////////////////////////////////////////////////////
    /// REDEEM_WITH_YT
    //////////////////////////////////////////////////////////////////////

    function testRedeemWithYT_RevertIfLscaleZero() public virtual {
        vm.warp(_maturity);
        vm.expectRevert(ITranche.NoAccruedYield.selector);
        tranche.redeemWithYT(address(this), address(this), 0);
    }

    /// @notice Test redeeming PT with YT
    ///         - Same amount of YT should be burned as PT
    function testRedeemWithYT_RevertIfInsufficientYieldTokenBalance() public virtual {
        // setup
        uint256 amount = 100 * ONE_SCALE;
        _issue(address(this), address(this), amount);
        yt.transfer(user, 1);
        // assert
        vm.expectRevert("ERC20: burn amount exceeds balance");
        tranche.redeemWithYT(address(this), user, amount);
    }

    function testRedeemWithYT_RevertIfInsufficientAllowance() public virtual {
        _issue(address(this), user, 100 * ONE_SCALE);
        _approve(address(tranche), user, address(this), 10);
        vm.warp(_maturity + 10 days);
        vm.expectRevert("ERC20: insufficient allowance");
        tranche.redeemWithYT({from: user, to: address(this), pyAmount: 11 * ONE_SCALE});
    }

    /////////////////////////////////////////////////////////////////////
    /// PREVIEW COLLECT
    /////////////////////////////////////////////////////////////////////

    struct PreviewCollectFuzzArgs {
        address caller; // caller of issue function
        uint256 uDeposit; // amount of underlying to deposit to issue PT+YT
        uint256 unclaimedYield; // unclaimed yield of caller
    }

    modifier boundPreviewCollectFuzzArgs(PreviewCollectFuzzArgs memory args) virtual {
        assumeNotZeroAddress(args.caller);
        vm.assume(accountsExcludedFromFuzzing[args.caller] == false);
        args.uDeposit = bound(args.uDeposit, 0, MAX_UNDERLYING_DEPOSIT);
        args.unclaimedYield = bound(args.unclaimedYield, 0, 100 * ONE_TARGET);
        _;
    }

    function testPreviewCollect_Zero(address account) public {
        vm.assume(tranche.lscales(account) == 0);
        assertEq(tranche.previewCollect(account), 0, "preview collect should not revert");
    }

    // "MUST NOT revert."
    /// @dev Condition: scale at the time of collect is higher than the scale at issuance
    /// @param args PreviewFuncFuzzArgs struct
    /// @param newTimestamp New timestamp to warp to
    function testPreviewCollect(
        PreviewCollectFuzzArgs memory args,
        uint256 cscale,
        uint32 newTimestamp
    ) public boundPreviewCollectFuzzArgs(args) {
        cscale = bound(cscale, 1, RAY);
        newTimestamp = boundU32(newTimestamp, block.timestamp, _maturity + 900 days);
        // Setup
        deal(address(underlying), args.caller, args.uDeposit, false);
        try this._setUpPreCollect(args.caller, args.uDeposit, args.unclaimedYield) {} catch {
            vm.assume(false);
        }
        vm.mockCall(address(adapter), abi.encodeWithSelector(IBaseAdapter.scale.selector), abi.encode(cscale));
        vm.warp(newTimestamp);
        // Execution
        uint256 preview = tranche.previewCollect(args.caller);
        vm.prank(args.caller);
        try tranche.collect() returns (uint256 collected) {
            // Assert
            assertEq(collected, preview, "prop/preview-collect");
        } catch {}
    }

    //////////////////////////////////////////////////////////////////////
    /// PROTECTED FUNCTIONS
    //////////////////////////////////////////////////////////////////////

    function testSetFeeRecipient_RevertIfNotManagement() public virtual {
        vm.expectRevert(ITranche.Unauthorized.selector);
        tranche.setFeeRecipient(address(0xcafe));
    }

    function testSetFeeRecipient_RevertIfZeroAddress() public virtual {
        vm.expectRevert(ITranche.ZeroAddress.selector);
        vm.prank(management);
        tranche.setFeeRecipient(address(0));
    }

    function testRecoverERC20_Ok() public override {
        deal(address(underlying), address(tranche), 100, false);
        vm.prank(management);
        tranche.recoverERC20(address(underlying), management);
        assertEq(underlying.balanceOf(management), 100, "recovered");
    }

    function testRecoverERC20_RevertIfProtectedToken() public virtual {
        // target is protected token
        vm.expectRevert(ITranche.ProtectedToken.selector);
        vm.prank(management);
        tranche.recoverERC20(address(target), management);
    }

    function testRecoverERC20_RevertIfNotManagement() public virtual {
        address uni = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984; // UNISWAP governance token
        vm.expectRevert(ITranche.Unauthorized.selector);
        tranche.recoverERC20(uni, management);
    }

    //////////////////////////////////////////////////////////////////////
    /// HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////////////

    function _simulateScaleIncrease() internal override {
        uint256 scale = adapter.scale();
        // set the scale to 1.5x of the current scale
        adapter.asMock().setScale((scale * 15) / 10);
    }

    function _simulateScaleDecrease() internal override {
        uint256 scale = adapter.scale();
        adapter.asMock().setScale((scale * 10) / 12);
    }
}

/// @notice A library to cast a contract type to another contract type.
library Cast {
    /// @dev Casts a tranche to a tranche harness.
    function asHarness(ITranche tranche) internal pure returns (TrancheHarness harness) {
        assembly {
            harness := tranche
        }
    }

    /// @dev Casts a factory to a mock factory.
    function asMock(TrancheFactory factory) internal pure returns (MockFactoryCallbackReceiver mock) {
        assembly {
            mock := factory
        }
    }

    function asMock(BaseAdapter adapter) internal pure returns (MockAdapter mock) {
        assembly {
            mock := adapter
        }
    }
}
