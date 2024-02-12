// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {IRocketDepositPool} from "src/adapters/rocketPool/interfaces/IRocketDepositPool.sol";
import {IRocketStorage} from "src/adapters/rocketPool/interfaces/IRocketStorage.sol";
import {IRocketTokenRETH} from "src/adapters/rocketPool/interfaces/IRocketTokenRETH.sol";
import {IRocketDAOProtocolSettingsDeposit} from "src/adapters/rocketPool/interfaces/IRocketDAOProtocolSettingsDeposit.sol";
import {WETH, RETH, WAD} from "src/Constants.sol";

library RocketPoolHelper {
    using stdStorage for StdStorage;

    /// @notice Rocket Pool Address storage https://www.codeslaw.app/contracts/ethereum/0x1d8f8f00cfa6758d7be78336684788fb0ee0fa46
    address constant ROCKET_STORAGE = 0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46;

    /// @notice Rocket Pool RETH total supply storage key in RocketStorage
    bytes32 constant ROCKET_NETWORK_RETH_TOTAL_SUPPLY_STORAGE_KEY = keccak256("network.balance.reth.supply");

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function getTotalRETHSupply() internal returns (uint256) {
        // stdstore.target(ROCKET_STORAGE).sig("getUint(bytes32)").with_key(ROCKET_NETWORK_RETH_TOTAL_SUPPLY_STORAGE_KEY).checked_write(newSupply);
        (bool s, bytes memory returndata) = ROCKET_STORAGE.call(
            abi.encodeWithSelector(IRocketStorage.getUint.selector, ROCKET_NETWORK_RETH_TOTAL_SUPPLY_STORAGE_KEY)
        );
        if (!s) {
            _revert(returndata);
        }
        return abi.decode(returndata, (uint256));
    }

    /// cheat code to override the total supply of RETH
    /// @param stdstore The storage object
    /// @param newSupply The value to set the total supply to
    function writeTotalRETHSupply(StdStorage storage stdstore, uint256 newSupply) internal {
        // rETH total supply is stored in RocketStorage and in the rETH contract itself
        // we need to update both
        // update the total supply in the RocketStorage
        // https://github.com/rocket-pool/rocketpool/blob/9710596d82189c54f0dc35be3501cda13a155f4d/contracts/contract/token/RocketTokenRETH.sol#L39-L47
        // https://github.com/rocket-pool/rocketpool/blob/9710596d82189c54f0dc35be3501cda13a155f4d/contracts/contract/network/RocketNetworkBalances.sol#LL56C1-L58C6

        // the total supply is stored in mapping(bytes32 => uint256)
        stdstore
            .target(ROCKET_STORAGE)
            .sig(IRocketStorage.getUint.selector)
            .with_key(ROCKET_NETWORK_RETH_TOTAL_SUPPLY_STORAGE_KEY)
            .checked_write(newSupply);
        // update the total supply in the rETH contract
        stdstore.target(RETH).sig(0x18160ddd).checked_write(newSupply);
    }

    /// @dev Get the address of a network contract by name
    /// Taken from RocketBase.sol
    function getRocketPoolModuleAddress(string memory _contractName) internal view returns (address) {
        // Get the current contract address
        address contractAddress = IRocketStorage(ROCKET_STORAGE).getAddress(
            keccak256(abi.encodePacked("contract.address", _contractName))
        );
        require(contractAddress != address(0x0), "Contract not found");
        return contractAddress;
    }

    ///  @dev Get the Rocket Pool deposit fee for a given value of ETH
    /// @param value The value to calculate the fee for
    /// Copied from RocketDepositPool.sol https://github.com/rocket-pool/rocketpool/blob/9710596d82189c54f0dc35be3501cda13a155f4d/contracts/contract/deposit/RocketDepositPool.sol#L119
    function getDepositFee(uint256 value) internal view returns (uint256) {
        // Rocket Pool Deposit Pool settings contract
        IRocketDAOProtocolSettingsDeposit rpDAOSettings = IRocketDAOProtocolSettingsDeposit(
            getRocketPoolModuleAddress("rocketDAOProtocolSettingsDeposit")
        );

        return (value * rpDAOSettings.getDepositFee()) / WAD;
    }

    function _revert(bytes memory returndata) internal pure {
        // Taken from: Openzeppelinc Address.sol
        // The easiest way to bubble the revert reason is using memory via assembly
        /// @solidity memory-safe-assembly
        assembly {
            let returndata_size := mload(returndata)
            revert(add(32, returndata), returndata_size)
        }
    }
}
