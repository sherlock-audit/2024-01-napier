// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {PoolSwapBaseTest} from "../../shared/Swap.t.sol";
import {FaultyCallbackReceiver} from "../../mocks/FaultyCallbackReceiver.sol";
import {CallbackInputType, SwapInput, SwapFaultilyInput} from "../../shared/CallbackInputType.sol";

import {SwapEventsLib} from "../../helpers/SwapEventsLib.sol";
import {Errors} from "src/libs/Errors.sol";
import {SafeCast} from "@openzeppelin/contracts@4.9.3/utils/math/SafeCast.sol";

using SafeCast for uint256;
using SafeCast for int256;

abstract contract PoolSwapBaseUnitTest is PoolSwapBaseTest {
    /// @dev msg.sender of swaps. The receiver of the callback
    address alice = makeAddr("alice");
    /// @dev The recipient of the swapped token
    address recipient = makeAddr("recipient");

    /// @dev The receiver of the callback but with faulty implementation
    /// This is used to test reentrancy and send insufficient underlying/baseLpt
    address faultyReceiver = makeAddr("faultyReceiver");

    function setUp() public override {
        super.setUp();

        // deploy mock callback receiver
        _deployMockCallbackReceiverTo(alice);
        _deployFaultyCallbackReceiverTo(faultyReceiver);
    }

    function test_RevertIf_Reentrant() public virtual;

    function _expectRevertIf_Reentrant(bytes memory callData) internal {
        FaultyCallbackReceiver(faultyReceiver).setReentrancyCall(callData, true);
        vm.expectRevert("ReentrancyGuard: reentrant call");
    }

    function test_RevertIf_MaturityPassed() public virtual;
}

