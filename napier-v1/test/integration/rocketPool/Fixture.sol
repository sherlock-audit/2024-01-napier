// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import {CompleteFixture} from "../../Fixtures.sol";

import {ERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";
import {RETHAdapter} from "src/adapters/rocketPool/RETHAdapter.sol";
import {WETH, RETH} from "src/Constants.sol";

import {RocketPoolHelper} from "../../utils/RocketPoolHelper.sol";

abstract contract RETHFixture is CompleteFixture {
    using RocketPoolHelper for StdStorage;

    uint256 constant FORKED_AT = 17_330_000;

    /// @dev cap that defines maximum amount of rETH that can be deposited to Tranche
    ///      this is used to bound fuzz arguments.
    uint256 constant FUZZ_UNDERLYING_DEPOSIT_CAP = 100 ether;

    /// @notice Rocket Pool Address storage https://www.codeslaw.app/contracts/ethereum/0x1d8f8f00cfa6758d7be78336684788fb0ee0fa46
    address constant ROCKET_STORAGE = 0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46;

    bytes32 ROCKET_NETWORK_ETH_BALANCE_TOTAL_STORAGE_KEY = keccak256("network.balance.total");

    function setUp() public virtual override {
        _DELTA_ = 10;
        MIN_UNDERLYING_DEPOSIT = 0.01 ether; // Rocket Pool requires a minimum deposit of some ETH
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
        underlying = ERC20(WETH);
        target = ERC20(RETH);
        adapter = new RETHAdapter(ROCKET_STORAGE);
    }

    //////////////////////////////////////////////////////////////////
    /// HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////////

    /// @dev simulate a scale increase
    /// this is used for simulating sunny day condition of Principal Token
    function _simulateScaleIncrease() internal override {
        // overwrite RETH total supply
        // Formula: rethAmount * totalEthBalance / rethSupply = ethAmount
        uint256 supply = RocketPoolHelper.getTotalRETHSupply();
        stdstore.writeTotalRETHSupply(supply - 1 ether); // price goes up
        require(supply - 1 ether == RocketPoolHelper.getTotalRETHSupply(), "failed to overwrite RETH total supply");
    }

    /// @dev simulate a scale decrease
    /// this is used for simulating not sunny day condition of Principal Token
    function _simulateScaleDecrease() internal override {
        uint256 supply = RocketPoolHelper.getTotalRETHSupply();
        stdstore.writeTotalRETHSupply(supply + 1 ether); // price goes down
        require(supply + 1 ether == RocketPoolHelper.getTotalRETHSupply(), "failed to overwrite RETH total supply");
    }

    /// @notice used to fund rETH to a fuzz input address.
    /// @dev if token is rETH, then stake ETH to get rETH.
    ///      rETH balance of `to` will be 1 wei greater than or equal to `give`.
    function deal(address token, address to, uint256 give, bool adjust) internal virtual override {
        if (token == WETH && adjust == true) {
            adjust = false;
            console2.log("`deal` called with WETH, ignore `adjust` and set to false");
        }
        super.deal(token, to, give, adjust);
    }
}
