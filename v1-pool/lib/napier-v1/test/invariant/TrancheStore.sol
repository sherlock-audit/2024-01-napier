// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "forge-std/StdCheats.sol";
import "forge-std/StdUtils.sol";

import {EnumerableSet} from "@openzeppelin/contracts@4.9.3/utils/structs/EnumerableSet.sol";

contract TrancheStore is StdCheats, StdUtils {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 private constant WAD = 1e18;
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @dev PT and YT recipients.
    EnumerableSet.AddressSet recipients;

    function getRecipients() external view returns (address[] memory) {
        return recipients.values();
    }

    function getRecipient(uint256 actorIndexSeed) external view returns (address) {
        uint256 length = recipients.length();
        if (length == 0) {
            return address(0);
        }
        return recipients.at(_bound(actorIndexSeed, 0, length - 1));
    }

    function addRecipient(address recipient) external {
        recipients.add(recipient);
    }
}
