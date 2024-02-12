// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {RouterSwapFuzzTest} from "../../shared/Swap.t.sol";

contract RouterAddLiquidityOneUnderlyingFuzzTest is RouterSwapFuzzTest {
    address receiver = makeAddr("receiver");

    function setUp() public override {
        super.setUp();
        _deployQuoter();
    }

    function testFuzz_addLiquidityOneUnderlyingWithApprox(
        RandomBasePoolReservesFuzzInput memory input,
        uint256 underlyingsToAdd
    ) public boundRandomBasePoolReservesFuzzInput(input) setUpRandomBasePoolReserves(input.ptsToBasePool) {
        vm.warp(input.timestamp);
        pool.skim(); // reserves in pool may be different from the actual balances. skim to make them equal to the actual balances
        underlyingsToAdd = bound(underlyingsToAdd, ONE_UNDERLYING, 1e6 * ONE_UNDERLYING);

        /// Execute ///
        // 1. Approximate the amount of baseLpt to be swapped out to add liquidity from `underlyingsToAdd` amount of underlying token only
        deal(address(underlying), address(this), underlyingsToAdd, false);
        (bool s, bytes memory result) = address(quoter).staticcall(
            abi.encodeCall(quoter.approxBaseLptToAddLiquidityOneUnderlying, (pool, underlyingsToAdd))
        );
        vm.assume(s);
        uint256 approxBaseLpt = abi.decode(result, (uint256));

        // 2. Add liquidity
        uint256 liquidity = router.addLiquidityOneUnderlying(
            address(pool), underlyingsToAdd, 0, address(this), block.timestamp, approxBaseLpt
        );

        /// Assertion ///
        assertEq(pool.balanceOf(address(this)), liquidity, "didn't receive enough pool lptoken");
        assertReserveBalanceMatch();
        assertNoFundLeftInPoolSwapRouter();
    }
}

contract RouterAddLiquidityOnePtFuzzTest is RouterSwapFuzzTest {
    address receiver = makeAddr("receiver");

    function setUp() public override {
        super.setUp();
        _deployQuoter();
    }

    function testFuzz_addLiquidityOnePtWithApprox(
        uint256 index,
        RandomBasePoolReservesFuzzInput memory input,
        uint256 onePtsToAdd
    ) public boundRandomBasePoolReservesFuzzInput(input) setUpRandomBasePoolReserves(input.ptsToBasePool) {
        vm.warp(input.timestamp);
        pool.skim(); // reserves in pool may be different from the actual balances. skim to make them equal to the actual balances
        onePtsToAdd = bound(onePtsToAdd, ONE_UNDERLYING / 100, 1e6 * ONE_UNDERLYING);
        index = bound(index, 0, N_COINS - 1);

        /// Execute ///
        // 1. Approximate the amount of baseLpt to be swapped out to add liquidity from `ptToAdd` amount of underlying token only
        (bool s, bytes memory result) = address(quoter).staticcall(
            abi.encodeCall(quoter.approxBaseLptToAddLiquidityOnePt, (pool, index, onePtsToAdd))
        );
        vm.assume(s);
        uint256 approxBaseLpt = abi.decode(result, (uint256));
        deal(address(pts[index]), address(this), onePtsToAdd, false);

        uint256 liquidity = router.addLiquidityOnePt(
            address(pool), index, onePtsToAdd, 0, address(this), block.timestamp, approxBaseLpt
        );
        /// Assertion ///
        // The router pulls only amounts needed to the pool, so there will be nothing left except fee in the pool but tokens can remain in the router if any.
        assertEq(pool.balanceOf(address(this)), liquidity, "didn't receive enough pool lptoken");
        assertReserveBalanceMatch();
        assertNoFundLeftInPoolSwapRouter();
    }
}

