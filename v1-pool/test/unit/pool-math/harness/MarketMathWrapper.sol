// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {MarketMathCore, MarketState, MarketPreCompute, PYIndex, Errors} from "../reference/MarketMathCore.sol";

/// @title MarketMathWrapper harness contract for testing MarketMathCore Library
/// @dev This wrapper is needed because the MarketMathCore library is colllections of internal functions.
/// This contract exposes the internal functions as public functions, which makes it easier to test revert messages.
/// @dev Terms:
/// - Sy: SY is a token that implements a standardized API for wrapped yield-bearing tokens within smart contracts.
/// - PY: PY stands for Principal Token and Yield Token.
/// - PYIndex: PTIndex is a conversion rate between SY and underlyin asset.
/// - market: AMM Pool
/// Changes:
/// @dev Pendle AMM takes SY and PY as a pair. Internally, it converts SY to underlying units using PYIndex when calculating swaps and adding/removing liquidity.
/// @dev In this contract, we use ONE as PYIndex, which means 1 SY = 1 underlying.
/// Technically we can consider Sy as the underlying in this contract.
/// @dev `blockTime` is set to current block timestamp in all functions.
contract MarketMathWrapper {
    PYIndex internal constant ONE = PYIndex.wrap(uint256(1e18));

    /// @notice swap exact amount of PT for SY
    /// @param market market state
    /// @param exactPtToMarket exact amount of PT to market
    function swapExactPtForSy(MarketState memory market, uint256 exactPtToMarket)
        public
        view
        returns (uint256 netSyToAccount, uint256 netSyFee, uint256 netSyToReserve)
    {
        uint256 blockTime = block.timestamp;
        (netSyToAccount, netSyFee, netSyToReserve) =
            MarketMathCore.swapExactPtForSy(market, ONE, exactPtToMarket, blockTime);
    }

    /// @notice swap exact amount of SY for PT
    /// @param market market state
    /// @param exactPtToAccount exact amount of PT to account
    function swapSyForExactPt(MarketState memory market, uint256 exactPtToAccount)
        public
        view
        returns (uint256 netSyToMarket, uint256 netSyFee, uint256 netSyToReserve)
    {
        uint256 blockTime = block.timestamp;
        (netSyToMarket, netSyFee, netSyToReserve) =
            MarketMathCore.swapSyForExactPt(market, ONE, exactPtToAccount, blockTime);
    }

    /// @notice Compute AMM parameters
    /// @param market market state
    function getMarketPreCompute(MarketState memory market) public view returns (MarketPreCompute memory) {
        return MarketMathCore.getMarketPreCompute(market, ONE, block.timestamp);
    }

    /// @notice Compute swap result
    function executeTradeCore(MarketState memory market, int256 netPtToAccount)
        public
        view
        returns (int256, int256, int256)
    {
        return MarketMathCore.executeTradeCore(market, ONE, netPtToAccount, block.timestamp);
    }

    /// @notice Note: Return new market state
    function _setNewMarketStateTrade(
        MarketState memory market,
        MarketPreCompute memory comp,
        int256 netPtToAccount,
        int256 netSyToAccount,
        int256 netSyToReserve
    ) public view returns (MarketState memory) {
        MarketMathCore._setNewMarketStateTrade(
            market, comp, ONE, netPtToAccount, netSyToAccount, netSyToReserve, block.timestamp
        );
        return market;
    }

    function _logProportion(int256 proportion) public pure returns (int256) {
        return MarketMathCore._logProportion(proportion);
    }

    function _getRateScalar(MarketState memory market, uint256 timeToExpiry) public pure returns (int256) {
        return MarketMathCore._getRateScalar(market, timeToExpiry);
    }

    function _getExchangeRateFromImpliedRate(uint256 lnImpliedRate, uint256 timeToExpiry)
        public
        pure
        returns (int256)
    {
        return MarketMathCore._getExchangeRateFromImpliedRate(lnImpliedRate, timeToExpiry);
    }

    function _getRateAnchor(
        int256 totalPt,
        uint256 lastLnImpliedRate,
        int256 totalAsset,
        int256 rateScalar,
        uint256 timeToExpiry
    ) public pure returns (int256) {
        return MarketMathCore._getRateAnchor(totalPt, lastLnImpliedRate, totalAsset, rateScalar, timeToExpiry);
    }

    function _getExchangeRate(
        int256 totalPt,
        int256 totalAsset,
        int256 rateScalar,
        int256 rateAnchor,
        int256 netPtToAccount
    ) public pure returns (int256) {
        return MarketMathCore._getExchangeRate(totalPt, totalAsset, rateScalar, rateAnchor, netPtToAccount);
    }

    function _getLnImpliedRate(
        int256 totalPt,
        int256 totalAsset,
        int256 rateScalar,
        int256 rateAnchor,
        uint256 timeToExpiry
    ) public pure returns (uint256) {
        return MarketMathCore._getLnImpliedRate(totalPt, totalAsset, rateScalar, rateAnchor, timeToExpiry);
    }

    /// @dev Compute the new market state after initial adding liquidity
    /// @dev Returns the new market state
    /// @param market market state
    /// @param initialAnchor initial anchor
    function setInitialLnImpliedRate(MarketState memory market, int256 initialAnchor)
        public
        view
        returns (MarketState memory)
    {
        MarketMathCore.setInitialLnImpliedRate(market, ONE, initialAnchor, block.timestamp);
        return market;
    }
}
