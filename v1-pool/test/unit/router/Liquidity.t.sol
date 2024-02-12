// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../Base.t.sol";
import {
    RouterAddLiquidityTest,
    RouterLiquidityBaseUnitTest,
    RouterRemoveLiquidityBaseUnitTest
} from "../../shared/Liquidity.t.sol";
import {CallbackInputType, SwapInput} from "../../shared/CallbackInputType.sol";

import {NapierRouter} from "src/NapierRouter.sol";
import {IQuoter} from "src/interfaces/IQuoter.sol";

import {Errors} from "src/libs/Errors.sol";
import {FaultyCallbackReceiver} from "../../mocks/FaultyCallbackReceiver.sol";
import {MockFakePool} from "../../mocks/MockFakePool.sol";

contract RouterAddLiquidityUnitTest is RouterAddLiquidityTest {
    function test_RevertIf_Reentrant() public virtual override {
        dealPts(address(0xbad), 1e18, true);
        _approvePts(address(0xbad), address(router), 1e18);
        _expectRevertIf_Reentrant(
            address(0xbad),
            abi.encodeWithSelector(
                router.addLiquidity.selector,
                address(pool),
                1000,
                [1000, 1000, 1000],
                0,
                address(0xbad),
                block.timestamp
            )
        );
        vm.prank(address(0xbad)); // receiver of the callback
        pool.swapPtForUnderlying(
            0, 1, address(0xbad), abi.encode(CallbackInputType.SwapPtForUnderlying, SwapInput(underlying, pts[0]))
        );
    }

    function test_RevertIf_DeadlinePassed() public override {
        vm.expectRevert(Errors.RouterTransactionTooOld.selector);
        router.addLiquidity({
            pool: address(pool),
            underlyingIn: 10 * ONE_UNDERLYING,
            ptsIn: [10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING],
            liquidityMin: 0,
            recipient: address(this),
            deadline: block.timestamp - 1
        });
    }

    function test_RevertIf_MaturityPassed() public virtual override whenMaturityPassed {
        vm.expectRevert(Errors.PoolExpired.selector);
        router.addLiquidity({
            pool: address(pool),
            underlyingIn: 10 * ONE_UNDERLYING,
            ptsIn: [10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING],
            liquidityMin: 0,
            recipient: address(this),
            deadline: block.timestamp
        });
    }

    function test_RevertIf_PoolNotExist() public virtual override {
        MockFakePool fakePool = new MockFakePool();
        vm.expectRevert(Errors.RouterPoolNotFound.selector);
        router.addLiquidity({
            pool: address(fakePool), // non-existent pool
            underlyingIn: 10 * ONE_UNDERLYING,
            ptsIn: [10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING],
            liquidityMin: 10 * 1e18 - 1,
            recipient: address(this),
            deadline: block.timestamp
        });
    }

    function test_RevertIf_InsufficientLpOut() public virtual override {
        vm.expectRevert(Errors.RouterInsufficientLpOut.selector);
        router.addLiquidity({
            pool: address(pool),
            underlyingIn: 10 * ONE_UNDERLYING,
            ptsIn: [10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING],
            liquidityMin: 10 * 1e18 - 1,
            recipient: address(this),
            deadline: block.timestamp
        });
    }

    function test_addLiquidity_WithBalanced() public virtual {
        uint256 liquidity = router.addLiquidity({
            pool: address(pool),
            underlyingIn: 10 * ONE_UNDERLYING,
            ptsIn: [10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING],
            liquidityMin: 10 * 1e18 * 0.999, // 0.1% slippage
            recipient: receiver,
            deadline: block.timestamp
        });
        assertApproxEqRel(liquidity, 10 * 1e18, 0.999 * 1e18, "liquidity out should be within the slippage");
        assertEq(pool.balanceOf(receiver), liquidity, "should receive 10 LP tokens");
        assertNoFundLeftInPoolSwapRouter();
    }

    function test_addLiquidity_WithImbalance() public virtual {
        this._setUpAllLiquidity(address(0xdead), 100 * ONE_UNDERLYING, 100 * ONE_UNDERLYING);

        uint256 _before = gasleft();
        vm.expectCall(
            address(tricrypto),
            abi.encodeWithSelector(tricrypto.transfer.selector, address(this) /* ~1e18  */ ) // Excess baseLpt (~1e18) will be refunded
        );
        uint256 liquidity = router.addLiquidity(
            address(pool),
            10 * ONE_UNDERLYING,
            [11 * ONE_UNDERLYING, 11 * ONE_UNDERLYING, 11 * ONE_UNDERLYING], // imbalance
            10 * 1e18 * 0.999, // 0.1% slippage
            receiver,
            block.timestamp
        );
        console2.log("gas usage: ", _before - gasleft());
        assertEq(pool.balanceOf(receiver), liquidity, "should receive LP tokens");
        assertGt(tricrypto.balanceOf(address(this)), 0, "should sweep remaining baseLpt");
        assertNoFundLeftInPoolSwapRouter();
        assertReserveBalanceMatch();
    }
}

