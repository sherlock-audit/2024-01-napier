// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {Tranche} from "src/Tranche.sol";
import {TrancheFactory} from "src/TrancheFactory.sol";
import {YieldToken} from "src/YieldToken.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockWETH} from "./MockWETH.sol";
import {MockAdapter, MockLendingProtocol} from "./MockAdapter.sol";

contract MockDeployer is Script {
    uint256 maturity = vm.envUint("MATURITY");
    uint256 tilt = 0;
    uint256 issuanceFee = 10; // 10000 bps = 100%, 10 bps = 0.1%

    function run() public {
        // Use option --private-key 0x...
        vm.startBroadcast();

        TrancheFactory factory = TrancheFactory(vm.envAddress("TRANCHE_FACTORY"));

        address management = factory.management();
        require(management == msg.sender, "MockDeployer: sender is not management");

        MockWETH weth = new MockWETH(management);

        MockERC20 cETH = new MockERC20("CompoundV2 ETH", "cETH", 18);
        MockERC20 morphoWETH = new MockERC20("Morpho AaveV3 Optimizer WETH", "ma3WETH", 18);
        MockERC20 aETH = new MockERC20("AaveV3 ETH", "aETH", 18);

        // Mint WETH unbaced by ETH
        MockAdapter cAdapter = new MockAdapter(address(weth), address(cETH), maturity);
        MockAdapter mAdapter = new MockAdapter(address(weth), address(morphoWETH), maturity);
        MockAdapter aAdapter = new MockAdapter(address(weth), address(aETH), maturity);

        console2.log("address(weth) :>>", address(weth));
        console2.log("address(cETH) :>>", address(cETH));
        console2.log("address(morphoWETH) :>>", address(morphoWETH));
        console2.log("address(aETH) :>>", address(aETH));

        console2.log("address(cAdapter) :>>", address(cAdapter));
        console2.log("address(mAdapter) :>>", address(mAdapter));
        console2.log("address(aAdapter) :>>", address(aAdapter));

        // Only Management can deploy tranches
        address cTranche = factory.deployTranche(address(cAdapter), maturity, tilt, issuanceFee);
        address mTranche = factory.deployTranche(address(mAdapter), maturity, tilt, issuanceFee);
        address aTranche = factory.deployTranche(address(aAdapter), maturity, tilt, issuanceFee);

        console2.log("cTranche :>>", cTranche);
        console2.log("mTranche :>>", mTranche);
        console2.log("aTranche :>>", aTranche);

        vm.stopBroadcast();
    }
}