contract PoolSwapPtForUnderlyingUnitTest is PoolSwapBaseUnitTest {
    function test_RevertIf_Reentrant() public override whenMaturityNotPassed {
        _expectRevertIf_Reentrant(
            abi.encodeWithSelector(pool.swapPtForUnderlying.selector, 1, 10 * ONE_UNDERLYING, address(0xcafe), "")
        );
        vm.prank(faultyReceiver);
        pool.swapPtForUnderlying(
            0, 10, faultyReceiver, abi.encode(CallbackInputType.SwapPtForUnderlying, SwapInput(underlying, pts[0]))
        );
    }

    function test_RevertIf_MaturityPassed() public override whenMaturityPassed {
        vm.warp(maturity);
        vm.expectRevert(Errors.PoolExpired.selector);
        pool.swapPtForUnderlying(1, 1, recipient, "");
    }

    function test_RevertIf_PtNotExist() public whenMaturityNotPassed {
        vm.expectRevert(stdError.indexOOBError);
        pool.swapPtForUnderlying(3, 1, recipient, "");
    }

    function test_RevertIf_UnauthorizedCallback() public whenMaturityNotPassed {
        assertFalse(poolFactory.isCallbackReceiverAuthorized(address(0xbad)), "[pre-condition] should be unauthorized");
        vm.expectRevert(Errors.PoolUnauthorizedCallback.selector);
        pool.swapPtForUnderlying(0, 10, address(0xbad), abi.encode("arbitrary data"));
    }

    function test_RevertIf_PoolZeroAmountsOutput() public whenMaturityNotPassed {
        // pre-condition
        vm.warp(maturity - 30 days);
        deal(address(pts[0]), alice, 1, false);
        vm.expectRevert(Errors.PoolZeroAmountsOutput.selector);
        vm.prank(alice);
        // To test this case, use small amount of underlying to mock attackers who want swap for free.
        pool.swapPtForUnderlying(
            0, 1, recipient, abi.encode(CallbackInputType.SwapPtForUnderlying, SwapInput(underlying, pts[0]))
        );
    }

    /// @dev
    /// Pre-condition: liquidity is added to the pool
    /// Test case: swap 1 underlying for approximately 1 pt
    /// Post-condition:
    ///   1. underlying balance of recipient should increase by the return value from swapPtForUnderlying
    ///   2. underlying reserve should be decreased by the amount of underlying sent to recipient and fee
    ///   3. Solvenvy check
    ///   4. baseLpt minted should be approximately equal to the expected amount
    function test_swapPtForUnderlying() public whenMaturityNotPassed {
        // pre-condition
        vm.warp(maturity - 30 days);
        deal(address(pts[0]), alice, type(uint96).max, false); // ensure alice has enough pt
        uint256 preBaseLptSupply = tricrypto.totalSupply();
        uint256 ptInDesired = 100 * ONE_UNDERLYING;
        uint256 expectedBaseLptIssued = tricrypto.calc_token_amount([ptInDesired, 0, 0], true);
        // execute
        vm.recordLogs();
        vm.prank(alice);
        uint256 underlyingOut = pool.swapPtForUnderlying(
            0, ptInDesired, recipient, abi.encode(CallbackInputType.SwapPtForUnderlying, SwapInput(underlying, pts[0]))
        );
        // sanity check
        uint256 protocolFee = SwapEventsLib.getProtocolFeeFromLastSwapEvent(pool);
        assertGt(protocolFee, 0, "fee should be charged");
        // assert 1
        assertEq(underlying.balanceOf(recipient), underlyingOut, "recipient should receive underlying");
        // assert 2
        assertUnderlyingReserveAfterSwap({
            underlyingToAccount: underlyingOut.toInt256(),
            protocolFeeIn: protocolFee,
            preTotalUnderlying: preTotalUnderlying
        });
        // assert 3
        assertReserveBalanceMatch();
        // assert 4
        assertApproxEqRel(
            expectedBaseLptIssued,
            (tricrypto.totalSupply() - preBaseLptSupply),
            0.01 * 1e18,
            "baseLpt minted is approximately equal to the expected amount"
        );
        // Pool is initialised with 1/2 proportion of baseLpt
        // Therefore, the marginal exchange rate is approximately 1.
        assertApproxEqRel(
            underlyingOut + protocolFee * (100 + poolConfig.protocolFeePercent) / 100,
            100 * ONE_UNDERLYING,
            0.03 * 1e18, // 3% tolerance
            "underlyingOut should be approximately equal to the expected amount"
        );
    }

    function test_RevertIf_InsufficientUnderlyingReceived() public virtual {
        // this test is not applicable to pt -> underlying swap
    }

    function test_RevertIf_InsufficientBaseLpTokenReceived() public virtual {
        vm.mockCall(
            address(tricrypto), abi.encodeWithSignature("add_liquidity(uint256[3],uint256)"), abi.encode(ONE_UNDERLYING)
        );
        deal(address(pts[2]), faultyReceiver, type(uint96).max, false);
        vm.expectRevert(Errors.PoolInsufficientBaseLptReceived.selector);
        vm.prank(faultyReceiver);
        pool.swapPtForUnderlying(
            2,
            ONE_UNDERLYING,
            recipient,
            abi.encode(CallbackInputType.SwapPtForUnderlying, SwapInput(underlying, pts[2]))
        );
    }

    function test_RevertIf_InsufficientPrincipalTokenReceived() public virtual {
        uint256 index = 2;
        uint256 ptIn = 100 * ONE_UNDERLYING;
        deal(address(pts[index]), faultyReceiver, type(uint96).max, false);

        vm.expectRevert("ERC20: transfer amount exceeds balance"); // Assume OZ contract
        vm.prank(faultyReceiver);
        pool.swapPtForUnderlying(
            index,
            ptIn,
            recipient,
            abi.encode(
                CallbackInputType.SwapPtForUnderlyingFaultily,
                SwapFaultilyInput({
                    underlying: underlying,
                    pt: pts[0],
                    invokeInsufficientUnderlying: false,
                    invokeInsufficientBaseLpt: true
                })
            )
        );
    }

    function test_RevertIf_InvariantViolated() public {
        uint256 index = 2;
        deal(address(pts[index]), faultyReceiver, type(uint96).max, false);

        vm.expectRevert(Errors.PoolInvariantViolated.selector);
        vm.prank(faultyReceiver);
        pool.swapPtForUnderlying(
            index,
            ONE_UNDERLYING,
            faultyReceiver,
            abi.encode(
                CallbackInputType.SwapPtForUnderlyingFaultily,
                SwapFaultilyInput({
                    underlying: underlying,
                    pt: pts[index],
                    invokeInsufficientUnderlying: true,
                    invokeInsufficientBaseLpt: false
                })
            )
        );
    }
}

