// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/IERC20.sol";
import {CurveTricryptoOptimizedWETH} from "src/interfaces/external/CurveTricryptoOptimizedWETH.sol";

contract MockFakePool {
    address fakeUnderlyingAddress;
    address fakeTricryptoAddress;

    constructor() {
        fakeUnderlyingAddress = address(0x1234);
        fakeTricryptoAddress = address(0x5678);
    }

    function getAssets() external view returns (address, address) {
        return (fakeUnderlyingAddress, fakeTricryptoAddress);
    }
}