contract RouterAddLiquidityEthUnitTest is RouterAddLiquidityUnitTest {
    receive() external payable {}

    function _deployUnderlying() internal override {
        _deployWETH();
        underlying = weth;
        uDecimals = 18;
        ONE_UNDERLYING = 1e18;
    }

    function test_RevertIf_Reentrant() public override {
        dealPts(address(0xbad), 1e18, true);
        _approvePts(address(0xbad), address(router), 1e18);
        _expectRevertIf_Reentrant(
            address(0xbad),
            abi.encodeWithSelector(
                router.addLiquidity.selector,
                address(pool),
                10000,
                [1e18, 1e18, 1e18],
                0,
                address(0xbad),
                block.timestamp
            )
        );
        vm.prank(address(0xbad)); // receiver of the callback
        pool.swapPtForUnderlying(0, 1, address(0xbad), abi.encode(NapierPool.swapPtForUnderlying.selector, pts[0]));
    }

    function test_addLiquidity_WithBalanced() public override {
        uint256 liquidity = router.addLiquidity{value: 10 * 1e18}({
            pool: address(pool),
            underlyingIn: 10 * ONE_UNDERLYING,
            ptsIn: [10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING],
            liquidityMin: 10 * 1e18 * 0.999, // 0.1% slippage
            recipient: receiver,
            deadline: block.timestamp
        });
        assertApproxEqRel(liquidity, 10 * 1e18, 0.999 * 1e18, "liquidity out should be within the slippage");
        assertEq(pool.balanceOf(receiver), liquidity, "should receive LP tokens");
        assertNoFundLeftInPoolSwapRouter();
    }

    /// @dev Test case: Add liquidity with BaseLpt amount that is 1e18 greater than the amount actually needed to add liquidity.
    function test_addLiquidity_WithImbalance() public override {
        this._setUpAllLiquidity(address(0xdead), 100 * ONE_UNDERLYING, 100 * ONE_UNDERLYING);

        vm.expectCall(
            address(tricrypto),
            abi.encodeWithSelector(tricrypto.transfer.selector, address(this)) // excess ~1e18 baseLpt will be refunded
        ); // Router should refund the excess baseLpt to the sender
        uint256 _before = gasleft();
        uint256 liquidity = router.addLiquidity{value: 10 * ONE_UNDERLYING}(
            address(pool),
            10 * ONE_UNDERLYING,
            [11 * ONE_UNDERLYING, 11 * ONE_UNDERLYING, 11 * ONE_UNDERLYING], // imbalance
            10 * 1e18 * 0.999, // 0.1% slippage
            receiver,
            block.timestamp
        );
        console2.log("gas usage: ", _before - gasleft());
        assertEq(pool.balanceOf(receiver), liquidity, "should receive LP tokens");
        assertGt(tricrypto.balanceOf(address(this)), 0, "should sweep remaining baseLpt");
        assertNoFundLeftInPoolSwapRouter();
        assertReserveBalanceMatch();
    }

    /// @dev Test case: Add liquidity with ETH amount that is 1 ether greater than the amount actually needed to add liquidity.
    function test_addLiquidity_WithImbalance_Eth() public {
        this._setUpAllLiquidity(address(0xdead), 100 * ONE_UNDERLYING, 100 * ONE_UNDERLYING);

        // Router should refund the excess ~1 ether to the sender at the next line
        uint256 ethBefore = address(this).balance;
        uint256 totalUnderlyingBefore = pool.totalUnderlying();
        uint256 _before = gasleft();
        uint256 liquidity = router.addLiquidity{value: 11 * ONE_UNDERLYING}(
            address(pool),
            11 * ONE_UNDERLYING,
            [10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING],
            10 * 1e18 * 0.999, // 0.1% slippage
            receiver,
            block.timestamp
        );
        console2.log("gas usage: ", _before - gasleft());
        uint256 ethAddedToPool = pool.totalUnderlying() - totalUnderlyingBefore; // amount of ETH added to the pool
        assertEq(address(this).balance, ethBefore - ethAddedToPool, "Remaining ETH should be refunded");
        assertEq(pool.balanceOf(receiver), liquidity, "should receive LP tokens");
        assertNoFundLeftInPoolSwapRouter();
        assertReserveBalanceMatch();
    }

    function test_RevertIf_PoolNotExist() public override {
        MockFakePool fakePool = new MockFakePool();
        vm.expectRevert(Errors.RouterPoolNotFound.selector);
        router.addLiquidity{value: 10 * 1e18}({
            pool: address(fakePool),
            underlyingIn: 10 * ONE_UNDERLYING,
            ptsIn: [10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING],
            liquidityMin: 10 * 1e18 - 1,
            recipient: address(this),
            deadline: block.timestamp
        });
    }

    function test_RevertIf_InsufficientLpOut() public override {
        vm.expectRevert(Errors.RouterInsufficientLpOut.selector);
        router.addLiquidity{value: 10 * ONE_UNDERLYING}({
            pool: address(pool),
            underlyingIn: 10 * ONE_UNDERLYING,
            ptsIn: [10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING],
            liquidityMin: 10 * 1e18 - 1,
            recipient: address(this),
            deadline: block.timestamp
        });
    }
}

