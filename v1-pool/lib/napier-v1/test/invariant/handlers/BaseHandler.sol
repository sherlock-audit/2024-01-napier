// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {TimestampStore} from "../TimestampStore.sol";
import {TrancheStore} from "../TrancheStore.sol";

abstract contract BaseHandler is CommonBase, StdCheats, StdUtils {
    /// @dev A mapping from function names to the number of times they have been called.
    mapping(bytes32 => uint256) public calls;

    /// @dev Reference to the timestamp store, which is needed for simulating the passage of time.
    TimestampStore timestampStore;
    TrancheStore trancheStore;

    address internal currentSender;

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    /// @dev Simulates the passage of time. The time jump is upper bounded so that principal token don't settle too quickly.
    /// See https://github.com/foundry-rs/foundry/issues/4994.
    /// @param timeJumpSeed A fuzzed value needed for generating random time warps.
    modifier adjustTimestamp(uint256 timeJumpSeed) {
        uint256 timeJump = _bound(timeJumpSeed, 2 minutes, 40 days);
        timestampStore.increaseCurrentTimestamp(timeJump);
        vm.warp(timestampStore.currentTimestamp());
        _;
    }

    /// @dev Checks user assumption.
    modifier checkActor(address actor) {
        // Protocol doesn't allow the zero address to be a user.
        // Prevent the contract itself from playing the role of any user.
        if (actor == address(0) || actor == address(this)) {
            return;
        }

        _;
    }

    /// @dev Makes the provided sender the caller.
    modifier useSender(address actor) {
        if (actor == address(0) || actor == address(this)) {
            return;
        }
        currentSender = actor;
        vm.startPrank(actor);
        _;
        vm.stopPrank();
    }

    function callSummary() public view virtual;
}
