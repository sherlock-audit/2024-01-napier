// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ScenarioLSTBaseTest} from "../ScenarioBaseTest.t.sol";
import {CompleteFixture} from "../../Fixtures.sol";
import {SFrxETHFixture} from "./Fixture.sol";

contract TestFraxEtherScenario is ScenarioLSTBaseTest, SFrxETHFixture {
    function setUp() public override(CompleteFixture, SFrxETHFixture) {
        SFrxETHFixture.setUp();
        _DELTA_ = 10;
    }

    function deal(
        address token,
        address to,
        uint256 give,
        bool adjust
    ) internal virtual override(StdCheats, SFrxETHFixture) {
        SFrxETHFixture.deal(token, to, give, adjust);
    }
}