contract RouterAddLiquidityOnePtUnitTest is RouterAddLiquidityTest {
    IQuoter quoter;

    function setUp() public override {
        super.setUp();
        quoter = IQuoter(_deployQuoter());
        // Set up initial liquidity on NapierPool
        // At this point, Curve pool doesn't have any liquidity
        this._setUpAllLiquidity(receiver, 100 * ONE_UNDERLYING, 100 * ONE_UNDERLYING);
    }

    function _expectRevertIf_Reentrant(address faultyReceiver, bytes memory callData) public override {
        // Mock Curve pool to return non-zero aomunt. The amount is not important.
        vm.mockCall(
            address(tricrypto),
            abi.encodeWithSelector(CurveTricryptoOptimizedWETH.calc_token_amount.selector),
            abi.encode(1e18)
        );
        // Deploy faulty callback receiver
        _deployFaultyCallbackReceiverTo(faultyReceiver);
        // Set reentrancy call
        FaultyCallbackReceiver(faultyReceiver).setReentrancyCall(callData, true);
        FaultyCallbackReceiver(faultyReceiver).setCaller(address(router));
        // reentrancy should not be possible because of ReentrancyGuard
        vm.expectRevert("ReentrancyGuard: reentrant call");
    }

    function test_RevertIf_MaturityPassed() public override whenMaturityPassed {
        vm.expectRevert(Errors.PoolExpired.selector);
        router.addLiquidityOnePt({
            pool: address(pool),
            index: 0,
            amountIn: 10 * ONE_UNDERLYING,
            liquidityMin: 0,
            recipient: address(this),
            deadline: block.timestamp,
            baseLpTokenSwap: ONE_UNDERLYING
        });
    }

    function test_RevertIf_Reentrant() public override {
        dealPts(address(0xbad), 1e18, true);
        _approvePts(address(0xbad), address(router), 1e18);
        _expectRevertIf_Reentrant(
            address(0xbad),
            abi.encodeWithSelector(
                router.addLiquidityOnePt.selector,
                address(pool),
                0,
                1000,
                0,
                address(0xbad),
                block.timestamp,
                1.5 * 1e12
            )
        );
        vm.prank(address(0xbad)); // receiver of the callback
        pool.swapPtForUnderlying(0, 1, address(0xbad), abi.encode(NapierPool.swapPtForUnderlying.selector, pts[0]));
    }

    function test_addLiquidityOnePtWithApprox() public virtual whenMaturityNotPassed {
        pool.skim(); // reserves in pool may be different from the actual balances. skim to make them equal to the actual balances
        uint256 onePtsToAdd = ONE_UNDERLYING;
        /// Execute ///
        // 1. Approximate the amount of baseLpt to be swapped out to add liquidity from `ptToAdd` amount of underlying token only
        deal(address(pts[0]), address(this), onePtsToAdd, false);
        uint256 approxBaseLpt = quoter.approxBaseLptToAddLiquidityOnePt(pool, 0, onePtsToAdd);
        uint256 _before = gasleft();
        uint256 liquidity =
            router.addLiquidityOnePt(address(pool), 0, onePtsToAdd, 0, address(this), block.timestamp, approxBaseLpt);
        console2.log("gas usage: ", _before - gasleft());
        /// Assertion ///
        // The router pulls only amounts needed to the pool, so there will be nothing left except fee in the pool but tokens can remain in the router if any.
        assertEq(pool.balanceOf(address(this)), liquidity, "didn't receive enough pool lptoken");
        assertReserveBalanceMatch();
        assertNoFundLeftInPoolSwapRouter();
    }

    function test_addLiquidityOnePt() public virtual whenMaturityNotPassed {
        uint256 liquidity = router.addLiquidityOnePt({
            pool: address(pool),
            index: 0,
            amountIn: 10 * ONE_UNDERLYING,
            liquidityMin: 0,
            recipient: address(this),
            deadline: block.timestamp,
            baseLpTokenSwap: 1.5 * 1e18
        });
        assertEq(pool.balanceOf(address(this)), liquidity, "didn't receive enough pool lptoken");
        assertNoFundLeftInPoolSwapRouter();
    }

    function test_RevertIf_DeadlinePassed() public virtual override {
        vm.expectRevert(Errors.RouterTransactionTooOld.selector);
        router.addLiquidityOnePt({
            pool: address(pool),
            index: 0,
            amountIn: 10 * ONE_UNDERLYING,
            liquidityMin: 0,
            recipient: address(this),
            deadline: block.timestamp - 1,
            baseLpTokenSwap: ONE_UNDERLYING
        });
    }

    function test_RevertIf_InsufficientLpOut() public virtual override {
        vm.expectRevert(Errors.RouterInsufficientLpOut.selector);
        router.addLiquidityOnePt({
            pool: address(pool),
            index: 0,
            amountIn: 10 * ONE_UNDERLYING,
            liquidityMin: 100 * 1e18,
            recipient: address(this),
            deadline: block.timestamp,
            baseLpTokenSwap: 1.5 * 1e18
        });
    }

    function test_RevertIf_PoolNotExist() public virtual override {
        MockFakePool fakePool = new MockFakePool();
        vm.expectRevert(Errors.RouterPoolNotFound.selector);
        router.addLiquidityOnePt({
            pool: address(fakePool), // non-existent pool
            index: 0,
            amountIn: 10 * ONE_UNDERLYING,
            liquidityMin: 0,
            recipient: address(this),
            deadline: block.timestamp,
            baseLpTokenSwap: ONE_UNDERLYING
        });
    }
}

