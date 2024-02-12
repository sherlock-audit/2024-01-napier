// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {console2, StdAssertions} from "forge-std/Test.sol";

import {BaseHandler} from "./BaseHandler.sol";

import {MockAdapter} from "test/mocks/MockAdapter.sol";
import {TimestampStore} from "../TimestampStore.sol";

import {Math} from "@openzeppelin/contracts@4.9.3/utils/math/Math.sol";

contract AdapterHandler is BaseHandler {
    MockAdapter adapter;

    constructor(MockAdapter _adapter, TimestampStore _timestampStore) {
        adapter = _adapter;
        timestampStore = _timestampStore;
    }

    function scale(uint256 timeJumpSeed, uint256 _scale) external adjustTimestamp(timeJumpSeed) countCall("scale") {
        uint256 cscale = adapter.scale();
        // set the scale between 97% and 107% of the current scale.
        _scale = _bound(_scale, (cscale * 97) / 100, (cscale * 107) / 100);
        adapter.setScale(_scale);
    }

    function callSummary() public view override {
        console2.log("scale:", calls["scale"]);
    }
}
