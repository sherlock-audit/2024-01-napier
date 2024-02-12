// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {IERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/IERC20.sol";

/// @title CallbackInputType - used to specify the type of input and data for testing callback functions.
/// @dev See `MockCallbackReceiver` and `FaultyCallbackReceiver` contracts for more details.

/// @title CallbackInputType - used to specify the type of input for the callback function for the test contract.
enum CallbackInputType {
    AddLiquidity,
    AddLiquidityFaultily,
    SwapUnderlyingForPt,
    SwapUnderlyingForPtFaultily,
    SwapPtForUnderlying,
    SwapPtForUnderlyingFaultily
}

struct AddLiquidityInput {
    IERC20 underlying;
    IERC20 tricrypto;
}

struct AddLiquidityFaultilyInput {
    IERC20 underlying;
    IERC20 tricrypto;
    bool sendInsufficientUnderlying; // if true, send 1 less underlying token than expected
    bool sendInsufficientBaseLpt; // if true, send 1 less baseLpt token than expected
}

struct SwapInput {
    IERC20 underlying;
    IERC20 pt;
}

struct SwapFaultilyInput {
    IERC20 underlying;
    IERC20 pt;
    bool invokeInsufficientUnderlying; // if true, send 1 less underlying token than expected
    bool invokeInsufficientBaseLpt; // if true, send 1 less baseLpt token than expected
}
