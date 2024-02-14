
# Napier contest details

- Join [Sherlock Discord](https://discord.gg/MABEWyASkp)
- Submit findings using the issue page in your private contest repo (label issues as med or high)
- [Read for more details](https://docs.sherlock.xyz/audits/watsons)

# Q&A

### Q: On what chains are the smart contracts going to be deployed?
Mainnet
___

### Q: Which ERC20 tokens do you expect will interact with the smart contracts? 
any
___

### Q: Which ERC721 tokens do you expect will interact with the smart contracts? 
Lido unstake NFT and Frax unstake NFT
___

### Q: Do you plan to support ERC1155?
No
___

### Q: Which ERC777 tokens do you expect will interact with the smart contracts? 
None
___

### Q: Are there any FEE-ON-TRANSFER tokens interacting with the smart contracts?

None
___

### Q: Are there any REBASING tokens interacting with the smart contracts?

stETH
___

### Q: Are the admins of the protocols your contracts integrate with (if any) TRUSTED or RESTRICTED?
RESTRICTED
___

### Q: Is the admin/owner of the protocol/contracts TRUSTED or RESTRICTED?
RESTRICTED
___

### Q: Are there any additional protocol roles? If yes, please explain in detail:
Owner: An account can deploy new pool and new Tranche (Principal Token), authorize callback receiver.
Rebalancer: An account can manage adapter and request withdrawal for liquid staking tokens. It can't steal funds.

___

### Q: Is the code/contract expected to comply with any EIPs? Are there specific assumptions around adhering to those EIPs that Watsons should be aware of?
EIP20 and IERC5095
___

### Q: Please list any known issues/acceptable risks that should not result in a valid finding.
napier-v1 repo
- We are aware that depositing tokens in advance into adapters can manipulate a parameter in events such as `Issue` . There shouldn't be any financial losses.
- According to Invariant testing, balances in Tranche can be less than issuance fees in accounting in underlying assets in some cases (We found there may be a slight insolvency in some cases).

v1-pool repo
1. 
2. **Cross-contract Reentrancy**
    1. Attack scenario: The current Tricrypto implementation exchange method with a callback, allowing an malicious user to reenter the Napier exchange method and let Tricrypto return manipulated value. 
    2. Solution: We think it’s impossible to fix this issue on our side. Curve team is working on new version of Tricrypto, which removes callback method that can cause kinds of reentrancy. We heard the new version is in audit stage. See [here](https://github.com/Napier-Lab/v1-pool/blob/7357c0c543b6b87ae09dad8337ae03644a49b486/test/unit/pool/TricryptoReentrancy.t.sol#L77-L79) and [here](https://github.com/Napier-Lab/v1-pool/issues/105) for more details. As a mitigation, only authorized caller can call NapierPool swap method.
3. **Removing tons of liquidity at once and burning most of total supply.**
    1. Property: `NapierPool.removeLiquidity` shouldn't change proportion of reserves. 
    2. Issue: When a user burn most of total supply of LP token, proportion of reserves can change. 
        1. https://github.com/Napier-Lab/v1-pool/issues/80
        2. https://github.com/napierfi/v1-pool/blob/1df5198c5844c7fab050b57f57289435aabcdf43/test/fuzz/pool/Liquidity.t.sol#L76
    3. **Solution: We haven’t found a solution but we think it wouldn’t cause critical issue. We want to make sure this wouldn’t be an security issue.**

___

### Q: Are there any off-chain mechanisms or off-chain procedures for the protocol (keeper bots, input validation expectations, etc)?
No
___

### Q: In case of external protocol integrations, are the risks of external contracts pausing or executing an emergency withdrawal acceptable? If not, Watsons will submit issues related to these situations that can harm your protocol's functionality.
External contracts pausing or executing an emergency withdrawal are acceptable. Issues regarding Lido being paused would be invalid.
___

### Q: Do you expect to use any of the following tokens with non-standard behaviour with the smart contracts?
None
___

### Q: Add links to relevant protocol resources
https://napier-labs.notion.site/Documents-for-security-reviewers-68fea90ca1d34d828a420fba0aae0c88?pvs=4
___



# Audit scope


[v1-pool @ 96689573e363667d920d59aa890b7b1f7418f4e8](https://github.com/napierfi/v1-pool/tree/96689573e363667d920d59aa890b7b1f7418f4e8)
- [v1-pool/src/NapierPool.sol](v1-pool/src/NapierPool.sol)
- [v1-pool/src/NapierRouter.sol](v1-pool/src/NapierRouter.sol)
- [v1-pool/src/PoolFactory.sol](v1-pool/src/PoolFactory.sol)
- [v1-pool/src/TrancheRouter.sol](v1-pool/src/TrancheRouter.sol)
- [v1-pool/src/base/Multicallable.sol](v1-pool/src/base/Multicallable.sol)
- [v1-pool/src/base/PeripheryImmutableState.sol](v1-pool/src/base/PeripheryImmutableState.sol)
- [v1-pool/src/base/PeripheryPayments.sol](v1-pool/src/base/PeripheryPayments.sol)
- [v1-pool/src/libs/CallbackDataTypes.sol](v1-pool/src/libs/CallbackDataTypes.sol)
- [v1-pool/src/libs/Constants.sol](v1-pool/src/libs/Constants.sol)
- [v1-pool/src/libs/Create2PoolLib.sol](v1-pool/src/libs/Create2PoolLib.sol)
- [v1-pool/src/libs/DecimalConversion.sol](v1-pool/src/libs/DecimalConversion.sol)
- [v1-pool/src/libs/Errors.sol](v1-pool/src/libs/Errors.sol)
- [v1-pool/src/libs/PoolAddress.sol](v1-pool/src/libs/PoolAddress.sol)
- [v1-pool/src/libs/PoolMath.sol](v1-pool/src/libs/PoolMath.sol)
- [v1-pool/src/libs/SignedMath.sol](v1-pool/src/libs/SignedMath.sol)
- [v1-pool/src/libs/TrancheAddress.sol](v1-pool/src/libs/TrancheAddress.sol)

[napier-v1 @ 31892e6ffecff018f2da25a45705857e509e0e11](https://github.com/napierfi/napier-v1/tree/31892e6ffecff018f2da25a45705857e509e0e11)
- [napier-v1/src/BaseAdapter.sol](napier-v1/src/BaseAdapter.sol)
- [napier-v1/src/BaseToken.sol](napier-v1/src/BaseToken.sol)
- [napier-v1/src/Constants.sol](napier-v1/src/Constants.sol)
- [napier-v1/src/Create2TrancheLib.sol](napier-v1/src/Create2TrancheLib.sol)
- [napier-v1/src/Tranche.sol](napier-v1/src/Tranche.sol)
- [napier-v1/src/TrancheFactory.sol](napier-v1/src/TrancheFactory.sol)
- [napier-v1/src/YieldToken.sol](napier-v1/src/YieldToken.sol)
- [napier-v1/src/adapters/BaseLSTAdapter.sol](napier-v1/src/adapters/BaseLSTAdapter.sol)
- [napier-v1/src/adapters/frax/SFrxETHAdapter.sol](napier-v1/src/adapters/frax/SFrxETHAdapter.sol)
- [napier-v1/src/adapters/frax/interfaces/IFraxEtherRedemptionQueue.sol](napier-v1/src/adapters/frax/interfaces/IFraxEtherRedemptionQueue.sol)
- [napier-v1/src/adapters/frax/interfaces/IFrxETHMinter.sol](napier-v1/src/adapters/frax/interfaces/IFrxETHMinter.sol)
- [napier-v1/src/adapters/lido/StEtherAdapter.sol](napier-v1/src/adapters/lido/StEtherAdapter.sol)
- [napier-v1/src/adapters/lido/interfaces/IStETH.sol](napier-v1/src/adapters/lido/interfaces/IStETH.sol)
- [napier-v1/src/adapters/lido/interfaces/IWithdrawalQueueERC721.sol](napier-v1/src/adapters/lido/interfaces/IWithdrawalQueueERC721.sol)
- [napier-v1/src/adapters/lido/interfaces/IWstETH.sol](napier-v1/src/adapters/lido/interfaces/IWstETH.sol)
- [napier-v1/src/interfaces/IBaseAdapter.sol](napier-v1/src/interfaces/IBaseAdapter.sol)
- [napier-v1/src/interfaces/IBaseToken.sol](napier-v1/src/interfaces/IBaseToken.sol)
- [napier-v1/src/interfaces/IERC5095.sol](napier-v1/src/interfaces/IERC5095.sol)
- [napier-v1/src/interfaces/ITranche.sol](napier-v1/src/interfaces/ITranche.sol)
- [napier-v1/src/interfaces/ITrancheFactory.sol](napier-v1/src/interfaces/ITrancheFactory.sol)
- [napier-v1/src/interfaces/IWETH9.sol](napier-v1/src/interfaces/IWETH9.sol)
- [napier-v1/src/interfaces/IYieldTier.sol](napier-v1/src/interfaces/IYieldTier.sol)
- [napier-v1/src/interfaces/IYieldToken.sol](napier-v1/src/interfaces/IYieldToken.sol)
