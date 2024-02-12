## Protocol Invariants

### NapierPool

| Property | Description                                                                                                                  | Category | Tested |
| -------- | ---------------------------------------------------------------------------------------------------------------------------- | -------- | ------ |
| P-01     | The underlying token balance in the pool is greater than or equal to the sum of the reserve and the protocol fees accounting |          |        |
| P-02     | The Tricrypto LP token balance in the pool is greater than or equal to the reserve accounting                                |          |        |
| P-03     | After or at the maturity, the pool does not accept any liquidity addition                                                    |          |        |
| P-04     | After or at the maturity, the pool does not allow swapping                                                                   |          |        |
| P-05     | At any time, the pool allows the removal of liquidity                                                                        |          |        |

# Function-Level Properties

## Tranche

| Property | Description                                                                                           | Category | Tested |
| -------- | ----------------------------------------------------------------------------------------------------- | -------- | ------ |
| P_FL_01  | When providing liquidity, the amount of tokens added is proportional to the reserve in the pool       |          |        |
| P_FL_02  | When withdrawing liquidity, the amount of tokens withdrawn is proportional to the reserve in the pool |          |        |
