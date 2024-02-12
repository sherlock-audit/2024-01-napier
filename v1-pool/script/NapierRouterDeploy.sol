// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {IWETH9} from "src/interfaces/external/IWETH9.sol";
import {IPoolFactory} from "src/interfaces/IPoolFactory.sol";
import {NapierRouter} from "src/NapierRouter.sol";

contract NapierRouterDeploy is Script {
    function run() public {
        address weth = vm.envAddress("WETH");
        IPoolFactory factory = IPoolFactory(vm.envAddress("POOL_FACTORY"));
        require(factory.owner() == msg.sender, "NapierRouterDeploy: not owner");

        vm.startBroadcast();
        NapierRouter router = new NapierRouter(factory, IWETH9(weth));
        factory.authorizeCallbackReceiver(address(router));
        vm.stopBroadcast();

        console2.log("COPY AND PASTE THE FOLLOWING LINES TO .env FILE");
        console2.log("SWAP_ROUTER=%s", address(router));
    }
}
