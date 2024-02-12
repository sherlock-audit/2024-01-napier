# Deployment

## Relevant Addresses

### Ethereum Mainnet

### Sepolia

| Name                                 | Address                                                                                                                            |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| Create2Deployer                      | 0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2                                                                                         |
| PoolFactory                          | TODO (address and link to etherscan)                                                                                               |
| CurveTricryptoFactory                | [0x898af82d705A1e368b4673a253374081Fc221FF1](https://sepolia.etherscan.io/address/0x898af82d705A1e368b4673a253374081Fc221FF1#code) |
| CurveCryptoOptimizedWETH (Blueprint) | [0xaa212B1097c4395c6755D6Cd94232aC551a6d26A](https://sepolia.etherscan.io/address/0xaa212B1097c4395c6755D6Cd94232aC551a6d26A#code) |
| CurveCryptoViews3Optimized           | [0xfEA521aD542D61a0D8888502224Ee2F33d1aeB31](https://sepolia.etherscan.io/address/0xfEA521aD542D61a0D8888502224Ee2F33d1aeB31#code) |
| CurveTricryptoMathOptimized          | [0xB7E728cC75392C7428D8f3bBfcE46819F5f397D9](https://sepolia.etherscan.io/address/0xB7E728cC75392C7428D8f3bBfcE46819F5f397D9#code) |

## Deployments

1. Prepare a private key `PK` and fund it with some ETH.
2. Export `owner` address of `PoolFactory` contract as `OWNER=$(cast wallet address $PK)`.
3. Export Underlying, WETH and Principal Token addresses as `UNDERLYING`, `WETH`, `PT1`, `PT2` and `PT3`.
4. Ensure that `RPC_URL` is set appropriately.
5. Build the contracts.
6. Deploy the contracts. [Testnet Deployments with mock tokens](#testnet-deployments-with-mock-tokens) or [Production Deployments](#production-deployments)

### Testnet Deployments with Mock Tokens

1. Deploy Curve Tricrypto Factory

If you want to deploy contracts to other testnests than Sepolia, you need to deploy Curve Tricrypto contracts to the network.

> [!NOTE]
> You can skip this step if you want to deploy contracts to Sepolia.

```bash
./script/deploy_curve.sh $PK $OWNER $RPC_URL
```

> Due to a bug in the `foundry` or etherscan, script for deploying will fail. See [issue](https://github.com/foundry-rs/foundry/issues/5251). To fix this, manually deploy CurveTricrypto contracts to the network.

Visit etherscan to get the deployed addresses of Curve Tricrypto and export those addresses.

```bash
export AMM_BLUEPRINT=<CurveCryptoOptimizedWETH>
export CURVE_FACTORY=<CurveTricryptoFactory>
export VIEWS=<CurveCryptoViews3Optimized>
export MATH=<CurveTricryptoMathOptimized>
```

After that, you can dry-run the deployment script to check if everything is fine. After that, add `--verify --broadcast` flags to deploy the contracts and verify them automatically at the same time.

```bash
AMM_BLUEPRINT=$AMM_BLUEPRINT CURVE_FACTORY=$CURVE_FACTORY VIEWS=$VIEWS MATH=$MATH WETH=$WETH UNDERLYING=$UNDERLYING PT1=$PT1 PT2=$PT2 PT3=$PT3 forge script --rpc-url=$RPC_URL --private-key=$PK -vvvv script/Deploy.s.sol:TestDeploy
```

### Production Deployments

WIP

## Verify Contracts

assumed that followed variables are get from deployment logs.
while verifying, you need to replace those variables to real address.

```bash
export POOL=<pool-address>
export SWAP_ROUTER=<swap-router-address>
export POOL_FACTORY=<factory-address>
export LIB_CREATE2_POOL=<lib-create2-pool-address>
export QUOTER=<quoter-address>
export TRANCHER_FACTORY=<trancher-factory-address>
export TRANCHE_ROUTER=<tranche-router-address>
```

- verify `NapierPool` contract

```bash
forge verify-contract --chain=sepolia $POOL src/NapierPool.sol:NapierPool
```

- verify `NapierRouter` contract

For verification, needed PoolFactory, WETH address for constructor parameters.

```bash
forge verify-contract --chain=sepolia $SWAP_ROUTER src/NapierRouter.sol:NapierRouter --constructor-args=$(cast abi-encode "constructor(address,address)" $POOL_FACTORY $WETH)
```

- verify `PoolFactory` contract

For verification, needed Create2PoolLib library with parameters (LIB_CREATE2_POOL, POOL_FACTORY) and also needed CURVE_FACTORY, OWNER for constructor parameters.

```bash
forge verify-contract --chain=sepolia --libraries=src/libs/Create2PoolLib.sol:Create2PoolLib:$LIB_CREATE2_POOL $POOL_FACTORY src/PoolFactory.sol:PoolFactory --constructor-args=$(cast abi-encode "cons(address,address)"  $CURVE_FACTORY $OWNER)
```

- verify `Quoter` contract

Needed PoolFactory address for constructor parameters.

```bash
forge verify-contract --chain=sepolia $QUOTER src/lens/Quoter.sol:Quoter --constructor-args=$(cast abi-encode "cons(address)" $POOL_FACTORY)
```

- verify `TrancheRouter` contract

Needed TrancheFactory, WETH address for constructor parameters.

```bash
forge verify-contract --chain=sepolia $TRANCHE_ROUTER src/TrancheRouter.sol:TrancheRouter --constructor-args=$(cast abi-encode "cons(address,address)" $TRANCHER_FACTORY $WETH)
```
