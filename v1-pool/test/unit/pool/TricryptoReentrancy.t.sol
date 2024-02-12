// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import {PoolSwapBaseTest} from "../../shared/Swap.t.sol";

import {CallbackInputType, SwapInput} from "../../shared/CallbackInputType.sol";

/// @notice Test reentrancy protection against Tricrypto pool exchange methods.
/// Tricrypto have exchange methods that can allows callback on exchange.
/// Napier pool depends on deposit and withdraw methods of Tricrypto pool that can be affected by such incomplete state changes.
/// A kind of reentrancy may be possible if Tricrypto pool is not protected against reentrancy.
/// This test verifies that swapping on Napier pool is protected against reentrancy via Tricrypto pool through exchange with a callback.
contract TricryptoReentrancyTest is PoolSwapBaseTest {
    /// @dev The receiver of callback from Napier pool.
    address charlie = makeAddr("charlie");

    function setUp() public override {
        super.setUp();
        _deployMockCallbackReceiverTo(charlie);
    }

    /// @dev Parameters for callback method.
    uint256 _tempIndex;
    bool _tempPtForUnderlying;

    /// Exchange with callback method.
    function test_RevertIf_Reentrant(uint256 i, uint256 j, uint256 index, bool ptForUnderlying) public {
        i = _bound(i, 0, 2);
        j = _bound(j, 0, 2);
        vm.assume(i != j);
        _tempIndex = _bound(index, 0, 2); // Save input for callback
        _tempPtForUnderlying = ptForUnderlying;

        deal(address(pts[i]), address(this), 100 * ONE_UNDERLYING);

        // Tricrypo should revert if reentrancy is detected
        vm.expectRevert(); // Tricrypto will revert without a specific reason
        tricrypto.exchange_extended({
            i: i,
            j: j,
            dx: 100 * ONE_UNDERLYING,
            min_dy: 0,
            use_eth: false,
            sender: address(this),
            receiver: address(this),
            // Encode callback sig to self to trigger reentrancy
            cb: bytes32(abi.encode(this.tricryptoSwapCallback.selector)) // note: 32 byte-length
        });

        // Tricrypo should revert if reentrancy is detected
        vm.expectRevert(); // Tricrypto will revert without a specific reason
        tricrypto.exchange_extended({
            i: i,
            j: j,
            dx: 100 * ONE_UNDERLYING,
            min_dy: 0,
            use_eth: false,
            sender: address(this),
            receiver: address(this),
            // Encode callback sig to self to trigger reentrancy
            cb: bytes32(abi.encode(this.tricryptoSwapCallback.selector))
        });
    }

    /// @dev Receive callback from Tricrypto on exchange.
    function tricryptoSwapCallback() external {
        // give charlie tokens to pay
        deal(address(pts[_tempIndex]), charlie, ONE_UNDERLYING);
        deal(address(underlying), charlie, ONE_UNDERLYING);

        // In the callback, swap on Napier pool.
        vm.startPrank(charlie); // impersonate MockCallbackReceiver to receive callback from Napier pool
        SwapInput memory input = SwapInput(underlying, pts[_tempIndex]);
        if (_tempPtForUnderlying) {
            bytes memory data = abi.encode(CallbackInputType.SwapPtForUnderlying, input);
            // NOTE: Tricrypto `calc_token_amount` should be guarded against (read-only) reentrancy call but currently it is not.
            // Practically after triggering swapCallback, at point where `add_liquidity` or `remove_liquidity_one_coin` to Tricrypto is called, Tricrypto and then Napier pool will revert.
            // It seems to prevent a kind of reentrancy attack but it should revert at the point where `calc_token_amount` is called.
            // TODO: Engage with the Curve team to implement protections against read-only reentrancy.
            // Ensure that Tricrypto `add_liquidity` is called
            vm.expectCall(address(tricrypto), abi.encodeWithSignature("add_liquidity(uint256[3],uint256)"));
            pool.swapPtForUnderlying(_tempIndex, ONE_UNDERLYING, address(0xcafe), data);
        } else {
            bytes memory data = abi.encode(CallbackInputType.SwapUnderlyingForPt, input);
            // Ensure that Tricrypto `remove_liquidity_one_coin` is called
            // NOTE: Same as above
            vm.expectCall(address(tricrypto), abi.encodeWithSelector(tricrypto.remove_liquidity_one_coin.selector));
            pool.swapUnderlyingForPt(_tempIndex, ONE_UNDERLYING, address(0xcafe), data);
        }
        vm.stopPrank();
    }
}