contract RouterAddLiquidityOneUnderlyingUnitTest is RouterAddLiquidityTest {
    IQuoter quoter;

    function setUp() public override {
        super.setUp();
        quoter = IQuoter(_deployQuoter());
        // Set up initial liquidity on NapierPool
        // At this point, Curve pool doesn't have any liquidity
        this._setUpAllLiquidity(receiver, 10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING);
    }

    function _expectRevertIf_Reentrant(address faultyReceiver, bytes memory callData) public override {
        // Mock Curve pool to return non-zero aomunt. The amount is not important.
        vm.mockCall(
            address(tricrypto),
            abi.encodeWithSelector(CurveTricryptoOptimizedWETH.calc_token_amount.selector),
            abi.encode(1e18)
        );
        // Deploy faulty callback receiver
        _deployFaultyCallbackReceiverTo(faultyReceiver);
        // Set reentrancy call
        FaultyCallbackReceiver(faultyReceiver).setReentrancyCall(callData, true);
        FaultyCallbackReceiver(faultyReceiver).setCaller(address(router));
        // reentrancy should not be possible because of ReentrancyGuard
        vm.expectRevert("ReentrancyGuard: reentrant call");
    }

    function test_RevertIf_MaturityPassed() public override whenMaturityPassed {
        vm.expectRevert(Errors.PoolExpired.selector);
        router.addLiquidityOneUnderlying({
            pool: address(pool),
            underlyingIn: 10 * ONE_UNDERLYING,
            liquidityMin: 0,
            recipient: address(this),
            deadline: block.timestamp,
            baseLpTokenSwap: 1.5 * 1e18
        });
    }

    function test_RevertIf_Reentrant() public override {
        deal(address(underlying), address(0xbad), 1e18, true);
        _approve(underlying, address(0xbad), address(router), 1e18);
        _expectRevertIf_Reentrant(
            address(0xbad),
            abi.encodeWithSelector(
                router.addLiquidityOneUnderlying.selector,
                address(pool),
                1000,
                0,
                address(0xbad),
                block.timestamp,
                1.5 * 1e12
            )
        );
        vm.prank(address(0xbad)); // receiver of the callback
        pool.swapPtForUnderlying(0, 1, address(0xbad), abi.encode(NapierPool.swapPtForUnderlying.selector, pts[0]));
    }

    function test_addLiquidityOneUnderlyingWithApprox() public virtual whenMaturityNotPassed {
        pool.skim(); // reserves in pool may be different from the actual balances. skim to make them equal to the actual balances
        uint256 underlyingsToAdd = 10 * ONE_UNDERLYING;
        /// Execute ///
        // 1. Approximate the amount of baseLpt to be swapped out to add liquidity from `underlyingsToAdd` amount of underlying token only
        deal(address(underlying), address(this), underlyingsToAdd, true);
        uint256 approxBaseLpt = quoter.approxBaseLptToAddLiquidityOneUnderlying(pool, underlyingsToAdd);
        uint256 _before = gasleft();
        uint256 liquidity = router.addLiquidityOneUnderlying(
            address(pool), underlyingsToAdd, 0, address(this), block.timestamp, approxBaseLpt
        );
        console2.log("gas usage: ", _before - gasleft());
        /// Assertion ///
        // The router pulls only amounts needed to the pool, so there will be nothing left except fee in the pool but tokens can remain in the router if any.
        assertEq(pool.balanceOf(address(this)), liquidity, "didn't receive enough pool lptoken");
        assertReserveBalanceMatch();
        assertNoFundLeftInPoolSwapRouter();
    }

    function test_addLiquidityOneUnderlying() public virtual whenMaturityNotPassed {
        uint256 liquidity = router.addLiquidityOneUnderlying({
            pool: address(pool),
            underlyingIn: 100 * ONE_UNDERLYING,
            liquidityMin: 0,
            recipient: address(this),
            deadline: block.timestamp,
            baseLpTokenSwap: 1.5 * 1e18
        });
        assertEq(pool.balanceOf(address(this)), liquidity, "didn't receive enough pool lptoken");
        assertNoFundLeftInPoolSwapRouter();
    }

    function test_RevertIf_DeadlinePassed() public virtual override {
        vm.expectRevert(Errors.RouterTransactionTooOld.selector);
        router.addLiquidityOneUnderlying({
            pool: address(pool),
            underlyingIn: 10 * ONE_UNDERLYING,
            liquidityMin: 0,
            recipient: address(this),
            deadline: block.timestamp - 1,
            baseLpTokenSwap: ONE_UNDERLYING
        });
    }

    function test_RevertIf_InsufficientLpOut() public virtual override {
        vm.expectRevert(Errors.RouterInsufficientLpOut.selector);
        router.addLiquidityOneUnderlying({
            pool: address(pool),
            underlyingIn: 10 * ONE_UNDERLYING,
            liquidityMin: 100 * 1e18,
            recipient: address(this),
            deadline: block.timestamp,
            baseLpTokenSwap: 1.5 * 1e18
        });
    }

    function test_RevertIf_PoolNotExist() public virtual override {
        MockFakePool fakePool = new MockFakePool();
        vm.expectRevert(Errors.RouterPoolNotFound.selector);
        router.addLiquidityOneUnderlying({
            pool: address(fakePool), // non-existent pool
            underlyingIn: 10 * ONE_UNDERLYING,
            liquidityMin: 0,
            recipient: address(this),
            deadline: block.timestamp,
            baseLpTokenSwap: ONE_UNDERLYING
        });
    }
}

