// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Properties {
    // Function-Level Properties
    string constant P_FL_01 =
        "When providing liquidity, the amount of tokens added is proportional to the reserve in the pool";
    string constant P_FL_02 =
        "When withdrawing liquidity, the amount of tokens withdrawn is proportional to the reserve in the pool";

    // Protocol Invariants
    string constant P_01 =
        "The underlying token balance in the pool is greater than or equal to the sum of the reserve and the protocol fees accounting";
    string constant P_02 =
        "The Tricrypto LP token balance in the pool is greater than or equal to the reserve accounting";
    string constant P_03 = "After or at the maturity, the pool does not accept any liquidity addition";
    string constant P_04 = "After or at the maturity, the pool does not allow swapping";
    string constant P_05 = "At any time, the pool allows the removal of liquidity";
}
