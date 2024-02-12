// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";

import {INapierPool} from "src/interfaces/INapierPool.sol";

library SwapEventsLib {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @dev Return the protocol fee from the last "Swap" or "SwapBaseLpt" event in the recorded logs
    function getProtocolFeeFromLastSwapEvent(INapierPool pool) internal returns (uint256) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        require(logs.length > 0, "No logs recorded");
        for (uint256 i = logs.length - 1; i > 0; i--) {
            bytes32 topic0 = logs[i].topics[0]; // topic0 is the event signature
            if (logs[i].emitter != address(pool)) continue;
            if (topic0 == keccak256("Swap(address,address,int256,uint256,int256,uint256,uint256)")) {
                (,,,, uint256 protocolFee) = abi.decode(logs[i].data, (int256, uint256, int256, uint256, uint256));
                console2.log("protocolFee : >>", protocolFee);
                return protocolFee;
            }
            if (topic0 == keccak256("SwapBaseLpt(address,address,int256,int256,uint256,uint256)")) {
                (,,, uint256 protocolFee) = abi.decode(logs[i].data, (int256, int256, uint256, uint256));
                console2.log("protocolFee : >>", protocolFee);
                return protocolFee;
            }
        }
        revert("Neither Swap or SwapBaseLpt event found");
    }

    function getFeesFromLastSwapEvent(INapierPool pool) internal returns (uint256, uint256) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        require(logs.length > 0, "No logs recorded");
        for (uint256 i = logs.length - 1; i > 0; i--) {
            bytes32 topic0 = logs[i].topics[0]; // topic0 is the event signature
            if (logs[i].emitter != address(pool)) continue;
            if (topic0 == keccak256("Swap(address,address,int256,uint256,int256,uint256,uint256)")) {
                (,,, uint256 swapFee, uint256 protocolFee) =
                    abi.decode(logs[i].data, (int256, uint256, int256, uint256, uint256));
                return (swapFee, protocolFee);
            }
            if (topic0 == keccak256("SwapBaseLpt(address,address,int256,int256,uint256,uint256)")) {
                (,, uint256 swapFee, uint256 protocolFee) = abi.decode(logs[i].data, (int256, int256, uint256, uint256));
                return (swapFee, protocolFee);
            }
        }
        revert("Neither Swap or SwapBaseLpt event found");
    }
}
