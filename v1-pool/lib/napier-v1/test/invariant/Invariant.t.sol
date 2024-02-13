// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {CompleteFixture} from "../Fixtures.sol";
import {Properties} from "./Properties.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockAdapter} from "../mocks/MockAdapter.sol";

import {TrancheHandler} from "./handlers/TrancheHandler.sol";
import {AdapterHandler} from "./handlers/AdapterHandler.sol";
import {BaseHandler} from "./handlers/BaseHandler.sol";
import {TimestampStore} from "./TimestampStore.sol";
import {TrancheStore} from "./TrancheStore.sol";

contract InvariantTest is CompleteFixture {
    TrancheHandler internal trancheHandler;
    AdapterHandler internal adapterHandler;
    TimestampStore internal timestampStore;
    TrancheStore internal trancheStore;

    modifier useCurrentTimestamp() {
        vm.warp(timestampStore.currentTimestamp());
        _;
    }

    function setUp() public virtual override {
        _issuanceFee = 100; // 10000 bps = 100%, 10 bps = 0.1%
        _tilt = 0; // Most cases will use 0.
        _maturity = block.timestamp + 365 days;
        super.setUp();

        timestampStore = new TimestampStore();
        trancheStore = new TrancheStore();
        trancheHandler = new TrancheHandler(tranche, timestampStore, trancheStore);
        adapterHandler = new AdapterHandler(MockAdapter(address(adapter)), timestampStore);

        // Target only the handlers for invariant testing (to avoid getting reverts).
        targetContract(address(trancheHandler));
        targetContract(address(adapterHandler));

        // Prevent these contracts from being fuzzed as `msg.sender`.
        excludeSender(address(tranche));
        excludeSender(address(adapter));
        excludeSender(address(yt));
        excludeSender(address(timestampStore));
        excludeSender(address(trancheStore));
    }

    function _deployAdapter() internal override {
        underlying = new MockERC20("Underlying", "U", 6);
        target = new MockERC20("Target", "T", 6);
        adapter = new MockAdapter(address(underlying), address(target));
    }

    /////// Invariant Tests ///////

    /// @dev All users should be able to withdraw their assets from the tranche.
    /// @dev Burns all PTs and then collects all yield and burns all YTs.
    function invariant_Solvency_1() public useCurrentTimestamp {
        address[] memory recipients = trancheStore.getRecipients(); // All PT/YT holders.
        if (tranche.maturity() > block.timestamp) {
            // Ensure that the tranche is mature to allow users to redeem their assets.
            vm.warp(tranche.maturity());
        }
        uint256 fees = tranche.issuanceFees();
        console2.log("Num of PT/YT holders :>>", recipients.length);
        console2.log("Total Issuance Fees :>>", fees);

        // Burn all PT and YT
        for (uint256 i = 0; i != recipients.length; i++) {
            uint256 bal = tranche.balanceOf(recipients[i]);
            vm.startPrank(recipients[i]);
            console2.log("Balance :>>", target.balanceOf(address(tranche)));
            tranche.redeem({principalAmount: bal, from: recipients[i], to: address(this)});
            console2.log("Balance :>>", target.balanceOf(address(tranche)));
            if (tranche.lscales(recipients[i]) != 0) tranche.collect();
            vm.stopPrank();
        }
        assertEq(tranche.totalSupply(), 0, "All PTs should be burned");
        assertEq(yt.totalSupply(), 0, "All YTs should be burned");
        // Now all PTs and YTs should be burned. so Tranche should have issuance fees only.
        if (target.balanceOf(address(tranche)) < fees) {
            // Due to precision loss, we allow 1000 wei difference.
            assertApproxEqAbs(target.balanceOf(address(tranche)), fees, 1000, Properties.T_01);
        }
    }

    /// @dev Asserts solvency of the tranche in a different way from `invariant_Solvency_1`.
    /// @dev Burns all PTs and then collects all yield and burns all YTs.
    /// If the user has both PT and YT, burn them together with `redeemWithYT`.
    function invariant_Solvency_2() public useCurrentTimestamp {
        address[] memory recipients = trancheStore.getRecipients();
        if (tranche.maturity() > block.timestamp) {
            // Ensure that the tranche is mature.
            vm.warp(tranche.maturity());
        }
        uint256 fees = tranche.issuanceFees();
        console2.log("Num of PT/YT holders :>>", recipients.length);
        console2.log("Total Issuance Fees :>>", fees);

        for (uint256 i = 0; i != recipients.length; i++) {
            uint256 pBal = tranche.balanceOf(recipients[i]);
            uint256 yBal = yt.balanceOf(recipients[i]);

            // Skip the iteration if both balances are zero
            if (pBal == 0 && yBal == 0) continue;

            vm.startPrank(recipients[i]);

            // Burn all PT and YT. If the user has both PT and YT, burn them together.
            if (pBal >= yBal) {
                // Early redemption PT and YT as much as possible
                if (yBal > 0) {
                    console2.log("Balance :>>", target.balanceOf(address(tranche)));
                    tranche.redeemWithYT({pyAmount: yBal, from: recipients[i], to: address(this)});
                }
                // Redeem the remaining PT
                if (pBal > yBal) {
                    console2.log("Balance :>>", target.balanceOf(address(tranche)));
                    tranche.redeem({principalAmount: pBal - yBal, from: recipients[i], to: address(this)});
                }
            } else {
                // pBal < yBal
                // Early redemption PT and YT as much as possible
                console2.log("Balance :>>", target.balanceOf(address(tranche)));
                tranche.redeemWithYT({pyAmount: pBal, from: recipients[i], to: address(this)});
            }

            console2.log("Balance :>>", target.balanceOf(address(tranche)));
            // Collect the remaining yield and shares belong to the YT holders if any.
            if (tranche.lscales(recipients[i]) != 0) tranche.collect();

            vm.stopPrank();
        }
        assertEq(tranche.totalSupply(), 0, "All PTs should be burned");
        assertEq(yt.totalSupply(), 0, "All YTs should be burned");
        // Now all PTs and YTs should be burned. so Tranche should have issuance fees only.
        if (target.balanceOf(address(tranche)) < fees) {
            // Due to precision loss, we allow 1000 wei difference.
            assertApproxEqAbs(target.balanceOf(address(tranche)), fees, 1000, Properties.T_01);
        }
    }

    function invariant_PrincipalTokenAndYieldTokenSupplyEquality() public useCurrentTimestamp {
        if (tranche.maturity() > block.timestamp) {
            assertEq(tranche.totalSupply(), yt.totalSupply(), Properties.YT_01);
        }
    }

    function invariant_callSummary() public useCurrentTimestamp {
        console2.log("Call summary:");
        console2.log("-------------------");
        console.log(tranche.maturity() > block.timestamp ? "before maturity" : "after maturity");
        address[] memory targets = targetContracts();
        for (uint256 i = 0; i < targets.length; i++) {
            BaseHandler(targets[i]).callSummary();
        }
    }

    /// @dev not used in this test
    function _simulateScaleIncrease() internal virtual override {}

    /// @dev not used in this test
    function _simulateScaleDecrease() internal virtual override {}
}
