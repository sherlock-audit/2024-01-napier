// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {PoolSwapFuzzTest} from "../../shared/Swap.t.sol";

import {CallbackInputType, AddLiquidityInput} from "../../shared/CallbackInputType.sol";

contract PoolAddLiquidityFuzzTest is PoolSwapFuzzTest {
    /// @dev Authorized address to call `addLiquidity`.
    /// @dev MockCallbackReceiver code is deployed to this address.
    address alice = makeAddr("alice");

    function setUp() public override {
        super.setUp();
        _deployMockCallbackReceiverTo(alice); // authorize alice to receive callbacks
    }

    function testFuzz_addLiquidity(
        RandomBasePoolReservesFuzzInput memory input,
        uint256 underlyingIn,
        uint256 baseLptIn,
        address recipient
    ) public boundRandomBasePoolReservesFuzzInput(input) setUpRandomReserves(input.ptsToBasePool) {
        // setup
        assumeNotZeroAddress(recipient);
        deal(address(pool), recipient, 0, false); // ensure recipient has no tokens for later assertions
        pool.skim(); // sweep excess tokens in pool

        underlyingIn = bound(underlyingIn, 100, 1e9 * ONE_UNDERLYING);
        baseLptIn = bound(baseLptIn, 1e9, 1e9 * WAD);
        deal(address(underlying), alice, underlyingIn, false);
        deal(address(tricrypto), alice, baseLptIn, false);

        // pre-condition
        uint256 preTotalLp = pool.totalSupply();
        uint256 preTotalBaseLpt = pool.totalBaseLpt();
        uint256 preTotalUnderlying = pool.totalUnderlying();

        // execution: add liquidity
        vm.startPrank(alice);
        uint256 liquidity = pool.addLiquidity(
            underlyingIn,
            baseLptIn,
            recipient,
            abi.encode(
                CallbackInputType.AddLiquidity, AddLiquidityInput({underlying: underlying, tricrypto: tricrypto})
            )
        );
        vm.stopPrank();

        // post-condition
        assertEq(pool.balanceOf(recipient), liquidity, "liquidity should be minted to recipient");
        assertEq(pool.totalSupply(), liquidity + preTotalLp, "total supply should increase");
        assertPoolReserveRatio(
            [preTotalBaseLpt, preTotalUnderlying],
            [uint256(pool.totalBaseLpt()), pool.totalUnderlying()],
            0.0000001 * 1e18
        );
    }
}

contract PoolRemoveLiquidityFuzzTest is PoolSwapFuzzTest {
    function testFuzz_removeLiquidity(
        RandomBasePoolReservesFuzzInput memory input,
        uint256 liquidity,
        address recipient
    ) public boundRandomBasePoolReservesFuzzInput(input) setUpRandomReserves(input.ptsToBasePool) {
        uint256 preTotalLp = pool.totalSupply();
        // setup
        vm.assume(recipient != address(pool) && recipient != address(0));
        pool.skim(); // sweep excess tokens in pool
        deal(address(tricrypto), recipient, 0, false); // ensure recipient has no tokens for later assertions
        deal(address(underlying), recipient, 0, false); // ensure recipient has no tokens for later assertions

        // Note: Withdrawing tons of liquidity (> 99%) from the pool will cause the reserve ratio to change due to rounding errors if underlying token decimals is smaller than base token decimals.
        liquidity = bound(liquidity, 10, preTotalLp * 90 / 100);
        deal(address(pool), address(0xcafe), liquidity, false); // cheat to get liquidity

        // pre-condition
        uint256 preTotalBaseLpt = pool.totalBaseLpt();
        uint256 preTotalUnderlying = pool.totalUnderlying();

        // execution: remove liquidity
        vm.startPrank(address(0xcafe));
        pool.transfer(address(pool), liquidity);
        (uint256 underlyingOut, uint256 baseLptOut) = pool.removeLiquidity(recipient);
        vm.stopPrank();

        // post-condition
        assertEq(pool.balanceOf(address(pool)), 0, "liquidity should be burned from pool");
        assertEq(pool.totalSupply(), preTotalLp - liquidity, "total supply should decrease");
        assertEq(underlying.balanceOf(recipient), underlyingOut, "underlying should be returned to pool");
        assertEq(tricrypto.balanceOf(recipient), baseLptOut, "base lpt should be returned to pool");
        assertSolvencyReserve();
        assertPoolReserveRatio(
            [preTotalBaseLpt, preTotalUnderlying],
            [uint256(pool.totalBaseLpt()), pool.totalUnderlying()],
            0.0000001 * 1e18
        );
    }
}
