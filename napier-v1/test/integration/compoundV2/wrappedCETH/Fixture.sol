// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import {CompleteFixture} from "../../../Fixtures.sol";

import {ERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";
import {WrappedCETHAdapter} from "src/adapters/compoundV2/WrappedCETHAdapter.sol";
import {WETH, CETH} from "src/Constants.sol";

abstract contract CETHFixture is CompleteFixture {
    uint256 constant FORKED_AT = 17_330_000;

    uint256 constant FUZZ_UNDERLYING_DEPOSIT_CAP = 100 ether;

    function setUp() public virtual override {
        _DELTA_ = 610000000;
        MIN_UNDERLYING_DEPOSIT = 0.01 ether;
        vm.createSelectFork("mainnet", FORKED_AT);
        _maturity = block.timestamp + 3 * 365 days;
        _tilt = 0;
        _issuanceFee = 0; // 10000 bps = 100%, 10 bps = 0.1%

        super.setUp();

        initialBalance = 300 ether;
        // fund tokens
        deal(WETH, address(this), initialBalance, false);
        // approve tranche to spend underlying
        _approve(address(underlying), address(this), address(tranche), type(uint256).max);
    }

    function _deployAdapter() internal virtual override {
        adapter = new WrappedCETHAdapter(address(0xABCD));
        underlying = ERC20(WETH);
        target = ERC20(address(adapter));
    }

    //////////////////////////////////////////////////////////////////
    /// HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////////

    /// @dev simulate a scale increase
    /// this is used for simulating sunny day condition of Principal Token
    function _simulateScaleIncrease() internal override {
        deal(CETH, CETH.balance + 1 ether);
    }

    /// @dev simulate a scale decrease
    /// this is used for simulating not sunny day condition of Principal Token
    function _simulateScaleDecrease() internal override {
        deal(CETH, CETH.balance - 1 ether);
    }

    function deal(address token, address to, uint256 give, bool adjust) internal virtual override {
        if (token == WETH && adjust == true) {
            adjust = false;
            console2.log("`deal` called with WETH, ignore `adjust` and set to false");
        }
        super.deal(token, to, give, adjust);
    }
}
