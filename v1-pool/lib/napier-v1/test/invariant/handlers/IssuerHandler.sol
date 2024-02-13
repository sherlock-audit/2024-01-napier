// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {console2, StdAssertions} from "forge-std/Test.sol";

import {BaseHandler} from "./BaseHandler.sol";
import {Properties} from "../Properties.sol";

import {ERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";
import {YieldToken} from "src/YieldToken.sol";
import {Tranche} from "src/Tranche.sol";
import {BaseAdapter} from "src/BaseAdapter.sol";

import {TimestampStore} from "../TimestampStore.sol";
import {TrancheStore} from "../TrancheStore.sol";

contract IssuerHandler is BaseHandler, StdAssertions {
    Tranche tranche;
    YieldToken yt;
    BaseAdapter adapter;
    uint256 maturity;
    ERC20 underlying;
    uint256 ONE_UNDERLYING;

    constructor(Tranche _tranche, TimestampStore _timestampStore, TrancheStore _trancheStore) {
        tranche = _tranche;
        yt = YieldToken(_tranche.yieldToken());
        adapter = BaseAdapter(_tranche.getSeries().adapter);
        maturity = _tranche.maturity();
        underlying = ERC20(_tranche.underlying());
        ONE_UNDERLYING = 10 ** underlying.decimals();
        timestampStore = _timestampStore;
        trancheStore = _trancheStore;
    }

    function issue(
        uint256 timeJumpSeed,
        address sender,
        address to,
        uint256 uDeposit
    ) external checkActor(to) useSender(sender) adjustTimestamp(timeJumpSeed) countCall("issue") {
        // If the tranche is mature, then we can't issue.
        if (maturity <= block.timestamp) {
            calls["issue_after_maturity"]++;
            return;
        }

        uint256 totFee = tranche.issuanceFees();
        uDeposit = _bound(uDeposit, ONE_UNDERLYING, 1_000_000 * ONE_UNDERLYING);
        deal(address(underlying), sender, uDeposit, false);

        underlying.approve(address(tranche), uDeposit);
        tranche.issue({underlyingAmount: uDeposit, to: to});
        trancheStore.addRecipient(to);

        uint256 fee = tranche.issuanceFees() - totFee;
        console2.log("issuance fee :>>", fee);

        assert_collectNoYield(to, Properties.T_FL_01);
    }

    function callSummary() public view virtual override {
        console2.log("issue:", calls["issue"]);
        console2.log("issue_after_maturity:", calls["issue_after_maturity"]);
    }

    function assert_collectNoYield(address user, string memory e) internal {
        changePrank(user);
        uint256 snapshot = vm.snapshot(); // snapshot the state
        assertEq(tranche.collect(), 0, e);
        vm.revertTo(snapshot); // revert to the original state
        changePrank(currentSender);
    }
}