contract PoolSwapUnderlingForPtUnitTest is PoolSwapBaseUnitTest {
    function test_RevertIf_Reentrant() public override whenMaturityNotPassed {
        _expectRevertIf_Reentrant(
            abi.encodeWithSelector(pool.swapUnderlyingForPt.selector, 1, 10 * ONE_UNDERLYING, recipient, "")
        );
        vm.prank(faultyReceiver);
        pool.swapUnderlyingForPt(
            0,
            10,
            faultyReceiver,
            abi.encode(abi.encode(CallbackInputType.SwapUnderlyingForPt, SwapInput(underlying, pts[0])))
        );
    }

    function test_RevertIf_MaturityPassed() public override whenMaturityPassed {
        vm.warp(maturity);
        vm.expectRevert(Errors.PoolExpired.selector);
        pool.swapUnderlyingForPt(1, 1, recipient, "");
    }

    function test_RevertIf_PtNotExist() public whenMaturityNotPassed {
        vm.expectRevert(stdError.indexOOBError);
        pool.swapUnderlyingForPt(3, 1, recipient, "");
    }

    function test_RevertIf_UnauthorizedCallback() public whenMaturityNotPassed {
        assertFalse(poolFactory.isCallbackReceiverAuthorized(address(0xbad)), "[pre-condition] should be unauthorized");
        vm.expectRevert(Errors.PoolUnauthorizedCallback.selector);
        pool.swapUnderlyingForPt(0, 10, address(0xbad), abi.encode("arbitrary data"));
    }

    function test_RevertIf_PoolZeroAmountsInput() public whenMaturityNotPassed {
        fund(address(underlying), alice, 1, false);
        vm.warp(maturity - 30 days);
        vm.expectRevert(Errors.PoolZeroAmountsInput.selector);
        vm.prank(alice);
        // To test this case, use small amount of underlying to mock attackers who want swap for free.
        pool.swapUnderlyingForPt(
            0, 1, recipient, abi.encode(CallbackInputType.SwapUnderlyingForPt, SwapInput(underlying, pts[0]))
        );
    }

    /// @dev
    /// Pre-condition: liquidity is added to the pool
    /// Test case: swap 1 underlying for approximately 1 pt
    /// Post-condition:
    ///     1. pt balance of recipient should be approx equal to the desired amount.
    //      2. underlying reserve should be increased by the received amount and fee.
    ///     3. baseLpt reserve should be decreased by at least the amount of baseLpt burned.
    ///     4. Solvenvy check
    function test_swapUnderlyingForPt() public whenMaturityNotPassed {
        fund(address(underlying), alice, 1000 * ONE_UNDERLYING, false);
        // pre-condition
        vm.warp(maturity - 30 days);
        uint256 preBaseLptSupply = tricrypto.totalSupply();
        // execute
        uint256 ptOutDesired = 1 * ONE_UNDERLYING;
        vm.recordLogs();
        vm.prank(alice);
        uint256 underlyingIn = pool.swapUnderlyingForPt(
            0, ptOutDesired, recipient, abi.encode(CallbackInputType.SwapUnderlyingForPt, SwapInput(underlying, pts[0]))
        );
        uint256 protocolFee = SwapEventsLib.getProtocolFeeFromLastSwapEvent(pool);
        // assert
        assertGt(underlyingIn, 0, "should receive some underlying");
        assertGt(protocolFee, 0, "fee should be accumulated");
        // assert 1
        assertApproxEqRel(
            pts[0].balanceOf(recipient),
            ptOutDesired,
            0.01 * 1e18, // This error is due to the approximation error between the actual and expected tricrypto minted
            // See CurveV2Pool.calc_token_amount and CurveV2Pool.remove_liquidity_one_coin
            "recipient should receive appropriately amount of pt [rel 1%]"
        );
        // assert 2
        assertUnderlyingReserveAfterSwap({
            underlyingToAccount: -underlyingIn.toInt256(),
            protocolFeeIn: protocolFee,
            preTotalUnderlying: preTotalUnderlying
        });
        // assert 3
        assertEq(
            pool.totalBaseLpt(),
            preTotalBaseLpt - (preBaseLptSupply - tricrypto.totalSupply()),
            "reserve should be decreased by baseLpt burned"
        );
        // assert 4
        assertReserveBalanceMatch();
        // Pool is initialised with 1/2 proportion of baseLpt
        // Therefore, the marginal exchange rate is approximately 1.
        assertApproxEqRel(
            underlyingIn + protocolFee * (100 + poolConfig.protocolFeePercent) / 100,
            1 * ONE_UNDERLYING,
            0.02 * 1e18, // 2% tolerance
            "underlyingIn should be approximately equal to the expected amount"
        );
    }

    function test_RevertIf_InsufficientUnderlyingReceived() public virtual {
        uint256 ptOut = 100 * ONE_UNDERLYING;
        deal(address(underlying), faultyReceiver, type(uint96).max, false);
        vm.expectRevert(Errors.PoolInsufficientUnderlyingReceived.selector);
        vm.prank(faultyReceiver);
        pool.swapUnderlyingForPt(
            0,
            ptOut,
            faultyReceiver,
            abi.encode(
                CallbackInputType.SwapUnderlyingForPtFaultily,
                SwapFaultilyInput({
                    underlying: underlying,
                    pt: pts[0],
                    invokeInsufficientUnderlying: true,
                    invokeInsufficientBaseLpt: false
                })
            )
        );
    }

    function test_RevertIf_InsufficientBaseLpTokenReceived() public virtual {
        // this test is not applicable to underlying -> pt swap
    }

    function test_RevertIf_InvariantViolated() public {
        deal(address(underlying), faultyReceiver, type(uint96).max, false);
        vm.expectRevert(Errors.PoolInvariantViolated.selector);
        vm.prank(faultyReceiver);
        pool.swapUnderlyingForPt(
            2,
            ONE_UNDERLYING,
            faultyReceiver,
            abi.encode(
                CallbackInputType.SwapUnderlyingForPtFaultily,
                SwapFaultilyInput({
                    underlying: underlying,
                    pt: pts[2],
                    invokeInsufficientUnderlying: false,
                    invokeInsufficientBaseLpt: true
                })
            )
        );
    }
}

