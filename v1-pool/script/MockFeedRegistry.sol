// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import {Ownable2Step} from "@openzeppelin/contracts@4.9.3/access/Ownable2Step.sol";

interface Aggregator {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function decimals() external view returns (uint8);
}

contract MockFeedRegistry is Ownable2Step {
    mapping(address => mapping(address => address)) private feeds;

    constructor() {
        // address of MockWeth on sepolia testnet
        address weth = 0xbCAA64446aE2f06Ad8cFB5b0500C842Eb23d2A70;
        // A Denominations.USD address (0x348), which is based on ISO 4217
        address usd = address(0x348);
        // add ETH/USD price feed address on sepolia testnet
        feeds[usd][weth] = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    }

    function latestRoundData(address base, address quote)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        Aggregator aggregator = Aggregator(feeds[base][quote]);
        require(address(aggregator) != address(0), "Feed not found");
        (roundId, answer, startedAt, updatedAt, answeredInRound) = aggregator.latestRoundData();
    }

    function setFeed(address base, address quote, address newAggregator) external onlyOwner {
        feeds[base][quote] = newAggregator;
    }

    function decimals(address base, address quote) external view returns (uint8) {
        Aggregator aggregator = Aggregator(feeds[base][quote]);
        return aggregator.decimals();
    }
}

contract MockFeedRegistryDeploy is Script {
    function run() public {
        vm.startBroadcast();
        MockFeedRegistry feedRegistry = new MockFeedRegistry();
        vm.stopBroadcast();

        console2.log("FeedRegistry=%s", address(feedRegistry));
    }
}
