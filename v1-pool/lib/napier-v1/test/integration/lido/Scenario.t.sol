// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ScenarioLSTBaseTest} from "../ScenarioBaseTest.t.sol";
import {CompleteFixture} from "../../Fixtures.sol";
import {StEtherFixture} from "./Fixture.sol";

contract TestStEtherScenario is ScenarioLSTBaseTest, StEtherFixture {
    function setUp() public override(CompleteFixture, StEtherFixture) {
        StEtherFixture.setUp();
        _DELTA_ = 10;
    }

    function deal(
        address token,
        address to,
        uint256 give,
        bool adjust
    ) internal virtual override(StdCheats, StEtherFixture) {
        StEtherFixture.deal(token, to, give, adjust);
    }
}
