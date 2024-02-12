// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolSwapBaseTest} from "./Swap.t.sol";

abstract contract ApproximationBaseTest is PoolSwapBaseTest {
    function setUp() public override {
        super.setUp();
        _approve(underlying, address(this), address(router), type(uint256).max);
        _approve(tricrypto, address(this), address(router), type(uint256).max);
        _approvePts(address(this), address(router), type(uint256).max);

        deal(address(underlying), address(this), 1000 * ONE_UNDERLYING, false);
        dealPts(address(this), 1000 * ONE_UNDERLYING, false);
        deal(address(tricrypto), address(this), 1000 * 1e18, false);
    }

    function test_RevertIf_InvaldParams() public virtual;
    function test_RevertIf_NotConverged() public virtual;
}