contract RouterRemoveLiquidityUnitTest is RouterRemoveLiquidityBaseUnitTest {
    function test_RevertIf_Reentrant() public override {
        deal(address(pool), address(0xbad), 1 ether, false);
        _approve(IERC20(address(pool)), address(0xbad), address(router), 1 ether);
        _expectRevertIf_Reentrant(
            address(0xbad),
            abi.encodeWithSelector(
                router.removeLiquidity.selector,
                address(pool),
                800,
                1000,
                [1000, 1000, 1000],
                address(0xbad),
                block.timestamp
            )
        );

        vm.prank(address(0xbad)); // receiver of the callback
        pool.swapPtForUnderlying(0, 1, address(0xbad), abi.encode(NapierPool.swapPtForUnderlying.selector, pts[0]));
    }

    function test_RevertIf_PoolNotExist() public override {
        MockFakePool fakePool = new MockFakePool();
        vm.expectRevert(Errors.RouterPoolNotFound.selector);
        router.removeLiquidity({
            pool: address(fakePool), // non-existent pool
            liquidity: 10 * 1e18,
            ptsOutMin: [10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING],
            underlyingOutMin: 10 * ONE_UNDERLYING,
            recipient: address(this),
            deadline: block.timestamp
        });
    }

    function test_RevertIf_DeadlinePassed() public override {
        vm.expectRevert(Errors.RouterTransactionTooOld.selector);
        router.removeLiquidity({
            pool: address(pool),
            liquidity: 10 * 1e18,
            ptsOutMin: [10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING],
            underlyingOutMin: 10 * ONE_UNDERLYING,
            recipient: address(this),
            deadline: block.timestamp - 1
        });
    }

    function test_RevertIf_InsufficientUnderlyingOut() public {
        uint256 liquidity = _setUpAllLiquidity({
            recipient: address(this),
            underlyingIn: 3000 * ONE_UNDERLYING,
            ptIn: 1000 * ONE_UNDERLYING
        });
        vm.expectRevert(Errors.RouterInsufficientUnderlyingOut.selector);
        router.removeLiquidity({
            pool: address(pool),
            liquidity: liquidity * 99 / 100, // withdraw 99%
            ptsOutMin: [10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING],
            underlyingOutMin: 3000 * ONE_UNDERLYING + 1, // try to withdraw more than deposited
            recipient: receiver,
            deadline: block.timestamp
        });
    }

    function test_RevertIf_InsufficientPtOut() public {
        uint256 liquidity = _setUpAllLiquidity({
            recipient: address(this),
            underlyingIn: 3000 * ONE_UNDERLYING,
            ptIn: 1000 * ONE_UNDERLYING
        });
        vm.expectRevert(); // Curve pool doesn't revert with specific error message when slippage is too high
        router.removeLiquidity({
            pool: address(pool),
            liquidity: liquidity * 99 / 100, // withdraw 99%
            ptsOutMin: [1000 * ONE_UNDERLYING, 1, 1],
            underlyingOutMin: 1,
            recipient: receiver,
            deadline: block.timestamp
        });
    }

    function test_removeLiquidity() public virtual whenMaturityNotPassed {
        uint256 liquidity = _setUpAllLiquidity({
            recipient: address(this),
            underlyingIn: 3000 * ONE_UNDERLYING,
            ptIn: 1000 * ONE_UNDERLYING
        });
        uint256 _before = gasleft();
        (uint256 underlyingOut, uint256[3] memory ptsOut) = router.removeLiquidity({
            pool: address(pool),
            liquidity: liquidity * 99 / 100, // withdraw 99%
            ptsOutMin: [10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING, 10 * ONE_UNDERLYING],
            underlyingOutMin: 3000 * ONE_UNDERLYING * 95 / 100,
            recipient: receiver,
            deadline: block.timestamp
        });
        console2.log("gas usage: ", _before - gasleft());
        assertEq(underlying.balanceOf(receiver), underlyingOut, "should receive underlying");
        assertEq(pts[0].balanceOf(receiver), ptsOut[0], "should receive pt0");
        assertEq(pts[1].balanceOf(receiver), ptsOut[1], "should receive pt1");
        assertEq(pts[2].balanceOf(receiver), ptsOut[2], "should receive pt2");
        assertNoFundLeftInPoolSwapRouter();
    }
}

