// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {ApproximationBaseTest} from "../../shared/Approximation.t.sol";

import {LibApproximation} from "src/lens/LibApproximation.sol";

import {ApproxParams} from "src/lens/ApproxParams.sol";
import {PoolState, PoolPreCompute} from "src/libs/PoolMath.sol";

import {Math} from "@openzeppelin/contracts@4.9.3/utils/math/Math.sol";
import {Errors} from "src/libs/Errors.sol";

// Alias
function getApproxParams(uint256 guessMin, uint256 guessMax) pure returns (ApproxParams memory) {
    return ApproxParams({
        guessMin: guessMin,
        guessMax: guessMax,
        maxIteration: 10_000,
        eps: 0.0001 * 1e18 // 0.01% relative error tolerance
    });
}

contract BisectionMethodUnitTest is Test {
    /// @dev This test is to assert that the bisection method is working as expected.
    /// @dev Find the square root of A using bisection method.
    function test_bisect_sqrt(uint256 A) public {
        uint256 guessMax = 10000 * 1e18;
        ApproxParams memory approx = getApproxParams(0, guessMax);

        vm.assume(A < guessMax && A > 1e18);

        uint256 sqrtA = LibApproximation.bisect("", _sqrt_variation_func, A, approx);
        assertApproxEqRel(sqrtA * sqrtA, A, approx.eps, "should be equal to A");
        assertApproxEqRel(sqrtA, Math.sqrt(A), approx.eps, "should be equal to Openzeppelin sqrt(A)");
    }

    /// @dev This computes relative error (in 18 decimals) between A and sqrt(A) * sqrt(A).
    /// (v - v_approx) / v = (A - sqrt(A) * sqrt(A)) / A
    function _sqrt_variation_func(uint256 sqrt, bytes memory, uint256 A) public pure returns (int256) {
        return (int256(A) - int256(sqrt * sqrt)) * 1e18 / int256(A); // relative error in 18 decimals
    }
}

contract ApproxSwapExactUnderlyingForBaseLpTokenUnitTest is ApproximationBaseTest {
    function test_approximation(uint256 guessMax) public virtual {
        uint256 exactUnderlying = 10 * ONE_UNDERLYING;
        ApproxParams memory approx = getApproxParams({guessMin: 0, guessMax: bound(guessMax, 60 * 1e18, 1e18 * 100000)});
        // estimate ptOut from exactUnderlying using approximation
        uint256 estimated = LibApproximation.approxSwapExactUnderlyingForBaseLpt(
            pool.readState(), // read state from pool
            exactUnderlying * 1e18 / ONE_UNDERLYING, // convert to 18 decimals
            approx
        );
        uint256 ptOutDesired = tricrypto.calc_withdraw_one_coin(estimated, 0);
        // execution
        uint256 underlyingIn = router.swapUnderlyingForPt({
            pool: address(pool),
            index: 0,
            ptOutDesired: ptOutDesired,
            underlyingInMax: exactUnderlying, // should be less than `exactUnderlying`
            recipient: address(0xbabe),
            deadline: block.timestamp
        });
        // Note: 10x error tolerance instead of 0.1% because of Tricrypto approximation precision loss
        assertApproxEqRel(underlyingIn, exactUnderlying, approx.eps * 10, "should be approx equal to exactUnderlying");
    }

    function test_RevertIf_InvaldParams() public override {
        PoolState memory state = pool.readState();
        // guessMin is larger than guessMax
        ApproxParams memory approx = getApproxParams({guessMin: 100 * 1e18, guessMax: 60 * 1e18});
        vm.expectRevert(Errors.ApproxBinarySearchInputInvalid.selector);
        LibApproximation.approxSwapExactUnderlyingForBaseLpt(state, 10 * 1e18, approx);
    }

    function test_RevertIf_NotConverged() public override {
        PoolState memory state = pool.readState();
        // guessMin is out of range
        ApproxParams memory approx = getApproxParams({guessMin: 40 * 1e18, guessMax: 80 * 1e18});
        vm.expectRevert(Errors.ApproxFail.selector);
        LibApproximation.approxSwapExactUnderlyingForBaseLpt(state, 10 * 1e18, approx);
    }
}

