// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

import {CallbackDataTypes, CallbackType} from "src/libs/CallbackDataTypes.sol";

contract CallbackDataTypesTest is Test {
    function test_getCallbackType(bytes calldata data) public {
        vm.assume(data.length >= 32);
        uint256 expected = abi.decode(data[0:32], (uint256));
        vm.assume(expected <= uint8(type(CallbackType).max));

        CallbackType _type = CallbackDataTypes.getCallbackType(data);
        assertEq(uint256(_type), expected, "CallbackType should be equal to the first 32 byte of the data");
    }

    function test_getCallbackType_RevertWhen_NonExistentEnum(bytes calldata data) public {
        vm.assume(data.length >= 32);

        uint256 expected = abi.decode(data[0:32], (uint256));
        vm.assume(expected > uint8(type(CallbackType).max));

        vm.expectRevert();
        this._getCallbackType(data);
    }

    function _getCallbackType(bytes calldata data) external pure returns (CallbackType callbackType) {
        return CallbackDataTypes.getCallbackType(data);
    }
}
