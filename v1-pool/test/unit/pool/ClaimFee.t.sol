// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {PoolSwapFuzzTest} from "../../shared/Swap.t.sol";

import {SwapEventsLib} from "../../helpers/SwapEventsLib.sol";
import {CallbackInputType, SwapInput} from "../../shared/CallbackInputType.sol";

contract PoolClaimFeeTest is PoolSwapFuzzTest {
    /// @dev The Sender of the swap transaction
    address alice = makeAddr("alice");

    function setUp() public override {
        super.setUp();

        _deployMockCallbackReceiverTo(alice);
    }

    modifier ensureNoExcessTokensLeft() {
        pool.skim(); // Ensure pool doesn't have any excess tokens (including fees) before each test
        // Reset the feeRecipient's balance to 0
        deal(address(underlying), feeRecipient, 0, false);
        deal(address(tricrypto), feeRecipient, 0, false);
        _;
    }

    function testFuzz_feesAreNotStolen(RandomBasePoolReservesFuzzInput memory input)
        public
        boundRandomBasePoolReservesFuzzInput(input)
        setUpRandomReserves(input.ptsToBasePool)
        ensureNoExcessTokensLeft
    {
        uint256 initialBalance = type(uint96).max;
        deal(address(underlying), alice, initialBalance, false); // ensure alice has enough underlying to swap
        uint256 ptOutDesired = 80 * ONE_UNDERLYING;

        /// Execution
        vm.recordLogs();
        // First swap
        vm.prank(alice);
        uint256 underlyingOut1 = pool.swapUnderlyingForPt(
            0, ptOutDesired, alice, abi.encode(CallbackInputType.SwapUnderlyingForPt, SwapInput(underlying, pts[0]))
        );
        uint256 protocolFee1 = SwapEventsLib.getProtocolFeeFromLastSwapEvent(pool);
        // Second swap
        vm.prank(alice);
        uint256 underlyingOut2 = pool.swapUnderlyingForPt(
            0, ptOutDesired, alice, abi.encode(CallbackInputType.SwapUnderlyingForPt, SwapInput(underlying, pts[0]))
        );
        uint256 protocolFee2 = SwapEventsLib.getProtocolFeeFromLastSwapEvent(pool);

        /// Assertions
        assertReserveBalanceMatch();
        // Protocol fee should be charged for both swaps
        assertGt(protocolFee1, 0, "fee should be charged");
        assertGt(protocolFee2, 0, "fee should be charged");
        // Check balance changes
        assertEq(
            underlying.balanceOf(alice),
            initialBalance - underlyingOut1 - underlyingOut2,
            "user's underlying should be decreased"
        );
        assertApproxEqAbs(
            underlying.balanceOf(address(pool)),
            pool.totalUnderlying() + protocolFee1 + protocolFee2,
            2,
            "sum of underlying reserve and fees should be equal to the current balance of the pool"
        );

        pool.skim();

        // `feeRecipient` should receive fees
        assertApproxEqAbs(
            underlying.balanceOf(feeRecipient), protocolFee1 + protocolFee2, 2, "feeRecipient should receive both fees"
        );
    }
}
