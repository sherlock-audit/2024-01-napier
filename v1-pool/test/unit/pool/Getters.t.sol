// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {LiquidityBaseTest} from "../../shared/Liquidity.t.sol";
import {NapierPoolHarness} from "./harness/NapierPoolHarness.sol";

import {IERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/IERC20.sol";
import {PoolFactory, IPoolFactory} from "src/PoolFactory.sol";
import {NapierPool} from "src/NapierPool.sol";
import {PoolState} from "src/libs/PoolMath.sol";

contract PoolGetters is LiquidityBaseTest {
    function setUp() public virtual override {
        super.setUp();
        // Overwrite deployed pool with harness
        vm.mockCall(
            address(poolFactory),
            abi.encodeWithSelector(PoolFactory.args.selector),
            abi.encode(
                IPoolFactory.InitArgs({
                    assets: IPoolFactory.PoolAssets({
                        basePool: address(tricrypto),
                        underlying: address(underlying),
                        principalTokens: [address(pts[0]), address(pts[1]), address(pts[2])]
                    }),
                    configs: poolConfig
                })
            )
        );
        vm.prank(address(poolFactory)); // impersonate pool factory
        deployCodeTo("NapierPoolHarness.sol", address(pool));
        vm.clearMockedCalls();

        _setUpNapierPoolLiquidity({
            recipient: address(0x13),
            underlyingIn: 3000 * ONE_UNDERLYING,
            baseLptIn: 1000 * 1e18
        });
    }

    function test_readState() public anytime {
        PoolState memory state = pool.readState();
        assertEq(state.totalUnderlying18, 3000 * 1e18, "totalUnderlying18");
        assertEq(state.totalBaseLptTimesN, N_COINS * 1000 * 1e18, "totalBaseLptTimesN");
        assertEq(state.lnFeeRateRoot, poolConfig.lnFeeRateRoot, "lnFeeRateRoot");
        assertEq(state.protocolFeePercent, poolConfig.protocolFeePercent, "protocolFeePercent");
        assertEq(state.scalarRoot, poolConfig.scalarRoot, "scalarRoot");
        assertEq(state.maturity, maturity, "expiry");
        assertGt(state.lastLnImpliedRate, 0, "lastLnImpliedRate");
    }

    function test_principalTokens() public {
        IERC20[3] memory principals = pool.principalTokens();
        assertEq(address(principals[0]), address(pts[0]));
        assertEq(address(principals[1]), address(pts[1]));
        assertEq(address(principals[2]), address(pts[2]));
    }

    function test_balance() public {
        deal(address(underlying), address(pool), 999, false);
        assertEq(NapierPoolHarness(address(pool)).exposed_balance(underlying), 999);
    }

    function test_RevertIf_MalformedReturnData_balance() public {
        vm.mockCall(
            address(underlying),
            abi.encodeWithSignature("balanceOf(address)", address(pool)),
            abi.encodePacked(uint8(12))
        );
        vm.expectRevert();
        NapierPoolHarness(address(pool)).exposed_balance(underlying);
        vm.clearMockedCalls();
    }

    function test_RevertIf_Fail_balance() public {
        vm.mockCallRevert(address(underlying), abi.encodeWithSignature("balanceOf(address)", address(pool)), "");
        vm.expectRevert();
        NapierPoolHarness(address(pool)).exposed_balance(underlying);
        vm.clearMockedCalls();
    }
}
