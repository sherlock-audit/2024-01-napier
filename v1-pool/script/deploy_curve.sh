
# Usage: ./deploy_curve.sh <private_key> <owner> <rpc_url>
PK=$1
OWNER=$2
RPC_URL=$3

# Deploy Curve Factory, Math and View contracts
# Deploy Curve Tricrypto Optimized WETH contract as blueprint

INIT_CODE=$(vyper lib/tricrypto-ng/contracts/main/CurveTricryptoFactory.vy)
ARGS=$(cast abi-encode "constructor(address, address)" $OWNER $OWNER)
INIT_CODE=$(cast concat-hex $INIT_CODE $ARGS) # Concatenate init code and arguments
cast send --private-key=$PK --rpc-url=$RPC_URL --create $INIT_CODE

INIT_CODE=$(vyper lib/tricrypto-ng/contracts/main/CurveCryptoMathOptimized3.vy)
cast send --private-key=$PK --rpc-url=$RPC_URL --create $INIT_CODE

INIT_CODE=$(vyper lib/tricrypto-ng/contracts/main/CurveCryptoViews3Optimized.vy)
cast send --private-key=$PK --rpc-url=$RPC_URL --create $INIT_CODE

INIT_CODE=$(vyper -f=blueprint_bytecode lib/tricrypto-ng/contracts/main/CurveTricryptoOptimizedWETH.vy)
cast send --private-key=$PK --rpc-url=$RPC_URL --create $INIT_CODE
