// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import {CompleteFixture} from "../../Fixtures.sol";

import {ERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/IERC20.sol";
import {MA3WETHAdapter} from "src/adapters/morphoAaveV3/MA3WETHAdapter.sol";
import {WETH, MA3WETH, MORPHO_AAVE_V3} from "src/Constants.sol";
import {IMorpho} from "src/adapters/morphoAaveV3/interfaces/IMorpho.sol";

contract MorphoFixture is CompleteFixture {
    uint256 constant FORKED_AT = 17_950_000;
    // @notice Morpho Aave V3 rewards handler contract address on mainnet
    address constant MORPHO_REWARDS_DISTRIBUTOR = 0x3B14E5C73e0A56D607A8688098326fD4b4292135;
    uint256 constant FUZZ_UNDERLYING_DEPOSIT_CAP = 100 ether;

    function setUp() public virtual override {
        _DELTA_ = 40;
        MIN_UNDERLYING_DEPOSIT = 0.01 ether;
        vm.createSelectFork("mainnet", FORKED_AT);
        _maturity = block.timestamp + 3 * 365 days;
        _tilt = 0;
        _issuanceFee = 0; // 10000 bps = 100%, 10 bps = 0.1%

        super.setUp();
        vm.label(MA3WETH, "ma3WETHERC4626Vault");
        vm.label(MORPHO_AAVE_V3, "morphoAaveV3ETH");
        vm.label(0xeA51d7853EEFb32b6ee06b1C12E6dcCA88Be0fFE, "aaveVariableDebtWETH");

        initialBalance = 300 ether;
        // fund tokens
        deal(WETH, address(this), initialBalance, false);
        // approve tranche to spend underlying
        _approve(address(underlying), address(this), address(tranche), type(uint256).max);
    }

    function _deployAdapter() internal virtual override {
        adapter = new MA3WETHAdapter(address(0xABCD), MORPHO_REWARDS_DISTRIBUTOR);
        underlying = ERC20(WETH);
        target = ERC20(address(adapter));
    }

    //////////////////////////////////////////////////////////////////
    /// HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////////

    /// @dev simulate a scale increase
    /// this is used for simulating sunny day condition of Principal Token
    function _simulateScaleIncrease() internal override {
        deal(WETH, address(0x1234), 1 ether, false);
        _approve(WETH, address(0x1234), MORPHO_AAVE_V3, 1 ether);
        vm.prank(address(0x1234));
        IMorpho(MORPHO_AAVE_V3).supply(WETH, 1 ether, MA3WETH, 0);
    }

    /// @dev simulate a scale decrease
    /// this is used for simulating not sunny day condition of Principal Token
    function _simulateScaleDecrease() internal override {
        // Unbacked mint to decrease scale
        deal(MA3WETH, MA3WETH, ERC20(MA3WETH).balanceOf(MA3WETH) + 1000 * 1e18, true);
    }

    function deal(address token, address to, uint256 give, bool adjust) internal virtual override {
        if (token == WETH && adjust == true) {
            adjust = false;
            console2.log("`deal` called with WETH, ignore `adjust` and set to false");
        }
        super.deal(token, to, give, adjust);
    }
}
