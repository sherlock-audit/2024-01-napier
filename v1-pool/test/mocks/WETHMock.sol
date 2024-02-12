// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IWETH9} from "src/interfaces/external/IWETH9.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";

interface Vm {
    function deal(address to, uint256 give) external;
}

contract WETHMock is ERC20("WETH", "WETH"), IWETH9 {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    /// @dev WETH9 returns ether balance instead of actual ERC20 token total supply.
    function totalSupply() public view override(ERC20, IERC20) returns (uint256) {
        return super.totalSupply();
    }

    function withdraw(uint256 value) external {
        _burn(msg.sender, value);
        (bool s,) = payable(msg.sender).call{value: value}("");
        require(s, "ETH transfer failed");
    }

    function mint(address account, uint256 amount) public {
        vm.deal(address(this), address(this).balance + amount);
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
        vm.deal(address(this), address(this).balance - amount);
    }
}
