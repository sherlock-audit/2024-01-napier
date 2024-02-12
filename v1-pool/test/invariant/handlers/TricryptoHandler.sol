// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import {BaseHandler} from "@napier/napier-v1/test/invariant/handlers/BaseHandler.sol";
import {TimestampStore} from "@napier/napier-v1/test/invariant/TimestampStore.sol";
import {TricryptoStore} from "../TricryptoStore.sol";

import {ERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";
import {CurveTricryptoOptimizedWETH} from "src/interfaces/external/CurveTricryptoOptimizedWETH.sol";
import {Tranche} from "@napier/napier-v1/src/Tranche.sol";

/// @dev This handler makes random pool states of Tricrypto to test Napier pool.
contract TricryptoHandler is BaseHandler {
    CurveTricryptoOptimizedWETH tricrypto;
    Tranche[3] pts;
    TricryptoStore tricryptoStore;
    uint256 ONE_UNDERLYING;

    /// @dev Makes a previously provided recipient the source of the tokens.
    modifier useFuzzedSender(uint256 actorIndexSeed) {
        currentSender = tricryptoStore.getRecipient(actorIndexSeed);
        if (currentSender == address(0)) return;
        vm.startPrank(currentSender);
        _;
        vm.stopPrank();
    }

    constructor(
        CurveTricryptoOptimizedWETH _tricrypto,
        Tranche[3] memory _pts,
        TricryptoStore _tricryptoStore,
        TimestampStore _timestampStore
    ) {
        tricrypto = _tricrypto;
        pts = _pts;
        tricryptoStore = _tricryptoStore;
        timestampStore = _timestampStore;
        ONE_UNDERLYING = 10 ** ERC20(_pts[0].underlying()).decimals();
    }

    function addLiquidity(uint256 timeJumpSeed, address sender, uint256[3] memory ptsIn, address to)
        public
        useSender(sender)
        checkActor(to)
        adjustTimestamp(timeJumpSeed)
        countCall("tricrypto_addLiquidity")
    {
        // Bound amounts to deposit to prevent unreasonable imbalances
        ptsIn[0] = _bound(ptsIn[0], 0, 1_000_000 * ONE_UNDERLYING);
        ptsIn[1] = _bound(ptsIn[1], ptsIn[0] * 50 / 100, ptsIn[0] * 150 / 100); // 50% - 150% of ptsIn[0]
        ptsIn[2] = _bound(ptsIn[2], ptsIn[0] * 50 / 100, ptsIn[0] * 150 / 100); // 50% - 150% of ptsIn[0]

        // sum(ptsIn) must be non-zero
        if (ptsIn[0] == 0 && ptsIn[1] == 0 && ptsIn[2] == 0) {
            return;
        }
        // approve principal tokens
        for (uint256 i = 0; i < 3; i++) {
            deal(address(pts[i]), currentSender, ptsIn[i], true);
            pts[i].approve(address(tricrypto), ptsIn[i]);
        }
        tricrypto.add_liquidity(ptsIn, 0, false, to);
        tricryptoStore.addRecipient(to);
    }

    function removeLiquidity(
        uint256 timeJumpSeed,
        uint256 senderSeed,
        uint256 shares,
        address to,
        bool claim_admin_fees
    )
        public
        useFuzzedSender(senderSeed)
        checkActor(to)
        adjustTimestamp(timeJumpSeed)
        countCall("tricrypto_removeLiquidity")
    {
        // set upper bound to prevent liquidity on Tricrypto from going to 0 or reverting
        uint256 userBalance = tricrypto.balanceOf(currentSender);
        uint256 halfSuppy = tricrypto.totalSupply() / 2;
        uint256 max = userBalance < halfSuppy ? userBalance : halfSuppy;
        shares = _bound(shares, 0, max);
        if (shares == 0) return;
        tricrypto.remove_liquidity({
            amount: shares,
            min_amounts: [uint256(0), 0, 0],
            use_eth: false,
            receiver: to,
            claim_admin_fees: claim_admin_fees
        });
    }

    function removeLiquidityOneCoin(uint256 timeJumpSeed, uint256 senderSeed, uint256 shares, uint256 i, address to)
        public
        useFuzzedSender(senderSeed)
        checkActor(to)
        adjustTimestamp(timeJumpSeed)
        countCall("tricrypto_removeLiquidityOneCoin")
    {
        // set upper bound to prevent liquidity on Tricrypto from going to 0 or reverting with imbalanced withdrawal
        uint256 max = tricrypto.balanceOf(currentSender);
        uint256 totalSupply = tricrypto.totalSupply();
        if (max > totalSupply / 100) max = totalSupply / 100; // cap at 1% of the total supply
        shares = _bound(shares, 0, max);
        i = _bound(i, 0, 2);
        if (shares == 0) return;
        tricrypto.remove_liquidity_one_coin({token_amount: shares, i: i, min_amount: 0, use_eth: false, receiver: to});
    }

    function exchange(uint256 timeJumpSeed, address sender, uint256 i, uint256 j, uint256 dx, address to)
        public
        useSender(sender)
        checkActor(to)
        adjustTimestamp(timeJumpSeed)
        countCall("tricrypto_exchange")
    {
        i = _bound(i, 0, 2);
        j = _bound(j, 0, 2);
        if (i == j) return;
        dx = _bound(dx, 0, tricrypto.balances(i) * 1 / 1000); // cap at 0.1% of the balance in the pool
        if (dx == 0) return;
        deal(address(pts[i]), currentSender, dx, true);
        pts[i].approve(address(tricrypto), dx);
        tricrypto.exchange(i, j, dx, 0, false, to);
    }

    function callSummary() public view override {
        console2.log("tricrypto_addLiquidity:", calls["tricrypto_addLiquidity"]);
        console2.log("tricrypto_removeLiquidity:", calls["tricrypto_removeLiquidity"]);
        console2.log("tricrypto_removeLiquidityOneCoin:", calls["tricrypto_removeLiquidityOneCoin"]);
        console2.log("tricrypto_exchange:", calls["tricrypto_exchange"]);
    }
}
