# Guideline for Creating an Adapter for a New Protocol.

## Adapter Requirements

1. Adapter must follow the requirement: [Napier Adapter Specification](./SPECIFICATION.md#L95-L101).
2. Adapter does not accept native ETH as an underlying asset; use WETH instead.
3. Adapter may need to be tokenized if an external protocol distributes rewards. In such cases, it is necessary to reliably transfer those rewards to the Napier treasury.

## Create a New Adapter

1. Create a new folder under `src/adapters` for the protocol. For example, if the protocol is called `Foo`, create a folder called `foo`.
2. Create a new contract `FooAdapter` under `src/adapters/{foo}/FooAdapter.sol`. This contract should inherit from `BaseAdapter`.
   - Interfaces for the external protocol should be imported from `src/adapters/{foo}/interfaces/`.
   - Addresses which are constants should be added to `src/Constants.sol`.

## How to Test

### Test Setup

- Use a mainnet fork with a fixed block number. Please refer to the documentation [here](https://book.getfoundry.sh/cheatcodes/create-select-fork) for instructions on setting up the environment variables required for this.
- Utilize the `deal` function to set the initial underlying balance for an account. [reference](https://book.getfoundry.sh/cheatcodes/deal?highlight=deal#deal).
  - The `deal` function may not work with certain tokens, such as aToken or stETH. In such cases, you should find a whale address for the token on Etherscan and impersonate it to transfer assets to your account.
- Set a human-friendly name for an address using `vm.label` in the `setUp` function. This can be helpful for examining traces and debugging.
- If necessary, utilize `vm.mockCall`. You may not need to create separate mock contracts as `vm.mockCall` can provide the required functionality.

### Unit Test

Create a unit test contract `TestFooAdapter` under `test/unit/adapters/FooAdapter.t.sol`. This contract is used to test the methods of `FooAdapter`. The test contract should inherit from `BaseTestAdapter`.

### Integration Test

1. Create a new folder under `test/integration` for the protocol. For example, if the protocol is called `Foo`, create a folder called `foo`.
2. Create a fixture contract `FooFixture` under `test/integration/{foo}/Fixture.t.sol`. This contract should inherit from `CompleteFixture`.

- The `FooFixture` contract should override the `setUp` function to set up the initial state of the protocol.
  - The `FooFixture` contract should override the `_deployAdapter` function to deploy the adapters for the protocol.
  - The `FooFixture` contract should override the `_simulateScaleIncrease` and `_simulateScaleDecrease` functions to simulate the increase and decrease of the scale.
  - The `FooFixture` contract may need to override the `deal` function if the underlying asset is WETH.

3. Create an integration test contract `{TargetTokenName}Tranche` under `test/integration/{foo}/Tranche.t.sol`. This test contract should inherit from `BaseTestTranche` and `FooFixture`
4. Create a scenario test `Test{TargetTokenName}Scenario` under `test/integration/{foo}/Scenario.t.sol`. The test contract should inherit from `BaseTestScenario` and `FooFixture`.
