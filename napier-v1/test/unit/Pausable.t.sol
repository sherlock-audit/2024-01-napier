// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {IERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts@4.9.3/utils/Address.sol";
import {CompleteFixture} from "../Fixtures.sol";
import {Tranche, ITranche} from "src/Tranche.sol";
import {MockAdapter} from "../mocks/MockAdapter.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract TestPausable is CompleteFixture {
    /// @dev data for function calls
    struct CallData {
        address target; // target of the call
        bytes data; // encoded call data
        address caller; // caller of the function
    }

    /// @notice function calls to test
    /// @dev data is encoded call data.
    CallData[] functionCalls;

    function _setUpFunctionCalls() internal {
        address caller = address(this);
        functionCalls.push(CallData(address(tranche), abi.encodeCall(Tranche.issue, (caller, 10)), caller)); // prettier-ignore
        functionCalls.push(CallData(address(tranche), abi.encodeCall(Tranche.collect, ()), caller)); // prettier-ignore
        functionCalls.push(
            CallData(address(tranche), abi.encodeCall(Tranche.updateUnclaimedYield, (caller, caller, 10)), address(yt))
        ); // prettier-ignore
        functionCalls.push(CallData(address(yt), abi.encodeCall(IERC20.transfer, (caller, 10)), caller)); // prettier-ignore
        functionCalls.push(CallData(address(yt), abi.encodeCall(IERC20.transferFrom, (caller, caller, 10)), caller)); // prettier-ignore

        _approve(address(yt), caller, caller, type(uint256).max);
    }

    function setUp() public virtual override {
        _maturity = block.timestamp + 365 days;
        _tilt = 0;
        _issuanceFee = 100;
        _DELTA_ = 0;

        super.setUp();

        initialBalance = 1000 * ONE_SCALE;
        // fund tokens
        deal(address(underlying), address(this), initialBalance, true);
        underlying.approve(address(tranche), type(uint256).max);

        _setUpFunctionCalls();
    }

    function _deployAdapter() internal override {
        underlying = new MockERC20("Underlying", "U", 6);
        target = new MockERC20("Target", "T", 6);

        adapter = new MockAdapter(address(underlying), address(target));
    }

    function testPause_RevertWhenPaused() public {
        tranche.issue(address(this), 1000);
        // execution
        vm.prank(management);
        tranche.pause();
        // assertion
        assertEq(tranche.paused(), true);
        for (uint256 i; i < functionCalls.length; i++) {
            // basically expect revert before maturity is checked
            vm.warp(_maturity + 1);
            // assert revert message
            vm.expectRevert("Pausable: paused");
            vm.prank(functionCalls[i].caller);
            Address.functionCall(functionCalls[i].target, functionCalls[i].data);
        }
    }

    function testUnpause_NoRevert() public {
        vm.prank(management);
        tranche.pause();
        // execution
        vm.prank(management);
        tranche.unpause();
        assertEq(tranche.paused(), false);
        // assert no reverts
        tranche.issue(address(this), ONE_SCALE);
        tranche.collect();
        // warp to maturity
        vm.warp(_maturity + 1);
        for (uint256 i; i < functionCalls.length; i++) {
            // skip if issue function call (issue is not allowed after maturity)
            if (bytes4(functionCalls[i].data) == ITranche.issue.selector) continue;
            // skip if collect function call because YT is burned before testing YT transfer
            // and collect function call is already tested above
            if (bytes4(functionCalls[i].data) == ITranche.collect.selector) continue;
            // assert revert message
            vm.prank(functionCalls[i].caller);
            Address.functionCall(functionCalls[i].target, functionCalls[i].data);
        }
    }

    function testPause_RevertIfNotManagement() public {
        // pause
        vm.expectRevert(ITranche.Unauthorized.selector);
        tranche.pause();
        // unpause
        vm.expectRevert(ITranche.Unauthorized.selector);
        tranche.unpause();
    }

    function _simulateScaleIncrease() internal virtual override {}

    function _simulateScaleDecrease() internal virtual override {}
}
