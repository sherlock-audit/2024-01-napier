// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseAdapter} from "src/BaseAdapter.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/utils/SafeERC20.sol";

contract MockLendingProtocol {
    constructor(address _underlying, address _target) {
        MockERC20(_underlying).approve(msg.sender, type(uint256).max);
        MockERC20(_target).approve(msg.sender, type(uint256).max);

        // Mint some tokens as reserve
        MockERC20(_underlying).mint(address(this), 100000 * 1e18);
    }
}

contract MockAdapter is BaseAdapter {
    MockLendingProtocol public lendingProtocol;

    uint256 uDecimals;
    uint256 tDecimals;
    uint256 constant WAD = 1e18;

    uint256 maturity;
    uint256 startTimestamp;
    uint256 lastTimestamp;
    uint256 increasePoint;
    uint256 _scale;

    constructor(address _underlying, address _target, uint256 _maturity) BaseAdapter(_underlying, _target) {
        lendingProtocol = new MockLendingProtocol(_underlying, _target);
        MockERC20(_underlying).approve(address(lendingProtocol), type(uint256).max);
        MockERC20(_target).approve(address(lendingProtocol), type(uint256).max);

        uDecimals = MockERC20(_underlying).decimals();
        tDecimals = MockERC20(_target).decimals();

        // At first, 1 target price = 1
        // => 10^(18 + uDecimals - tDecimals)
        // if t=6 decimals and u=6 decimals, scale should be 1*1e18
        // when block.timestamp == maturity, scale would be ~15*1e18 (assume nobody sets scale before maturity)
        _scale = 10 ** (18 + uDecimals - tDecimals);
        maturity = _maturity;
        lastTimestamp = block.timestamp;
        increasePoint = block.timestamp >= maturity ? 0 : (14 * _scale) / (maturity - block.timestamp);
    }

    function previewScale() public view returns (uint256) {
        return _scale + increasePoint * (block.timestamp - lastTimestamp);
    }

    function scale() public view override returns (uint256) {
        return previewScale();
    }

    function updateScale() public {
        _scale = previewScale();
        lastTimestamp = block.timestamp;
    }

    function prefundedDeposit() public virtual returns (uint256 underlyingUsed, uint256 sharesMinted) {
        updateScale();
        underlyingUsed = MockERC20(underlying).balanceOf(address(this));
        // external call to `scale` is intentional so that `vm.mockCall` can work properly.
        sharesMinted = (underlyingUsed * WAD) / this.scale();

        SafeERC20.safeTransfer(MockERC20(underlying), address(lendingProtocol), underlyingUsed);
        MockERC20(target).mint(msg.sender, sharesMinted);
    }

    function prefundedRedeem(address to) public virtual returns (uint256 amountWithrawn, uint256 sharesRedeemed) {
        updateScale();
        sharesRedeemed = MockERC20(target).balanceOf(address(this));
        // external call to `scale` is intentional so that `vm.mockCall` can work properly.
        amountWithrawn = (sharesRedeemed * this.scale()) / WAD;

        SafeERC20.safeTransfer(MockERC20(target), address(lendingProtocol), sharesRedeemed);
        MockERC20(target).burn(address(lendingProtocol), sharesRedeemed);
        SafeERC20.safeTransferFrom(MockERC20(underlying), address(lendingProtocol), to, amountWithrawn);
    }
}
