# Integration
This document describes how to integrate smart contracts into Frontend.

## Overview

- `NapierRouter` is the main entry point for the frontend.
  - User can:
    - Swap
    - Add liquidity
    - Remove liquidity
- `TrancheRouter` is the main entry point for the frontend.
    - User can:
        - Mint Principal Token (PT) and Yield Token (YT)
        - Redeem PT
        - Combine PT and YT
- Each `Tranche` contract is responsible for collecting yield from the underlying protocol.
    - User can:
        - Collect yield
- `Quoter` is a helper contract that provides quotes for swaps and liquidity addition/removal.
    - User can:
        - Get price of tokens
        - Get quote for swap
        - Get quote for adding/removing liquidity

## Terminology

- `pool`- Address - A pool of 3 principal tokens and 1 underlying token. Each pool is `NapierPool` instance.
- `index` - Uint - A unique identifier for each Principal token in a pool. `index = 0, 1, 2` is corresponding to a coin in Curve Tricrypto pool. `CurveTricrypto.coin(index) == pool.principalToken(index)`
- `recipient` - Address - A recipient of swapped tokens.
- `deadline` - Uint - A timestamp in seconds. `deadline` is used to prevent unexpected slippage.

## NapierRouter

### Multicall
`Multicall` is a special method that allows to call multiple methods in a single transaction. If one of the methods fails, the whole transaction will be reverted. It is used to unwrap WETH to native ETH after swapping/adding liquidity etc.

- Unwraps WETH9 to native ETH.
```js
router.unwrapWETH9(ethAmount, recipient)
```

- Sweep tokens in router
```js
router.sweepToken(token, recipient)
```

- Refund ETH in router to the caller.
```js
router.refundETH()
```

### Swap
- Swaps MUST be disable after maturity.
- Caller MUST approve the router to spend tokens prior to calling this method.

#### Swaps `ptInDesired` of `index` of Principal Token in `pool` for underlying asset.

- `ptInDesired` - Uint - An amount of PT to swap.
- `underlyingOutMin` - Uint - A minimum amount of underlying asset to receive.
- `recipient` - Address - A recipient of swapped tokens.

```js
underlyingReceived = router.swapPtForUnderlying(pool, index, ptInDesired, underlyingOutMin, recipient, deadline)
```

If a caller wants to unwrap WETH to native ETH, multicall should be used:

```js
router.multicall(
    [
        // note: 5th parameter is set to router address itself.
        router.swapPtForUnderlying.encode(pool, index, ptInDesired, underlyingOutMin, router, deadline),
        // 1th parameter SHOULD be set to exactly equal to `underlyingOutMin`
        // specify the address to receive the unwrapped ETH as `recipient`
        router.unwrapWETH9.encode(underlyingOutMin, recipient)
    ]
)
```

#### Swaps underlying asset for `ptOutDesired` of Principal Token.

- `ptOutDesired` - Uint - An amount of PT to receive.
- `underlyingInMax` - Uint - A maximum amount of underlying asset to spend.
```js
router.swapUnderlyingForPt(pool, index, ptOutDesired, underlyingInMax, recipient, deadline)
```
If a caller wants to swap in native ETH, multicall should be used:
```js
router.multicall(
    [
        router.swapUnderlyingForPt.encode(pool, index, ptOutDesired, underlyingInMax, recipient, deadline),
        router.refundETH.encode() // no arguments needed
    ],
    {
        value: underlyingInMax // specify the max amount of ETH to swap in
    }
)
```

#### Swaps underlying asset for `ytOut` of Yield Token.
 - `ytOutDesired` - Uint - An amount of YT to receive. (At least `ytOutDesired` amount of YT will be received.)
 - `underlyingInMax` - Uint - A maximum amount of underlying asset to spend.

- Caller must approve the router to spend at least `underlyingInMax` of underlying asset prior to calling this method.
- Caller may receive remaining principal tokens as a result of the swap.
```js
router.swapUnderlyingForYt(pool, index, ytOutDesired, underlyingInMax, recipient, deadline)
```

