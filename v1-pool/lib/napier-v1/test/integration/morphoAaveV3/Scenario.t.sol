// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../ScenarioBaseTest.t.sol";
import {MorphoFixture} from "./Fixture.sol";

contract TestMorphoScenario is ScenarioBaseTest, MorphoFixture {
    function setUp() public override(CompleteFixture, MorphoFixture) {
        MorphoFixture.setUp();
    }

    function deal(
        address token,
        address to,
        uint256 give,
        bool adjust
    ) internal virtual override(StdCheats, MorphoFixture) {
        MorphoFixture.deal(token, to, give, adjust);
    }
}
