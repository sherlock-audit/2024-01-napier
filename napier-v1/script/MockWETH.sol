// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {Pausable} from "@openzeppelin/contracts@4.9.3/security/Pausable.sol";
import {Ownable2Step} from "@openzeppelin/contracts@4.9.3/access/Ownable2Step.sol";
import {ERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";

contract MockWETH is Ownable2Step, Pausable, ERC20("WETH", "WETH") {
    constructor(address _owner) {
        _transferOwnership(_owner);
    }

    receive() external payable {
        _mint(msg.sender, msg.value);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function fund() external payable onlyOwner {}

    function mint(address to, uint256 value) external whenNotPaused {
        _mint(to, value);
    }

    function burn(address from, uint256 value) external whenNotPaused {
        _burn(from, value);
    }

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 value) external {
        _burn(msg.sender, value);
        payable(msg.sender).transfer(value);
    }
}