If a caller wants to swap in native ETH, multicall should be used:
```js
router.multicall(
    [
        router.swapUnderlyingForYt.encode(pool, index, ytOutDesired, underlyingInMax, recipient, deadline)
        router.refundETH.encode()
    ],
    {
        value: underlyingInMax // specify the max amount of ETH to swap in
    }
)
```

#### Swaps `ytIn` of Yield Token for underlying asset. 
- `ytIn` - Uint - An amount of YT to swap in.
- `underlyingOutMin` - Uint - A minimum amount of underlying asset to receive.

```js
router.swapYtForUnderlying(pool, index, ytIn, underlyingOutMin, recipient, deadline)
```
Same as `swapPtForUnderlying`, multicall should be used if a caller wants to unwrap WETH to native ETH.

### Add Liquidity
- Methods for adding liqudity MUST be disabled after maturity.

- `caller` - Address - A caller of the method.
- `liquidity` - Uint - An amount of LP tokens to mint.
- `ptsIn` - Uint[3] - An amount of Principal Tokens in a `pool` to add liquidity.
- `underlyingIn` - Uint - An amount of underlying asset in a `pool` to add liquidity.
- `baseLptIn` - Uint - An amount of Curve Tricrypto LP token in a `pool` to add liquidity.
- `recipient` - Address - A recipient of LP tokens.

```md
INPUT: User can input amounts of the following tokens `(pt1In, pt2In, pt3In, underlyingIn)`

If `underlyingIn` is non-zero AND at least one of the `pt`s is non-zero, call `addLiquidity`
If `underlyingIn` is non-zero AND all `pt`s are zero, call `addLiquidityOneUnderlying`
If `underlyingIn` is zero AND one of the `pt`s is non-zero, call `addLiquidityOnePt`
```

#### Adds liquidity to a `pool` with underlying asset and Principal Token.
- Accepts underlying asset as ETH. Send ETH if user wants to add liquidity with ETH.
- Caller must approve the router to spend underlying asset and PTs prior to calling this method.
- Sends remaining underlying asset and Base LP tokens to the caller.

- `underlyingIn` - Uint - Must be non-zero.
- `ptsIn` - Uint[3] - At least one of the elements must be non-zero. Swap may fail if the amounts are too biased.

If a caller wants to deposit with WETH or ERC20,

```js
liquidity = router.addLiquidity(pool, underlyingIn, ptsIn, liquidityMin, recipient, deadline)
```

If a caller wants to deposit with ETH,

```js
liquidity = router.addLiquidity(pool, underlyingIn, ptsIn, liquidityMin, recipient, deadline, {value: underlyingIn})
```

#### Adds liquidity to a `pool` with one Principal Token.
    
- Caller must approve the router to spend one principal asset prior to calling this method.
- Off-chain computation is utilized to reduce gas costs. The caller is responsible for computing the `baseLptSwap` amount using the `Quoter.approxBaseLptToAddLiquidityOnePt` method (refer to the `Quoter` section for details).

- `liquidityEstimate` - Uint - Estimated liquidity amount to be minted.
- `baseLptSwap` - Uint - An amount of Curve Tricrypto LP tokens to be swapped to underlying asset, allowing the router to add liquidity proportionally.

```js
baseLptSwap = quoter.approxBaseLptToAddLiquidityOnePt(pool, index, ptToAdd)
// The following method can estimate the amount of liquidity and baseLpt to swap
liquidityEstimate, baseLptSwap = quoter.quoteAddLiquidityOnePt(pool, index, ptIn)
```

```js
liquidityMin = liquidityEstimate * 0.999 // set minimum to 99.9% of estimate
// It would automatically sweep remaining baseLpt and underlying.
liquidity = router.addLiquidityOnePt(pool, ptIndex, ptAmountIn, liquidityMin, recipient, deadline, baseLptSwap)
```

> Note: recommend to set `baseLptSwap` param to 90~99% of calculated amount. Transaction may revert if pool state changes before the transaction is executed and the approximation becomes outdated.

