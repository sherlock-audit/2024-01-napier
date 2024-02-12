// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

library LibIterator {
    function sum(uint256[3] memory arr) internal pure returns (uint256) {
        return arr[0] + arr[1] + arr[2];
    }
}
