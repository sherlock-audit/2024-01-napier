// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

import {PoolSwapFuzzTest} from "../../shared/Swap.t.sol";
import {CallbackInputType, AddLiquidityInput} from "../../shared/CallbackInputType.sol";
import {Math} from "@openzeppelin/contracts@4.9.3/utils/math/Math.sol";

import {INapierSwapCallback} from "src/interfaces/INapierSwapCallback.sol";
import {IQuoter} from "src/interfaces/IQuoter.sol";
import {Errors} from "src/libs/Errors.sol";

contract QuoteTest is PoolSwapFuzzTest {
    address alice = makeAddr("alice");
    IQuoter quoter;

    function setUp() public override {
        super.setUp();
        quoter = IQuoter(_deployQuoter());
        // Set up liquidity
        _issueAndAddLiquidities(
            address(this), 3000 * ONE_UNDERLYING, [1000 * ONE_UNDERLYING, 999 * ONE_UNDERLYING, 1001 * ONE_UNDERLYING]
        );
        _approve(underlying, address(this), address(router), type(uint128).max);
        _approvePts(address(this), address(router), type(uint256).max);
        skip(1 days);
        _approve(pool, address(this), address(router), type(uint256).max);

        _deployMockCallbackReceiverTo(alice);
    }

    function test_basePoolLpPrice(SwapFuzzInput memory input)
        public
        boundSwapFuzzInput(input)
        setUpRandomReserves(input.ptsToBasePool)
    {
        uint256 lpPrice = quoter.quoteBasePoolLpPrice(pool);
        assertGt(lpPrice, 0, "lpPrice should be greater than 0");
        assertLt(lpPrice, 3 * 1e18, "lpPrice should be less than 3");

        // Effective price should be close to the spot price if price impact is small enough
        deal(address(tricrypto), address(this), 1e15, false);
        uint256 out = pool.swapExactBaseLpTokenForUnderlying(1e15, address(this)); // swap small amount of baseLpt to underlying
        uint256 effectivePrice = (out * 1e18 / ONE_UNDERLYING) * WAD / 1e15; // Effective price of underlying token.
        assertApproxEqRel(effectivePrice, lpPrice, 0.01 * 1e18, "effective price of underlying token");
    }

    /// @dev Assertion: IF balance1 < balance0 < balance2 THEN, pt1Price > pt0Price > pt2Price
    function test_ptPrices(SwapFuzzInput memory input)
        public
        boundSwapFuzzInput(input)
        setUpRandomReserves(input.ptsToBasePool)
    {
        // Ensure that the balances are different enough
        vm.assume(
            tricrypto.balances(1) + 10 * ONE_UNDERLYING < tricrypto.balances(0)
                && tricrypto.balances(0) + 10 * ONE_UNDERLYING < tricrypto.balances(2)
        );
        vm.warp(input.timestamp); // tricrypto price oracle is EMA. advance time to update price correctly

        uint256 pt0Price = quoter.quotePtPrice(pool, 0);
        uint256 pt1Price = quoter.quotePtPrice(pool, 1);
        uint256 pt2Price = quoter.quotePtPrice(pool, 2);

        // Note: `ptPrice` CAN be greater than 1e18.
        // pt1Price > pt0Price > pt2Price > 0
        assertGt(pt1Price, pt0Price, "[expected] pt1Price > pt0Price");
        assertGt(pt0Price, pt2Price, "[expected] pt0Price > pt2Price");
        assertGt(pt2Price, 0, "[expected] pt2Price > 0");
    }

    function test_swapCallback_RevertIf_NotPool() public {
        vm.expectRevert(Errors.RouterPoolNotFound.selector);
        vm.prank(address(0xbabe));
        INapierSwapCallback(address(quoter)).swapCallback(1, -100, abi.encode(1, 0, address(0)));
    }

    /////////////////// Quote for swap ///////////////////

    modifier boundUint256s(uint256[3] memory amounts, uint256 min, uint256 upper) {
        amounts = bound(amounts, min, upper);
        _;
    }

    /// @dev the quote should be close to the amount in/out calculated based on spot price if price impact is small enough
    function test_quotePtForUnderlying(SwapFuzzInput memory input)
        public
        boundSwapFuzzInput(input)
        boundUint256s(input.ptsToBasePool, 1_000, 100 * ONE_UNDERLYING)
        setUpRandomBasePoolReserves(input.ptsToBasePool)
    {
        uint256 index = input.index;
        vm.warp(input.timestamp);
        uint256 ptIn = ONE_UNDERLYING / 1_000; // small amount

        uint256 ptPrice = quoter.quotePtPrice(pool, index);
        (uint256 underlyingOut,) = quoter.quotePtForUnderlying(pool, index, ptIn);

        assertApproxEqAbs(underlyingOut, ptPrice * ptIn / WAD, ONE_UNDERLYING / 100_000, "quote pt for underlying");
    }

    /// @dev the quote should be close to the amount in/out calculated based on spot price if price impact is small enough
    function test_quoteUnderlyingForPt(SwapFuzzInput memory input)
        public
        boundSwapFuzzInput(input)
        boundUint256s(input.ptsToBasePool, 1_000, 100 * ONE_UNDERLYING)
        setUpRandomBasePoolReserves(input.ptsToBasePool)
    {
        uint256 index = input.index;
        vm.warp(input.timestamp);
        uint256 ptOutDesired = ONE_UNDERLYING / 1_000; // small amount

        uint256 ptPrice = quoter.quotePtPrice(pool, index);
        (uint256 underlyingIn,) = quoter.quoteUnderlyingForPt(pool, index, ptOutDesired);

        assertApproxEqAbs(
            underlyingIn, ptPrice * ptOutDesired / WAD, ONE_UNDERLYING / 100_000, "quote underlying for pt"
        );
    }

    /// @dev the quote should be close to the amount in/out calculated based on spot price if price impact is small enough
    function test_quoteYtForUnderlying(SwapFuzzInput memory input)
        public
        boundSwapFuzzInput(input)
        boundUint256s(input.ptsToBasePool, 1_000, 100 * ONE_UNDERLYING)
        setUpRandomBasePoolReserves(input.ptsToBasePool)
    {
        uint256 index = input.index;
        // Note: If timestamp get close to maturity, the price impact would be large and could revert with `RouterInsufficientUnderlyingRepay`.
        vm.warp((maturity - block.timestamp) / 2 + block.timestamp); // closer than half of maturity time
        uint256 ytIn = ONE_UNDERLYING / 1_000; // small amount

        uint256 ytPrice = WAD - quoter.quotePtPrice(pool, index);
        (uint256 underlyingOut,) = quoter.quoteYtForUnderlying(pool, index, ytIn);

        assertApproxEqAbs(underlyingOut, ytPrice * ytIn / WAD, ONE_UNDERLYING / 100_000, "quote yt for underlying");
    }

    function test_quotePtForUnderlying_RevertIf_InsufficientUnderlyingRepay(uint256 index) public {
        vm.assume(index < N_COINS);
        uint256 newscale = adapters[index].scale() * 10 / 12; // decrease scale
        vm.mockCall(
            address(adapters[index]), abi.encodeWithSelector(adapters[index].scale.selector), abi.encode(newscale)
        );

        vm.expectRevert(Errors.RouterInsufficientUnderlyingRepay.selector);
        quoter.quoteYtForUnderlying(pool, index, ONE_UNDERLYING);
    }

    function test_quoteAddLiquidity(
        RandomBasePoolReservesFuzzInput memory input,
        uint256[3] memory ptsIn,
        uint256 underlyingIn
    )
        public
        boundRandomBasePoolReservesFuzzInput(input)
        boundUint256s(ptsIn, ONE_UNDERLYING, 100 * ONE_UNDERLYING)
        setUpRandomReserves(input.ptsToBasePool)
    {
        underlyingIn = bound(underlyingIn, ONE_UNDERLYING, 100 * ONE_UNDERLYING);
        vm.warp(input.timestamp);

        uint256 snapshot = vm.snapshot();
        uint256 liquidity;
        {
            // avoid stack too deep
            deal(address(underlying), address(this), underlyingIn, false);

            for (uint256 i; i < N_COINS; i++) {
                deal(address(pts[i]), address(this), ptsIn[i], false);
            }

            bytes memory data = abi.encodeCall(
                router.addLiquidity, (address(pool), underlyingIn, ptsIn, 0, address(this), block.timestamp)
            );
            (bool s, bytes memory returndata) = address(router).call(data);
            vm.assume(s); // skip test if addLiquidity fails
            liquidity = abi.decode(returndata, (uint256));
        }
        vm.revertTo(snapshot); // revert to state before addLiquidity and check quote result
        (uint256 liquidityApprox,) = quoter.quoteAddLiquidity(pool, ptsIn, underlyingIn);
        assertApproxEqAbs(liquidity, liquidityApprox, 1, "quote liquidity token amount");
    }

    function test_quoteAddLiquidityOneUnderlying(RandomBasePoolReservesFuzzInput memory input, uint256 underlyingIn)
        public
        boundRandomBasePoolReservesFuzzInput(input)
        setUpRandomReserves(input.ptsToBasePool)
    {
        underlyingIn = bound(underlyingIn, ONE_UNDERLYING, 100 * ONE_UNDERLYING);
        vm.warp(input.timestamp);
        uint256 baseLptOut = quoter.approxBaseLptToAddLiquidityOneUnderlying(pool, underlyingIn);

        uint256 snapshot = vm.snapshot();
        uint256 liquidity;
        {
            // avoid stack too deep
            deal(address(underlying), address(this), underlyingIn, false);

            bytes memory data = abi.encodeCall(
                router.addLiquidityOneUnderlying,
                (address(pool), underlyingIn, 0, address(this), block.timestamp, baseLptOut)
            );
            (bool s, bytes memory returndata) = address(router).call(data);
            vm.assume(s); // skip test if call fails
            liquidity = abi.decode(returndata, (uint256));
        }
        vm.revertTo(snapshot); // revert to state before addLiquidity and check quote result
        (uint256 liquidityApprox, uint256 baseLptSwap) = quoter.quoteAddLiquidityOneUnderlying(pool, underlyingIn);
        assertApproxEqAbs(liquidity, liquidityApprox, 1, "quote liquidity token amount");
        assertEq(baseLptOut, baseLptSwap, "quote Base Lpt swap amount");
    }

    function test_quoteAddLiquidityOnePt(SwapFuzzInput memory input, uint256 ptAmount)
        public
        boundSwapFuzzInput(input)
        setUpRandomReserves(input.ptsToBasePool)
    {
        uint256 index = input.index;
        ptAmount = bound(ptAmount, ONE_UNDERLYING, 100 * ONE_UNDERLYING);
        vm.warp(input.timestamp);
        (bool s1, bytes memory ret1) =
            address(quoter).call(abi.encodeCall(quoter.approxBaseLptToAddLiquidityOnePt, (pool, index, ptAmount)));
        vm.assume(s1); // skip test if call fails
        uint256 baseLptIn = abi.decode(ret1, (uint256));

        uint256 snapshot = vm.snapshot();
        uint256 liquidity;
        {
            // avoid stack too deep
            deal(address(pts[index]), address(this), ptAmount, false);

            bytes memory data = abi.encodeCall(
                router.addLiquidityOnePt, (address(pool), index, ptAmount, 0, address(this), block.timestamp, baseLptIn)
            );
            (bool s, bytes memory returndata) = address(router).call(data);
            vm.assume(s); // skip test if call fails
            liquidity = abi.decode(returndata, (uint256));
        }
        vm.revertTo(snapshot); // revert to state before addLiquidity and check quote result
        (uint256 liquidityApprox, uint256 baseLptSwapApprox) = quoter.quoteAddLiquidityOnePt(pool, index, ptAmount);
        assertApproxEqRel(liquidity, liquidityApprox, 0.00001 * 1e18, "quote liquidity token amount");
        assertEq(baseLptIn, baseLptSwapApprox, "quote Base Lpt swap amount");
    }

    function test_quoteUnderlyingForYt(SwapFuzzInput memory input, uint256 ytDesired, uint256 cscale)
        public
        boundSwapFuzzInput(input)
        boundUint256s(input.ptsToBasePool, 1_000, 100 * ONE_UNDERLYING)
        setUpRandomBasePoolReserves(input.ptsToBasePool)
    {
        uint256 index = input.index;
        ytDesired = bound(ytDesired, ONE_UNDERLYING / 100, yts[index].totalSupply() * 30 / 100);

        // Pre-condition
        vm.warp(input.timestamp);

        // mock scale change
        {
            uint256 scale = adapters[index].scale();
            cscale = bound(cscale, scale * 90 / 100, scale * 180 / 100);
            mockCallAdapterScale(index, cscale);
        }
        // Simulate swap
        uint256 snapshot = vm.snapshot();
        uint256 expected;
        {
            // avoid stack too deep
            deal(address(underlying), address(this), type(uint128).max, false);
            _approve(underlying, address(this), address(router), type(uint128).max);
            bytes memory data = abi.encodeCall(
                router.swapUnderlyingForYt,
                (address(pool), index, ytDesired, type(uint128).max, address(this), block.timestamp)
            );
            (bool s, bytes memory returndata) = address(router).call(data);
            vm.assume(s); // skip test if swap fails
            expected = abi.decode(returndata, (uint256));
        }
        // Execute
        vm.revertTo(snapshot); // revert to state before swap and check quote result
        (uint256 underlyingIn,) = quoter.quoteUnderlyingForYt(pool, index, ytDesired);

        // Assert
        assertApproxEqRel(underlyingIn, expected, 0.000001 * 1e18, "quote underlying for yt");

        vm.clearMockedCalls();
    }

    function mockCallAdapterScale(uint256 index, uint256 scale) internal {
        vm.mockCall(address(adapters[index]), abi.encodeWithSelector(adapters[index].scale.selector), abi.encode(scale));
    }

    /////////////////// Approximation ///////////////////

    function test_approxPtExactUnderlyingIn(SwapFuzzInput memory input, uint256 underlyingDesired)
        public
        boundSwapFuzzInput(input)
        setUpRandomReserves(input.ptsToBasePool)
    {
        uint256 index = input.index;
        vm.warp(input.timestamp);
        // swap more than 40% of the reserve would result in underlying price < 1 and revert
        underlyingDesired =
            bound(underlyingDesired, ONE_UNDERLYING / 100, underlying.balanceOf(address(pool)) * 40 / 100);

        uint256 approxPtOut = quoter.approxPtForExactUnderlyingIn(pool, index, underlyingDesired);
        (uint256 exact,) = quoter.quoteUnderlyingForPt(pool, index, approxPtOut);

        assertApproxEqAbs(underlyingDesired, exact, 0.001 * 1e18, "approx exact underlying in");
    }

    function test_approxPtExactUnderlyingOut(SwapFuzzInput memory input, uint256 underlyingDesired)
        public
        boundSwapFuzzInput(input)
        setUpRandomReserves(input.ptsToBasePool)
    {
        uint256 index = input.index;
        vm.warp(input.timestamp);
        // swap more than 80% of the reserve would result in reserve proportion too high and revert
        // swap more than 40% of the reserve(=most of tricrypto Lp total supply) would result in `tricrypto.calc_withdraw_one_coin` revert.
        underlyingDesired =
            bound(underlyingDesired, ONE_UNDERLYING / 100, underlying.balanceOf(address(pool)) * 40 / 100);

        uint256 approxPtIn = quoter.approxPtForExactUnderlyingOut(pool, index, underlyingDesired);
        (uint256 actual,) = quoter.quotePtForUnderlying(pool, index, approxPtIn);

        assertApproxEqAbs(underlyingDesired, actual, 0.001 * 1e18, "approx actual underlying out");
    }

    /// forge-config: default.fuzz.runs = 2000
    function test_approxYtForExactUnderlyingOut(SwapFuzzInput memory input, uint256 underlyingDesired, uint256 cscale)
        public
        boundSwapFuzzInput(input)
        setUpRandomReserves(input.ptsToBasePool)
    {
        uint256 index = input.index;
        underlyingDesired = bound(underlyingDesired, ONE_UNDERLYING / 100, pool.totalUnderlying() * 30 / 100);
        // Pre-condition
        vm.warp(input.timestamp);
        {
            // mock scale change
            uint256 scale = adapters[index].scale();
            cscale = bound(cscale, scale * 90 / 100, scale * 180 / 100);
            mockCallAdapterScale(index, cscale);
        }
        // Execute
        uint256 snapshot = vm.snapshot();
        bytes memory data = abi.encodeCall(quoter.approxYtForExactUnderlyingOut, (pool, index, underlyingDesired));
        (bool s, bytes memory returndata) = address(quoter).call(data);
        if (!s) {
            // If the price of the principal token is close or higher than 1, the tx could revert with `RouterInsufficientUnderlyingRepay`.
            // In this case, we just skip the test.
            if (bytes4(returndata) != Errors.RouterInsufficientUnderlyingRepay.selector) bubbleUpRevert(returndata);
            else vm.assume(false);
        }
        vm.revertTo(snapshot);
        uint256 approxYtIn = abi.decode(returndata, (uint256));
        (uint256 actual,) = quoter.quoteYtForUnderlying(pool, index, approxYtIn);

        assertApproxEqAbs(underlyingDesired, actual, 0.01 * 1e18, "approx actual underlying in");
    }

    function test_approxYtForExactUnderlyingIn(SwapFuzzInput memory input, uint256 ytDesired, uint256 cscale)
        public
        boundSwapFuzzInput(input)
        setUpRandomReserves(input.ptsToBasePool)
    {
        uint256 index = input.index;
        ytDesired = bound(ytDesired, ONE_UNDERLYING / 100, pool.totalUnderlying() * 80 / 100);
        // Pre-condition
        vm.warp(input.timestamp);
        {
            // mock scale change
            uint256 scale = adapters[index].scale();
            cscale = bound(cscale, scale * 90 / 100, scale * 180 / 100);
            mockCallAdapterScale(index, cscale);
        }
        // Execute
        uint256 expected; // expected amount of underlying to be swapped in
        uint256 snapshot = vm.snapshot();

        {
            // Simulate swap underlying for yt
            // avoid stack too deep
            deal(address(underlying), address(this), type(uint128).max, false); // unlimited underlying
            _approve(underlying, address(this), address(router), type(uint128).max);
            bytes memory data = abi.encodeCall(
                router.swapUnderlyingForYt,
                (address(pool), index, ytDesired, type(uint128).max, address(this), block.timestamp)
            );
            (bool s, bytes memory ret) = address(router).call(data);
            vm.assume(s); // skip test if swap fails
            expected = abi.decode(ret, (uint256));
        }

        vm.assume(expected > ONE_UNDERLYING / 100); // skip if no underlying deposit required (approximation fails)
        vm.revertTo(snapshot); // revert to state before swap and check quote result

        (bool success, bytes memory returndata) = address(quoter).call(
            abi.encodeWithSelector(quoter.approxYtForExactUnderlyingIn.selector, pool, index, expected)
        );
        if (!success) {
            // skip if no underlying deposit required
            vm.assume(
                !checkEq0(
                    returndata,
                    abi.encodeWithSelector(Errors.ApproxFailWithHint.selector, "No underlying deposit required")
                )
            );
            bubbleUpRevert(returndata);
        }
        // Assert approximation result
        uint256 approxYt = abi.decode(returndata, (uint256));
        assertApproxEqAbs(ytDesired, approxYt, 0.01 * 1e18, "approx exact underlying in");
    }

    /// Setup ///
    // 1. Random Napier Pool reserves
    // 2. Reserve in pool is equal to the actual balances
    // 3. Random timestamp
    /// @param underlyingsToAdd total amount of underlying token to add liquidity
    function test_approxBaseLptToAddLiquidityOneUnderlying(SwapFuzzInput memory input, uint256 underlyingsToAdd)
        public
        boundSwapFuzzInput(input)
        setUpRandomReserves(input.ptsToBasePool)
    {
        // Ensure that no tokens are left in the pool after setup operation
        pool.skim(); // reserves in pool may be different from the actual balances. skim to make them equal to the actual balances
        vm.warp(input.timestamp);

        // To prevent the underlying price from dropping below 1, limit the amount of underlyingsToAdd.
        underlyingsToAdd = bound(underlyingsToAdd, ONE_UNDERLYING / 100, pool.totalUnderlying() * 40 / 100);

        deal(address(underlying), alice, underlyingsToAdd, false);
        _approve(underlying, alice, address(pool), type(uint256).max);
        /// Execute ///
        // 1. Approximate the amount of baseLpt to be swapped out to add liquidity from `underlyingsToAdd` amount of underlying token only
        uint256 approxBaseLpt = quoter.approxBaseLptToAddLiquidityOneUnderlying(pool, underlyingsToAdd);
        vm.prank(alice);
        uint256 spent = pool.swapUnderlyingForExactBaseLpToken(approxBaseLpt, alice);

        /// Pre-condition ///
        // snapshot reserves after swap
        uint256 underlyingReserve = pool.totalUnderlying();
        uint256 baseLptReserve = pool.totalBaseLpt();
        uint256 remainingUnderlying = underlyingsToAdd - spent;

        // 2. Add liquidity to Napier pool based on the result of approximation
        vm.prank(alice);
        pool.addLiquidity(
            remainingUnderlying,
            approxBaseLpt,
            alice,
            abi.encode(CallbackInputType.AddLiquidity, AddLiquidityInput(underlying, tricrypto))
        );

        /// Assertion ///
        // 1. Ensure that all `underlyingsToAdd` have been used.
        assertApproxEqAbs(underlying.balanceOf(alice), 0, 10, "should use all underlying token to add liquidity");

        // 2. Verify that the reserve ratio remains the same after the swap and liquidity addition (Pool invariant).
        assertPoolReserveRatio(
            [baseLptReserve, underlyingReserve],
            [uint256(pool.totalBaseLpt()), pool.totalUnderlying()],
            0.0000001 * 1e18
        );
        assertReserveBalanceMatch();
    }

    /// Setup ///
    // 1. Random Napier Pool reserves
    // 2. Reserve in pool is equal to the actual balances
    // 3. Random timestamp
    /// @param ptToAdd total amount of principal token to add liquidity
    function test_approxBaseLptToAddLiquidityOnePt(SwapFuzzInput memory input, uint256 ptToAdd)
        public
        boundSwapFuzzInput(input)
        setUpRandomReserves(input.ptsToBasePool)
    {
        uint256 index = input.index;
        // Ensure that no tokens are left in the pool after setup operation
        pool.skim(); // reserves in pool may be different from the actual balances. skim to make them equal to the actual balances
        vm.warp(input.timestamp);

        // To prevent the Tricrypto pool from going to imbalance state, limit the amount of ptToAdd.
        // max ptToAdd = 80% of the Base pool LP token reserve * N_COINS
        ptToAdd = bound(ptToAdd, ONE_UNDERLYING / 10, pool.totalBaseLpt() * 80 / 100 * N_COINS * ONE_UNDERLYING / WAD);

        uint256[3] memory ptsIn;
        ptsIn[index] = ptToAdd;
        deal(address(pts[index]), alice, ptToAdd, false);
        _approvePts(alice, address(tricrypto), type(uint256).max);
        _approve(tricrypto, alice, address(pool), type(uint256).max);

        /// Execute ///
        // 1. Approximate the amount of baseLpt to be swapped out to add liquidity from `ptToAdd` amount of underlying token only
        uint256 approxBaseLpt = quoter.approxBaseLptToAddLiquidityOnePt(pool, index, ptToAdd);
        // Convert all pt to baseLpt
        vm.startPrank(alice);
        uint256 baseLptToAdd = tricrypto.add_liquidity(ptsIn, 0);
        uint256 underlyingIn = pool.swapExactBaseLpTokenForUnderlying(approxBaseLpt, alice);
        vm.stopPrank();

        /// Pre-condition ///
        // snapshot reserves after swap
        uint256 underlyingReserve = pool.totalUnderlying();
        uint256 baseLptReserve = pool.totalBaseLpt();
        uint256 remainingBaseLpt = baseLptToAdd - approxBaseLpt;
        // 1. Add liquidity to Napier pool based on the result of approximation
        vm.prank(alice);
        pool.addLiquidity(
            underlyingIn,
            remainingBaseLpt,
            alice,
            abi.encode(CallbackInputType.AddLiquidity, AddLiquidityInput(underlying, tricrypto))
        );

        /// Assertion ///
        // 2. Verify that the reserve ratio remains the same after the swap and liquidity addition (Pool invariant).
        assertPoolReserveRatio(
            [baseLptReserve, underlyingReserve],
            [uint256(pool.totalBaseLpt()), pool.totalUnderlying()],
            0.0000001 * 1e18
        );
        assertReserveBalanceMatch();
    }

    /// Setup ///
    // 1. Random Napier Pool reserves
    // 2. Reserve in pool is equal to the actual balances
    // 3. Random timestamp
    /// @param liquidity liquidity to remove from Napier pool
    function test_approxBaseLptToRemoveLiquidityOnePt(SwapFuzzInput memory input, uint256 liquidity)
        public
        boundSwapFuzzInput(input)
        setUpRandomReserves(input.ptsToBasePool)
    {
        // Ensure that no tokens are left in the pool after setup operation
        pool.skim(); // reserves in pool may be different from the actual balances. skim to make them equal to the actual balances
        vm.warp(input.timestamp);

        // To prevent the exchange rate of underlying to baseLpt from dropping below 1, limit the amount of baseLpt to remove and liquidity to remove.
        liquidity = bound(liquidity, 0.00001 * 1e18, pool.totalSupply() * 30 / 100);

        /// Execute ///
        uint256 approxBaseLpt = quoter.approxBaseLptToRemoveLiquidityOnePt(pool, liquidity);

        // Remove liquidity from Napier pool and convert all underlying to Base Pool LP token based on the result of approximation
        deal(address(pool), address(pool), liquidity, false);
        (uint256 underlyingOut, uint256 baseLptOut) = pool.removeLiquidity(address(this));
        console2.log("underlyingOut :>>", underlyingOut);
        console2.log("baseLptOut :>>", baseLptOut);
        pool.swapUnderlyingForExactBaseLpToken(approxBaseLpt, address(this));
        /// Assertion ///
        assertReserveBalanceMatch();
    }

    function test_approxBaseLptToRemoveLiquidityOnePt_RevertIf_LiquidityZero() public {
        vm.expectRevert(Errors.PoolZeroAmountsInput.selector);
        quoter.approxBaseLptToRemoveLiquidityOnePt(pool, 0);
    }

    /////////////////// Quote for Liquidity addition & removal ///////////////////

    function test_quoteRemoveLiquidityBaseLpt(RandomBasePoolReservesFuzzInput memory input, uint256 liquidity)
        public
        boundRandomBasePoolReservesFuzzInput(input)
        setUpRandomReserves(input.ptsToBasePool)
    {
        pool.skim(); // Ensure that no tokens are left in the pool after setup operation
        liquidity = bound(liquidity, 1000, pool.totalSupply() * 90 / 100);
        deal(address(pool), address(this), liquidity, false); // fund LP token to be burned

        // Pre-condition
        vm.warp(input.timestamp);

        // Execute
        uint256 snapshot = vm.snapshot();
        pool.transfer(address(pool), liquidity); // transfer LP token to be burned
        (bool s, bytes memory returndata) = address(pool).call(abi.encodeCall(pool.removeLiquidity, (address(0xbabe))));
        vm.assume(s); // skip test if tx fails
        vm.revertTo(snapshot);
        (uint256 uActual, uint256 baseLptActual) = abi.decode(returndata, (uint256, uint256));
        (uint256 uWithdrawn, uint256 baseLptWithdrawn) = quoter.quoteRemoveLiquidityBaseLpt(pool, liquidity);

        // Assert
        assertApproxEqAbs(uActual, uWithdrawn, 2, "quote remove liquidity baseLpt");
        assertApproxEqAbs(baseLptActual, baseLptWithdrawn, 2, "quote remove liquidity baseLpt");
    }

    function test_quoteRemoveLiquidity(RandomBasePoolReservesFuzzInput memory input, uint256 liquidity)
        public
        boundRandomBasePoolReservesFuzzInput(input)
        setUpRandomReserves(input.ptsToBasePool)
    {
        pool.skim(); // Ensure that no tokens are left in the pool after setup operation
        liquidity = bound(liquidity, 1e10, pool.totalSupply() * 90 / 100);
        deal(address(pool), address(this), liquidity, false);

        // Pre-condition
        vm.warp(input.timestamp);

        // Execute
        uint256 snapshot = vm.snapshot();
        (bool s, bytes memory returndata) = address(router).call(
            abi.encodeCall(
                router.removeLiquidity,
                // `liquidity` should be bounded somewhat large to avoid revert with insufficient amounts out.
                (address(pool), liquidity, 1, [uint256(1), 1, 1], address(0xbabe), block.timestamp)
            )
        );
        vm.assume(s); // skip test if tx fails
        vm.revertTo(snapshot);
        (uint256 uActual, uint256[3] memory ptsActual) = abi.decode(returndata, (uint256, uint256[3]));
        (uint256 uWithdrawn, uint256[3] memory ptsWithdrawn) = quoter.quoteRemoveLiquidity(pool, liquidity);

        // Assert
        assertApproxEqAbs(uActual, uWithdrawn, 2, "quote withdrawn amount of underlying");
        assertApproxEqAbs(ptsActual[0], ptsWithdrawn[0], 2, "quote withdrawn amount of pt[0]");
        assertApproxEqAbs(ptsActual[1], ptsWithdrawn[1], 2, "quote withdrawn amount of pt[1]");
        assertApproxEqAbs(ptsActual[2], ptsWithdrawn[2], 2, "quote withdrawn amount of pt[2]");
    }

    function test_quoteRemoveLiquidityOnePt(SwapFuzzInput memory input, uint256 liquidity)
        public
        boundSwapFuzzInput(input)
        setUpRandomReserves(input.ptsToBasePool)
    {
        pool.skim(); // Ensure that no tokens are left in the pool after setup operation
        liquidity = bound(liquidity, 1000, pool.totalSupply() * 90 / 100);
        deal(address(pool), address(this), liquidity, false);

        // Pre-condition
        vm.warp(input.timestamp);

        // Execute
        uint256 snapshot = vm.snapshot();
        // Get approx amount of baseLpt to be swapped out used for `removeLiquidityOnePt`
        (bool s1, bytes memory ret1) =
            address(quoter).call(abi.encodeCall(quoter.approxBaseLptToRemoveLiquidityOnePt, (pool, liquidity)));
        vm.assume(s1); // skip test if approximation fails
        uint256 approxBaseLptSwap = abi.decode(ret1, (uint256));
        // Simulate `removeLiquidityOnePt`
        try router.removeLiquidityOnePt(
            address(pool), input.index, liquidity, 1, address(0xbabe), block.timestamp, approxBaseLptSwap
        ) returns (uint256 ptActual) {
            vm.revertTo(snapshot); // revert to state before swap and check quote result
            (uint256 ptEstimate, uint256 baseLptSwapEstimate,) =
                quoter.quoteRemoveLiquidityOnePt(pool, input.index, liquidity);
            // Assert
            assertApproxEqAbs(ptActual, ptEstimate, 2, "quote remove liquidity one pt");
            assertEq(approxBaseLptSwap, baseLptSwapEstimate, "quote approx baseLpt swap");
        } catch {
            vm.assume(false); // skip test if `removeLiquidityOnePt` fails
        }
    }

    function test_quoteRemoveLiquidityOneUnderlying_BeforeMaturity(
        RandomBasePoolReservesFuzzInput memory input,
        uint256 liquidity
    ) public boundRandomBasePoolReservesFuzzInput(input) setUpRandomReserves(input.ptsToBasePool) {
        pool.skim(); // Ensure that no tokens are left in the pool after setup operation
        liquidity = bound(liquidity, 1000, pool.totalSupply() * 90 / 100);
        deal(address(pool), address(this), liquidity, false);

        // Pre-condition
        vm.warp(input.timestamp); // before maturity
        // Execute & Assert
        _test_quoteRemoveLiquidityOneUnderlying(0, liquidity);
    }

    function test_quoteRemoveLiquidityOneUnderlying_AfterMaturity(SwapFuzzInput memory input, uint256 liquidity)
        public
        boundSwapFuzzInput(input)
        setUpRandomReserves(input.ptsToBasePool)
    {
        pool.skim();
        liquidity = bound(liquidity, 1000, pool.totalSupply() * 90 / 100);
        deal(address(pool), address(this), liquidity, false);

        // Pre-condition
        vm.warp(maturity + input.timestamp); // after maturity
        // Execute & Assert
        _test_quoteRemoveLiquidityOneUnderlying(input.index, liquidity);
    }

    /// @dev Set up should be done before calling this function
    function _test_quoteRemoveLiquidityOneUnderlying(uint256 index, uint256 liquidity) internal {
        // Execute
        uint256 snapshot = vm.snapshot();
        (bool s, bytes memory returndata) = address(router).call(
            abi.encodeCall(
                router.removeLiquidityOneUnderlying,
                (address(pool), index, liquidity, 1, address(0xbabe), block.timestamp)
            )
        );
        vm.assume(s); // skip test if tx fails
        vm.revertTo(snapshot);
        (uint256 uActual) = abi.decode(returndata, (uint256));
        (uint256 uWithdrawn,) = quoter.quoteRemoveLiquidityOneUnderlying(pool, index, liquidity);
        // Assert
        assertApproxEqAbs(uActual, uWithdrawn, 2, "quote remove liquidity one pt");
    }

    /////////////////// Utils ///////////////////

    function bubbleUpRevert(bytes memory returndata) internal pure {
        // The easiest way to bubble the revert reason is using memory via assembly
        assembly {
            revert(add(32, returndata), mload(returndata))
        }
    }
}
