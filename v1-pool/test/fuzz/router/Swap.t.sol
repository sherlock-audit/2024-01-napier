// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {RouterSwapFuzzTest} from "../../shared/Swap.t.sol";
import {SwapEventsLib} from "../../helpers/SwapEventsLib.sol";

import {SafeCast} from "@openzeppelin/contracts@4.9.3/utils/math/SafeCast.sol";
import {Errors} from "src/libs/Errors.sol";

using SafeCast for uint256;

contract RouterSwapUnderlyingForPtFuzzTest is RouterSwapFuzzTest {
    address receiver = makeAddr("receiver");

    function testFuzz_routerSwapUnderlyingForPt(SwapFuzzInput memory swapInput, AmountFuzzInput memory ptDesired)
        public
        boundSwapFuzzInput(swapInput)
        whenMaturityNotPassed
        setUpRandomBasePoolReserves(swapInput.ptsToBasePool)
        boundPtDesired(swapInput, ptDesired)
    {
        uint256 index = swapInput.index;
        uint256 ptOutDesired = ptDesired.value;
        vm.warp(swapInput.timestamp);

        // give enough underlying to caller
        deal(address(underlying), address(this), 1e6 * ONE_UNDERLYING, false);
        // pre-condition
        uint256 preBaseLptSupply = tricrypto.totalSupply();
        // execute
        vm.recordLogs();
        uint256 underlyingIn = router.swapUnderlyingForPt(
            address(pool), index, ptOutDesired, 1e6 * ONE_UNDERLYING, receiver, block.timestamp
        );
        // assert 1
        assertApproxEqRel(
            pts[index].balanceOf(receiver),
            ptOutDesired,
            0.01 * 1e18,
            "receiver should receive appropriately amount of pt [rel 1%]"
        );
        // assert 2
        assertUnderlyingReserveAfterSwap({
            underlyingToAccount: -underlyingIn.toInt256(),
            protocolFeeIn: SwapEventsLib.getProtocolFeeFromLastSwapEvent(pool),
            preTotalUnderlying: preTotalUnderlying
        });
        // assert 3
        assertEq(
            pool.totalBaseLpt(),
            preTotalBaseLpt - (preBaseLptSupply - tricrypto.totalSupply()),
            "reserve should be decreased by baseLpt burned"
        );
        // assert 4
        assertReserveBalanceMatch();
    }
}

contract RouterSwapPtForUnderlyingFuzzTest is RouterSwapFuzzTest {
    address receiver = makeAddr("receiver");

    function testFuzz_routerSwapPtForUnderlying(SwapFuzzInput memory swapInput, AmountFuzzInput memory ptDesired)
        public
        boundSwapFuzzInput(swapInput)
        whenMaturityNotPassed
        setUpRandomBasePoolReserves(swapInput.ptsToBasePool)
        boundPtDesired(swapInput, ptDesired)
    {
        uint256 index = swapInput.index;
        uint256 ptInDesired = ptDesired.value;
        vm.warp(swapInput.timestamp);

        // give enough pt to caller
        deal(address(pts[swapInput.index]), address(this), ptDesired.value, false);

        // pre-condition
        uint256 preBaseLptSupply = tricrypto.totalSupply();
        uint256[3] memory amounts;
        amounts[index] = ptInDesired;
        uint256 expectedBaseLptIssued = tricrypto.calc_token_amount(amounts, true);

        // execute
        vm.recordLogs();
        uint256 underlyingOut =
            router.swapPtForUnderlying(address(pool), index, ptInDesired, 0, receiver, block.timestamp);

        // assert 1
        assertEq(underlying.balanceOf(receiver), underlyingOut, "receiver should receive underlying");
        // assert 2
        assertUnderlyingReserveAfterSwap({
            underlyingToAccount: underlyingOut.toInt256(),
            protocolFeeIn: SwapEventsLib.getProtocolFeeFromLastSwapEvent(pool),
            preTotalUnderlying: preTotalUnderlying
        });
        // assert 3
        assertReserveBalanceMatch();
        // assert 4
        assertApproxEqRel(
            expectedBaseLptIssued,
            (tricrypto.totalSupply() - preBaseLptSupply),
            0.01 * 1e18, // 1% tolerance
            "baseLpt minted is approximately equal to the expected amount"
        );
    }
}

