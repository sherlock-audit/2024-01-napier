// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {PoolGetters} from "./Getters.t.sol";

import {LiquidityBaseTest} from "../../shared/Liquidity.t.sol";
import {NapierPoolHarness} from "./harness/NapierPoolHarness.sol";

import {PoolState} from "src/libs/PoolMath.sol";
import {MAX_LN_FEE_RATE_ROOT, MAX_PROTOCOL_FEE_PERCENT, MIN_INITIAL_ANCHOR} from "src/libs/Constants.sol";
import {Errors} from "src/libs/Errors.sol";

contract PoolSetters is PoolGetters {
    function test_writeState() public anytime {
        PoolState memory state = PoolState({
            totalUnderlying18: 3000 * 1e18,
            totalBaseLptTimesN: N_COINS * 1000 * 1e18,
            lnFeeRateRoot: poolConfig.lnFeeRateRoot,
            protocolFeePercent: poolConfig.protocolFeePercent,
            scalarRoot: poolConfig.scalarRoot,
            maturity: maturity,
            lastLnImpliedRate: 1.2 * 1e18
        });
        NapierPoolHarness(address(pool)).exposed_writeState(state);

        assertEq(
            pool.totalUnderlying(),
            3000 * ONE_UNDERLYING,
            "totalUnderlying18 should be converted to underlying token decimals"
        );
        assertEq(pool.totalBaseLpt(), 1000 * 1e18, "totalBaseLptTimesN should be divided by N_COINS");
        assertEq(pool.lastLnImpliedRate(), 1.2 * 1e18, "lastLnImpliedRate should be updated");
    }

    function test_setFeeParameter() public anytime {
        vm.startPrank(owner);
        pool.setFeeParameter("lnFeeRateRoot", 0.001111 * 1e18);
        pool.setFeeParameter("protocolFeePercent", 11);
        vm.stopPrank();

        PoolState memory state = pool.readState();
        assertEq(state.lnFeeRateRoot, 0.001111 * 1e18, "lnFeeRateRoot should be updated");
        assertEq(state.protocolFeePercent, 11, "protocolFeePercent should be updated");
    }

    function test_setFeeParameter_RevertIf_NotOwner() public anytime {
        vm.startPrank(address(0xbabe));
        vm.expectRevert(Errors.PoolOnlyOwner.selector);
        pool.setFeeParameter("lnFeeRateRoot", 0.001 * 1e18);

        vm.expectRevert(Errors.PoolOnlyOwner.selector);
        pool.setFeeParameter("protocolFeePercent", 10);
        vm.stopPrank();
    }

    function test_setFeeParameter_RevertIf_InvalidParameterName() public anytime {
        vm.prank(owner);
        vm.expectRevert(Errors.PoolInvalidParamName.selector);
        pool.setFeeParameter("random_name", 0.001 * 1e18);
    }

    function test_setFeeParameter_RevertIf_LnFeeRateRootTooHigh() public anytime {
        vm.prank(owner);
        vm.expectRevert(Errors.LnFeeRateRootTooHigh.selector);
        pool.setFeeParameter("lnFeeRateRoot", MAX_LN_FEE_RATE_ROOT + 1);
    }

    function test_setFeeParameter_RevertIf_ProtocolFeePercent() public anytime {
        vm.prank(owner);
        vm.expectRevert(Errors.ProtocolFeePercentTooHigh.selector);
        pool.setFeeParameter("protocolFeePercent", MAX_PROTOCOL_FEE_PERCENT + 1);
    }
}
