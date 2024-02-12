// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {PoolAddLiquidityBaseUnitTest, PoolRemoveLiquidityBaseUnitTest} from "../../shared/Liquidity.t.sol";

import {INapierMintCallback} from "src/interfaces/INapierMintCallback.sol";
import {CallbackInputType, AddLiquidityInput, AddLiquidityFaultilyInput} from "../../shared/CallbackInputType.sol";

import {CurveTricryptoOptimizedWETH} from "src/interfaces/external/CurveTricryptoOptimizedWETH.sol";
import {NapierPool} from "src/NapierPool.sol";
import {PoolMath} from "src/libs/PoolMath.sol";
import {Errors} from "src/libs/Errors.sol";

/// @notice test NapierPool.addLiquidity()
contract PoolAddLiquidityUnitTest is PoolAddLiquidityBaseUnitTest {
    /// @dev Authorized address to call `addLiquidity`.
    /// @dev MockCallbackReceiver code is deployed to this address.
    address alice = makeAddr("alice");

    function setUp() public override {
        super.setUp();
        _deployMockCallbackReceiverTo(alice); // authorize alice to receive callbacks
    }

    function test_RevertIf_Reentrant() public override whenMaturityNotPassed {
        _expectRevertIf_Reentrant(
            address(0xbad), // faulty callback receiver
            abi.encodeWithSignature(
                "addLiquidity(uint256,uint256,address,bytes)", 1000, 1000, address(0xbad), bytes("")
            )
        );
        vm.prank(address(0xbad)); // 0xbad receives callback from pool
        pool.addLiquidity(1000, 1000, address(0xbad), "");
    }

    function test_WhenZeroTotalSupply() public override whenMaturityNotPassed whenZeroTotalSupply {
        uint256 baseLptIn = 1000 * 1e18;
        uint256 underlyingIn = 3000 * ONE_UNDERLYING;

        deal(address(underlying), alice, underlyingIn, false);
        deal(address(tricrypto), alice, baseLptIn, false);

        vm.prank(alice);
        uint256 liquidity = pool.addLiquidity(
            underlyingIn,
            baseLptIn,
            address(0xcafe),
            abi.encode(
                CallbackInputType.AddLiquidity, AddLiquidityInput({underlying: underlying, tricrypto: tricrypto})
            )
        );

        assertEq(pool.totalBaseLpt(), baseLptIn, "should be added to baseLpt reserve");
        assertEq(pool.totalUnderlying(), underlyingIn, "should be added to underlying reserve");
        assertEq(
            pool.totalSupply(),
            liquidity + PoolMath.MINIMUM_LIQUIDITY,
            "total supply should be sum of received LP token and MINIMUM_LIQUIDITY"
        );
        assertEq(pool.balanceOf(address(0xcafe)), liquidity, "should be added to recipient's balance");
        assertEq(pool.balanceOf(address(1)), PoolMath.MINIMUM_LIQUIDITY, "some liquidity should be permanently locked");
        assertGt(pool.lastLnImpliedRate(), 0, "lastLnImpliedRate should be gt zero");
    }

    function test_RevertWhen_ProportionTooHigh() public {
        uint256 baseLptIn = 1_000_000 * 1e18;
        uint256 underlyingIn = 3000 * ONE_UNDERLYING;

        // Revert if baseLptIn reserve gets more than max proportion
        vm.expectRevert(Errors.PoolProportionTooHigh.selector);
        vm.prank(alice);
        pool.addLiquidity(underlyingIn, baseLptIn, address(0xcafe), "");
    }

    function test_RevertWhen_ExchangeRateBelowOne() public {
        uint256 baseLptIn = 1000 * 1e18;
        uint256 underlyingIn = 3_000_000 * ONE_UNDERLYING;

        deal(address(underlying), alice, underlyingIn, false);
        deal(address(tricrypto), alice, baseLptIn, false);

        // Revert if effective exchange rate is below one
        vm.prank(alice);
        try pool.addLiquidity(underlyingIn, baseLptIn, address(0xcafe), "") {
            revert("should revert");
        } catch (bytes memory reason) {
            int256 exchangeRate = abi.decode(reason, (int256));
            assertEq(
                bytes4(reason), Errors.PoolExchangeRateBelowOne.selector, "should revert with ExchangeRateBelowOne"
            );
            assertLt(exchangeRate, 1, "should be less than 1");
        }
    }

    function test_RevertWhen_ProportionEqualToOne() public {}

    function test_RevertWhen_LessThanMinLiquidity() public override whenMaturityNotPassed {
        uint256 baseLptIn = 1000;
        uint256 underlyingIn = 0;

        // Revert if initial liquidity provided is less than min liquidity
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(alice);
        pool.addLiquidity(underlyingIn, baseLptIn, address(0xcafe), "");
    }

    // Pre-condition: liquidity is added once
    // Test case: add liquidity with the 10x amount
    // Post-condition: liquidity should be added proportionally to baseLpt and underlying reserve
    function test_WhenAddProportionally() public override whenMaturityNotPassed whenNonZeroTotalSupply {
        uint256 baseLptIn = 1000 * 1e18;
        uint256 underlyingIn = 3000 * ONE_UNDERLYING;
        // pre-condition
        _setUpNapierPoolLiquidity(address(0xcafe), underlyingIn, baseLptIn);
        uint256 totalLp = pool.totalSupply();
        // execution: add liquidity again with the 10x amount
        // set previous balance, plus 10x amount
        deal(address(underlying), alice, 10 * underlyingIn + underlyingIn, false);
        deal(address(tricrypto), alice, 10 * baseLptIn + baseLptIn, false);

        vm.prank(alice);
        uint256 liquidity = pool.addLiquidity(
            10 * underlyingIn,
            10 * baseLptIn,
            address(0xcafe),
            abi.encode(
                CallbackInputType.AddLiquidity, AddLiquidityInput({underlying: underlying, tricrypto: tricrypto})
            )
        );
        // post-condition
        assertEq(liquidity, totalLp * 10, "should be added proportionally to total supply");
        assertEq(pool.totalBaseLpt(), baseLptIn * 10 + baseLptIn, "should be added proportionally to baseLpt reserve");
        assertEq(
            pool.totalUnderlying(),
            underlyingIn * 10 + underlyingIn,
            "should be added proportionally to underlying reserve"
        );
        assertEq(
            pool.balanceOf(address(1)),
            PoolMath.MINIMUM_LIQUIDITY,
            "locked liquidity should be equal to MINIMUM_LIQUIDITY"
        );
    }

    // Pre-condition: liquidity is added once
    // Test case: add liquidity with the 10x underlying and the 11x baseLpt
    // Post-condition: liquidity should be added in proportion to underlying reserve
    function test_WhenAddBaseLptImbalance() public override whenMaturityNotPassed whenNonZeroTotalSupply {
        {
            // set up initial liquidity
            uint256 initialBaseLpt = 1000 * 1e18;
            uint256 initialUnderlying = 3000 * ONE_UNDERLYING;
            _setUpNapierPoolLiquidity(address(0xcafe), initialUnderlying, initialBaseLpt);
        }
        // pre-condition
        uint256 totalLp = pool.totalSupply();
        uint256 preTotalBaseLpt = pool.totalBaseLpt(); // Equal to initialBaseLpt
        uint256 preTotalUnderlying = pool.totalUnderlying(); // Equal to initialUnderlying

        uint256 underlyingIn = 10 * preTotalUnderlying;
        uint256 baseLptIn = 11 * preTotalBaseLpt; // imbalance
        // execution: add liquidity again
        deal(address(underlying), alice, underlyingIn + preTotalUnderlying, false); // plus previous balance
        deal(address(tricrypto), alice, baseLptIn + preTotalBaseLpt, false);
        vm.prank(alice);
        uint256 liquidity = pool.addLiquidity(
            underlyingIn,
            baseLptIn,
            address(0xcafe),
            abi.encode(
                CallbackInputType.AddLiquidity, AddLiquidityInput({underlying: underlying, tricrypto: tricrypto})
            )
        );

        // post-condition
        assertEq(pool.totalSupply(), liquidity + totalLp, "total supply should increase");
        assertEq(
            pool.totalBaseLpt() - preTotalBaseLpt, // minus previous balance
            // Note: should be added proportionally to pre-reserves
            // Note: Formula: reserve1 / reserve0 = amountIn1 / amountIn0
            (underlyingIn * preTotalBaseLpt) / preTotalUnderlying,
            "should be added proportionally to pre-reserves"
        );
        assertEq(
            pool.totalUnderlying() - preTotalUnderlying, // minus previous balance
            underlyingIn,
            "all underlying should be added to underlying reserve"
        );
    }

    // Pre-condition: liquidity is added once
    // Test case: add liquidity with the 11x underlying and the 10x baseLpt
    // Post-condition: liquidity should be added in proportion to baseLpt reserve
    function test_WhenAddUnderlyingImbalance() public override whenMaturityNotPassed whenNonZeroTotalSupply {
        {
            uint256 initialBaseLpt = 1000 * 1e18;
            uint256 initialUnderlying = 3000 * ONE_UNDERLYING;
            _setUpNapierPoolLiquidity(address(0xcafe), initialUnderlying, initialBaseLpt);
        }
        // pre-condition
        uint256 totalLp = pool.totalSupply();
        uint256 preTotalBaseLpt = pool.totalBaseLpt(); // Equal to initialBaseLpt
        uint256 preTotalUnderlying = pool.totalUnderlying(); // Equal to initialUnderlying

        uint256 underlyingIn = 11 * preTotalUnderlying; // imbalance
        uint256 baseLptIn = 10 * preTotalBaseLpt;

        // execution: add liquidity again
        deal(address(underlying), alice, underlyingIn + preTotalUnderlying, false); // plus previous balance
        deal(address(tricrypto), alice, baseLptIn + preTotalBaseLpt, false);
        vm.prank(alice);
        uint256 liquidity = pool.addLiquidity(
            underlyingIn,
            baseLptIn,
            address(0xcafe),
            abi.encode(
                CallbackInputType.AddLiquidity, AddLiquidityInput({underlying: underlying, tricrypto: tricrypto})
            )
        );

        // post-condition
        assertEq(pool.totalSupply(), liquidity + totalLp, "total supply should increase");
        assertEq(
            pool.totalUnderlying() - preTotalUnderlying, // minus previous balance
            // Note: should be added proportionally to pre-reserves
            // Note: Formula: reserve1 / reserve0 = amountIn1 / amountIn0
            ((baseLptIn) * preTotalUnderlying) / preTotalBaseLpt,
            "should be added proportionally to pre-reserves"
        );
        assertEq(
            pool.totalBaseLpt() - preTotalBaseLpt, // minus previous balance
            baseLptIn,
            "all baseLpt should be added to baseLpt reserve"
        );
    }

    function test_RevertIf_DeadlinePassed() public override whenMaturityNotPassed {
        vm.warp(maturity);
        vm.expectRevert(Errors.PoolExpired.selector);
        pool.addLiquidity(100, 100, address(0xcafe), "");
    }

    function test_RevertIf_UnauthorizedCallback() public whenMaturityNotPassed {
        address badCaller = address(0xbad);
        assertFalse(poolFactory.isCallbackReceiverAuthorized(badCaller), "[pre-condition] should be unauthorized");
        vm.expectRevert(Errors.PoolUnauthorizedCallback.selector);
        vm.prank(badCaller);
        pool.addLiquidity(1000000, 1000000, address(0x11111), "arbitrary data");
    }

    function test_RevertIf_InsufficientUnderlyingReceived() public whenMaturityNotPassed {
        uint256 baseLptIn = 1000 * 1e18;
        uint256 underlyingIn = 3000 * ONE_UNDERLYING;

        address badUser = address(0xbad);
        deal(address(underlying), badUser, underlyingIn, false);
        deal(address(tricrypto), badUser, baseLptIn, false);

        _deployFaultyCallbackReceiverTo(badUser); // deploy faulty callback receiver to badUser

        // Revert if insufficient underlying received
        vm.expectRevert(Errors.PoolInsufficientUnderlyingReceived.selector);
        vm.prank(badUser);
        pool.addLiquidity(
            underlyingIn,
            baseLptIn,
            address(this),
            abi.encode(
                CallbackInputType.AddLiquidityFaultily,
                AddLiquidityFaultilyInput({
                    underlying: underlying,
                    tricrypto: tricrypto,
                    sendInsufficientUnderlying: true,
                    sendInsufficientBaseLpt: false
                })
            )
        );
    }

    function test_RevertIf_InsufficientBaseLptReceived() public whenMaturityNotPassed {
        uint256 baseLptIn = 1000 * 1e18;
        uint256 underlyingIn = 3000 * ONE_UNDERLYING;

        address badUser = address(0xbad);
        deal(address(underlying), badUser, underlyingIn, false);
        deal(address(tricrypto), badUser, baseLptIn, false);

        _deployFaultyCallbackReceiverTo(badUser); // deploy faulty callback receiver to badUser

        // Revert if insufficient baseLpt received
        vm.expectRevert(Errors.PoolInsufficientBaseLptReceived.selector);
        vm.prank(badUser);
        pool.addLiquidity(
            underlyingIn,
            baseLptIn + 1,
            address(this),
            abi.encode(
                CallbackInputType.AddLiquidityFaultily,
                AddLiquidityFaultilyInput({
                    underlying: underlying,
                    tricrypto: tricrypto,
                    sendInsufficientUnderlying: false,
                    sendInsufficientBaseLpt: true
                })
            )
        );
    }
}

