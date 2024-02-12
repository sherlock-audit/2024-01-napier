# Napier Protocol Technical Specification

See [Specification](./SPECIFICATION.md) for basic concepts and terminologies.

## Napier Minting System

[Detailed specification](./NapierMintingSystem.md)

### Pseudocode

None

<!-- ## Yield Tier

![yieldTier.png](../assets/yieldTier.png)

Tier is used when NapierPoolFactory creates NapierPool. Tokens with the different tier CAN't be grouped together.

- Doing for what?
  - Store asset tiers for each yield source.
- What methods are called?
  - The following methods are called by users.
    - Read Tier from off-chain `getTier`
  - The following methods are called by developers or governance.
    - Set Tier for a adapter (Yield source) `setTier`. Yield Tier is calculated off-chain and set on-chain.
  - The following methods are called by `NapierPoolFactory`.
    - Read Tier from on-chain `getTier`.
- Which methods this contract calls?
  - None
- Dependencies
  - None
- Deployed by
  - Dev

Data Model

1. tiers - The mapping of Tier for each adapter.

Business Logic

1. Set Tier for a adapter
   1. Dev/Governance calls `setTier` with Adapter address and Tier.
   2. Store Tier in storage.
   3. Emit `TierSet` event.
   - Conditions that lead to errors and failures
     - Caller is not authorized. Must be governance or dev.

## Yield Tier (Off-chain)

- Doing for what?
  - Calculate Tier for Target token transparently and verifiably.
  - User can input Target token infos on our website and calculate its tiers and verify how Tier is calculated.

Data Model -->

## Napier AMM

[Detailed specification](https://github.com/Napier-Lab/v1-pool/tree/main/docs/NapierAMM.md)

### Pseudocode

[Pseudocode](https://github.com/Napier-Lab/v1-pool/tree/main/docs/pseudocode.md)

## Monitoring and Alerting Plan

Monitoring and alerting plan and tools

- Forta
  - Security alerts
- Tenderly

Automate smart contract operations

- OpenZeppelin Defender

# Alternative solutions

What alternatives did you consider? Describe the evaluation criteria for how you chose the proposed solution.

### Why not use a single contract for all PT+YT pairs?

- Pros
  - Easier to manage many PT and YT contracts.
- Cons
  - Debugging would be harder. Tranche contract holds all Target tokens for all PTs and YTs. (e.g. Compound DAI, Compound USDC, Aave DAI, Aave USDC, etc.)
    - It might be mitigated by storing Target token balance in Series struct.
  - A bug caused by one PT may affect other PTs in the same target asset.

### Why do we adopt ERC20 for PT and YT?

- Pros
  - More gas efficient than ERC20.
- Cons
  - ERC1155 is not supported by many wallets and portfolio services like debank.

### Why do we adopt ERC5095 for PT?

- Achieve developer experience.
- Composability with other DeFi protocols.

### Why contracts are not upgradable?

- Pros
  - Easier to iterate and deploy new contracts.
- Cons
  - DeFi ecosystem have seen many bugs in upgradable contracts.
    - Developers implement upgradable contracts in a wrong way. Storage layout collision, etc.
    - Developers implement upgradable contracts in a right way. But a bug is introduced by improper managements or at the time of deployment of upgrades. This is the case of Nomad Bridge hack, I think.
  - More runtime gas costs for users.

### Why should we have emergency stop mechanism?


## Success Criteria

**How will you validate the solution is working correctly?**

Describe what automated and/or manual testing you will do. Does this project need load or stress testing? This can also be a separate Testing Plan doc that is shared with QA, and linked here.

TBD

### Prioritization

# Milestones & Tasks

[Milestones](https://docs.google.com/spreadsheets/d/1Jp-6rKOMsBnAHZAP-4d3sxmZppMZcYuAAbyYO7ol2Dk/edit#gid=0)
