# Napier Pool V1

### Requirements

The following will need to be installed. Please follow the links and instructions.

- [Foundry](https://github.com/foundry-rs/foundry)
- Node >= 14
- yarn or npm >= 7
- Python >= 3.10

### Quickstart

1. Install dependencies

Once you've cloned and entered into your repository, you need to install the necessary dependencies. In order to do so, simply run:

```shell
yarn install
forge install
```

And then you need to install the python dependencies to compile Vyper contracts.

```shell
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

2. Build

```bash
forge build
```

3. Test

Set up your environment variables in `.env`:

```bash
export ETH_RPC_URL=<your_mainnet_rpc_url>
```

```bash
source .venv/bin/activate # This is needed to compile Vyper contracts
forge test -vvv
```

For more optimal optimizer setting, you can compile with Hardhat:

```bash
npx hardhat compile
OPTIMIZE=true forge test -vvv # This will read the artifacts from hardhat with FFI and run the tests
```

For more information on how to use Foundry, check out the [Foundry Github Repository](https://github.com/foundry-rs/foundry/tree/master/forge) or type `forge help` in your terminal.

### Formatting

Type:

```bash
forge fmt
```

## Development

![](.github/assets/diagram.svg)

### Deployment

See [deployment](./deployment.md)

### Links

[napier-v1](https://github.com/Napier-Lab/napier-v1/tree/main)
