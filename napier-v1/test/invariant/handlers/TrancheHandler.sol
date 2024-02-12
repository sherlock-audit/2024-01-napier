// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {console2} from "forge-std/Test.sol";

import {Properties} from "../Properties.sol";
import {IssuerHandler} from "./IssuerHandler.sol";
import {TimestampStore} from "../TimestampStore.sol";
import {TrancheStore} from "../TrancheStore.sol";

import {Tranche} from "src/Tranche.sol";
import {ERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts@4.9.3/utils/math/Math.sol";

contract TrancheHandler is IssuerHandler {
    address internal currentFrom;

    /// @dev Makes a previously provided recipient the source of the tokens.
    modifier useFuzzedFrom(uint256 actorIndexSeed) {
        currentFrom = trancheStore.getRecipient(actorIndexSeed);
        if (currentFrom == address(0)) return;
        _;
    }

    /// @dev Makes the previously provided recipient the caller.
    modifier useFuzzedSender(uint256 actorIndexSeed) {
        currentSender = trancheStore.getRecipient(actorIndexSeed);
        if (currentSender == address(0)) return;
        vm.startPrank(currentSender);
        _;
        vm.stopPrank();
    }

    constructor(
        Tranche _tranche,
        TimestampStore _timestampStore,
        TrancheStore _trancheStore
    ) IssuerHandler(_tranche, _timestampStore, _trancheStore) {}

    function redeem(
        uint256 timeJumpSeed,
        address sender,
        uint256 fromSeed,
        address to,
        uint256 principal
    )
        external
        checkActor(to)
        useSender(sender)
        useFuzzedFrom(fromSeed)
        adjustTimestamp(timeJumpSeed)
        countCall("redeem")
    {
        // If the tranche is not mature, then we can't redeem.
        if (maturity > block.timestamp) {
            calls["redeem_before_maturity"]++;
            return;
        }

        principal = _bound(principal, 0, tranche.balanceOf(currentFrom));

        if (principal == 0) {
            return;
        }

        // Simulate the withdraw to get the estimated amount of underlying tokens.
        uint256 cscale = adapter.scale();
        vm.mockCall(address(adapter), abi.encodeWithSelector(adapter.scale.selector), abi.encode(cscale));
        uint256 preview = tranche.previewRedeem(principal);
        vm.clearMockedCalls();

        if (currentSender != currentFrom) {
            changePrank(currentFrom);
            tranche.approve(currentSender, principal);
            changePrank(currentSender);
        }
        uint256 withdrawn = tranche.redeem({principalAmount: principal, to: to, from: currentFrom});

        assertApproxEqRel(
            preview,
            withdrawn,
            0.0001 * 1e18,
            "redeem: previewed amount should be close to withdrawn amount"
        );
    }

    function withdraw(
        uint256 timeJumpSeed,
        address sender,
        uint256 fromSeed,
        address to,
        uint256 underlyingAmount
    )
        external
        checkActor(to)
        useSender(sender)
        useFuzzedFrom(fromSeed)
        adjustTimestamp(timeJumpSeed)
        countCall("withdraw")
    {
        // If the tranche is not mature, then we can't redeem.
        if (maturity > block.timestamp) {
            calls["withdraw_before_maturity"]++;
            return;
        }

        // Cap max withdraw amount.
        underlyingAmount = _bound(underlyingAmount, 0, tranche.maxWithdraw(currentFrom));

        if (underlyingAmount == 0) {
            return;
        }

        // Simulate the withdraw to get the estimated amount of principal tokens to be burned.
        uint256 cscale = adapter.scale();
        vm.mockCall(address(adapter), abi.encodeWithSelector(adapter.scale.selector), abi.encode(cscale));
        uint256 preview = tranche.previewWithdraw(underlyingAmount);
        vm.clearMockedCalls();

        // If the previewed amount is greater than the user's balance, then we can't withdraw.
        // This may happen due to precision loss in the round trip `maxWithdraw` -> `previewWithdraw`.
        uint256 balance = tranche.balanceOf(currentFrom);
        if (preview > balance) return;

        if (currentSender != currentFrom) {
            changePrank(currentFrom);
            tranche.approve(currentSender, preview);
            changePrank(currentSender);
        }
        uint256 ptRedeemed = tranche.withdraw({underlyingAmount: underlyingAmount, to: to, from: currentFrom});

        assertApproxEqRel(
            preview,
            ptRedeemed,
            0.0001 * 1e18,
            "withdraw: previewed amount should be close to redeemed amount"
        );
    }

    function redeemWithYt(
        uint256 timeJumpSeed,
        uint256 fromSeed,
        address sender,
        address to,
        uint256 amount
    )
        external
        checkActor(to)
        useSender(sender)
        useFuzzedFrom(fromSeed)
        adjustTimestamp(timeJumpSeed)
        countCall("redeemWithYt")
    {
        amount = _bound(amount, 0, Math.min(tranche.balanceOf(currentFrom), yt.balanceOf(currentFrom)));

        if (amount == 0) {
            return;
        }

        if (currentSender != currentFrom) {
            changePrank(currentFrom);
            tranche.approve(currentSender, amount);
            yt.approve(currentSender, amount);
            changePrank(currentSender);
        }

        tranche.redeemWithYT({pyAmount: amount, from: currentFrom, to: to});

        // If the tranche is NOT mature OR the tilt is zero, collecting twice doesn't claim anything.
        // Otherwise, collecting after the maturity claims some shares belongs to YT holders by tilting.
        if (maturity > block.timestamp || tranche.getSeries().tilt == 0) {
            assert_collectNoYield(currentFrom, Properties.T_FL_03);
        }
    }

    function collect(
        uint256 timeJumpSeed,
        uint256 senderSeed
    ) external useFuzzedSender(senderSeed) adjustTimestamp(timeJumpSeed) countCall("collect") {
        // If the recorded user scale is 0, protocol doesn't allow to collect.
        if (tranche.lscales(currentSender) == 0) return;
        tranche.collect();

        // After maturity, user's YT balance should be 0.
        if (maturity <= block.timestamp) {
            assertEq(yt.balanceOf(currentSender), 0, "collect: YT balance should be 0 after maturity");
        }
        // Both before and after maturity, user's claimable yield should be 0.
        assert_collectNoYield(currentSender, Properties.T_FL_02);
    }

    // Note: `claimIssuanceFees` may cause the `invariant_solvency` to fail because the shares in Tranche can be less than fee due to rounding error/precision loss.
    // function claimIssuanceFees(uint256 timeJumpSeed) external adjustTimestamp(timeJumpSeed) countCall("claimFee") {
    //     vm.prank(tranche.management());
    //     tranche.claimIssuanceFees();
    // }

    function transferFromPt(
        uint256 timeJumpSeed,
        address sender,
        uint256 fromSeed,
        address to,
        uint256 amount
    )
        external
        checkActor(to)
        useSender(sender)
        useFuzzedFrom(fromSeed)
        adjustTimestamp(timeJumpSeed)
        countCall("transferPt")
    {
        amount = _bound(amount, 0, tranche.balanceOf(currentFrom));

        _transferFrom(tranche, currentSender, currentFrom, to, amount);
    }

    function transferFromYt(
        uint256 timeJumpSeed,
        address sender,
        uint256 fromSeed,
        address to,
        uint256 amount
    )
        external
        checkActor(to)
        useSender(sender)
        useFuzzedFrom(fromSeed)
        adjustTimestamp(timeJumpSeed)
        countCall("transferYt")
    {
        amount = _bound(amount, 0, yt.balanceOf(currentFrom));

        // Expected amount of shares to be collected if the `from` and `to` collect yield before the transfer.
        uint256 expected_1 = simulate_collect(currentFrom);
        uint256 expected_2 = simulate_collect(to);

        _transferFrom(yt, currentSender, currentFrom, to, amount);

        // If *tilt is non-zero* AND *maturity is passed*, calling `collect` will claim some non-zero shares belongs to YT holders based on the balance of YT.
        // This will cause shares to be collected to be different before and after the transfer.
        if (tranche.getSeries().tilt != 0 && maturity <= block.timestamp) return;

        // If *tilt is zero* OR *maturity is not passed*, calling `collect` will NOT claim any shares.
        uint256 collected_1 = simulate_collect(currentFrom);
        uint256 collected_2 = simulate_collect(to);

        assertApproxEqAbs(collected_1, expected_1, 1, Properties.Y_FL_01);
        assertApproxEqAbs(collected_2, expected_2, 1, Properties.Y_FL_02);
    }

    function simulate_collect(address user) internal returns (uint256 collected) {
        if (tranche.lscales(user) != 0) {
            changePrank(user);
            uint256 snapshot = vm.snapshot();
            collected = tranche.collect();
            vm.revertTo(snapshot);
            changePrank(currentSender);
        }
    }

    function _transferFrom(ERC20 token, address sender, address from, address to, uint256 amount) internal {
        uint256 random = uint256(
            keccak256(abi.encodePacked(block.timestamp, block.prevrandao, sender, from, to, amount))
        );
        // 50% chance to transfer directly, 50% chance to transferFrom even if sender == from.
        if (sender == from && random % 2 == 0) {
            token.transfer(to, amount);
        } else {
            changePrank(from);
            token.approve(sender, amount);
            changePrank(sender);
            token.transferFrom(from, to, amount);
        }
        trancheStore.addRecipient(to);
    }

    function callSummary() public view override {
        super.callSummary();
        console2.log("redeem:", calls["redeem"]);
        console2.log("redeemWithYt:", calls["redeemWithYt"]);
        console2.log("collect:", calls["collect"]);
        console2.log("claimFee:", calls["claimFee"]);
        console2.log("transferPt:", calls["transferPt"]);
        console2.log("transferYt:", calls["transferYt"]);
        console2.log("redeem_before_maturity:", calls["redeem_before_maturity"]);
        console2.log("withdraw_before_maturity:", calls["withdraw_before_maturity"]);
    }
}
