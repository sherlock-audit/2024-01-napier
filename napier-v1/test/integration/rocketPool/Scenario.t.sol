// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../ScenarioBaseTest.t.sol";
import {RETHFixture} from "./Fixture.sol";

contract TestRETHScenario is ScenarioBaseTest, RETHFixture {
    function setUp() public override(CompleteFixture, RETHFixture) {
        RETHFixture.setUp();
    }

    function deal(
        address token,
        address to,
        uint256 give,
        bool adjust
    ) internal virtual override(StdCheats, RETHFixture) {
        RETHFixture.deal(token, to, give, adjust);
    }
}