contract RouterRemoveLiquidityOnePtUnitTest is RouterRemoveLiquidityBaseUnitTest {
    IQuoter quoter;

    function setUp() public override {
        super.setUp();
        quoter = IQuoter(_deployQuoter());
    }

    function _expectRevertIf_Reentrant(address faultyReceiver, bytes memory callData) public override {
        // Mock Curve pool to return non-zero aomunt. The amount is not important.
        vm.mockCall(
            address(tricrypto),
            abi.encodeWithSelector(CurveTricryptoOptimizedWETH.calc_token_amount.selector),
            abi.encode(1e18)
        );
        // Deploy faulty callback receiver
        _deployFaultyCallbackReceiverTo(faultyReceiver);
        // Set reentrancy call
        FaultyCallbackReceiver(faultyReceiver).setReentrancyCall(callData, true);
        FaultyCallbackReceiver(faultyReceiver).setCaller(address(router));
        // reentrancy should not be possible because of ReentrancyGuard
        vm.expectRevert("ReentrancyGuard: reentrant call");
    }

    function test_RevertIf_Reentrant() public override {
        _setUpAllLiquidity({recipient: address(this), underlyingIn: 3000 * ONE_UNDERLYING, ptIn: 1000 * ONE_UNDERLYING});
        deal(address(pool), address(0xbad), ONE_UNDERLYING, true);
        _approve(IERC20(pool), address(0xbad), address(router), ONE_UNDERLYING);
        _expectRevertIf_Reentrant(
            address(0xbad),
            abi.encodeWithSelector(
                router.removeLiquidityOnePt.selector,
                address(pool),
                0,
                ONE_UNDERLYING,
                0,
                address(0xABCD),
                block.timestamp,
                100 * ONE_UNDERLYING
            )
        );
        vm.prank(address(0xbad)); // receiver of the callback
        pool.swapPtForUnderlying(0, 1, address(0xbad), abi.encode(NapierPool.swapPtForUnderlying.selector, pts[0]));
    }

    function test_removeLiquidityOnePt() public virtual whenMaturityNotPassed {
        uint256 liquidity = _setUpAllLiquidity({
            recipient: address(this),
            underlyingIn: 3000 * ONE_UNDERLYING,
            ptIn: 1000 * ONE_UNDERLYING
        });
        uint256 _before = gasleft();
        uint256 ptOut = router.removeLiquidityOnePt({
            pool: address(pool),
            index: 0,
            liquidity: liquidity * 10 / 100, // withdraw 10%
            ptOutMin: 100 * ONE_UNDERLYING,
            recipient: address(0xABCD),
            deadline: block.timestamp,
            baseLpTokenSwap: 10 ** 17
        });
        console2.log("gas usage: ", _before - gasleft());
        assertNoFundLeftInPoolSwapRouter();
        assertEq(IERC20(pts[0]).balanceOf(address(0xABCD)), ptOut, "didn't receive enough principal token");
        console2.log(ptOut);
    }

    function test_RevertIf_PoolNotExist() public virtual override {
        MockFakePool fakePool = new MockFakePool();
        vm.expectRevert(Errors.RouterPoolNotFound.selector);
        router.removeLiquidityOnePt({
            pool: address(fakePool), // non-existance ppol
            index: 0,
            liquidity: ONE_UNDERLYING, // withdraw 10%
            ptOutMin: 100 * ONE_UNDERLYING,
            recipient: address(0xABCD),
            deadline: block.timestamp,
            baseLpTokenSwap: 100 * ONE_UNDERLYING
        });
    }

    function test_RevertIf_DeadlinePassed() public virtual override {
        vm.expectRevert(Errors.RouterTransactionTooOld.selector);
        router.removeLiquidityOnePt({
            pool: address(pool),
            index: 0,
            liquidity: ONE_UNDERLYING, // withdraw 10%
            ptOutMin: 100 * ONE_UNDERLYING,
            recipient: address(0xABCD),
            deadline: block.timestamp - 1,
            baseLpTokenSwap: 100 * ONE_UNDERLYING
        });
    }

    function test_removeLiquidityOnePtWithApprox() public virtual whenMaturityNotPassed {
        pool.skim(); // reserves in pool may be different from the actual balances. skim to make them equal to the actual balances

        uint256 liquidity = _setUpAllLiquidity({
            recipient: address(this),
            underlyingIn: 3000 * ONE_UNDERLYING,
            ptIn: 1000 * ONE_UNDERLYING
        });
        uint256 liquidityRemoveAmount = liquidity * 10 / 100;

        /// Execute ///
        uint256 approxBaseLpt = quoter.approxBaseLptToRemoveLiquidityOnePt(pool, liquidityRemoveAmount);
        uint256 _before = gasleft();
        uint256 ptOut = router.removeLiquidityOnePt(
            address(pool),
            0,
            liquidityRemoveAmount,
            100 * ONE_UNDERLYING,
            address(0xABCD),
            block.timestamp,
            approxBaseLpt
        );
        console2.log("gas usage: ", _before - gasleft());
        /// Assertion ///
        // The router pulls only amounts needed to the pool, so there will be nothing left except fee in the pool but tokens can remain in the router if any.
        assertEq(IERC20(pts[0]).balanceOf(address(0xABCD)), ptOut, "didn't receive enough principal token");
        assertReserveBalanceMatch();
        assertNoFundLeftInPoolSwapRouter();
    }
}

