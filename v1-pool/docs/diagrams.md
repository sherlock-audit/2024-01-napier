# Diagrams

## SwapPtForUnderlying

![Alt text](/assets/SwapPtForUnderlying.svg)

## SwapUnderlyingForPt

![Alt text](/assets/SwapUnderlyingForPt.svg)

## SwapYtForUnderlying

Napier executes the following operations:

1. Initiate flash swap of underlying token for Principal Token.
2. Combine Principal Tokens (PTs) with Yield Tokens (YTs) to get underlying token.
3. Pay back flash swap by returning underlying token to pool.
4. Return remaining underlying token to user

![Alt text](/assets/SwapYtForUnderlying.svg)

## SwapUnderlyingForYt

Napier executes the following operations:

1. Initiate flash swap of PT for underlying token.
2. Deposit underlying token to issue PTs and YTs.
3. Pay back flash swap by returning PTs to pool.
4. Return YTs to user.

![Alt text](/assets/SwapUnderlyingForYt.svg)

## AddLiquidityOnePt

Napier executes the following operations:

1. Add PT to a Base pool and receive Base pool LP tokens.
2. Swap some of the LP tokens for underlying token on Napier pool.
3. Add remaining LP tokens and underlying token just bought to Napier pool.

![Alt text](/assets/AddLiquidityOnePt.svg)

## AddLiquidityOneUnderlying

Napier executes the following operations:

1. Swap some of the underlying token for Base pool LP tokens on Napier pool.
2. Add remaining underlying token and LP tokens just bought to Napier pool.

![Alt text](/assets/AddLiquidityOneUnderlying.svg)

## RemoveLiquidityOnePt

Napier executes the following operations:

1. Remove liquidity from Napier pool and receive underlying token and Base pool LP tokens.
2. Swap the underlying token for Base pool LP tokens on Napier pool.
3. Withdraw PT from Base pool by burning the Base pool LP tokens from step 1 and 2.
4. Return the PT obtained at step 3 to the user.

![Alt text](/assets/RemoveLiquidityOnePt.svg)

## RemoveLiquidityOneUnderlying

Napier executes the following operations:

When the timestamp is before the maturity date:

1. Remove liquidity from Napier pool and receive underlying token and Base pool LP tokens.
2. Swap the Base pool LP tokens for underlying token on Napier pool.
3. Return the underlying token obtained at step 1 and 2 to the user.

When the timestamp is after the maturity date:

1. Remove liquidity from Napier pool and receive underlying token and Base pool LP tokens.
2. Remove liquidity from Base pool and receive a kind of PT.
3. Redeem the PT for underlying token.
4. Return the underlying token obtained at step 1 and 3 to the user.

![Alt text](/assets/RemoveLiquidityOneUnderlying.svg)
