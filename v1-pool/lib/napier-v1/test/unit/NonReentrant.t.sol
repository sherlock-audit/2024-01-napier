// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {CompleteFixture} from "../Fixtures.sol";
import {Tranche, ITranche} from "src/Tranche.sol";
import {BaseAdapter, MockFaultyAdapter} from "../mocks/MockFaultyAdapter.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract TestNonReentrant is CompleteFixture {
    using Cast for *;

    /// @dev data for function calls
    struct CallData {
        bytes data; // encoded call data
        address caller; // caller of the function
        bytes revertMessage; // expected revert message
    }

    /// @notice function calls to test
    /// @dev data is encoded call data.
    CallData[] functionCalls;

    CallData[] mutativeCalls;
    CallData[] viewCalls;

    function _setUpFunctionCalls() internal {
        address caller = address(this);
        // non-view functions
        bytes memory reentrancyRevertMsg = bytes("ReentrancyGuard: reentrant call");
        mutativeCalls.push(CallData(abi.encodeCall(Tranche.issue, (caller, 10)), caller, reentrancyRevertMsg)); // prettier-ignore
        mutativeCalls.push(CallData(abi.encodeCall(Tranche.redeem, (10, caller, caller)), caller, reentrancyRevertMsg)); // prettier-ignore
        mutativeCalls.push(CallData(abi.encodeCall(Tranche.collect, ()), caller, reentrancyRevertMsg)); // prettier-ignore
        mutativeCalls.push(
            CallData(abi.encodeCall(Tranche.withdraw, (10, caller, caller)), caller, reentrancyRevertMsg)
        ); // prettier-ignore
        mutativeCalls.push(
            CallData(abi.encodeCall(Tranche.redeemWithYT, (caller, caller, 10)), caller, reentrancyRevertMsg)
        ); // prettier-ignore
        // view functions
        bytes memory viewReentrancyRevertMsg = abi.encodeWithSelector(ITranche.ReentrancyGuarded.selector);
        viewCalls.push(CallData(abi.encodeCall(Tranche.maxWithdraw, (caller)), address(0), viewReentrancyRevertMsg)); // prettier-ignore
        viewCalls.push(CallData(abi.encodeCall(Tranche.maxRedeem, (caller)), address(0), viewReentrancyRevertMsg)); // prettier-ignore
        viewCalls.push(CallData(abi.encodeCall(Tranche.convertToUnderlying, (10)), address(0), viewReentrancyRevertMsg)); // prettier-ignore
        viewCalls.push(CallData(abi.encodeCall(Tranche.convertToPrincipal, (10)), address(0), viewReentrancyRevertMsg)); // prettier-ignore
        viewCalls.push(CallData(abi.encodeCall(Tranche.previewRedeem, (10)), address(0), viewReentrancyRevertMsg)); // prettier-ignore
        viewCalls.push(CallData(abi.encodeCall(Tranche.previewWithdraw, (10)), address(0), viewReentrancyRevertMsg)); // prettier-ignore
        viewCalls.push(CallData(abi.encodeCall(Tranche.getSeries, ()), address(0), viewReentrancyRevertMsg)); // prettier-ignore
        viewCalls.push(CallData(abi.encodeCall(Tranche.getGlobalScales, ()), address(0), viewReentrancyRevertMsg)); // prettier-ignore

        for (uint256 i; i < mutativeCalls.length; i++) {
            functionCalls.push(mutativeCalls[i]);
        }
        for (uint256 i; i < viewCalls.length; i++) {
            functionCalls.push(viewCalls[i]);
        }
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
        _approve(address(underlying), address(this), address(tranche), type(uint256).max);

        _setUpFunctionCalls();
    }

    function _deployAdapter() internal override {
        underlying = new MockERC20("Underlying", "U", 6);
        target = new MockERC20("Target", "T", 6);

        adapter = new MockFaultyAdapter(address(underlying), address(target));
    }

    function test_RevertIfReentered() public {
        tranche.issue(address(this), 100);

        for (uint256 i; i < functionCalls.length; i++) {
            for (uint256 j; j < mutativeCalls.length; j++) {
                testReentrancy(
                    address(tranche),
                    mutativeCalls[j].data,
                    functionCalls[i].data,
                    functionCalls[i].revertMessage
                );
            }
        }
    }

    function testReentrancy(
        address target,
        bytes memory data,
        bytes memory reentrancyCalldata,
        bytes memory revertReason
    ) internal {
        {
            bytes4 selector = bytes4(data);
            // some functions are callable only before or after maturity
            if (selector == Tranche.issue.selector) {
                vm.warp(_maturity - 1);
            }
            if (selector == Tranche.redeem.selector || selector == Tranche.withdraw.selector) {
                vm.warp(_maturity + 1);
            }
        }
        {
            bytes4 rselector = bytes4(reentrancyCalldata);
            // some functions are callable only before or after maturity
            // if reentered function doesn't have same maturity check,
            // we would ignore the revert
            if (_isMatured() && rselector == Tranche.issue.selector) return;
            if (!_isMatured() && (rselector == Tranche.redeem.selector || rselector == Tranche.withdraw.selector)) {
                return;
            }
            // Edge case:
            // max* and preview* functions can be reentered *before* maturity*
            // because they always consistently return zero before maturity.
            // Here skip the test if the function is max* or preview* and the tranche is matured.
            if (
                !_isMatured() &&
                (rselector == Tranche.maxWithdraw.selector ||
                    rselector == Tranche.maxRedeem.selector ||
                    rselector == Tranche.previewRedeem.selector ||
                    rselector == Tranche.previewWithdraw.selector)
            ) return;
        }
        adapter.asMock().setReentrancyCall(reentrancyCalldata, true);
        vm.expectRevert(revertReason);
        this.extcall(target, data);
    }

    function extcall(address target, bytes memory data) external returns (bool s, bytes memory returndata) {
        if (bytes4(data) == Tranche.updateUnclaimedYield.selector) vm.prank(address(yt));
        (s, returndata) = target.call(data);
        if (!s) bubbleUpRevert(returndata);
    }

    function bubbleUpRevert(bytes memory returndata) internal pure {
        // Taken from: Openzeppelinc Address.sol
        // The easiest way to bubble the revert reason is using memory via assembly
        /// @solidity memory-safe-assembly
        assembly {
            let returndata_size := mload(returndata)
            revert(add(32, returndata), returndata_size)
        }
    }

    function _simulateScaleIncrease() internal virtual override {}

    function _simulateScaleDecrease() internal virtual override {}
}

library Cast {
    function asMock(BaseAdapter adapter) internal pure returns (MockFaultyAdapter mock) {
        assembly {
            mock := adapter
        }
    }
}
