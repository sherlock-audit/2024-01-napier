// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "forge-std/StdUtils.sol";

import {EnumerableSet} from "@openzeppelin/contracts@4.9.3/utils/structs/EnumerableSet.sol";

contract RecipientsStore is StdUtils {
    using EnumerableSet for EnumerableSet.AddressSet;

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