contract RouterRemoveLiquidityFuzzTest is RouterSwapFuzzTest {
    address receiver = makeAddr("receiver");

    function setUp() public override {
        super.setUp();
        _deployQuoter();
    }

    /// @param input Fuzz input
    /// @param liquidity amount of pool lptoken to remove
    function testFuzz_removeLiquidity(RandomBasePoolReservesFuzzInput memory input, uint256 liquidity)
        public
        boundRandomBasePoolReservesFuzzInput(input)
        setUpRandomReserves(input.ptsToBasePool)
    {
        liquidity = bound(liquidity, 0.00001 * 1e18, pool.totalSupply() * 40 / 100);
        input.timestamp = bound(input.timestamp, input.timestamp, maturity + input.timestamp);

        vm.warp(input.timestamp);
        pool.skim(); // reserves in pool may be different from the actual balances. skim to make them equal to the actual balances

        /// Execute ///
        deal(address(pool), address(this), liquidity, false);
        _approve(pool, address(this), address(router), liquidity);

        // Remove liquidity and get underlying and principal assets
        (uint256 underlyingOut, uint256[3] memory ptsOut) =
            router.removeLiquidity(address(pool), liquidity, 0, [uint256(0), 0, 0], receiver, block.timestamp);

        /// Assertion ///
        assertEq(underlying.balanceOf(address(receiver)), underlyingOut, "didn't receive enough underlying");
        assertEq(pts[0].balanceOf(address(receiver)), ptsOut[0], "didn't receive enough 1th principal token");
        assertEq(pts[1].balanceOf(address(receiver)), ptsOut[1], "didn't receive enough 2th principal token");
        assertEq(pts[2].balanceOf(address(receiver)), ptsOut[2], "didn't receive enough 3th principal token");
        assertReserveBalanceMatch();
        assertNoFundLeftInPoolSwapRouter();
    }
}

contract RouterRemoveLiquidityFuzzETHTest is RouterSwapFuzzTest {
    address receiver = makeAddr("receiver");

    function setUp() public override {
        super.setUp();
        _deployQuoter();
    }

    function _deployUnderlying() internal override {
        _deployWETH();
        underlying = weth;
        uDecimals = 18;
        ONE_UNDERLYING = 1e18;
    }

    function testFuzz_removeLiquidityETH(RandomBasePoolReservesFuzzInput memory input, uint256 liquidity)
        public
        boundRandomBasePoolReservesFuzzInput(input)
        setUpRandomReserves(input.ptsToBasePool)
    {
        liquidity = bound(liquidity, 0.00001 * 1e18, pool.totalSupply() * 40 / 100);
        input.timestamp = bound(input.timestamp, input.timestamp, maturity + input.timestamp);

        vm.warp(input.timestamp);
        pool.skim(); // reserves in pool may be different from the actual balances. skim to make them equal to the actual balances

        /// Execute ///
        deal(address(pool), address(this), liquidity, false);
        _approve(pool, address(this), address(router), liquidity);

        // Remove liquidity and get underlying and principal assets
        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeCall(
            router.removeLiquidity, (address(pool), liquidity, 0, [uint256(0), 0, 0], receiver, block.timestamp)
        );
        // Unwrap WETH, and send ETH to receiver
        data[1] = abi.encodeCall(router.unwrapWETH9, (0, receiver));
        address[] memory tokens = new address[](3);
        tokens[0] = address(pts[0]);
        tokens[1] = address(pts[1]);
        tokens[2] = address(pts[2]);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 0;
        amounts[1] = 0;
        amounts[2] = 0;
        data[2] = abi.encodeCall(router.sweepTokens, (tokens, amounts, receiver));
        bytes[] memory ret = router.multicall(data);
        (uint256 underlyingOut, uint256[3] memory ptsOut) = abi.decode(ret[0], (uint256, uint256[3]));

        /// Assertion ///
        assertEq(underlying.balanceOf(address(receiver)), underlyingOut, "didn't receive enough underlying");
        assertEq(pts[0].balanceOf(address(receiver)), ptsOut[0], "didn't receive enough 1th principal token");
        assertEq(pts[1].balanceOf(address(receiver)), ptsOut[1], "didn't receive enough 2th principal token");
        assertEq(pts[2].balanceOf(address(receiver)), ptsOut[2], "didn't receive enough 3th principal token");
        assertReserveBalanceMatch();
        assertNoFundLeftInPoolSwapRouter();
    }
}

contract RouterRemoveLiquidityOnePtFuzzTest is RouterSwapFuzzTest {
    address receiver = makeAddr("receiver");

    function setUp() public override {
        super.setUp();
        _deployQuoter();
    }

    function testFuzz_removeLiquidityOnePtWithApprox(
        uint256 index,
        RandomBasePoolReservesFuzzInput memory input,
        uint256 liquidity
    ) public boundRandomBasePoolReservesFuzzInput(input) setUpRandomReserves(input.ptsToBasePool) {
        index = bound(index, 0, N_COINS - 1);
        liquidity = bound(liquidity, 0.00001 * 1e18, pool.totalSupply() * 25 / 100);

        vm.warp(input.timestamp);
        pool.skim(); // reserves in pool may be different from the actual balances. skim to make them equal to the actual balances

        /// Execute ///
        deal(address(pool), address(this), liquidity, false);
        _approve(pool, address(this), address(router), liquidity);
        (bool s, bytes memory result) =
            address(quoter).staticcall(abi.encodeCall(quoter.approxBaseLptToRemoveLiquidityOnePt, (pool, liquidity)));
        vm.assume(s);
        uint256 approxBaseLpt = abi.decode(result, (uint256));

        // Remove liquidity and get only one principal token

        uint256 ptOut = router.removeLiquidityOnePt(
            address(pool), index, liquidity, 0, address(0xABCD), block.timestamp, approxBaseLpt
        );

        /// Assertion ///
        assertEq(pts[index].balanceOf(address(0xABCD)), ptOut, "didn't receive enough pool lptoken");
        assertReserveBalanceMatch();
        assertNoFundLeftInPoolSwapRouter();
    }
}

