// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Base} from "../../Base.t.sol";

import {PoolMath} from "src/libs/PoolMath.sol";
import {PoolMathHarness, PoolState, PoolPreCompute} from "./harness/PoolMathHarness.sol";
import {SafeCast} from "@openzeppelin/contracts@4.9.3/utils/math/SafeCast.sol";
import {Errors} from "src/libs/Errors.sol";

import {MarketMathWrapper, MarketState, MarketPreCompute, Errors as RefErrors} from "./harness/MarketMathWrapper.sol";

/// @notice Differential fuzz testing is used to test the correctness of the PoolMath library
/// @notice The reference implementation is MarketMathWrapper which is a wrapper of MarketMathCore (from Pendle finance)
contract PoolMathDifferentialTest is Base {
    using Cast for *;
    using SafeCast for uint256;
    using SafeCast for int256;

    MarketMathWrapper ref;
    PoolMathHarness pmath;

    function setUp() public {
        vm.warp(365 days);

        ref = new MarketMathWrapper(); // reference implementation of market math
        pmath = new PoolMathHarness();

        vm.label(address(ref), "ref_math");
        vm.label(address(pmath), "pmath");
    }

    /// @dev 18 decimal places
    /// @dev This function is used to bound the input of the fuzz test
    /// @dev expiry should be in the range (now, now + 2 years]
    modifier boundPoolStateInput(PoolState memory state) {
        state.totalBaseLptTimesN = bound(state.totalBaseLptTimesN, 1e-6 * 1e18, 1e10 * 1e18);
        state.totalUnderlying18 = bound(state.totalBaseLptTimesN, 1e-6 * 1e18, 1e10 * 1e18);
        // now < expiry < now + 2 years
        // swap can only happen before expiry but library itself doesn't check this condition
        state.maturity = bound(state.maturity, block.timestamp + 1, block.timestamp + 2 * 365 days);
        state.scalarRoot = bound(state.scalarRoot, 1e18, 5000 * 1e18);
        state.lnFeeRateRoot = bound(state.lnFeeRateRoot, 0.000_99 * 1e18, 0.001 * 1e18);
        state.protocolFeePercent = bound(state.protocolFeePercent, 0, 80);
        state.lastLnImpliedRate = bound(state.lastLnImpliedRate, 0.01 * 1e18, 0.6 * 1e18);
        _;
    }

    /// forge-config: default.fuzz.runs = 10000
    /// @dev Proportion too high Error is not applicable to underlying -> pt swap
    /// So, we only test pt -> underlying swap
    function testFuzz_RevertIf_BaseLpTokenProportionTooHigh(PoolState memory state, uint256 exactBaseLptIn)
        public
        virtual
        boundPoolStateInput(state)
    {
        // Note: Bound exactBaseLptIn to be maximum 1/3 of totalBaseLptTimesN
        // because in PoolMath, the input is internally multiplied by 3 to adjust the BaseLp token value. See `PoolMath` for more details.
        // On the other hand, in MarketMath, the input is used directly.
        // We multiply the input by 3 prior to calling to make sure that the input to compute swap is exactly the same in both libraries.
        exactBaseLptIn = bound(exactBaseLptIn, 0, state.totalBaseLptTimesN / N_COINS);
        try ref.swapExactPtForSy(state.toMarket(), exactBaseLptIn * N_COINS) {
            vm.assume(false);
        } catch (bytes memory reason) {
            vm.assume(bytes4(reason) == RefErrors.MarketProportionTooHigh.selector);
        }
        try pmath.swapExactBaseLpTokenForUnderlying(state, exactBaseLptIn) {
            revert("Should revert with PoolProportionTooHigh");
        } catch (bytes memory reason) {
            assertEq(bytes4(reason), Errors.PoolProportionTooHigh.selector, "Should revert with PoolProportionTooHigh");
        }
    }

    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_RevertIf_EffectiveExchangeRateBelowOne(PoolState memory state, uint256 exactBaseLptOut)
        public
        virtual
        boundPoolStateInput(state)
    {
        exactBaseLptOut = bound(exactBaseLptOut, 0, state.totalBaseLptTimesN / N_COINS);
        try ref.swapSyForExactPt(state.toMarket(), exactBaseLptOut * N_COINS) {
            vm.assume(false);
        } catch (bytes memory reason) {
            vm.assume(bytes4(reason) == RefErrors.MarketExchangeRateBelowOne.selector);
        }
        try pmath.swapUnderlyingForExactBaseLpToken(state, exactBaseLptOut) {
            revert("Should revert with PoolProportionTooHigh");
        } catch (bytes memory reason) {
            // Ignore the error args because it's hard to compute the exchange rate.
            assertEq(
                bytes4(reason), Errors.PoolExchangeRateBelowOne.selector, "Should revert with PoolProportionTooHigh"
            );
        }
    }

    /// forge-config: default.fuzz.runs = 10000
    /// @param proportion 0 <= proportion <= 1e18 - 1
    function testFuzz_logProportion(uint256 proportion) public {
        proportion = bound(proportion, 100_000, 1e18 - 1);
        int256 refLog = ref._logProportion(proportion.toInt256());
        int256 log = pmath._logProportion(proportion);
        assertApproxEqAbs(refLog, log, 100, "log should be equal");
    }

    function test_RevertIf_ProportionZero_logProportion() public {
        uint256 proportion = 1e18;
        vm.expectRevert(RefErrors.MarketProportionMustNotEqualOne.selector);
        ref._logProportion(proportion.toInt256());
        vm.expectRevert(Errors.PoolProportionMustNotEqualOne.selector);
        pmath._logProportion(proportion);
    }

    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_RevertIf_RateScalarZero_getRateScalar(PoolState memory state) public boundPoolStateInput(state) {
        state.scalarRoot = bound(state.scalarRoot, 0, 1e6); // intentionally set scalarRoot to be small
        uint256 timeToExpiry = state.maturity - block.timestamp;
        try ref._getRateScalar(state.toMarket(), timeToExpiry) {
            vm.assume(false);
        } catch (bytes memory reason) {
            vm.assume(bytes4(reason) == RefErrors.MarketRateScalarBelowZero.selector);
            vm.expectRevert(Errors.PoolRateScalarZero.selector);
            pmath._getRateScalar(state, timeToExpiry);
        }
    }

    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_getRateScalar(PoolState memory state) public boundPoolStateInput(state) {
        uint256 timeToExpiry = state.maturity - block.timestamp;
        try ref._getRateScalar(state.toMarket(), timeToExpiry) returns (int256 expectedRateScalar) {
            int256 rateScalar = pmath._getRateScalar(state, timeToExpiry);
            assertEq(expectedRateScalar, rateScalar, "rate scalar should be equal");
        } catch {
            vm.assume(false);
        }
    }

    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_getExchangeRateFromImpliedRate(uint256 lnImpliedRate, uint256 timeToExpiry) public {
        lnImpliedRate = bound(lnImpliedRate, 0.001 * 1e18, 0.9 * 1e18);
        timeToExpiry = bound(timeToExpiry, 1, 10 * 365 days); // Exclude expiry = 0 because swap can only happen before expiry
        (bool s1, bytes memory ret) =
            address(ref).staticcall(abi.encodeCall(ref._getExchangeRateFromImpliedRate, (lnImpliedRate, timeToExpiry)));
        vm.assume(s1);
        int256 expectedExchangeRate = abi.decode(ret, (int256));
        // execution
        int256 exchangeRate = pmath._getExchangeRateFromImpliedRate(lnImpliedRate, timeToExpiry);
        // Note: The error in absolute terms get large. This is because:
        // 1) error on exponenial function
        // 2) multiplying by timeToExpiry increases the error
        assertApproxEqAbs(expectedExchangeRate, exchangeRate, 100_000, "exchange rate from IR should be equal (abs)");
        assertApproxEqRel(
            expectedExchangeRate, exchangeRate, 0.000_000_000_1 * 1e18, "exchange rate from IR should be equal (rel)"
        );
    }

    function testFuzz_ExchangeRate_ShouldBe_NonZero_getExchangeRateFromImpliedRate(
        uint256 lnImpliedRate,
        uint256 timeToExpiry
    ) public {
        lnImpliedRate = bound(lnImpliedRate, 0, 1e5); // intentionally set small lnImpliedRate
        timeToExpiry = bound(timeToExpiry, 1, 1 days); // Exclude expiry = 0 because swap can only happen before expiry
        int256 exchangeRate = pmath._getExchangeRateFromImpliedRate(lnImpliedRate, timeToExpiry);
        assertGt(exchangeRate, 0, "exchange rate should be greater than 0");
    }

    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_getRateAnchor(PoolState memory state) public boundPoolStateInput(state) {
        uint256 timeToExpiry = state.maturity - block.timestamp;

        int256 expectedRateAnchor;
        MarketState memory market = state.toMarket();
        try ref._getRateAnchor(
            market.totalPt,
            market.lastLnImpliedRate,
            market.totalSy,
            market.scalarRoot, // rateScalar
            timeToExpiry
        ) returns (int256 ret) {
            expectedRateAnchor = ret;
        } catch {
            vm.assume(false);
        }
        int256 rateAnchor = pmath._getRateAnchor(
            state.totalBaseLptTimesN,
            state.lastLnImpliedRate,
            state.totalUnderlying18,
            state.scalarRoot.toInt256(), // rateScalar
            timeToExpiry
        );
        assertApproxEqAbs(expectedRateAnchor, rateAnchor, 5, "rate scalar should be approximately equal");
    }

    /// @dev See testFuzz_ExchangeRate_ShouldBe_NonZero_getExchangeRateFromImpliedRate
    function testFuzz_RevertIf_ExchangeRateBelowOne_getRateAnchor(PoolState memory state)
        public
        boundPoolStateInput(state)
    {
        // It is very unlikely to happen because exchange rate from implied rate is computed as:
        // `exchangeRate = exp(lnImpliedRate * rateScalar)`
        // where
        // `lnImpliedRate` would be bounded by 0.00001 * 1e18 and 1 * 1e18
        // `timeToExpiry` would be greater than 0 (swap can only happen before expiry)
        // Therefore, the input to exp function would be bounded by 0.00001 * 1e18 and 1 * 1e18
        // which doesn't result in exchangeRate below 1e18.

        state.lastLnImpliedRate = bound(state.lastLnImpliedRate, 0, 1e7); // intentionally set lastLnImpliedRate to be small
        uint256 timeToExpiry = 1; // intentionally set timeToExpiry to 0

        vm.expectRevert();
        pmath._getRateAnchor(
            state.totalBaseLptTimesN,
            state.lastLnImpliedRate,
            state.totalUnderlying18,
            state.scalarRoot.toInt256(), // rateScalar
            timeToExpiry
        );
    }

    /// forge-config: default.fuzz.runs = 10000
    /// @param rateAnchor around 0.001 * 1e18 to 10 * 1e18
    /// @param netBaseLptToAccount range from -totalBaseLptTimesN to totalBaseLptTimesN
    function testFuzz_getExchangeRate(PoolState memory state, int256 rateAnchor, int256 netBaseLptToAccount)
        public
        boundPoolStateInput(state)
    {
        netBaseLptToAccount =
            bound(netBaseLptToAccount, -state.totalBaseLptTimesN.toInt256(), state.totalBaseLptTimesN.toInt256());
        rateAnchor = bound(rateAnchor, 0.001 * 1e18, 10 * 1e18);

        MarketState memory market = state.toMarket();
        uint256 expectedExchangeRate;

        try ref._getExchangeRate(
            market.totalPt,
            market.totalSy,
            market.scalarRoot, // rateScalar
            rateAnchor,
            netBaseLptToAccount
        ) returns (int256 ret) {
            expectedExchangeRate = ret.toUint256();
        } catch {
            vm.assume(false);
        }
        uint256 exchangeRate = pmath._getExchangeRate(
            state.totalBaseLptTimesN,
            state.totalUnderlying18,
            state.scalarRoot.toInt256(), // rateScalar
            rateAnchor,
            netBaseLptToAccount
        );
        assertApproxEqAbs(expectedExchangeRate, exchangeRate, 1000, "exchange rate should be approximately equal");
    }

    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_getLnImpliedRate(PoolState memory state, int256 rateAnchor) public boundPoolStateInput(state) {
        rateAnchor = bound(rateAnchor, 0.001 * 1e18, 10 * 1e18);
        uint256 timeToExpiry = state.maturity - block.timestamp;

        MarketState memory market = state.toMarket();
        uint256 expectedLnImpliedRate;
        try ref._getLnImpliedRate(
            market.totalPt,
            market.totalSy,
            market.scalarRoot, // rateScalar
            rateAnchor,
            timeToExpiry
        ) returns (uint256 ret) {
            expectedLnImpliedRate = ret;
        } catch {
            vm.assume(false);
        }
        uint256 lnIR = pmath._getLnImpliedRate(
            state.totalBaseLptTimesN,
            state.totalUnderlying18,
            state.scalarRoot.toInt256(), // rateScalar
            rateAnchor,
            timeToExpiry
        );
        assertApproxEqRel(
            expectedLnImpliedRate, lnIR, 0.000_000_000_1 * 1e18, "Log(implied rate) should be approximately equal"
        );
    }

    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_LnImpliedRate_ExtRate(PoolState memory state, int256 rateAnchor)
        public
        boundPoolStateInput(state)
    {
        rateAnchor = bound(rateAnchor, 0.001 * 1e18, 10 * 1e18);
        uint256 timeToExpiry = state.maturity - block.timestamp;
        // path 1: get extRate directly
        (bool s, bytes memory ret) = address(pmath).staticcall(
            abi.encodeCall(
                pmath._getExchangeRate,
                (
                    state.totalBaseLptTimesN,
                    state.totalUnderlying18,
                    state.scalarRoot.toInt256(), // rateScalar
                    rateAnchor,
                    0
                )
            )
        );
        vm.assume(s);
        uint256 expected = abi.decode(ret, (uint256));

        // path 2: lnIR -> extRate
        uint256 lnIr = pmath._getLnImpliedRate(
            state.totalBaseLptTimesN,
            state.totalUnderlying18,
            state.scalarRoot.toInt256(), // rateScalar
            rateAnchor,
            timeToExpiry
        );
        uint256 extRate = pmath._getExchangeRateFromImpliedRate(lnIr, timeToExpiry).toUint256();
        assertApproxEqAbs(extRate, expected, 10_000, "extRate should be approx equal");
    }

    /// forge-config: default.fuzz.runs = 15000
    function testFuzz_computeAmmParameters(PoolState memory state) public boundPoolStateInput(state) {
        (bool s1, bytes memory ret) =
            address(ref).staticcall(abi.encodeCall(ref.getMarketPreCompute, (state.toMarket())));
        vm.assume(s1);
        MarketPreCompute memory expected = abi.decode(ret, (MarketPreCompute));

        PoolPreCompute memory cache = pmath.computeAmmParameters(state);
        assertEq(expected.rateScalar, cache.rateScalar, "rate scalar should be equal");
        assertApproxEqAbs(expected.rateAnchor, cache.rateAnchor, 5, "rate anchor should be equal");
        assertApproxEqAbs(expected.feeRate, cache.feeRate, 10, "fee rate should be equal");
    }

    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_RevertIf_InsufficientBaseLptForTrade(PoolState memory state, int256 netBaseLptToAccount)
        public
        virtual
        boundPoolStateInput(state)
    {
        try ref.executeTradeCore(state.toMarket(), netBaseLptToAccount) {
            vm.assume(false);
        } catch (bytes memory reason) {
            vm.assume(bytes4(reason) == RefErrors.MarketInsufficientPtForTrade.selector);
        }
        vm.expectRevert(Errors.PoolInsufficientBaseLptForTrade.selector);
        pmath.executeSwap(state, netBaseLptToAccount);
    }

    function testFuzz_RevertIf_InsufficientBaseLptForTrade_executeSwap(
        PoolState memory state,
        int256 netBaseLptToAccount
    ) public virtual boundPoolStateInput(state) {
        netBaseLptToAccount = bound(netBaseLptToAccount, state.totalBaseLptTimesN.toInt256(), type(int128).max);
        vm.expectRevert(Errors.PoolInsufficientBaseLptForTrade.selector);
        pmath.executeSwap(state, netBaseLptToAccount);
    }

    modifier boundPoolPreComputeFuzzInput(PoolPreCompute memory comp) {
        comp.rateScalar = bound(comp.rateScalar, 1e18, 5000 * 1e18);
        comp.rateAnchor = bound(comp.rateAnchor, 1e18, 5000 * 1e18);
        comp.feeRate = bound(comp.feeRate, 0.01 * 1e18, 0.6 * 1e18);
        _;
    }

    function testFuzz_RevertIf_LastLnImpliedRateZero_setPostPoolState(
        PoolState memory state,
        PoolPreCompute memory comp,
        int256 netBaseLptToAccount,
        int256 netUnderlyingToAccount,
        int256 netUnderlyingToProtocol
    ) public virtual boundPoolStateInput(state) boundPoolPreComputeFuzzInput(comp) {
        // @todo
        // it is very unlikely to happen.
    }

    /// forge-config: default.fuzz.runs = 150000
    function testFuzz_setPostPoolState(
        PoolState memory state,
        PoolPreCompute memory comp,
        int256 netBaseLptToAccount,
        int256 netUnderlyingToAccount,
        int256 netUnderlyingToProtocol
    ) public virtual boundPoolStateInput(state) boundPoolPreComputeFuzzInput(comp) {
        netBaseLptToAccount =
            bound(netBaseLptToAccount, -state.totalBaseLptTimesN.toInt256(), state.totalBaseLptTimesN.toInt256());
        netUnderlyingToAccount =
            bound(netUnderlyingToAccount, -state.totalUnderlying18.toInt256(), state.totalUnderlying18.toInt256());
        netUnderlyingToProtocol =
            bound(netUnderlyingToProtocol, 0, int256((stdMath.abs(netBaseLptToAccount) * 999) / 1000));

        (bool s1, bytes memory ret1) = address(ref).staticcall(
            abi.encodeCall(
                ref._setNewMarketStateTrade,
                (
                    state.toMarket(),
                    Cast.toMarketPreCompute({comp: comp, totalUnderlying18: state.totalUnderlying18}),
                    netBaseLptToAccount,
                    netUnderlyingToAccount,
                    netUnderlyingToProtocol
                )
            )
        );
        vm.assume(s1); // assume that the reference implementation doesn't revert
        MarketState memory newMarket = abi.decode(ret1, (MarketState));
        // Note: If the lastLnImpliedRate is too small, error on exponentiation results in a large error in absolute terms.
        // Therefore, we bound the lastLnImpliedRate to be greater than a certain value.
        // This seems to be reasonable range for lastLnImpliedRate.
        vm.assume(newMarket.lastLnImpliedRate > 1e15);
        // execution
        try pmath._setPostPoolState(state, comp, netBaseLptToAccount, netUnderlyingToAccount, netUnderlyingToProtocol)
        returns (PoolState memory stateAfter) {
            assertEq(stateAfter.totalBaseLptTimesN, newMarket.totalPt.toUint256(), "total base lpt should be equal");
            assertEq(stateAfter.totalUnderlying18, newMarket.totalSy.toUint256(), "total underlying should be equal");
            // Note: The error in absolute terms get large. This is because:
            // 1) error on exponenial function
            // 2) error on logarithmic function
            // 3) division by small timeToExpiry increases the error
            // See testFuzz_getLnImpliedRate for more details.
            assertApproxEqRel(
                stateAfter.lastLnImpliedRate,
                newMarket.lastLnImpliedRate,
                0.000_001 * 1e18,
                "lastLnIR should be approx equal"
            );
        } catch (bytes memory ret) {
            // Pendle MarketMath lib depends on LogExpMath lib, which has a bug in the `ln` function.
            // LogExpMath.ln(1e18 + some wei) returns 1, which is incorrect (should return 0).
            // In our case, PoolMath depends on PrbMath, which returns 0 for `ln(1e18 + some wei)`.
            // Therefore, when computing the ln of the exchange rate, the result can be totally different.
            // In our case, `lnImpliedRate` becomes 0, which reverts the function at the end.
            // Hence, we need to catch the revert here though it's unlikely to happen in real.
            assertEq(bytes4(ret), Errors.PoolZeroLnImpliedRate.selector, "Should revert with PoolZeroLnImpliedRate");
        }
    }

    /// forge-config: default.fuzz.runs = 20000
    /// @dev The following should be true:
    /// reference.swap({ptIn: baseLptIn * N_COINS}) == poolMath.swap({baseLptIn: baseLptIn})
    // The Principal Token in Pendle AMM corresponds to Base LP token in Napier.
    // The Base LP token is the LP token of a Curve Pool consisting of three PTs (Principal Tokens).
    // 1 Curve LP token is three times valuable than 1 PT.
    // Consequently, three times amount of PT is required to buy 1 underlying token in comparison to Pendle AMM.
    function testFuzz_swapExactBaseLptForUnderlying(PoolState memory state, uint256 exactBaseLptIn)
        public
        boundPoolStateInput(state)
    {
        state.totalBaseLptTimesN = bound(state.totalBaseLptTimesN, 1e18, 1e9 * 1e18);
        state.totalUnderlying18 = bound(state.totalUnderlying18, 1e18, 1e9 * 1e18);
        // Note Lower bound is 1e-3 * 1e18
        exactBaseLptIn = bound(
            exactBaseLptIn,
            1e15,
            // max amount of base LP token swapped in:
            // (baseLptReserve + 3 * d) / (underlyingReserve + d) < p
            // (n_d + 3 * d) / (n_d + n_u + 3 * d) < p
            // => n_d + 3 * d < p * (n_d + n_u + 3 * d)
            // => 3 * d < p/(1-p) * n_u - n_d
            // where n_d: totalBaseLptTimesN, n_u: totalUnderlying18, d: baseLptIn, p: maxPoolProportion
            (
                state.totalUnderlying18 * PoolMath.MAX_POOL_PROPORTION / (1e18 - PoolMath.MAX_POOL_PROPORTION)
                    - state.totalBaseLptTimesN
            ) / N_COINS
        );

        (bool s1, bytes memory ret) =
            address(ref).staticcall(abi.encodeCall(ref.swapExactPtForSy, (state.toMarket(), exactBaseLptIn * N_COINS)));
        vm.assume(s1);
        (uint256 syOut, uint256 swapFee, uint256 protocolFee) = abi.decode(ret, (uint256, uint256, uint256));

        try pmath.swapExactBaseLpTokenForUnderlying(state, exactBaseLptIn) returns (
            uint256 underlyingOut18, uint256 swapFee18, uint256 protocolFee18
        ) {
            // Note: If the amount is small, the error affects largely in absolute terms.
            // On the other hand, if the amount is large enough, the error can be ignored.
            assertApproxEqRel(underlyingOut18, syOut, 0.000_000_001 * 1e18, "asset to account should be equal [rel]");
            if (swapFee > 1e8) {
                assertApproxEqRel(swapFee18, swapFee, 0.000_001 * 1e18, "swap fee should be equal [rel]");
                assertApproxEqRel(protocolFee18, protocolFee, 0.000_001 * 1e18, "protocol fee should be equal [rel]");
            } else {
                assertApproxEqAbs(swapFee18, swapFee, 1_000, "swap fee should be equal [abs]");
                assertApproxEqAbs(protocolFee18, protocolFee, 1_000, "protocol fee should be equal [abs]");
            }
        } catch (bytes memory reason) {
            // should NOT revert
            revert(string(reason));
        }
    }

    /// forge-config: default.fuzz.runs = 20000
    /// @dev The following should be true:
    /// reference.swap({ptOut: baseLptOut * N_COINS}) == poolMath.swap({baseLptOut: baseLptOut})
    /// @dev See the comment in `testFuzz_swapExactBaseLptForUnderlying`
    function testFuzz_swapUnderlyingForExactBaseLpt(PoolState memory state, uint256 exactBaseLptOut)
        public
        virtual
        boundPoolStateInput(state)
    {
        state.totalBaseLptTimesN = bound(state.totalBaseLptTimesN, 1e18, 1e9 * 1e18);
        state.totalUnderlying18 = bound(state.totalUnderlying18, 1e18, 1e9 * 1e18);
        // Note Lower bound is 1e-3 * 1e18
        exactBaseLptOut = bound(exactBaseLptOut, 1e15, state.totalBaseLptTimesN / N_COINS);

        (bool s1, bytes memory ret) =
            address(ref).staticcall(abi.encodeCall(ref.swapSyForExactPt, (state.toMarket(), exactBaseLptOut * N_COINS)));
        vm.assume(s1);
        (uint256 syIn, uint256 swapFee, uint256 protocolFee) = abi.decode(ret, (uint256, uint256, uint256));

        try pmath.swapUnderlyingForExactBaseLpToken(state, exactBaseLptOut) returns (
            uint256 underlyingIn18, uint256 swapFee18, uint256 protocolFee18
        ) {
            assertApproxEqRel(underlyingIn18, syIn, 0.000_000_000_1 * 1e18, "asset to account should be equal [rel]");
            if (swapFee > 1e8) {
                assertApproxEqRel(swapFee18, swapFee, 0.000_001 * 1e18, "swap fee should be equal [rel]");
                assertApproxEqRel(protocolFee18, protocolFee, 0.000_001 * 1e18, "protocol fee should be equal [rel]");
            } else {
                assertApproxEqAbs(swapFee18, swapFee, 1_000, "swap fee should be equal [abs]");
                assertApproxEqAbs(protocolFee18, protocolFee, 1_000, "protocol fee should be equal [abs]");
            }
        } catch (bytes memory reason) {
            // should NOT revert
            revert(string(reason));
        }
    }

    function testFuzz_RevertIf_PoolExchangeRateBelowZero_swapUnderlyingForExactBaseLpt(
        PoolState memory state,
        uint256 exactBaseLptOut
    ) public virtual boundPoolStateInput(state) {
        exactBaseLptOut = bound(exactBaseLptOut, 0, state.totalBaseLptTimesN / N_COINS);
        (bool s1, bytes memory ret) =
            address(ref).staticcall(abi.encodeCall(ref.swapSyForExactPt, (state.toMarket(), exactBaseLptOut * N_COINS)));
        vm.assume(!s1 && bytes4(ret) == RefErrors.MarketExchangeRateBelowOne.selector);

        (bool s2, bytes memory ret2) =
            address(pmath).staticcall(abi.encodeCall(pmath.swapUnderlyingForExactBaseLpToken, (state, exactBaseLptOut)));
        assertFalse(s2, "Should revert");
        assertEq(bytes4(ret2), Errors.PoolExchangeRateBelowOne.selector, "Should revert with PoolExchangeRateBelowOne");
    }

    /// forge-config: default.fuzz.runs = 15000
    function testFuzz_computeInitialLnImpliedRate(PoolState memory state, int256 initialAnchor)
        public
        virtual
        boundPoolStateInput(state)
    {
        initialAnchor = bound(initialAnchor, 0.001 * 1e18, 10 * 1e18);

        uint256 expected;
        try ref.setInitialLnImpliedRate(state.toMarket(), initialAnchor) returns (MarketState memory newMarket) {
            expected = newMarket.lastLnImpliedRate;
        } catch {
            vm.assume(false);
        }

        try pmath.computeInitialLnImpliedRate(state, initialAnchor) returns (uint256 lnImpliedRate) {
            assertApproxEqRel(
                lnImpliedRate, expected, 0.000_000_000_1 * 1e18, "Log(implied rate) should be approximately equal"
            );
        } catch (bytes memory reason) {
            // should NOT revert
            revert(string(reason));
        }
    }
}

library Cast {
    using SafeCast for uint256;
    using SafeCast for int256;

    function toMarket(PoolState memory pool) internal pure returns (MarketState memory) {
        return MarketState({
            totalPt: pool.totalBaseLptTimesN.toInt256(),
            totalSy: pool.totalUnderlying18.toInt256(),
            totalLp: 0, // only used in addLiquidity and removeLiquidity functions on reference implementation. We don't have this variable in PoolState
            treasury: address(0), // we don't have this variable in PoolState
            scalarRoot: pool.scalarRoot.toInt256(),
            expiry: pool.maturity,
            lnFeeRateRoot: pool.lnFeeRateRoot,
            reserveFeePercent: pool.protocolFeePercent,
            lastLnImpliedRate: pool.lastLnImpliedRate
        });
    }

    function toMarketPreCompute(PoolPreCompute memory comp, uint256 totalUnderlying18)
        internal
        pure
        returns (MarketPreCompute memory)
    {
        return MarketPreCompute({
            rateScalar: comp.rateScalar,
            totalAsset: totalUnderlying18.toInt256(),
            rateAnchor: comp.rateAnchor,
            feeRate: comp.feeRate
        });
    }
}