contract RouterSwapYtForUnderlyingFuzzTest is RouterSwapFuzzTest {
    address receiver = makeAddr("receiver");

    uint256[3] pyBalances;

    function setUp() public override {
        super.setUp();
        // mint pt and yt
        address whale = makeAddr("whale");
        deal(address(underlying), whale, 3000 * ONE_UNDERLYING, true);
        for (uint256 i = 0; i < N_COINS; i++) {
            _approve(underlying, whale, address(pts[i]), type(uint256).max);
            vm.prank(whale);
            pyBalances[i] = pts[i].issue(address(this), 1000 * ONE_UNDERLYING);
            // approve router to spend yt
            _approve(yts[i], address(this), address(router), type(uint256).max);
        }
    }

    function testFuzz_routerSwapYtForUnderlying(SwapFuzzInput memory swapInput, uint256 ytDesired, uint256 cscale)
        public
        boundSwapFuzzInput(swapInput)
        setUpRandomBasePoolReserves(swapInput.ptsToBasePool)
        pushUpUnderlyingPrice(swapInput.ptsToBasePool)
    {
        uint256 index = swapInput.index;
        ytDesired = bound(ytDesired, ONE_UNDERLYING, 10 * ONE_UNDERLYING);
        vm.warp(swapInput.timestamp);
        uint256 scale = adapters[index].scale();
        cscale = bound(cscale, scale * 110 / 100, scale * 180 / 100); // if scale decreases, it will revert with `RouterInsufficientUnderlyingOut`
        // mock scale change
        vm.mockCall(
            address(adapters[index]), abi.encodeWithSelector(adapters[index].scale.selector), abi.encode(cscale)
        );
        // execution
        (bool s, bytes memory returndata) = address(router).call(
            abi.encodeCall(router.swapYtForUnderlying, (address(pool), index, ytDesired, 0, receiver, block.timestamp))
        );
        if (!s) {
            // if pt isn't traded at a great discount, the received underlying would be less than the amount of redeemed PT and YT.
            // In such siutaion, the router can't repay enough underlying to pool.
            // in this case, it revert with RouterInsufficientUnderlyingRepay
            if (bytes4(returndata) != Errors.RouterInsufficientUnderlyingRepay.selector) {
                revert(string(returndata));
            }
            vm.assume(false);
        }
        uint256 underlyingOut = abi.decode(returndata, (uint256));

        assertApproxEqRel(
            yts[index].balanceOf(address(this)),
            pyBalances[index] - 10 * ONE_UNDERLYING,
            0.05 * 1e18,
            "yt should be transferred from sender"
        );
        assertGe(underlyingOut, 0, "underlyingOut should be gt underlyingOutMin");
        assertEq(underlying.balanceOf(receiver), underlyingOut, "underlyingOut should be transferred to recipient");
        assertNoFundLeftInPoolSwapRouter();
        vm.clearMockedCalls();
    }
}

contract RouterSwapUnderlyingForYtFuzzTest is RouterSwapFuzzTest {
    address receiver = makeAddr("receiver");

    uint256 uBalance;

    function setUp() public override {
        super.setUp();

        uBalance = 3000 * ONE_UNDERLYING;
        deal(address(underlying), address(this), uBalance, false);
    }

    function testFuzz_routerSwapUnderlyingForYt(SwapFuzzInput memory swapInput, uint256 ytDesired, uint256 cscale)
        public
        boundSwapFuzzInput(swapInput)
        setUpRandomBasePoolReserves(swapInput.ptsToBasePool)
        pushUpUnderlyingPrice(swapInput.ptsToBasePool)
    {
        uint256 index = swapInput.index;
        // Note: if ytDesired value is much smaller, it can cause the precision loss/ rounding error. In that case, it can be reverted with `RouterInsufficientPtRepay`
        // To skip that case, bound range that is greater than ONE_UNDERLYING is much reasonable.
        ytDesired = bound(ytDesired, ONE_UNDERLYING, 10 * ONE_UNDERLYING);
        vm.warp(swapInput.timestamp);
        uint256 scale = adapters[index].scale();
        cscale = bound(cscale, scale * 90 / 100, scale * 180 / 100);
        // mock scale change
        vm.mockCall(
            address(adapters[index]), abi.encodeWithSelector(adapters[index].scale.selector), abi.encode(cscale)
        );
        // execution
        (bool s, bytes memory returndata) = address(router).call(
            abi.encodeCall(
                router.swapUnderlyingForYt,
                (address(pool), index, ytDesired, 15 * ONE_UNDERLYING, receiver, block.timestamp)
            )
        );
        if (!s) {
            // when pt price isn't discounted much enough, users don't need to pay underlying for yt, rather he can receive and yt and underlying.
            // In such situation, it is reverted with `RouterNonSituationSwapUnderlyingForYt`
            if (bytes4(returndata) != Errors.RouterNonSituationSwapUnderlyingForYt.selector) {
                revert(string(returndata));
            }
            vm.assume(false);
        }
        uint256 underlyingSpent = abi.decode(returndata, (uint256));

        assertApproxEqRel(
            yts[index].balanceOf(receiver), ytDesired, 0.05 * 1e18, "yt should be transferred to receiver"
        );
        assertEq(
            underlying.balanceOf(address(this)), uBalance - underlyingSpent, "underlyingIn should be spent from sender"
        );
        assertNoFundLeftInPoolSwapRouter();
        vm.clearMockedCalls();
    }
}
