// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import {CompleteFixture} from "../../Fixtures.sol";

import {ERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/IERC20.sol";
import {AaveV3Adapter} from "src/adapters/aaveV3/AaveV3Adapter.sol";
import {WETH, AWETH, AAVEV3_POOL_ADDRESSES_PROVIDER} from "src/Constants.sol";
import {IPool} from "src/adapters/aaveV3/interfaces/IPool.sol";
import {ILendingPoolAddressesProvider} from "src/adapters/aaveV3/interfaces/ILendingPoolAddressesProvider.sol";

contract AAVEFixture is CompleteFixture {
    uint256 constant FORKED_AT = 17_330_000;

    uint256 constant FUZZ_UNDERLYING_DEPOSIT_CAP = 100 ether;

    /// @notice AaveV3 reward controller address on mainnet
    address rewardsController = 0x8164Cc65827dcFe994AB23944CBC90e0aa80bFcb;
    /// @notice AaveV3 pool address on mainnet
    address pool;

    function setUp() public virtual override {
        _DELTA_ = 40;
        MIN_UNDERLYING_DEPOSIT = 0.01 ether;
        vm.createSelectFork("mainnet", FORKED_AT);
        _maturity = block.timestamp + 3 * 365 days;
        _tilt = 0;
        _issuanceFee = 0; // 10000 bps = 100%, 10 bps = 0.1%

        super.setUp();
        pool = ILendingPoolAddressesProvider(AAVEV3_POOL_ADDRESSES_PROVIDER).getPool();

        initialBalance = 300 ether;
        // fund tokens
        deal(WETH, address(this), initialBalance, false);
        // approve tranche to spend underlying
        _approve(address(underlying), address(this), address(tranche), type(uint256).max);
    }

    function _deployAdapter() internal virtual override {
        adapter = new AaveV3Adapter(WETH, AWETH, address(0xABCD), rewardsController);
        // deal(WETH, address(adapter), 500 ether, false);
        underlying = ERC20(WETH);
        target = ERC20(address(adapter));
    }

    //////////////////////////////////////////////////////////////////
    /// HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////////

    /// @dev simulate a scale increase
    /// this is used for simulating sunny day condition of Principal Token
    function _simulateScaleIncrease() internal override {
        uint256 amount = 200 ether;
        deal(WETH, address(adapter), amount, false);
        _approve(WETH, address(adapter), pool, amount);
        vm.prank(address(adapter));
        IPool(pool).supply(WETH, amount, address(adapter), 0);
    }

    /// @dev simulate a scale decrease
    /// this is used for simulating not sunny day condition of Principal Token
    function _simulateScaleDecrease() internal override {
        uint256 atokenBalance = IERC20(AWETH).balanceOf(address(adapter));
        vm.prank(address(adapter));
        IPool(pool).withdraw(WETH, atokenBalance / 3, address(0x1234));
    }

    function deal(address token, address to, uint256 give, bool adjust) internal virtual override {
        if (token == WETH && adjust == true) {
            adjust = false;
            console2.log("`deal` called with WETH, ignore `adjust` and set to false");
        }
        super.deal(token, to, give, adjust);
    }
}
