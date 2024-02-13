// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../ScenarioBaseTest.t.sol";
import {CETHFixture} from "./Fixture.sol";

contract TestCompoundScenario is ScenarioBaseTest, CETHFixture {
    function setUp() public override(CompleteFixture, CETHFixture) {
        CETHFixture.setUp();
    }

    function deal(
        address token,
        address to,
        uint256 give,
        bool adjust
    ) internal virtual override(StdCheats, CETHFixture) {
        CETHFixture.deal(token, to, give, adjust);
    }
}