contract RouterRemoveLiquidityOneUnderlyingUnitTest is RouterRemoveLiquidityBaseUnitTest {
    function test_RevertIf_Reentrant() public override {
        deal(address(pool), address(0xbad), 1 ether, false);
        _approve(IERC20(address(pool)), address(0xbad), address(router), 1 ether);
        _expectRevertIf_Reentrant(
            address(0xbad),
            abi.encodeWithSelector(
                router.removeLiquidityOneUnderlying.selector,
                address(pool),
                0,
                1 * 1e18,
                1,
                address(0xbad),
                block.timestamp
            )
        );
        vm.prank(address(0xbad)); // receiver of the callback
        pool.swapPtForUnderlying(0, 1, address(0xbad), abi.encode(NapierPool.swapPtForUnderlying.selector, pts[0]));
    }

    /// @dev
    /// Pre-condition: Issues 1000 underlying equivalent each PT and add liquidity with 3000 underlying and those PTs
    /// Test case: Remove liquidity with the 80% of total supply
    /// Post-condition:
    ///     - Expect pool.swapExactBaseLpTokenForUnderlying to be called
    ///     - Withdrawn underlying should be transferred to receiver
    ///     - No funds are left in Router
    function test_When_MaturityNotPassed() public virtual whenMaturityNotPassed {
        uint256 liquidity = _issueAndAddLiquidities({
            recipient: address(this),
            underlyingIn: 3000 * ONE_UNDERLYING,
            uIssues: [1000 * ONE_UNDERLYING, 1000 * ONE_UNDERLYING, 1000 * ONE_UNDERLYING]
        });
        // if maturity not passed, should call swap internally
        vm.expectCall(address(pool), abi.encodeWithSelector(pool.swapExactBaseLpTokenForUnderlying.selector));
        uint256 _before = gasleft();
        uint256 underlyingOut = router.removeLiquidityOneUnderlying({
            pool: address(pool),
            index: 0,
            liquidity: 10 * 1e18,
            underlyingOutMin: 1,
            recipient: receiver,
            deadline: block.timestamp
        });
        console2.log("gas usage: ", _before - gasleft());
        assertEq(pool.balanceOf(address(this)), liquidity - 10 * 1e18, "should withdraw 10 LP tokens");
        assertEq(underlying.balanceOf(receiver), underlyingOut, "should receive underlying");
        assertNoFundLeftInPoolSwapRouter();
    }

    function test_RevertIf_InssuficientUnderlyingOut_When_MaturityNotPassed() public virtual {
        _issueAndAddLiquidities({
            recipient: address(this),
            underlyingIn: 3000 * ONE_UNDERLYING,
            uIssues: [1000 * ONE_UNDERLYING, 1000 * ONE_UNDERLYING, 1000 * ONE_UNDERLYING]
        });
        vm.warp((maturity + block.timestamp) / 2); // warp to half of maturity
        // Withdraw 10% LP tokens of total supply
        // This is equivalent to 10% of (3000 underlying + 3 * 1000 underlying equivalent PT)
        uint256 liquidityRemove = pool.totalSupply() * 10 / 100;
        vm.expectRevert(Errors.RouterInsufficientUnderlyingOut.selector);
        router.removeLiquidityOneUnderlying({
            pool: address(pool),
            index: 2,
            liquidity: liquidityRemove,
            // Due to price impact, should not be able to withdraw 10% initially deposited
            underlyingOutMin: (3 * 1000 + 3000) * ONE_UNDERLYING * 10 / 100,
            recipient: receiver,
            deadline: block.timestamp
        });
    }

    /// @dev
    /// Pre-condition: Issues 1000 underlying equivalent each PT and add liquidity with 3000 underlying and those PTs
    /// Test case: Remove liquidity with the 80% of total supply
    /// Post-condition:
    ///     - Expect Tranche.redeem method to be called
    ///     - Withdrawn underlying should be transferred to receiver
    ///     - No funds are left in Router
    function test_When_MaturityPassed() public virtual {
        uint256 liquidity = _issueAndAddLiquidities({
            recipient: address(this),
            underlyingIn: 3000 * ONE_UNDERLYING,
            uIssues: [1000 * ONE_UNDERLYING, 1000 * ONE_UNDERLYING, 1000 * ONE_UNDERLYING]
        });
        vm.warp(maturity); // warp to maturity
        // if maturity passed, should redeem internally
        vm.expectCall(address(pts[1]), abi.encodeWithSelector(pts[1].redeem.selector));
        uint256 _before = gasleft();
        uint256 underlyingOut = router.removeLiquidityOneUnderlying({
            pool: address(pool),
            index: 1,
            liquidity: 10 * 1e18,
            underlyingOutMin: 1,
            recipient: receiver,
            deadline: block.timestamp
        });
        console2.log("gas usage: ", _before - gasleft());
        assertEq(pool.balanceOf(address(this)), liquidity - 10 * 1e18, "should withdraw 10 LP tokens");
        assertEq(underlying.balanceOf(receiver), underlyingOut, "should receive underlying");
        assertNoFundLeftInPoolSwapRouter();
    }

    function test_RevertIf_InssuficientUnderlyingOut_When_MaturityPassed() public virtual {
        _issueAndAddLiquidities({
            recipient: address(this),
            underlyingIn: 3000 * ONE_UNDERLYING,
            uIssues: [1000 * ONE_UNDERLYING, 1000 * ONE_UNDERLYING, 1000 * ONE_UNDERLYING]
        });
        vm.warp(maturity); // warp to maturity

        // Withdraw 40% LP tokens from total supply
        // This is equivalent to 40% of (3000 underlying + 3 * 1000 underlying equivalent PT)
        uint256 liquidityRemove = pool.totalSupply() * 40 / 100;
        vm.expectRevert(Errors.RouterInsufficientUnderlyingOut.selector);
        router.removeLiquidityOneUnderlying({
            pool: address(pool),
            index: 0,
            liquidity: liquidityRemove,
            // Due to price impact, should not be able to withdraw 40% initially deposited
            underlyingOutMin: (3 * 1000 + 3000) * ONE_UNDERLYING * 40 / 100,
            recipient: receiver,
            deadline: block.timestamp
        });
    }

    function test_RevertIf_PoolNotExist() public virtual override {
        MockFakePool fakePool = new MockFakePool();
        vm.expectRevert(Errors.RouterPoolNotFound.selector);
        router.removeLiquidityOneUnderlying({
            pool: address(fakePool), // non-existent pool
            index: 0,
            liquidity: 10 * 1e18,
            underlyingOutMin: 1,
            recipient: address(this),
            deadline: block.timestamp
        });
    }

    function test_RevertIf_DeadlinePassed() public virtual override {
        vm.expectRevert(Errors.RouterTransactionTooOld.selector);
        router.removeLiquidityOneUnderlying({
            pool: address(pool),
            index: 0,
            liquidity: 10 * 1e18,
            underlyingOutMin: 1,
            recipient: address(this),
            deadline: block.timestamp - 1
        });
    }
}
