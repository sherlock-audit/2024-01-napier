// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {CurveTricryptoFactory} from "src/interfaces/external/CurveTricryptoFactory.sol";
import {IPoolFactory} from "src/interfaces/IPoolFactory.sol";

import {Quoter} from "src/lens/Quoter.sol";

contract QuoterDeploy is Script {
    function run() public {
        IPoolFactory poolFactory = IPoolFactory(vm.envAddress("POOL_FACTORY"));

        vm.startBroadcast();
        require(poolFactory.owner() == msg.sender, "QuoterDeploy: not owner");

        Quoter quoter = new Quoter(poolFactory);
        poolFactory.authorizeCallbackReceiver(address(quoter));

        vm.stopBroadcast();

        console2.log("QUOTER=%s", address(quoter));
    }
}
