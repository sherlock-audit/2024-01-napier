// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {RecipientsStore} from "./RecipientsStore.sol";

/// @dev Napier Pool LP token recipients.
contract NapierPoolStore is RecipientsStore {
    /// @dev The sum of protocol fees charged on swaps.
    uint256 public ghost_sumProtocolFees;

    /// @dev The sum of swap fees (including protocol fees) charged on swaps.
    uint256 public ghost_sumSwapFees;

    /// @dev The sum of skimmed underlyings.
    uint256 public ghost_sumSkimmedUnderlyings;

    /// @dev The sum of skimmed base LP tokens.
    uint256 public ghost_sumSkimmedBaseLpTokens;

    function ghost_addProtocolFees(uint256 _protocolFees) external {
        ghost_sumProtocolFees += _protocolFees;
    }

    function ghost_addSwapFees(uint256 _swapFees) external {
        ghost_sumSwapFees += _swapFees;
    }

    function ghost_addSkimmedUnderlyings(uint256 _skimmedUnderlyings) external {
        ghost_sumSkimmedUnderlyings += _skimmedUnderlyings;
    }

    function ghost_addSkimmedBaseLpTokens(uint256 _skimmedBaseLpTokens) external {
        ghost_sumSkimmedBaseLpTokens += _skimmedBaseLpTokens;
    }
}
