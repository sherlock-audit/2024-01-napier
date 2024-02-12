// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {LiquidityBaseTest} from "../../shared/Liquidity.t.sol";

contract PoolSkimTest is LiquidityBaseTest {
    function setUp() public override {
        super.setUp();
        _setUpNapierPoolLiquidity({
            recipient: address(0x13),
            underlyingIn: 3000 * ONE_UNDERLYING,
            baseLptIn: 1000 * 1e18
        });
        pool.skim(); // Ensure pool doesn't have any excess tokens (including fees) before each test
    }

    function test_skim_RevertIf_Reentrant() public {
        _deployFaultyCallbackReceiverTo(address(0xbad)); // 0xbad is a faulty callback receiver
        _expectRevertIf_Reentrant(
            address(0xbad), // faulty callback receiver
            abi.encodeCall(pool.skim, ())
        );
        vm.prank(address(0xbad)); // 0xbad receives callback from pool
        pool.addLiquidity(1000, 1000, address(0xbad), "");
    }

    function test_skim_WhenBothExcess() public {
        uint256 excessUnderlying = 10 * ONE_UNDERLYING;
        uint256 excessBaseLpt = 0.1 * 1e18;
        _test_skim(excessUnderlying, excessBaseLpt);
    }

    function test_skim_WhenUnderlyingExcess() public {
        uint256 excessUnderlying = 10 * ONE_UNDERLYING;
        uint256 excessBaseLpt = 0;
        _test_skim(excessUnderlying, excessBaseLpt);
    }

    function test_skim_WhenBaseLptExcess() public {
        uint256 excessUnderlying = 0;
        uint256 excessBaseLpt = 0.1 * 1e18;
        _test_skim(excessUnderlying, excessBaseLpt);
    }

    function test_skim_WhenNoExcess() public {
        uint256 excessUnderlying = 0;
        uint256 excessBaseLpt = 0;
        _test_skim(excessUnderlying, excessBaseLpt);
    }

    function _test_skim(uint256 excessUnderlying, uint256 excessBaseLpt) public {
        uint256 preTotalUnderlying = pool.totalUnderlying();
        uint256 preTotalBaseLpt = pool.totalBaseLpt();
        fund(address(underlying), address(pool), excessUnderlying, false);
        fund(address(tricrypto), address(pool), excessBaseLpt, false);

        pool.skim();

        // Check that the pool state has been updated
        assertEq(underlying.balanceOf(feeRecipient), excessUnderlying, "feeRecipient should receive underlying");
        assertEq(tricrypto.balanceOf(feeRecipient), excessBaseLpt, "feeRecipient should receive baseLpt");

        assertEq(underlying.balanceOf(address(pool)), preTotalUnderlying, "underlying balance");
        assertEq(tricrypto.balanceOf(address(pool)), preTotalBaseLpt, "baseLpt balance");

        assertEq(pool.totalUnderlying(), preTotalUnderlying, "totalUnderlying does not change");
        assertEq(pool.totalBaseLpt(), preTotalBaseLpt, "totalBaseLpt does not change");

        assertReserveBalanceMatch();
    }
}
