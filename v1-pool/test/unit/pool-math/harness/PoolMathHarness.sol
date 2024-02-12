// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {PoolMath, PoolState, PoolPreCompute} from "src/libs/PoolMath.sol";

contract PoolMathHarness {
    function swapExactBaseLpTokenForUnderlying(PoolState memory pool, uint256 exactBaseLptInTimesN)
        public
        view
        returns (uint256 underlyingOut18, uint256 swapFee18, uint256 protocolFee18)
    {
        (underlyingOut18, swapFee18, protocolFee18) =
            PoolMath.swapExactBaseLpTokenForUnderlying(pool, exactBaseLptInTimesN);
    }

    function swapUnderlyingForExactBaseLpToken(PoolState memory pool, uint256 exactBaseLptOutTimesN)
        public
        view
        returns (uint256 underlyingIn18, uint256 swapFee18, uint256 protocolFee18)
    {
        (underlyingIn18, swapFee18, protocolFee18) =
            PoolMath.swapUnderlyingForExactBaseLpToken(pool, exactBaseLptOutTimesN);
    }

    function computeAmmParameters(PoolState memory pool) public view returns (PoolPreCompute memory) {
        return PoolMath.computeAmmParameters(pool);
    }

    function executeSwap(PoolState memory pool, int256 netBaseLptToAccount)
        public
        view
        returns (int256, int256, int256)
    {
        return PoolMath.executeSwap(pool, netBaseLptToAccount);
    }

    function _setPostPoolState(
        PoolState memory pool,
        PoolPreCompute memory comp,
        int256 netBaseLptToAccount,
        int256 netUnderlyingToAccount,
        int256 netUnderlyingToProtocol
    ) public view returns (PoolState memory) {
        PoolMath._setPostPoolState(pool, comp, netBaseLptToAccount, netUnderlyingToAccount, netUnderlyingToProtocol);
        return pool;
    }

    function _logProportion(uint256 proportion) public pure returns (int256) {
        return PoolMath._logProportion(proportion);
    }

    function _getRateScalar(PoolState memory market, uint256 timeToExpiry) public pure returns (int256) {
        return PoolMath._getRateScalar(market, timeToExpiry);
    }

    function _getExchangeRateFromImpliedRate(uint256 lnImpliedRate, uint256 timeToExpiry)
        public
        pure
        returns (int256)
    {
        return PoolMath._getExchangeRateFromImpliedRate(lnImpliedRate, timeToExpiry);
    }

    function _getRateAnchor(
        uint256 totalPt,
        uint256 lastLnImpliedRate,
        uint256 totalAsset,
        int256 rateScalar,
        uint256 timeToExpiry
    ) public pure returns (int256) {
        return PoolMath._getRateAnchor(totalPt, lastLnImpliedRate, totalAsset, rateScalar, timeToExpiry);
    }

    function _getExchangeRate(
        uint256 totalPt,
        uint256 totalAsset,
        int256 rateScalar,
        int256 rateAnchor,
        int256 netPtToAccount
    ) public pure returns (uint256) {
        return PoolMath._getExchangeRate(totalPt, totalAsset, rateScalar, rateAnchor, netPtToAccount);
    }

    function _getLnImpliedRate(
        uint256 totalPt,
        uint256 totalAsset,
        int256 rateScalar,
        int256 rateAnchor,
        uint256 timeToExpiry
    ) public pure returns (uint256) {
        return PoolMath._getLnImpliedRate(totalPt, totalAsset, rateScalar, rateAnchor, timeToExpiry);
    }

    function computeInitialLnImpliedRate(PoolState memory pool, int256 initialAnchor) public view returns (uint256) {
        return PoolMath.computeInitialLnImpliedRate(pool, initialAnchor);
    }
}