#### Adds liquidity to a `pool` with one underlying asset.
- This function doesn't accept native ETH; it must be wrapped to WETH.
- Caller must approve the router to spend underlying asset prior to calling this method.
- Off-chain computation is utilized to reduce gas costs. The caller is responsible for computing the proper parameters using the `Quoter.approxBaseLptToAddLiquidityOneUnderlying` method (refer to the `Quoter` section for details).

- `liquidityEstimate` - Uint - Estimated liquidity amount to be minted.
- `baseLptSwap` - Uint - An amount of Curve Tricrypto LP tokens to be swapped out, allowing the router to add liquidity proportionally.

```js
baseLptSwap = quoter.approxBaseLptToAddLiquidityOneUnderlying(pool, underlyingInDesired)
// The following method can estimate the amount of liquidity and baseLpt to swap
liquidityEstimate, baseLptSwap = quoter.quoteAddLiquidityOneUnderlying(pool, underlyingInDesired)
```

```js
liquidityMin = liquidityEstimate * 0.999 // set minimum to 99.9% of estimate
// It would automatically sweep remaining baseLpt and underlying.
liquidity = router.addLiquidityOneUnderlying(pool, underlyingInDesired, liquidityMin, recipient, deadline, baseLptSwap)
```

> Note: recommend to set `baseLptSwap` param to 90~99% of calculated amount. Transaction may revert if pool state changes before the transaction is executed and the approximation becomes outdated.

### Remove Liquidity

- `liquidity` - Uint - An amount of LP tokens to burn.
- `ptsOutMin` - Uint[3] - A minimum amount of Principal Tokens to receive.
- `underlyingOutMin` - Uint - A minimum amount of underlying asset to receive.
- `recipient` - Address - A recipient of withdrawn tokens.

#### Removes liquidity from a `pool` and withdraws underlying asset and Principal Tokens 

- Caller must approve the router to spend NapierPool LP tokens prior to calling this method.

Estimate amounts to withdraw with `quoter.quoteRemoveLiquidity`:
- `underlyingOutEst` - Uint - Estimated amount of underlying asset to receive
- `ptsOutEst` - Uint[3] - Estimated amounts of Principal Tokens to receive

```js
underlyingOutEst, ptsOutEst = quoter.quoteRemoveLiquidity(pool, liquidity)
```

If a caller wants to withdraw to WETH,
```js
uint256 underlyingOut, uint256[3] ptsOut = router.removeLiquidity(pool, liquidity, ptsOutMin, underlyingOutMin, recipient, deadline)
```

If a caller wants to withdraw to ETH,
```js
// Set proper minimums to avoid slippage.
res = router.multicall([
    router.removeLiquidity.encode(pool, liquidity, ptsOutMin, underlyingOutMin, router, deadline),
    router.unwrapWETH9.encode(underlyingOutMin, recipient),
    router.sweepTokens.encode([pts[0], pts[1], pts[2]], [0, 0, 0], caller),
])
```

#### Removes liquidity from a `pool` and withdraws one underlying asset.
> Note: The `index` of PT to be withdrawn when removing liquidity from Base pool. Ignored if maturity has not passed.

Estimate amounts to withdraw with `quoter.quoteRemoveLiquidityOneUnderlying`:
- `underlyingOutEst` - Uint - Estimated amount of underlying asset to receive
- `gasEstimate` - Uint - Estimated gas cost (Unreliable, for reference only)

```js
underlyingOutEst, gasEstimate = quoter.quoteRemoveLiquidityOneUnderlying(pool, index, liquidity)
```

If a caller wants to withdraw to WETH, this method can be used directly.
If a caller wants to withdraw to ETH,
```js
res = router.multicall(
    [
        // note: 5th parameter is set to router address itself.
        router.removeLiquidityOneUnderlying.encode(pool, index, liquidity, underlyingOutMin, router, deadline),
        router.unwrapWETH9.encode(underlyingOutMin, recipient),
    ]
)
```

#### Removes liquidity from a `pool` and withdraws one Principal Token.
- Caller use this method to withdraw in one principal Token.
- Caller must approve the router to spend liquidity token prior to calling this method.
- Off-chain computation is utilized to reduce gas costs. The caller is responsible for computing the `baseLptSwap` using the `Quoter.approxBaseLptToRemoveLiquidityOnePt` method (refer to the `Quoter` section for details).

