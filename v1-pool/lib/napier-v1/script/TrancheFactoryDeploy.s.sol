// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {TrancheFactory} from "src/TrancheFactory.sol";

/// @dev https://github.com/pcaversaccio/create2deployer/blob/main/contracts/Create2Deployer.sol
interface Create2Deployer {
    /**
     * @dev Deploys a contract using `CREATE2`. The address where the
     * contract will be deployed can be known in advance via {computeAddress}.
     *
     * The bytecode for a contract can be obtained from Solidity with
     * `type(contractName).creationCode`.
     *
     * Requirements:
     * - `bytecode` must not be empty.
     * - `salt` must have not been used for `bytecode` already.
     * - the factory must have a balance of at least `value`.
     * - if `value` is non-zero, `bytecode` must have a `payable` constructor.
     */
    function deploy(uint256 value, bytes32 salt, bytes memory code) external;

    /**
     * @dev Returns the address where a contract will be stored if deployed via {deploy}.
     * Any change in the `bytecodeHash` or `salt` will result in a new destination address.
     */
    function computeAddress(bytes32 salt, bytes32 codeHash) external view returns (address);
}

Create2Deployer constant create2Deployer = Create2Deployer(0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2);

contract TrancheFactoryDeploy is Script {
    function run() public {
        // Use option --private-key 0x...
        vm.startBroadcast();

        address management = vm.envAddress("MANAGEMENT");

        // Packed and ABI-encoded contract bytecode and constructor arguments.
        bytes memory initCode = abi.encodePacked(type(TrancheFactory).creationCode, abi.encode(management));

        create2Deployer.deploy(0, bytes32(vm.envUint("SALT")), initCode);

        TrancheFactory factory =
            TrancheFactory(create2Deployer.computeAddress(bytes32(vm.envUint("SALT")), keccak256(initCode)));
        vm.stopBroadcast();

        console2.log("Deployed TrancheFactory address :>>", address(factory));

        // Ensure that the factory was deployed correctly
        require(factory.management() == management, "TrancheFactoryDeploy: invalid management");
    }
}