contract RouterRemoveLiquidityOneUnderlyingFuzzTest is RouterSwapFuzzTest {
    address receiver = makeAddr("receiver");

    function setUp() public override {
        super.setUp();
        _deployQuoter();
    }

    function testFuzz_removeLiquidityOneUnderlying(
        uint256 index,
        RandomBasePoolReservesFuzzInput memory input,
        uint256 liquidity
    ) public boundRandomBasePoolReservesFuzzInput(input) setUpRandomReserves(input.ptsToBasePool) {
        index = bound(index, 0, N_COINS - 1);
        liquidity = bound(liquidity, 0.00001 * 1e18, pool.totalSupply() * 40 / 100);
        input.timestamp = bound(input.timestamp, input.timestamp, maturity + input.timestamp); // jump to timestamp before maturity or after maturity

        vm.warp(input.timestamp);
        pool.skim(); // reserves in pool may be different from the actual balances. skim to make them equal to the actual balances

        /// Execute ///
        deal(address(pool), address(this), liquidity, false);
        _approve(pool, address(this), address(router), liquidity);

        // Remove liquidity and get only underlying token
        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeCall(
            router.removeLiquidityOneUnderlying, (address(pool), index, liquidity, 0, receiver, block.timestamp)
        );
        data[1] = abi.encodeCall(router.sweepToken, (address(pts[index]), 0, receiver));
        data[2] = abi.encodeCall(router.sweepToken, (address(tricrypto), 0, receiver));
        bytes[] memory ret = router.multicall(data);
        uint256 underlyingOut = abi.decode(ret[0], (uint256));

        /// Assertion ///
        assertEq(underlying.balanceOf(address(receiver)), underlyingOut, "didn't receive enough underlying");
        assertReserveBalanceMatch();
        assertNoFundLeftInPoolSwapRouter();
    }
}

contract RouterRemoveLiquidityOneUnderlyingETHFuzzTest is RouterSwapFuzzTest {
    address receiver = makeAddr("receiver");

    function setUp() public override {
        super.setUp();
        _deployQuoter();
    }

    function _deployUnderlying() internal override {
        _deployWETH();
        underlying = weth;
        uDecimals = 18;
        ONE_UNDERLYING = 1e18;
    }

    function testFuzz_removeLiquidityOneUnderlyingETH(
        uint256 index,
        RandomBasePoolReservesFuzzInput memory input,
        uint256 liquidity
    ) public boundRandomBasePoolReservesFuzzInput(input) setUpRandomReserves(input.ptsToBasePool) {
        index = bound(index, 0, N_COINS - 1);
        liquidity = bound(liquidity, 0.00001 * 1e18, pool.totalSupply() * 40 / 100);
        input.timestamp = bound(input.timestamp, input.timestamp, maturity + input.timestamp); // jump to timestamp before maturity or after maturity

        pool.skim(); // reserves in pool may be different from the actual balances. skim to make them equal to the actual balances
        vm.warp(input.timestamp);

        /// Execute ///
        deal(address(pool), address(this), liquidity, false);
        _approve(pool, address(this), address(router), liquidity);

        // Remove liquidity and router receive only WETH (underlying)
        bytes[] memory data = new bytes[](4);
        data[0] = abi.encodeCall(
            router.removeLiquidityOneUnderlying, (address(pool), index, liquidity, 0, address(router), block.timestamp)
        );
        // Unwrap WETH, and send ETH to receiver
        data[1] = abi.encodeCall(router.unwrapWETH9, (0, receiver));
        data[2] = abi.encodeCall(router.sweepToken, (address(pts[index]), 0, receiver));
        data[3] = abi.encodeCall(router.sweepToken, (address(tricrypto), 0, receiver));
        bytes[] memory ret = router.multicall(data);
        uint256 underlyingOut = abi.decode(ret[0], (uint256));

        /// Assertion ///
        assertEq(receiver.balance, underlyingOut, "didn't receive enough underlying");
        assertReserveBalanceMatch();
        assertNoFundLeftInPoolSwapRouter();
    }
}
