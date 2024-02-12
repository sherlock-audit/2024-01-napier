// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

library Properties {
    ///// Function-Level Assertions /////

    // Tranche
    string constant T_FL_01 = "No yield should be claimable immediately after issuing";
    string constant T_FL_02 = "No yield should be claimable immediately after collecting";
    string constant T_FL_03 =
        "No yield should be claimable immediately after early redemption if the maturity is not passed";

    // Yield Token
    string constant Y_FL_01 =
        "Transferring YT shouldn't change `from`'s claimable yield  before and after the transfer if the maturity is not passed";
    string constant Y_FL_02 =
        "Transferring YT shouldn't change `to`'s claimable yield  before and after the transfer if the maturity is not passed";

    ///// Protocol-Level Assertions /////

    // Tranche
    string constant T_01 =
        "The Target balance in the Tranche is greater than or equal to the sum of the claimable yield and the redeemable amount of Target for individual users";
    string constant T_02 =
        "The sum of the claimed yield and the redeemed Target through the early redemption of PT and YT is equal to the amount of Target initially issued when issuing PT and YT";

    // Yield Token
    string constant YT_01 =
        "The total supply of the Principal Token is equal to the total supply of the Yield Token if the maturity is not passed";
    string constant YT_02 =
        "When user's PT and YT balances remain unchanged, the sum of total unclaimed yield and claimed yield is equal to the total claimable yield regardless of when and how many times the user claimed yield";
}