> Note: The `baseLptSwap` is the amount of baseLptoken that can be gets from swapping with underlying.

```js
baseLptSwap = quoter.approxBaseLptToRemoveLiquidityOnePt(pool, liquidity)
```

Estimate amounts to withdraw with `quoter.quoteRemoveLiquidityOnePt`:
- `ptOutEst` - Uint - Estimated amount of Principal Token to receive
- `gasEstimate` - Uint - Estimated gas cost (Unreliable, for reference only)

```js
ptOutEst, baseLptSwap, gasEstimate = quoter.quoteRemoveLiquidityOnePt(pool, index, liquidity)
```

> Note: recommend to set baseLptSwap param to 90~99% of calculated amount. 
(transaction may revert if baseLptSwap is tightly set.
`pool.swapUnderlyingForExactBaseLpToken` can revert due to insufficient underlying amount if pool state changes before the transaction is executed.)
Remained underlying asset in router would be sent caller.

```js
ptOut = router.removeLiquidityOnePt(pool, ptIndex, liquidity, ptOutMin, recipient, deadline, baseLptSwap)
```

## TrancheRouter

- `caller` - Address - A caller of the method.
- `adapter` - Address - An address of the adapter to be used in the `Tranche`
- `maturity` - Uint - A maturity of the `Tranche` (in unix timestamp seconds)

`Tranche` instance is uniquely identified by `adapter` and `maturity`.

Each `Tranche` instance is responsible for minting PT and YT, redeeming PT, and collecting yield from the underlying protocol etc.

### Mint PT and YT
- `underlyingAmount` - Uint - An amount of underlying asset to be deposited.
- `to` - Address - A recipient of minted PT and YT.
- `issued` - Uint - An amount of minted PT and YT.

- A caller must approve the router to spend underlying asset prior to calling this method.
- This method MUST be disabled after maturity.
- Send an `underlyingAmount` of ETH if a caller wants to deposit with ETH.

```js
issued = router.mint(adapter, maturity, underlyingAmount, to, {value: underlyingAmount})
```

### Combine PT and YT (Redeem PT and YT)
- `pyAmount` - Uint - An amount of PT and YT to be combined.
- `to` - Address - A recipient of redeemed underlying asset.

- Caller must approve the router to spend PT and YT prior to calling this method.
```js
underlyingAmount = router.redeemWithYT(adapter, maturity, pyAmount, to)
```

If a caller wants to redeem to WETH as native ETH,
```js
amountMin = ... // specify the minimum amount of ETH to receive
res = router.multicall([
    router.redeemWithYT.encode(adapter, maturity, pyAmount, router), // note `to` is set to router address itself.
    router.unwrapWETH9.encode(amountMin=amountMin, recipient=to) 
])
```

### Redeem PT
A caller can redeem PT to underlying asset in two ways.

1. Redeem `principalAmount` of PT for underlying asset.
2. Redeem `underlyingAmount` underlying equivalent of PT for underlying asset.

- Caller must approve the router to spend PT prior to calling this method.
- These methods MUST be disabled before maturity.

```js
underlyingRedeemed = router.redeem(adapter, maturity, principalAmount, to)
```

```js
underlyingRedeemed = router.withdraw(adapter, maturity, underlyingAmount, to)
```

Same as `redeemWithYT` but only PT is redeemed. Multicall should be used if a caller wants to redeem to WETH as native ETH.

## Tranche

- Each `Tranche` instance exposes the methods that `TrancheRouter` can call.
- Each `Tranche` instance is responsible for collecting yield from the underlying protocol.
- Each `Tranche` address is uniquely computed with `CREATE2` as follows:

```js
computedTranche = getContractAddress({
  bytecodeHash: TRANCHE_FACTORY.TRANCHE_CREATION_HASH(),
  from: TRANCHE_FACTORY.address,
  opcode: 'CREATE2',
  salt: abi.encode(['address', 'uint256'], [adapter, maturity]), // Standard abi encoding
})
```