contract ApproxSwapBaseLpTokenForExactUnderlyingUnitTest is ApproximationBaseTest {
    function test_approximation(uint256 guessMax) public virtual {
        uint256 exactUnderlying = 10 * ONE_UNDERLYING;
        ApproxParams memory approx = ApproxParams({
            guessMin: 0, // initial a
            guessMax: bound(guessMax, 60 * 1e18, 1e18 * 100000), // initial b
            maxIteration: 1_000,
            eps: 0.001 * 1e18 // 0.1% relative error tolerance
        });
        // estimate
        uint256 estimated = LibApproximation.approxSwapBaseLptForExactUnderlying(
            pool.readState(),
            exactUnderlying * 1e18 / ONE_UNDERLYING, // convert to 18 decimals
            approx
        );
        uint256 ptInDesired = tricrypto.calc_withdraw_one_coin(estimated, 0);
        // execution
        uint256 underlyingOut = router.swapPtForUnderlying({
            pool: address(pool),
            index: 0,
            ptInDesired: ptInDesired,
            underlyingOutMin: 0,
            recipient: address(0xbabe),
            deadline: block.timestamp
        });
        // 10x error tolerance because of Tricrypto approximation precision loss
        assertApproxEqRel(underlyingOut, exactUnderlying, approx.eps * 10, "should be approx equal to exactUnderlying");
    }

    function test_RevertIf_InvaldParams() public override {
        PoolState memory state = pool.readState();
        // guessMin is larger than guessMax
        ApproxParams memory approx = getApproxParams({guessMin: 100 * 1e18, guessMax: 60 * 1e18});
        vm.expectRevert(Errors.ApproxBinarySearchInputInvalid.selector);
        LibApproximation.approxSwapBaseLptForExactUnderlying(state, 10 * 1e18, approx);
    }

    function test_RevertIf_NotConverged() public override {
        PoolState memory state = pool.readState();
        // guessMin is out of range
        ApproxParams memory approx = getApproxParams({guessMin: 40 * 1e18, guessMax: 80 * 1e18});
        vm.expectRevert(Errors.ApproxFail.selector);
        LibApproximation.approxSwapBaseLptForExactUnderlying(state, 10 * 1e18, approx);
    }
}

contract ApproxBaseLptToAddLiquidityOneUnderlyingUnitTest is ApproximationBaseTest {
    function test_approximation() public {
        // See Quoter.t.sol for this test
    }

    function test_RevertIf_InvaldParams() public override {
        PoolState memory state = pool.readState();
        // guessMin is larger than guessMax
        ApproxParams memory approx = getApproxParams({guessMin: 100 * 1e18, guessMax: 60 * 1e18});
        vm.expectRevert(Errors.ApproxBinarySearchInputInvalid.selector);
        LibApproximation.approxBaseLptToAddLiquidityOneUnderlying(state, 10 * 1e18, approx);
    }

    function test_RevertIf_NotConverged() public override {
        PoolState memory state = pool.readState();
        // guessMin is out of range
        ApproxParams memory approx = getApproxParams({guessMin: 40 * 1e18, guessMax: 80 * 1e18});
        vm.expectRevert(Errors.ApproxFail.selector);
        LibApproximation.approxBaseLptToAddLiquidityOneUnderlying(state, 10 * 1e18, approx);
    }
}

contract ApproxBaseLptToAddLiquidityOnePtUnitTest is ApproximationBaseTest {
    function test_approximation() public {
        // See Quoter.t.sol for this test
    }

    function test_RevertIf_InvaldParams() public override {
        PoolState memory state = pool.readState();
        // guessMin is larger than guessMax
        ApproxParams memory approx = getApproxParams({guessMin: 100 * 1e18, guessMax: 60 * 1e18});
        vm.expectRevert(Errors.ApproxBinarySearchInputInvalid.selector);
        LibApproximation.approxBaseLptToAddLiquidityOnePt(state, 10 * 1e18, approx);
    }

    function test_RevertIf_NotConverged() public override {
        PoolState memory state = pool.readState();
        // guessMin is out of range
        ApproxParams memory approx = getApproxParams({guessMin: 40 * 1e18, guessMax: 80 * 1e18});
        vm.expectRevert(Errors.ApproxFail.selector);
        LibApproximation.approxBaseLptToAddLiquidityOnePt(state, 10 * 1e18, approx);
    }
}
