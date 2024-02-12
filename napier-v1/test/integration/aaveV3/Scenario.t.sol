// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../ScenarioBaseTest.t.sol";
import {AAVEFixture} from "./Fixture.sol";

contract TestAAVEScenario is ScenarioBaseTest, AAVEFixture {
    function setUp() public override(CompleteFixture, AAVEFixture) {
        AAVEFixture.setUp();
    }

    function deal(
        address token,
        address to,
        uint256 give,
        bool adjust
    ) internal virtual override(StdCheats, AAVEFixture) {
        AAVEFixture.deal(token, to, give, adjust);
    }
}