abstract contract PoolSwapBaseLptUnitTest is PoolSwapBaseUnitTest {
    function test_RevertIf_BaseLpTokenOutIsGreaterThanReserve() public virtual;

    function test_RevertIf_UnderlyingOutIsGreaterThanReserve() public virtual;

    function test_RevertIf_BaseLpTokenProportionTooHigh() public virtual;

    function test_RevertIf_EffectiveExchangeRateBelowOne() public virtual;
}

contract PoolSwapBaseLpTokenForUnderlyingUnitTest is PoolSwapBaseLptUnitTest {
    function test_RevertIf_Reentrant() public override whenMaturityNotPassed {
        _expectRevertIf_Reentrant(
            abi.encodeWithSelector(pool.swapExactBaseLpTokenForUnderlying.selector, 10 * 1e18, recipient)
        );
        vm.prank(faultyReceiver);
        pool.swapPtForUnderlying(
            0, 10, faultyReceiver, abi.encode(CallbackInputType.SwapPtForUnderlying, SwapInput(underlying, pts[0]))
        );
    }

    function test_RevertIf_MaturityPassed() public override whenMaturityPassed {
        vm.warp(maturity);
        vm.expectRevert(Errors.PoolExpired.selector);
        pool.swapExactBaseLpTokenForUnderlying(1, recipient);
    }

    function test_RevertIf_BaseLpTokenOutIsGreaterThanReserve() public virtual override whenMaturityNotPassed {
        // this test is not applicable to baseLpt -> underlying swap
    }

    function test_RevertIf_UnderlyingOutIsGreaterThanReserve() public virtual override whenMaturityNotPassed {}

    function test_RevertIf_BaseLpTokenProportionTooHigh() public virtual override whenMaturityNotPassed {
        uint256 amountIn = 999 * 1e18;
        fund(address(tricrypto), address(this), amountIn, false);

        vm.expectRevert(Errors.PoolProportionTooHigh.selector);
        pool.swapExactBaseLpTokenForUnderlying(amountIn, recipient);
    }

    function test_RevertIf_EffectiveExchangeRateBelowOne() public virtual override whenMaturityNotPassed {
        // this test is not applicable to baseLpt -> underlying swap
    }

    function test_RevertIf_PoolZeroAmountsOutput() public whenMaturityNotPassed {
        vm.warp(maturity - 30 days);
        fund(address(tricrypto), address(this), 1, false);
        vm.expectRevert(Errors.PoolZeroAmountsOutput.selector);
        // To test this case, use small amount of underlying to mock attackers who want swap for free.
        pool.swapExactBaseLpTokenForUnderlying(1, recipient);
    }

    function test_swap() public whenMaturityNotPassed {
        vm.warp(maturity - 30 days);
        fund(address(tricrypto), address(this), 1 * 1e18, false);

        // execute
        vm.recordLogs();
        uint256 underlyingOut = pool.swapExactBaseLpTokenForUnderlying(1 * 1e18, recipient);

        // assert
        uint256 protocolFee = SwapEventsLib.getProtocolFeeFromLastSwapEvent(pool);
        assertGt(protocolFee, 0, "fee should be accumulated");
        // Pool is initialised with 1/2 proportion of baseLpt
        // Therefore, the marginal exchange rate is approximately 3.
        assertApproxEqRel(
            underlyingOut + protocolFee * (100 + poolConfig.protocolFeePercent) / 100,
            1 * ONE_UNDERLYING * N_COINS,
            0.02 * 1e18, // 2% tolerance
            "underlyingOut should be approximately equal to the expected amount"
        );
        assertEq(underlying.balanceOf(recipient), underlyingOut, "recipient should receive underlying");
        assertEq(pool.totalBaseLpt(), preTotalBaseLpt + 1 * 1e18, "reserve should be increased");
        assertSolvencyReserve();
        assertUnderlyingReserveAfterSwap({
            underlyingToAccount: underlyingOut.toInt256(),
            protocolFeeIn: protocolFee,
            preTotalUnderlying: preTotalUnderlying
        });
    }
}

