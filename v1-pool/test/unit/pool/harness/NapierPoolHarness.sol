// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {IERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/IERC20.sol";
import {NapierPool} from "src/NapierPool.sol";
import {PoolState} from "src/libs/PoolMath.sol";

contract NapierPoolHarness is NapierPool {
    function exposed_balance(IERC20 token) external view returns (uint256) {
        return _balance(token);
    }

    function exposed_writeState(PoolState memory pool) external {
        _writeState(pool);
    }
}
