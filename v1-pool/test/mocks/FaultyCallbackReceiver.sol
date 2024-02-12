// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {Vm, StdCheats} from "forge-std/StdCheats.sol";

// Interfaces
import {IERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/IERC20.sol";
import {INapierPool} from "src/interfaces/INapierPool.sol";

// Libraries
import {CallbackInputType, AddLiquidityFaultilyInput, SwapFaultilyInput} from "../shared/CallbackInputType.sol";
import {SignedMath} from "@openzeppelin/contracts@4.9.3/utils/math/SignedMath.sol";

// Inherits
import {MockCallbackReceiver} from "./MockCallbackReceiver.sol";

contract FaultyCallbackReceiver is MockCallbackReceiver, StdCheats {
    using SignedMath for int256;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice true if the callback should trigger a reentrancy call
    bool public doCallback;
    /// @notice data to be used in the reentrancy call
    bytes public callData;
    address public caller;

    /// @notice set reentrancy call data and whether or not to do the callback
    function setReentrancyCall(bytes memory _callData, bool _doCallback) public {
        callData = _callData;
        doCallback = _doCallback;
        caller = address(0x0);
    }

    function mintCallback(uint256 underlyingDelta, uint256 basePoolDelta, bytes calldata data) public override {
        // Do reentrancy call if flag is set
        if (doCallback) _reentrancyCall();
        // If input specifies to do a normal callback, then do it
        // Otherwise, do a faulty callback
        super.mintCallback(underlyingDelta, basePoolDelta, data);

        ////////////// Faulty callback //////////////

        // Read the first 32 bytes of contents to get the input type
        CallbackInputType inputType = abi.decode(data[0:0x20], (CallbackInputType));

        if (inputType == CallbackInputType.AddLiquidityFaultily) {
            // Decode the input data
            AddLiquidityFaultilyInput memory input = abi.decode(data[0x20:], (AddLiquidityFaultilyInput));
            // Check if the faulty flag is set
            if (input.sendInsufficientUnderlying) underlyingDelta -= 1;
            if (input.sendInsufficientBaseLpt) basePoolDelta -= 1;

            input.underlying.transfer(msg.sender, underlyingDelta);
            input.tricrypto.transfer(msg.sender, basePoolDelta);
        }
    }

    /// @notice swap callback
    function swapCallback(int256 underlyingDelta, int256 ptDelta, bytes calldata data) public override {
        // Do reentrancy call if flag is set
        if (doCallback) _reentrancyCall();
        // If input specifies to do a normal callback, then do it
        // Otherwise, do a faulty callback
        super.swapCallback(underlyingDelta, ptDelta, data);

        ////////////// Faulty callback //////////////

        CallbackInputType inputType = abi.decode(data[0:0x20], (CallbackInputType));

        // Swap pt for underlying
        if (inputType == CallbackInputType.SwapPtForUnderlyingFaultily) {
            SwapFaultilyInput memory input = abi.decode(data[0x20:], (SwapFaultilyInput));
            require(
                underlyingDelta >= 0,
                "MockCallbackReceiver: underlyingDelta must be positive. Check the inputType is correct."
            );

            // Send pt to pool
            uint256 value = ptDelta.abs();
            if (input.invokeInsufficientBaseLpt) value -= 1;
            input.pt.transfer(msg.sender, value); // 1 wei less than it should be

            if (input.invokeInsufficientUnderlying) {
                // Set underlying balance of pool to a balance less than it should be so that invariant is violated
                uint256 balanceAfterSwap = input.underlying.balanceOf(msg.sender) - 1; // 1 wei less than it should be
                vm.mockCall(
                    address(input.underlying),
                    abi.encodeCall(input.underlying.balanceOf, (msg.sender)),
                    abi.encode(balanceAfterSwap)
                );
            }
        }
        // Swap underlying for pt
        if (inputType == CallbackInputType.SwapUnderlyingForPtFaultily) {
            SwapFaultilyInput memory input = abi.decode(data[0x20:], (SwapFaultilyInput));
            require(ptDelta >= 0, "MockCallbackReceiver: ptDelta must be positive. Check the inputType is correct.");

            // Send pt to pool
            uint256 value = underlyingDelta.abs();
            if (input.invokeInsufficientUnderlying) value -= 1;
            input.underlying.transfer(msg.sender, value); // 1 wei less than it should be

            if (input.invokeInsufficientBaseLpt) {
                // Set Base Pool LP token balance of pool to a balance less than it should be so that invariant is violated
                IERC20 tricrypto = INapierPool(msg.sender).tricrypto();
                uint256 balanceAfterSwap = tricrypto.balanceOf(msg.sender) - 1; // 1 wei less than it should be
                vm.mockCall(
                    address(tricrypto), abi.encodeCall(tricrypto.balanceOf, (msg.sender)), abi.encode(balanceAfterSwap)
                );
            }
        }
    }

    /// @notice set caller address
    function setCaller(address _caller) public {
        caller = _caller;
    }

    /// @notice reentrancy call
    function _reentrancyCall() public {
        address target = caller;
        if (target == address(0x0)) target = msg.sender;
        (bool success, bytes memory returndata) = target.call(callData);
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
