// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import {CompleteFixture} from "../../Fixtures.sol";

import {ERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/IERC20.sol";
import {IFrxETHMinter} from "src/adapters/frax/interfaces/IFrxETHMinter.sol";
import {IFraxEtherRedemptionQueue} from "src/adapters/frax/interfaces/IFraxEtherRedemptionQueue.sol";

import {SFrxETHAdapter, BaseLSTAdapter} from "src/adapters/frax/SFrxETHAdapter.sol";
import "src/Constants.sol" as Constants;

contract SFrxETHFixture is CompleteFixture {
    uint256 constant FORKED_AT = 19_000_000;

    uint256 constant FUZZ_UNDERLYING_DEPOSIT_CAP = 1000 ether;

    /// @dev FraxEther redemption queue contract https://etherscan.io/address/0x82bA8da44Cd5261762e629dd5c605b17715727bd
    IFraxEtherRedemptionQueue constant REDEMPTION_QUEUE =
        IFraxEtherRedemptionQueue(0x82bA8da44Cd5261762e629dd5c605b17715727bd);

    /// @dev FraxEther minter contract
    IFrxETHMinter constant FRXETH_MINTER = IFrxETHMinter(0xbAFA44EFE7901E04E39Dad13167D089C559c1138);

    address whale = makeAddr("whale");
    address rebalancer = makeAddr("rebalancer");

    function setUp() public virtual override {
        _DELTA_ = 10;
        MIN_UNDERLYING_DEPOSIT = 0.01 ether;
        MAX_UNDERLYING_DEPOSIT = 10_000 ether;

        vm.createSelectFork("mainnet", FORKED_AT);
        // note sfrxETH Exchange rate increases as the frax msig mints new frxETH corresponding to the staking yield and drops it into the vault (sfrxETH contract).
        // There is a short time period, “cycles” which the exchange rate increases linearly over.
        // See `sfrxETH` and `xERC4626` contract for more details.
        // https://github.com/FraxFinance/frxETH-public/blob/master/src/sfrxETH.sol
        // https://github.com/corddry/ERC4626/blob/6cf2bee5d784169acb02cc6ac0489ca197a4f149/src/xERC4626.sol
        // Here, we need to set the last sync time to the current timestamp.
        // Otherwise, the sfrxETH will revert with underflow error on share price calculation (totalAssets function in xERC4626.sol).
        (bool s, bytes memory ret) = Constants.STAKED_FRXETH.staticcall(abi.encodeWithSignature("lastSync()"));
        require(s, "sfrxETH.lastSync() failed");
        uint32 lastSyncAt = abi.decode(ret, (uint32));
        vm.warp(lastSyncAt);

        _maturity = block.timestamp + 3 * 365 days;
        _tilt = 0;
        _issuanceFee = 0; // 10000 bps = 100%, 10 bps = 0.1%

        super.setUp();
        vm.label(address(FRXETH_MINTER), "FrxETHMinter");
        vm.label(address(REDEMPTION_QUEUE), "RedemptionQueue");
        vm.label(Constants.FRXETH, "frxETH");
        vm.label(Constants.STAKED_FRXETH, "sfrxETH");

        initialBalance = 1_000 ether;
        // fund tokens
        deal(Constants.WETH, address(this), initialBalance, false);
        // approve tranche to spend underlying
        _approve(address(underlying), address(this), address(tranche), type(uint256).max);

        vm.prank(rebalancer);
        SFrxETHAdapter(payable(address(adapter))).setTargetBufferPercentage(0.1 * 1e18); // 10%
    }

    function _deployAdapter() internal virtual override {
        adapter = new SFrxETHAdapter(rebalancer);
        underlying = ERC20(Constants.WETH);
        target = ERC20(address(adapter));
    }

    //////////////////////////////////////////////////////////////////
    /// HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////////

    /// @dev simulate a scale increase
    /// this is used for simulating sunny day condition of Principal Token
    function _simulateScaleIncrease() internal override {
        uint256 amount = (underlying.balanceOf(address(adapter)) * 5) / 100;
        deal(whale, amount);
        vm.prank(whale);
        FRXETH_MINTER.submitAndDeposit{value: amount}(address(adapter));
    }

    /// @dev simulate a scale decrease
    /// this is used for simulating not sunny day condition of Principal Token
    function _simulateScaleDecrease() internal override {
        uint256 sfrxEthBalance = IERC20(Constants.STAKED_FRXETH).balanceOf(address(adapter));
        // Loss 10% of frxETH
        vm.prank(address(adapter));
        IERC20(Constants.STAKED_FRXETH).transfer(whale, sfrxEthBalance / 10);
    }

    function deal(address token, address to, uint256 give, bool adjust) internal virtual override {
        if (token == Constants.WETH && adjust == true) {
            adjust = false;
            console2.log("`deal` called with WETH, ignore `adjust` and set to false");
        }
        super.deal(token, to, give, adjust);
    }
}
