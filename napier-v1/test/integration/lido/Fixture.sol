// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import {CompleteFixture} from "../../Fixtures.sol";

import {ERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/IERC20.sol";
import {IStETH} from "src/adapters/lido/interfaces/IStETH.sol";
import {IWithdrawalQueueERC721} from "src/adapters/lido/interfaces/IWithdrawalQueueERC721.sol";

import {StEtherAdapter, BaseLSTAdapter} from "src/adapters/lido/StEtherAdapter.sol";
import "src/Constants.sol" as Constants;

contract StEtherFixture is CompleteFixture {
    using stdStorage for StdStorage;

    uint256 constant FORKED_AT = 19_000_000;

    uint256 constant FUZZ_UNDERLYING_DEPOSIT_CAP = 1000 ether;

    bytes32 constant BUFFERED_ETHER_POSITION_SLOT = 0xed310af23f61f96daefbcd140b306c0bdbf8c178398299741687b90e794772b0;

    /// @notice stETH
    IStETH public constant STETH = IStETH(Constants.STETH);

    /// @dev Lido WithdrawalQueueERC721
    IWithdrawalQueueERC721 public constant LIDO_WITHDRAWAL_QUEUE =
        IWithdrawalQueueERC721(Constants.LIDO_WITHDRAWAL_QUEUE);

    address rebalancer = makeAddr("rebalancer");

    function setUp() public virtual override {
        _DELTA_ = 10;
        MIN_UNDERLYING_DEPOSIT = 0.01 ether;
        MAX_UNDERLYING_DEPOSIT = 10_000 ether;

        vm.createSelectFork("mainnet", FORKED_AT);

        _maturity = block.timestamp + 3 * 365 days;
        _tilt = 0;
        _issuanceFee = 0; // 10000 bps = 100%, 10 bps = 0.1%

        super.setUp();
        vm.label(Constants.LIDO_WITHDRAWAL_QUEUE, "stWERC721");
        vm.label(Constants.STETH, "stETH");

        initialBalance = 1_000 ether;
        // fund tokens
        deal(Constants.WETH, address(this), initialBalance, false);
        // approve tranche to spend underlying
        _approve(address(underlying), address(this), address(tranche), type(uint256).max);

        vm.prank(rebalancer);
        StEtherAdapter(payable(address(adapter))).setTargetBufferPercentage(0.1 * 1e18); // 10%
    }

    function _deployAdapter() internal virtual override {
        adapter = new StEtherAdapter(rebalancer);
        underlying = ERC20(Constants.WETH);
        target = ERC20(address(adapter));
    }

    //////////////////////////////////////////////////////////////////
    /// HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////////

    /// @dev simulate a scale increase
    /// this is used for simulating sunny day condition of Principal Token
    function _simulateScaleIncrease() internal override {
        // Increase 5% of stETH
        bytes32 pooledETH = vm.load(address(STETH), BUFFERED_ETHER_POSITION_SLOT);
        vm.store(address(STETH), BUFFERED_ETHER_POSITION_SLOT, bytes32(((uint256(pooledETH) * 105) / 100)));
    }

    /// @dev simulate a scale decrease
    /// this is used for simulating not sunny day condition of Principal Token
    function _simulateScaleDecrease() internal override {
        // Loss 5% of stETH
        bytes32 pooledETH = vm.load(address(STETH), BUFFERED_ETHER_POSITION_SLOT);
        vm.store(address(STETH), BUFFERED_ETHER_POSITION_SLOT, bytes32(((uint256(pooledETH) * 95) / 100)));
    }

    function deal(address token, address to, uint256 give, bool adjust) internal virtual override {
        if (token == Constants.WETH && adjust == true) {
            adjust = false;
            console2.log("`deal` called with WETH, ignore `adjust` and set to false");
        }
        super.deal(token, to, give, adjust);
    }
}
