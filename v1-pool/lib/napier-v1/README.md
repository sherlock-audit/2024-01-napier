# Napier v1 contracts

## Getting Started

### Requirements

The following will need to be installed. Please follow the links and instructions.

- [Foundry](https://github.com/foundry-rs/foundry)
- Node >= 16
- yarn or npm >= 7
- Python >= 3.9.0

### Quickstart

1. Install dependencies

Once you've cloned and entered into your repository, you need to install the necessary dependencies. In order to do so, simply run:

```shell
yarn install
forge install
```

2. Build

```bash
forge build
```

3. Test

Set up your environment variables in `.env`:

```bash
ETH_RPC_URL=
```

And then run the tests.

```bash
forge test -vvv
```

For more optimal optimizer setting, you can compile with Hardhat:

```bash
npx hardhat compile
OPTIMIZE=true forge test -vvv # This will read the artifacts from hardhat with FFI and run the tests
```

For more information on how to use Foundry, check out the [Foundry Github Repository](https://github.com/foundry-rs/foundry/tree/master/forge) or type `forge help` in your terminal.

### Install Libraries

- Install libraries with Foundry which work with Hardhat.

```bash
forge install openzeppelin/openzeppelin-contracts # just an example
```

And then update remappings in `foundry.toml`.

```
remappings = [
    "@openzeppelin/=lib/openzeppelin-contracts/",
]
```

This will allow you to import libraries like this:

```solidity
// Instead of import "lib/openzeppelin-contracts/token/ERC20/ERC20.sol";
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
```

### Usage

```bash
FOUNDRY_PROFILE=optimized forge build
FOUNDRY_PROFILE=deep_fuzz forge test
forge inspect <contract> ir-optimized # for optimizoooor
forge doc --out=docs/foundry-docs # Generate docs
forge doc --out=docs/foundry-docs --serve # Generate docs and serve them on localhost:3000 (default)
forge coverage --report=lcov # Generate coverage report
forge snapshot # Update snapshot
```

### Testing

Slither, Slitherin and Halmos are used to check for security vulnerabilities.

To install slither and halmos, create a virtual environment.

```bash
python3 -m venv .venv
source .venv/bin/activate
```

And then install the requirements.

```bash
pip install -r requirements.txt
```

#### Slither

To run slither on all project files (except npm dependencies and forge-std) and save the results to json, which is then converted to a csv table. To do this at the root of the project, type:

```bash
solc-select install 0.8.19
solc-select use 0.8.19
slither . --config-file slither.config.json --checklist --json result.json
```

To print various reports, type:

```bash
slither . --config-file slither.config.json --print human-summary
slither . --config-file slither.config.json --print call-graph
slither --list-printers # to see all printers
```

### Formatting

Type:

```bash
yarn lint:fix
```

## Development

![](./assets/diagram.svg)

### Contributing

For breaking changes: make sure to edit the excalidraw asset and export the file to [./assets/diagram.excalidraw](./assets/diagram.excalidraw) along with an svg to [./assets/diagram.svg](./assets/diagram.svg)

### Deployment

See [deployment](./docs/deployment.md)

### License

### Acknowledgements

- [Slitherin](https://github.com/pessimistic-io/slitherin/tree/master)
- [Halmos](https://github.com/a16z/halmos)
