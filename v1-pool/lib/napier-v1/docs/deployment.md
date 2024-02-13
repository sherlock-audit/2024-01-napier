# Deployments

## Relevant Addresses

| Name                      | Address                                    |
| ------------------------- | ------------------------------------------ |
| Create2Deployer (Sepolia) | 0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2 |
| TrancheFactory (Sepolia)  | TODO (address and link to etherscan)       |

## TrancheFactory Deployments

1. Prepare a private key `PK` and fund it with some ETH.
2. Export `management` address of `TrancheFactory` contract as `MANAGEMENT`.
3. Ensure that `RPC_URL` is set appropriately.
4. Build the contracts.

```bash
export CREATION_CODE=$(cat out/TrancheFactory.sol/TrancheFactory.json | jq -r .bytecode.object)

export INIT_CODE=$(cast concat-hex $CREATION_CODE $(cast abi-encode "abi_encode(address)" $MANAGEMENT))

cast create2 --deployer=$CREATE2_DEPLOYER --init-code=$INIT_CODE --starts-with=<starts-with>
```

TODO: The above is not working yet because `TrancheFactory` bytecode includes a placeholder for a external library to be linked.

```bash
SALT=$SALT MANAGEMENT=$MANAGEMENT forge script -vvvv --private-key=$PK --rpc-url=$RPC_URL script/TrancheFactoryDeploy.s.sol:TrancheFactoryDeploy
```

### Testnet Deployments

1. Export `TrancheFactory` address obtained from the previous step as `TRANCHE_FACTORY` and maturity as `MATURITY` (unix timestamp in seconds).
2. Dry-run the deployment script with the following command:

```bash
MATURITY=$MATURITY TRANCHE_FACTORY=$TRANCHE_FACTORY forge script --rpc-url=$RPC_URL --private-key=$PK  script/MockDeploy.s.sol
```

3. If the dry-run is successful, run the command with `--broadcast --verify` flag to deploy the contracts.

### Verification

Export the following variables as environment variables:

```bash
export NETWORK=<network> # e.g. mainnet or sepolia
export TRANCHE_FACTORY=<tranche-factory-address>
export TRANCHE=<tranche-factory-address>
export LIB_CREATE2_TRANCHE=<create2-tranche-lib-address>
export MANAGEMENT=<management-address>
export TARGET=<target1-address> # e.g. cETH
export ADAPTER=<adapter1-address> # e.g. WCETHAdapter
export UNDERLYING=<underlying-address> # e.g. WETH
export WETH=<weth-address>
export MATURITY=<maturity> # e.g. 1640995200
```

- TrancheFactory

```bash
forge verify-contract --chain=$NETWORK $TRANCHE_FACTORY src/TrancheFactory.sol:TrancheFactory --constructor-args=$(cast abi-encode "constructor(address)" $MANAGEMENT) --libraries=src/Create2TrancheLib.sol:Create2TrancheLib:$LIB_CREATE2_TRANCHE
```

- Tranche

```bash
forge verify-contract --chain=$NETWORK --libraries=src/Create2TrancheLib.sol:Create2TrancheLib:$LIB_CREATE2_TRANCHE $TRANCHE src/Tranche.sol:Tranche
```

- MockERC20

```bash
forge verify-contract --chain=sepolia $TARGET test/mocks/MockERC20.sol:MockERC20 --constructor-args=$(cast abi-encode "a(string,string,uint8)" "CompoundV2 ETH" "cETH" 18)
```

- MockWETH

```bash
forge verify-contract --chain=sepolia $WETH script/MockWETH.sol:MockWETH --constructor-args=$(cast abi-encode "c(address)" $MANAGEMENT )
```

- MockAdapter

```bash
forge verify-contract --chain=sepolia $ADAPTER script/MockAdapter.sol:MockAdapter --constructor-args=$(cast abi-encode "a(address,address,uint256)" $UNDERLYING $TARGET $MATURITY)
```

### References

- [create2deployer](https://github.com/pcaversaccio/create2deployer/tree/main/)
  - Helper smart contract to make easier and safer usage of the `CREATE2` EVM opcode.