### Collect Yield
This method collects yield from the underlying protocol. The caller of this method receives the collected yield in the form of the target token of the `Tranche`.

- `accruedYield` - Uint - An amount of accrued yield to be collected in units of Tranche's target token.
- No allowance is needed to call this method.
- YTs are burned if after maturity.
- Not callable anymore once called after maturity.

```js
accruedYield = tranche.collect()
```

### View Methods
See `EIP5095` specification.

## Quote

`Quoter` is a helper contract that provides quotes for swaps and price of principal tokens.  
This contract is not designed to be called on-chain. It simplify fetching on-chain data from off-chain. 

`Quoter` gets:
- Price of Principal Token in a `pool` in terms of underlying asset.
- A quote for swapping without executing tx.
- A quote for adding/removing liquidity without executing tx.

> Some functions for quote are mutative functions. Integrators should use `eth_call` to simulate the call without actually executing the transaction. See [here](https://docs.ethers.org/v5/api/contract/contract/#contract-callStatic) for ethers.js documentation. See [here](https://viem.sh/docs/contract/simulateContract.html) for viem documentation.

### Price of Base LP Token in terms of underlying asset
- `pool` - Address - A pool address.

```js
basePoolLpPrice = quoter.quoteBasePoolLpPrice(pool)
```

### Price of Principal Token
- `pool` - Address - A pool address.
- `index` - Uint - An index of Principal Token in a `pool` to get the price.

```js
ptPrice = quoter.quotePtPrice(pool, index)
```

### Quote Swap

- `pool` - Address - A pool address.
- `index` - Uint - An index of Principal Token in a pool.

- Quote swap PT for underlying asset.
    - `ptIn` - Uint - An amount of PT to swap in.
    - `underlyingOut` - Uint - An expected amount of underlying asset to receive.

    ```js
    underlyingOut = quoter.quotePtForUnderlying(pool, index, ptIn)
    ```

See `IQuoter` for API details.

### Estimate principal token amount needed to swap for a given amount of underlying asset

`NapierRouter` defines swap methods in terms of PT. This method is useful to estimate the amount of PT needed to swap for a given amount of underlying asset.

- `underlyingDesired` - Uint - An amount of underlying asset desired.

Swap PT for exact underlying asset out.
```js
// For example, if you want to swap 1000 USDC for PT, you can use this method to estimate the amount of PT needed.
ptIn = quoter.approxPtForExactUnderlyingOut(pool, index, underlyingDesired=1000 * 1e6)
// Use this amount to call `swapPtForUnderlying` method. `deadline` should be tightly set.
actualUnderlyingReceived = router.swapPtForUnderlying(pool, index, ptIn, minUnderlying, recipient, deadline)
```

Swap exact underlying asset in for PT.
```js
ptOut = quoter.approxPtForExactUnderlyingIn(pool, index, underlyingDesired)
// Use this amount to call `swapUnderlyingForPt` method. `deadline` should be tightly set.
actualUnderlyingSpent = router.swapUnderlyingForPt(pool, index, ptOut, underlyingDesired, recipient, deadline)
```

See `IQuoter` for API details.

### Quote Liquidity Addition and Removal

These methods can be used to estimate the amounts involved in adding or removing liquidity from a pool.
See ![here](#add-liquidity) for liqiduty addition methods and ![here](#remove-liquidity) for removal methods.

### Get parameters for `addLiquidityOne*` methods

`addLiquidityOne*` functions utilize off-chain computation to reduce gas costs. `Quoter` provides a method to get those parameters from off-chain.

- `baseLptSwap` - Uint - An amount of Curve Tricrypto LP tokens to be passed to a target method, allowing the router to add liquidity proportionally.

#### Estimate base LP token amount to be swapped out to add liquidity with `addLiquidityOneUnderlying`

```js
baseLptSwap = quoter.approxBaseLptToAddLiquidityOneUnderlying(pool, underlyingInDesired)
```

#### Estimate base LP token amount to be swapped in to add liquidity with `addLiquidityOnePt`

```js
baseLptSwap = quoter.approxBaseLptToAddLiquidityOnePt(pool, index, ptInDesired)
```
