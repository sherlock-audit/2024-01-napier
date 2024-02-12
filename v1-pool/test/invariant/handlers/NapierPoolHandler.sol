// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {StdAssertions} from "forge-std/StdAssertions.sol";
import {console2} from "forge-std/console2.sol";
import {BaseHandler} from "@napier/napier-v1/test/invariant/handlers/BaseHandler.sol";
import {TimestampStore} from "@napier/napier-v1/test/invariant/TimestampStore.sol";
import {TricryptoStore} from "../TricryptoStore.sol";
import {NapierPoolStore} from "../NapierPoolStore.sol";

import {IERC20, ERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";
import {CurveTricryptoOptimizedWETH} from "src/interfaces/external/CurveTricryptoOptimizedWETH.sol";
import {IPoolFactory} from "src/interfaces/IPoolFactory.sol";
import {Ownable} from "@openzeppelin/contracts@4.9.3/access/Ownable.sol";
import {DecimalConversion} from "src/libs/DecimalConversion.sol";

import {NapierPool} from "src/NapierPool.sol";
import {CallbackInputType, AddLiquidityInput, SwapInput} from "../../shared/CallbackInputType.sol";
import {SwapEventsLib} from "../../helpers/SwapEventsLib.sol";
import {Errors} from "src/libs/Errors.sol";

import "src/libs/Constants.sol" as Constants;

contract NapierPoolHandler is BaseHandler, StdAssertions {
    using DecimalConversion for uint256;

    uint256 constant N_COINS = 3;
    NapierPool pool;
    IPoolFactory factory;
    CurveTricryptoOptimizedWETH tricrypto;
    IERC20 underlying;
    IERC20[3] principalTokens;
    NapierPoolStore napierPoolStore;
    TricryptoStore tricryptoStore;
    uint256 maturity;
    uint8 uDecimals;
    uint256 ONE_UNDERLYING;

    /// @dev Makes a previously provided recipient the source of the tokens.
    modifier useFuzzedSender(uint256 actorIndexSeed) {
        currentSender = napierPoolStore.getRecipient(actorIndexSeed);
        if (currentSender == address(0)) return;
        vm.startPrank(currentSender);
        _;
        vm.stopPrank();
    }

    /// @dev Makes a previously provided recipient of Tricrypto (Base pool) LP token the source of the tokens.
    modifier useFuzzedTricryptoSender(uint256 actorIndexSeed) {
        currentSender = tricryptoStore.getRecipient(actorIndexSeed);
        if (currentSender == address(0)) return;
        vm.startPrank(currentSender);
        _;
        vm.stopPrank();
    }

    modifier useOwner() {
        currentSender = Ownable(address(factory)).owner();
        vm.startPrank(currentSender);
        _;
        vm.stopPrank();
    }

    modifier recordLogs() {
        vm.recordLogs();
        _;
    }

    constructor(
        NapierPool _pool,
        NapierPoolStore _napierPoolStore,
        TricryptoStore _tricryptoStore,
        TimestampStore _timestampStore
    ) {
        pool = _pool;
        factory = pool.factory();
        underlying = pool.underlying();
        tricrypto = pool.tricrypto();
        principalTokens = pool.principalTokens();
        napierPoolStore = _napierPoolStore;
        tricryptoStore = _tricryptoStore;
        timestampStore = _timestampStore;
        maturity = pool.maturity();
        uDecimals = ERC20(address(underlying)).decimals();
        ONE_UNDERLYING = 10 ** ERC20(address(underlying)).decimals();
    }

    function isOverwritable(address addr) public view returns (bool) {
        // zero address and precompiles on all EVM-compatible chains.
        if (addr <= address(0x9)) return false;
        // vm and console addresses
        if (addr == address(vm) || addr == 0x000000000000000000636F6e736F6c652e6c6f67) return false;
        if (addr.code.length == 0) return true;
        (bool s, bytes memory isMock) = addr.staticcall(abi.encodeWithSignature("isMockCallbackReceiver()"));
        return s && abi.decode(isMock, (bool));
    }

    /// @dev setup mock callback receiver by overwriting code at address `to`
    function _deployMockCallbackReceiverTo(address to) internal {
        deployCodeTo("MockCallbackReceiver.sol", to);
        changePrank(factory.owner());
        factory.authorizeCallbackReceiver(to);
        changePrank(currentSender);
    }

    function addLiquidity(
        uint256 timeJumpSeed,
        uint256 senderSeed,
        uint256 underlyingIn,
        uint256 baseLptIn,
        address recipient
    )
        public
        useFuzzedTricryptoSender(senderSeed)
        checkActor(recipient)
        adjustTimestamp(timeJumpSeed)
        countCall("addLiquidity")
    {
        underlyingIn = _bound(underlyingIn, 0, 1_000_000 * ONE_UNDERLYING);
        baseLptIn = _bound(baseLptIn, 0, tricrypto.balanceOf(currentSender));

        // Initial deposit determines the ratio of the reserve in the pool.
        if (pool.totalSupply() == 0) {
            // Dev: Make sure the baseLP token is priced at less than 3 underlying tokens to avoid revert with `ExchangeRateBelowOne` error.
            // Set upper bound to 3 underlying tokens per baseLP token.
            // Dev: Make sure the proportion of the baseLP token reserve is not too high to avoid revert with `ProportionTooHigh` error.
            // Set lower bound so that the proportion of the baseLP token reserve is less than 90%.
            // Formula:
            // Proportion of baseLP token reserve = B * 3 / (B * 3 + U)
            // where `B` is the amount of baseLP token in the pool in 18 decimals
            // and `U` is the amount of underlying token in the pool in 18 decimals
            //
            // B * 3 / (B * 3 + U) < 0.9
            // 0.9 U > 3 B (1 - 0.9) = 0.3 B
            // U > 1/3 B
            underlyingIn = _bound(
                underlyingIn, baseLptIn.from18Decimals(uDecimals) / 3, N_COINS * baseLptIn.from18Decimals(uDecimals)
            );
        }
        if (underlyingIn == 0 || baseLptIn == 0) return;

        deal(address(underlying), currentSender, underlyingIn, false);

        if (!isOverwritable(currentSender)) return;
        _deployMockCallbackReceiverTo(currentSender);
        if (block.timestamp >= maturity) vm.expectRevert(Errors.PoolExpired.selector);
        pool.addLiquidity(
            underlyingIn,
            baseLptIn,
            recipient,
            abi.encode(
                CallbackInputType.AddLiquidity,
                AddLiquidityInput({underlying: IERC20(underlying), tricrypto: IERC20(tricrypto)})
            )
        );
        // add recipient to the list of recipients
        napierPoolStore.addRecipient(recipient);
    }

    function removeLiquidity(uint256 timeJumpSeed, uint256 senderSeed, uint256 liquidty, address recipient)
        public
        useFuzzedSender(senderSeed)
        checkActor(recipient)
        adjustTimestamp(timeJumpSeed)
        countCall("removeLiquidity")
    {
        liquidty = _bound(liquidty, 0, pool.balanceOf(currentSender));
        if (liquidty == 0) return;

        // transfer liquidity token to NapierPool and remove Liquidity.
        pool.transfer(address(pool), liquidty);
        pool.removeLiquidity(recipient);
    }

    function swapPtForUnderlying(address sender, uint256 timeJumpSeed, uint256 index, uint256 ptIn, address recipient)
        public
        useSender(sender)
        checkActor(recipient)
        adjustTimestamp(timeJumpSeed)
        countCall("swapPtForUnderlying")
        recordLogs
    {
        uint256 i = _bound(index, 0, N_COINS - 1);
        // Bound amount of principal token to swap
        // Cap at 1% of the balance in the tricrypto pool. Otherwise, the swap would revert in the tricrypto pool.
        ptIn = _bound(ptIn, 0, tricrypto.balances(i) * 1 / 100);
        if (ptIn == 0) return;

        deal(address(principalTokens[i]), currentSender, ptIn, false);

        if (!isOverwritable(currentSender)) return;
        _deployMockCallbackReceiverTo(currentSender);

        // Protocol fees not yet collected, including donation
        uint256 floatingUnderlying = underlying.balanceOf(address(pool)) - pool.totalUnderlying();

        if (block.timestamp >= maturity) vm.expectRevert(Errors.PoolExpired.selector);
        uint256 underlyingOut = pool.swapPtForUnderlying(
            i,
            ptIn,
            recipient,
            abi.encode(CallbackInputType.SwapPtForUnderlying, SwapInput(underlying, principalTokens[i]))
        );
        (uint256 swapFee, uint256 protocolFee) = SwapEventsLib.getFeesFromLastSwapEvent(pool);

        // NOTE: If the recipient is the pool itself, then the `underlyingOut` is included in `balanceOf`.
        uint256 expectedFloatingUnderlyingAfter = floatingUnderlying + protocolFee;
        if (recipient == address(pool)) {
            expectedFloatingUnderlyingAfter += underlyingOut;
        }
        uint256 floatingUnderlyingAfter = underlying.balanceOf(address(pool)) - pool.totalUnderlying();

        assertGe(
            floatingUnderlyingAfter,
            expectedFloatingUnderlyingAfter,
            "floating underlying should increase by protocol fee"
        );

        // add protocol fees to the store
        napierPoolStore.ghost_addProtocolFees(protocolFee);
        napierPoolStore.ghost_addSwapFees(swapFee);
    }

    function swapUnderlyingForPt(
        address sender,
        uint256 timeJumpSeed,
        uint256 index,
        uint256 ptOutDesired,
        address recipient
    )
        public
        useSender(sender)
        checkActor(recipient)
        adjustTimestamp(timeJumpSeed)
        countCall("swapUnderlyingForPt")
        recordLogs
    {
        uint256 i = _bound(index, 0, N_COINS - 1);
        // Bound amount of principal token to swap
        // Cap at 1% of the balance in the tricrypto pool. Otherwise, the swap would revert in the tricrypto pool.
        ptOutDesired = _bound(ptOutDesired, 0, tricrypto.balances(i) * 1 / 100);
        if (ptOutDesired == 0) return;

        uint256 underlyingAmount = type(uint128).max;
        deal(address(underlying), currentSender, underlyingAmount, false);

        if (!isOverwritable(currentSender)) return;
        _deployMockCallbackReceiverTo(currentSender);

        // Protocol fees not yet collected, including donation
        uint256 floatingUnderlying = underlying.balanceOf(address(pool)) - pool.totalUnderlying();

        if (block.timestamp >= maturity) vm.expectRevert(Errors.PoolExpired.selector);
        pool.swapUnderlyingForPt(
            i,
            ptOutDesired,
            recipient,
            abi.encode(CallbackInputType.SwapUnderlyingForPt, SwapInput(underlying, principalTokens[i]))
        );

        (uint256 swapFee, uint256 protocolFee) = SwapEventsLib.getFeesFromLastSwapEvent(pool);

        uint256 expectedFloatingUnderlyingAfter = floatingUnderlying + protocolFee;
        uint256 floatingUnderlyingAfter = underlying.balanceOf(address(pool)) - pool.totalUnderlying();

        assertGe(
            floatingUnderlyingAfter,
            expectedFloatingUnderlyingAfter,
            "floating underlying should increase by protocol fee"
        );

        // add protocol fees to the store
        napierPoolStore.ghost_addProtocolFees(protocolFee);
        napierPoolStore.ghost_addSwapFees(swapFee);
    }

    function swapBaseLptForUnderlying(uint256 senderSeed, uint256 timeJumpSeed, uint256 baseLptIn, address recipient)
        public
        useFuzzedTricryptoSender(senderSeed)
        checkActor(recipient)
        adjustTimestamp(timeJumpSeed)
        countCall("swapBaseLptForUnderlying")
        recordLogs
    {
        // Bound amount of baseLptoken to swap
        uint256 userBalance = tricrypto.balanceOf(currentSender);
        uint256 poolBalance = tricrypto.balanceOf(address(pool));
        uint256 maxAmount = userBalance < poolBalance ? userBalance : poolBalance;
        baseLptIn = _bound(baseLptIn, 0, maxAmount);
        if (baseLptIn == 0) return;

        tricrypto.approve(address(pool), baseLptIn);

        uint256 floatingUnderlying = underlying.balanceOf(address(pool)) - pool.totalUnderlying();

        if (block.timestamp >= maturity) vm.expectRevert(Errors.PoolExpired.selector);
        uint256 underlyingOut = pool.swapExactBaseLpTokenForUnderlying(baseLptIn, recipient);

        (uint256 swapFee, uint256 protocolFee) = SwapEventsLib.getFeesFromLastSwapEvent(pool);

        // NOTE: If the recipient is the pool itself, then the `underlyingOut` is included in `balanceOf`.
        uint256 expectedFloatingUnderlyingAfter = floatingUnderlying + protocolFee;
        if (recipient == address(pool)) {
            expectedFloatingUnderlyingAfter += underlyingOut;
        }
        uint256 floatingUnderlyingAfter = underlying.balanceOf(address(pool)) - pool.totalUnderlying();

        assertGe(
            floatingUnderlyingAfter,
            expectedFloatingUnderlyingAfter,
            "floating underlying should increase by protocol fee"
        );

        // add protocol fees to the store
        napierPoolStore.ghost_addProtocolFees(protocolFee);
        napierPoolStore.ghost_addSwapFees(swapFee);
    }

    function swapUnderlyingForBaseLpt(address sender, uint256 timeJumpSeed, uint256 baseLptOut, address recipient)
        public
        useSender(sender)
        checkActor(recipient)
        adjustTimestamp(timeJumpSeed)
        countCall("swapUnderlyingForBaseLpt")
        recordLogs
    {
        // Bound baseLptOut amount to less than reserve in pool.
        baseLptOut = _bound(baseLptOut, 0, tricrypto.balanceOf(address(pool)));
        if (baseLptOut == 0) return;

        // Approve underlying token to swap
        uint256 underlyingAmount = type(uint128).max;
        deal(address(underlying), currentSender, underlyingAmount, false);
        underlying.approve(address(pool), underlyingAmount);

        uint256 floatingUnderlying = underlying.balanceOf(address(pool)) - pool.totalUnderlying();

        if (block.timestamp >= maturity) vm.expectRevert(Errors.PoolExpired.selector);
        pool.swapUnderlyingForExactBaseLpToken(baseLptOut, recipient);

        (uint256 swapFee, uint256 protocolFee) = SwapEventsLib.getFeesFromLastSwapEvent(pool);

        uint256 expectedFloatingUnderlyingAfter = floatingUnderlying + protocolFee;
        uint256 floatingUnderlyingAfter = underlying.balanceOf(address(pool)) - pool.totalUnderlying();

        assertGe(
            floatingUnderlyingAfter,
            expectedFloatingUnderlyingAfter,
            "floating underlying should increase by protocol fee"
        );

        // add protocol fees to the store
        napierPoolStore.ghost_addProtocolFees(protocolFee);
        napierPoolStore.ghost_addSwapFees(swapFee);
    }

    function skim(address sender, uint256 timeJumpSeed)
        public
        useSender(sender)
        adjustTimestamp(timeJumpSeed)
        countCall("skim")
    {
        uint256 underlyingBefore = underlying.balanceOf(address(pool));
        uint256 baseLptBefore = tricrypto.balanceOf(address(pool));
        pool.skim();
        uint256 skimmedUnderlying = underlyingBefore - underlying.balanceOf(address(pool));
        uint256 skimmedBaseLpt = baseLptBefore - tricrypto.balanceOf(address(pool));
        // add skimmed amount to the store
        napierPoolStore.ghost_addSkimmedUnderlyings(skimmedUnderlying);
        napierPoolStore.ghost_addSkimmedBaseLpTokens(skimmedBaseLpt);
    }

    function setFeeParameter(uint256 paramSeed, uint256 newParamSeed) public useOwner countCall("setFeeParameter") {
        bytes32 paramName;
        uint256 value;
        if (paramSeed % 2 == 0) {
            paramName = "lnFeeRateRoot";
            value = _bound(newParamSeed, 0, Constants.MAX_LN_FEE_RATE_ROOT);
        } else {
            paramName = "protocolFeePercent";
            value = _bound(newParamSeed, 0, Constants.MAX_PROTOCOL_FEE_PERCENT);
        }
        pool.setFeeParameter(paramName, value);
    }

    function callSummary() public view override {
        console2.log("addLiquidity:", calls["addLiquidity"]);
        console2.log("removeLiquidity:", calls["removeLiquidity"]);
        console2.log("swapPtForUnderlying:", calls["swapPtForUnderlying"]);
        console2.log("swapUnderlyingForPt:", calls["swapUnderlyingForPt"]);
        console2.log("swapBaseLptForUnderlying:", calls["swapBaseLptForUnderlying"]);
        console2.log("swapUnderlyingForBaseLpt:", calls["swapUnderlyingForBaseLpt"]);
        console2.log("skim:", calls["skim"]);
        console2.log("setFeeParameter:", calls["setFeeParameter"]);
    }
}
