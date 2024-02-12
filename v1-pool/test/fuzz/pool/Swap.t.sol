// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {PoolSwapFuzzTest} from "../../shared/Swap.t.sol";
import {CallbackInputType, SwapInput} from "../../shared/CallbackInputType.sol";

import {SwapEventsLib} from "../../helpers/SwapEventsLib.sol";
import {SafeCast} from "@openzeppelin/contracts@4.9.3/utils/math/SafeCast.sol";

using SafeCast for uint256;

contract PoolSwapUnderlyingForPtFuzzTest is PoolSwapFuzzTest {
    /// @dev The Sender of the swap transaction
    address alice = makeAddr("alice");

    function setUp() public override {
        super.setUp();
        _deployMockCallbackReceiverTo(alice);
    }

    /// @notice test swap when callback data is given
    /// @dev
    /// Pre-condition: liquidity is added to the pool
    /// Test case: swap underlying for pt
    /// Post-condition:
    ///   1. underlying balance of alice should increase by the return value from swapPtForUnderlying
    ///   2. underlying reserve should be decreased by the amount of underlying sent to alice and fee
    ///   3. Solvenvy check
    ///   4. baseLpt minted should be approximately equal to the expected amount
    function testFuzz_swapUnderlyingForPt(SwapFuzzInput memory swapInput, AmountFuzzInput memory ptDesired)
        public
        boundSwapFuzzInput(swapInput)
        whenMaturityNotPassed
        setUpRandomBasePoolReserves(swapInput.ptsToBasePool)
        boundPtDesired(swapInput, ptDesired)
    {
        deal(address(underlying), alice, 1e6 * ONE_UNDERLYING, false);
        vm.warp(swapInput.timestamp);

        uint256 index = swapInput.index;
        uint256 ptOutDesired = ptDesired.value;

        // pre-condition
        uint256 preBaseLptSupply = tricrypto.totalSupply();
        bytes memory callbackData = abi.encode(CallbackInputType.SwapUnderlyingForPt, SwapInput(underlying, pts[index]));
        // execute
        vm.recordLogs();
        vm.prank(alice);
        uint256 underlyingIn = pool.swapUnderlyingForPt(index, ptOutDesired, alice, callbackData);
        uint256 protocolFee = SwapEventsLib.getProtocolFeeFromLastSwapEvent(pool);
        // assert 1
        assertApproxEqRel(
            pts[index].balanceOf(alice),
            ptOutDesired,
            0.01 * 1e18, // This error is due to the approximation error between the actual and expected tricrypto minted
            // See CurveV2Pool.calc_token_amount and CurveV2Pool.remove_liquidity_one_coin
            "alice should receive appropriately amount of pt [rel 1%]"
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
        assertSolvencyReserve();
    }
}

contract PoolSwapPtForUnderlyingFuzzTest is PoolSwapFuzzTest {
    address alice = makeAddr("alice");

    function setUp() public override {
        super.setUp();
        _deployMockCallbackReceiverTo(alice);
    }

    /// @notice test swap when callback data is given
    /// @dev
    /// Pre-condition: liquidity is added to the pool
    /// Test case: swap pt for underlying
    /// Post-condition:
    ///   1. underlying balance of alice should increase by the return value from swapPtForUnderlying
    ///   2. underlying reserve should be decreased by the amount of underlying sent to alice and fee
    ///   3. Solvenvy check
    ///   4. baseLpt minted should be approximately equal to the expected amount
    function testFuzz_swapPtForUnderlying(SwapFuzzInput memory swapInput, AmountFuzzInput memory ptDesired)
        public
        boundSwapFuzzInput(swapInput)
        whenMaturityNotPassed
        setUpRandomBasePoolReserves(swapInput.ptsToBasePool)
        boundPtDesired(swapInput, ptDesired)
    {
        deal(address(pts[swapInput.index]), alice, ptDesired.value, false);
        vm.warp(swapInput.timestamp);

        uint256 index = swapInput.index;
        uint256 ptInDesired = ptDesired.value;

        // pre-condition
        uint256 preBaseLptSupply = tricrypto.totalSupply();
        bytes memory callbackData = abi.encode(CallbackInputType.SwapPtForUnderlying, SwapInput(underlying, pts[index]));

        uint256[3] memory amounts;
        amounts[index] = ptInDesired;
        uint256 expectedBaseLptIssued = tricrypto.calc_token_amount(amounts, true);

        // execute
        vm.recordLogs();
        vm.prank(alice);
        uint256 underlyingOut = pool.swapPtForUnderlying(index, ptInDesired, alice, callbackData);
        uint256 protocolFee = SwapEventsLib.getProtocolFeeFromLastSwapEvent(pool);
        // assert 1
        assertEq(underlying.balanceOf(alice), underlyingOut, "alice should receive underlying");
        // assert 2
        assertUnderlyingReserveAfterSwap({
            underlyingToAccount: underlyingOut.toInt256(),
            protocolFeeIn: protocolFee,
            preTotalUnderlying: preTotalUnderlying
        });
        // assert 3
        assertSolvencyReserve();
        // assert 4
        assertApproxEqRel(
            expectedBaseLptIssued,
            (tricrypto.totalSupply() - preBaseLptSupply),
            0.01 * 1e18, // 1% tolerance
            "baseLpt minted is approximately equal to the expected amount"
        );
    }
}
