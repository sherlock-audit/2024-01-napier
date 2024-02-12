// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {ITranche} from "src/interfaces/ITranche.sol";
import "./MockAdapter.sol";

contract MockFaultyAdapter is MockAdapter {
    bytes public callData;
    bool public doCallback;

    constructor(address _underlying, address _target) MockAdapter(_underlying, _target) {}

    function setReentrancyCall(bytes memory _callData, bool _doCallback) public {
        callData = _callData;
        doCallback = _doCallback;
    }

    function scale() public view override returns (uint256) {
        return _scale;
    }

    function prefundedDeposit() public override returns (uint256, uint256) {
        if (doCallback) {
            _reentrancyCall();
            return (0, 0);
        }
        return super.prefundedDeposit();
    }

    function prefundedRedeem(address to) public override returns (uint256, uint256) {
        if (doCallback) {
            _reentrancyCall();
            return (0, 0);
        }
        return super.prefundedRedeem(to);
    }

    function _reentrancyCall() public {
        (bool success, bytes memory returndata) = msg.sender.call(callData);
        if (!success) {
            // Taken from: Openzeppelinc Address.sol
            // The easiest way to bubble the revert reason is using memory via assembly
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        }
    }
}