contract PoolSwapUnderlyingForBaseLpTokenUnitTest is PoolSwapBaseLptUnitTest {
    function test_RevertIf_Reentrant() public override whenMaturityNotPassed {
        _expectRevertIf_Reentrant(
            abi.encodeWithSelector(pool.swapUnderlyingForExactBaseLpToken.selector, 10 * 1e18, recipient)
        );
        vm.prank(faultyReceiver);
        pool.swapPtForUnderlying(
            0, 10, faultyReceiver, abi.encode(CallbackInputType.SwapPtForUnderlying, SwapInput(underlying, pts[0]))
        );
    }

    function test_RevertIf_MaturityPassed() public override whenMaturityPassed {
        vm.warp(maturity);
        vm.expectRevert(Errors.PoolExpired.selector);
        pool.swapUnderlyingForExactBaseLpToken(1, recipient);
    }

    function test_RevertIf_BaseLpTokenOutIsGreaterThanReserve() public virtual override {
        fund(address(underlying), address(this), 1000 * 1e18 + 1, false);

        vm.expectRevert(Errors.PoolInsufficientBaseLptForTrade.selector);
        pool.swapUnderlyingForExactBaseLpToken(1000 * 1e18 + 1, recipient);
    }

    function test_RevertIf_BaseLpTokenProportionTooHigh() public virtual override {
        // this test is not applicable to underlying -> baseLpt swap
    }

    function test_RevertIf_EffectiveExchangeRateBelowOne() public virtual override {
        vm.warp(maturity - 30 days);
        fund(address(underlying), address(this), 3000 * ONE_UNDERLYING, false);

        try pool.swapUnderlyingForExactBaseLpToken(800 * 1e18, recipient) {
            fail("Should revert with PoolExchangeRateBelowOne");
        } catch (bytes memory reason) {
            // Note: doesn't assert error args because it's hard to get the exchange rate.
            assertEq(
                bytes4(reason), Errors.PoolExchangeRateBelowOne.selector, "Should revert with PoolProportionTooHigh"
            );
        }
    }

    function test_RevertIf_UnderlyingOutIsGreaterThanReserve() public virtual override {
        // this test is not applicable to underlying -> baseLpt swap
    }

    function test_RevertIf_PoolZeroAmountsInput() public whenMaturityNotPassed {
        vm.warp(maturity - 30 days);
        fund(address(underlying), address(this), 2, false);
        vm.expectRevert(Errors.PoolZeroAmountsInput.selector);
        // To test this case, use small amount of underlying to mock attackers who want swap for free.
        pool.swapUnderlyingForExactBaseLpToken(1, recipient);
    }

    function test_swap() public whenMaturityNotPassed {
        vm.warp(maturity - 30 days);
        fund(address(underlying), address(this), 10 * 1e18, false);

        vm.recordLogs();
        uint256 underlyingIn = pool.swapUnderlyingForExactBaseLpToken(10 * 1e18, recipient);

        uint256 protocolFee = SwapEventsLib.getProtocolFeeFromLastSwapEvent(pool);
        assertGt(protocolFee, 0, "fee should be accumulated");
        // assert
        // Pool is initialised with 1/2 proportion of baseLpt
        // Therefore, the marginal exchange rate is approximately 3.
        assertApproxEqRel(
            underlyingIn + protocolFee * (100 + poolConfig.protocolFeePercent) / 100,
            10 * ONE_UNDERLYING * N_COINS,
            0.02 * 1e18, // 2% tolerance
            "underlyingIn should be approximately equal to the expected amount"
        );
        assertEq(tricrypto.balanceOf(recipient), 10 * 1e18, "recipient should receive baseLpt");
        assertEq(pool.totalBaseLpt(), preTotalBaseLpt - 10 * 1e18, "reserve should be increased");
        assertSolvencyReserve();
        assertUnderlyingReserveAfterSwap({
            underlyingToAccount: -underlyingIn.toInt256(),
            protocolFeeIn: protocolFee,
            preTotalUnderlying: preTotalUnderlying
        });
    }
}