contract PoolRemoveLiquidityUnitTest is PoolRemoveLiquidityBaseUnitTest {
    function test_RevertIf_Reentrant() public override whenMaturityNotPassed {
        _expectRevertIf_Reentrant(address(0xbad), abi.encodeCall(NapierPool.removeLiquidity, address(0xbad)));
        vm.prank(address(0xbad)); // 0xbad receives callback from pool
        pool.addLiquidity(1000, 1000, address(0xbad), "");
    }

    /// @dev Should revert if zero liquidity is removed
    function test_RevertWhen_RemoveZeroLiquidity() public override anytime {
        _setUpNapierPoolLiquidity(address(this), 1000 * 10 ** uDecimals, 1000 * 1e18);

        vm.expectRevert(Errors.PoolZeroAmountsInput.selector);
        pool.removeLiquidity(address(0xcafe));
    }

    /// @dev Should revert if zero amounts are removed
    function test_RevertWhen_RemoveZeroAmount() public override anytime {
        uint256 baseLptIn = 1000 * 1e18;
        uint256 underlyingIn = 3000 * ONE_UNDERLYING;
        // pre-condition
        _setUpNapierPoolLiquidity(address(this), underlyingIn, baseLptIn);
        // execution
        pool.transfer(address(pool), 1);
        vm.expectRevert(Errors.PoolZeroAmountsOutput.selector);
        pool.removeLiquidity(address(0xcafe));
    }

    /// @dev See _test_RemoveProportionally for details
    function test_RemoveProportionally() public override anytime {
        uint256 baseLptReserve = 1000 * 1e18;
        uint256 underlyingReserve = 3000 * ONE_UNDERLYING;
        // pre-condition
        _setUpNapierPoolLiquidity(address(this), underlyingReserve, baseLptReserve);
        // remove 40% of total supply
        _test_RemoveProportionally(underlyingReserve, baseLptReserve, 0.4 * 1e18);
    }

    /// @dev See _test_RemoveProportionally for details
    function testFuzz_RemoveProportionally(uint256 underlyingReserve, uint256 baseLptReserve, uint256 percentWei)
        public
        anytime
    {
        underlyingReserve = bound(underlyingReserve, 1, type(uint96).max);
        baseLptReserve = bound(baseLptReserve, 1, type(uint96).max);
        percentWei = bound(percentWei, 1, 1e18);
        // pre-condition
        try this._setUpNapierPoolLiquidity(address(this), underlyingReserve, baseLptReserve) {}
        catch {
            vm.assume(false);
        }
        // execution/assertion
        try this._test_RemoveProportionally(underlyingReserve, baseLptReserve, percentWei) {}
        catch (bytes memory reason) {
            // ignore revert from zero amounts input/output
            // this is because percentWei could be too small
            vm.assume(bytes4(reason) != Errors.PoolZeroAmountsInput.selector);
            vm.assume(bytes4(reason) != Errors.PoolZeroAmountsOutput.selector);
            revert(string(reason));
        }
    }

    /// @dev
    /// Pre-condition: liquidity is added by address(this)
    /// Test case: remove liquidity with the x% of total supply
    /// Post-condition:
    ///                 1.the removed underlying and baseLpt should be transferred to recipient.
    ///                 2. x% of underlying and baseLpt should be removed proportionally to total supply.
    ///                 3. x% of underlying and baseLpt should be removed from reserves.
    ///                 3. x% of total supply should be removed from total supply.
    /// @dev Early return when the account burns more than circulating supply
    /// @dev Assume that address(this) has enough liquidity
    /// @param underlyingReserve pre underlying reserve
    /// @param baseLptReserve pre baseLpt reserve
    /// @param percentWei % of total supply to be removed (1e18 = 100%)
    function _test_RemoveProportionally(uint256 underlyingReserve, uint256 baseLptReserve, uint256 percentWei) public {
        uint256 totalLp = pool.totalSupply();
        // execution
        uint256 liquidityRemove = (totalLp * percentWei) / WAD;
        if (liquidityRemove > totalLp - PoolMath.MINIMUM_LIQUIDITY) return;
        // transfer liquidity to pool
        pool.transfer(address(pool), liquidityRemove);
        (uint256 underlyingOut, uint256 baseLptOut) = pool.removeLiquidity(address(0xcafe));
        // post-condition
        // assert 1
        assertEq(
            underlyingOut,
            underlying.balanceOf(address(0xcafe)),
            "removed underlying should be transferred to recipient"
        );
        assertEq(baseLptOut, tricrypto.balanceOf(address(0xcafe)), "removed baseLpt should be transferred to recipient");
        // assert 2
        uint256 expectedUnderlyingOut = (underlyingReserve * percentWei) / WAD;
        uint256 expectedBaseLptOut = (baseLptReserve * percentWei) / WAD;
        assertApproxEqAbs(underlyingOut, expectedUnderlyingOut, 5, "should be removed proportionally to total supply");
        assertApproxEqAbs(baseLptOut, expectedBaseLptOut, 5, "should be removed proportionally to total supply");
        // assert 3
        assertEq(pool.totalBaseLpt(), baseLptReserve - baseLptOut, "should be removed from baseLpt reserve");
        assertEq(pool.totalUnderlying(), underlyingReserve - underlyingOut, "should be removed from underlying reserve");
        assertEq(pool.totalSupply(), totalLp - liquidityRemove, "liquidity should be removed from total supply");
    }
}
