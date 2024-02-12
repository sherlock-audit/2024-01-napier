// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {CallbackInputType, AddLiquidityInput, SwapInput} from "../shared/CallbackInputType.sol";

import {IERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/IERC20.sol";
import {INapierSwapCallback} from "src/interfaces/INapierSwapCallback.sol";
import {INapierMintCallback} from "src/interfaces/INapierMintCallback.sol";
import {INapierPool} from "src/interfaces/INapierPool.sol";
import {SignedMath} from "@openzeppelin/contracts@4.9.3/utils/math/SignedMath.sol";
import "forge-std/Test.sol";

/// @notice Callback contract for testing swap functions
contract MockCallbackReceiver is INapierSwapCallback, INapierMintCallback {
    using SignedMath for int256;

    /// @dev Used by invariant tests to check whether an address is MockCallbackReceiver
    bool public isMockCallbackReceiver = true;

    function mintCallback(uint256 underlyingDelta, uint256 basePoolDelta, bytes calldata data) public virtual {
        // Read the first 32 bytes of contents to get the input type
        CallbackInputType inputType = abi.decode(data[0:0x20], (CallbackInputType));

        if (inputType == CallbackInputType.AddLiquidity) {
            // Decode the input data
            AddLiquidityInput memory input = abi.decode(data[0x20:], (AddLiquidityInput));
            input.underlying.transfer(msg.sender, underlyingDelta);
            input.tricrypto.transfer(msg.sender, basePoolDelta);
        }
    }

    function swapCallback(int256 underlyingDelta, int256 ptDelta, bytes calldata data) public virtual {
        CallbackInputType inputType = abi.decode(data[0:0x20], (CallbackInputType));

        if (inputType == CallbackInputType.SwapPtForUnderlying) {
            SwapInput memory input = abi.decode(data[0x20:], (SwapInput));
            require(
                underlyingDelta >= 0,
                "MockCallbackReceiver: underlyingDelta must be positive. Check the inputType is correct."
            );
            // Send pt to pool
            input.pt.transfer(msg.sender, ptDelta.abs());
        }
        if (inputType == CallbackInputType.SwapUnderlyingForPt) {
            SwapInput memory input = abi.decode(data[0x20:], (SwapInput));
            require(ptDelta >= 0, "MockCallbackReceiver: ptDelta must be positive. Check the inputType is correct.");
            // Send underlying to pool
            input.underlying.transfer(msg.sender, underlyingDelta.abs());
        }
    }
}
