// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseAdapter} from "../../src/BaseAdapter.sol";
import {MockERC20} from "./MockERC20.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/utils/SafeERC20.sol";

contract MockLendingProtocol {
    constructor(address _underlying, address _target) {
        MockERC20(_underlying).approve(msg.sender, type(uint256).max);
        MockERC20(_target).approve(msg.sender, type(uint256).max);

        // Mint some tokens as reserve
        MockERC20(_underlying).mint(address(this), 1e9 * 1e18);
    }
}

contract MockAdapter is BaseAdapter {
    MockLendingProtocol public lendingProtocol;

    uint256 uDecimals;
    uint256 tDecimals;
    uint256 constant WAD = 1e18;

    uint256 _scale;

    constructor(address _underlying, address _target) BaseAdapter(_underlying, _target) {
        lendingProtocol = new MockLendingProtocol(_underlying, _target);
        MockERC20(_underlying).approve(address(lendingProtocol), type(uint256).max);
        MockERC20(_target).approve(address(lendingProtocol), type(uint256).max);

        uDecimals = MockERC20(_underlying).decimals();
        tDecimals = MockERC20(_target).decimals();

        // 1 target price = 1.2
        // => 1.2 * 10^(18 + uDecimals - tDecimals)
        // if t=6 decimals and u=6 decimals, scale should be 1.2*1e18
        _scale = (10 ** (18 + uDecimals - tDecimals) * 12) / 10;
    }

    function setScale(uint256 scale_) external {
        _scale = scale_;
    }

    function scale() public view virtual override returns (uint256) {
        return _scale;
    }

    function prefundedDeposit() public virtual returns (uint256 underlyingUsed, uint256 sharesMinted) {
        underlyingUsed = MockERC20(underlying).balanceOf(address(this));
        // external call to `scale` is intentional so that `vm.mockCall` can work properly.
        sharesMinted = (underlyingUsed * WAD) / this.scale();

        SafeERC20.safeTransfer(MockERC20(underlying), address(lendingProtocol), underlyingUsed);
        MockERC20(target).mint(msg.sender, sharesMinted);
    }

    function prefundedRedeem(address to) public virtual returns (uint256 amountWithrawn, uint256 sharesRedeemed) {
        sharesRedeemed = MockERC20(target).balanceOf(address(this));
        // external call to `scale` is intentional so that `vm.mockCall` can work properly.
        amountWithrawn = (sharesRedeemed * this.scale()) / WAD;

        uint uBalance = MockERC20(underlying).balanceOf(address(lendingProtocol)); // balance of the external lending protocol
        require(uBalance >= amountWithrawn, "LendingProtocol: insufficient balance");

        SafeERC20.safeTransfer(MockERC20(target), address(lendingProtocol), sharesRedeemed);
        MockERC20(target).burn(address(lendingProtocol), sharesRedeemed);
        SafeERC20.safeTransferFrom(MockERC20(underlying), address(lendingProtocol), to, amountWithrawn);
    }
}
