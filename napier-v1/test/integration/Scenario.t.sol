// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./ScenarioBaseTest.t.sol";
import {BaseAdapter} from "src/BaseAdapter.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockAdapter} from "../mocks/MockAdapter.sol";

contract TestMockAssetScenario is ScenarioBaseTest {
    using Cast for *;

    function setUp() public override {
        ENABLE_GAS_LOGGING = true;

        vm.warp(365 days);
        _DELTA_ = 5;
        _maturity = block.timestamp + 365 days;
        _tilt = 10;
        _issuanceFee = 100;

        super.setUp();

        initialBalance = 100 * ONE_SCALE;

        // fund tokens
        deal(address(underlying), address(this), initialBalance, true);
        _approve(address(underlying), address(this), address(tranche), type(uint256).max);
    }

    function _deployAdapter() internal virtual override {
        underlying = new MockERC20("Underlying", "U", 6);
        target = new MockERC20("Target", "T", 6);

        adapter = new MockAdapter(address(underlying), address(target));
    }

    function _simulateScaleIncrease() internal override {
        uint256 oldScale = adapter.scale();
        adapter.asMock().setScale((oldScale * 15) / 10);
    }

    function _simulateScaleDecrease() internal override {
        uint256 oldScale = adapter.scale();
        adapter.asMock().setScale((oldScale * 9) / 10);
    }
}

/// @notice A library to cast a contract type to another contract type.
library Cast {
    function asMock(BaseAdapter adapter) internal pure returns (MockAdapter mock) {
        assembly {
            mock := adapter
        }
    }
}
