// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {CompleteFixture} from "../Fixtures.sol";

abstract contract ScenarioBaseTest is CompleteFixture {
    function testIssues_Ok() public virtual {
        uint256 amount = 100 * ONE_SCALE;
        // issue twice
        _issue({from: address(this), to: address(this), underlyingAmount: amount / 2});
        uint256 halfIssued = _issue({from: address(this), to: address(this), underlyingAmount: amount / 2});

        // issue full amount
        deal(address(underlying), user, amount, true);
        uint256 issued = _issue({from: user, to: user, underlyingAmount: amount});

        assertApproxEqAbs(2 * halfIssued, issued, _DELTA_, "half issued");
        assertApproxEqAbs(tranche.balanceOf(address(this)), issued, _DELTA_, "tranche balance");
        assertEq(underlying.balanceOf(address(this)), initialBalance - amount, "user1 balance");
    }

    function testRedeemsWithYT_ScaleIncrease_Ok() public virtual {
        uint256 amount = 50 * ONE_SCALE;
        // issue 2x amount
        _issue({from: address(this), to: address(this), underlyingAmount: 2 * amount});
        // issue amount
        deal(address(underlying), user, amount, true);
        uint256 issued = _issue({from: user, to: user, underlyingAmount: amount});
        // scale increase
        _simulateScaleIncrease();
        // redeem half
        uint256 withdrawn1 = _redeemWithYT({
            from: address(this),
            to: address(this),
            amount: issued,
            caller: address(this)
        });
        // redeem full
        uint256 withdrawn2 = _redeemWithYT({from: user, to: user, amount: issued, caller: user});

        // if scale increases, there are a accrued yield.
        // address(this) should get more yield than user gets because address(this) has more YT.
        assertGe(withdrawn1, withdrawn2, "withdrawn1 >= withdrawn2");
    }

    function testRedeemsWithYT_ScaleDecrease_Ok() public virtual {
        uint256 amount = 50 * ONE_SCALE;
        // this issues
        _issue({from: address(this), to: address(this), underlyingAmount: 2 * amount});
        // user issues 2x amount
        deal(address(underlying), user, amount, true);
        uint256 issued = _issue({from: user, to: user, underlyingAmount: amount});
        // scale decrease
        _simulateScaleDecrease();
        // this redeems half
        uint256 withdrawn1 = _redeemWithYT({
            from: address(this),
            to: address(this),
            amount: issued,
            caller: address(this)
        });
        // user redeems same amount
        // underlying withdrawn should be same
        uint256 withdrawn2 = _redeemWithYT({from: user, to: user, amount: issued, caller: user});
        assertEq(withdrawn2, withdrawn1, "withdrawn1 == withdrawn2");
        // this redeems half again
        _redeemWithYT({from: address(this), to: address(this), amount: issued, caller: address(this)});
        // all underlying should be withdrawn.
        // the remaining amount should be all fees
        assertApproxEqAbs(
            target.balanceOf(address(tranche)),
            tranche.issuanceFees(),
            _DELTA_,
            "target balance should be equal to fee"
        );
    }

    function testCollects_BeforeMaturity_Ok() public virtual {
        _testCollects_Ok(uint32(_maturity - 1));
    }

    function testCollects_AfterMaturity_Ok() public virtual {
        _testCollects_Ok(uint32(_maturity));
    }

    function _testCollects_Ok(uint32 newTimestamp) public virtual {
        uint256 amount = 100 * ONE_SCALE;
        // this issues
        _issue({from: address(this), to: address(this), underlyingAmount: amount});
        // user issues 1/2 amount
        deal(address(underlying), user, amount / 2, true);
        _issue({from: user, to: user, underlyingAmount: amount / 2});

        _simulateScaleIncrease();

        vm.warp(newTimestamp);
        // collect yield + (principal portion if after maturity)
        (uint256 collected, ) = _collect(address(this));
        (uint256 collectedUser, ) = _collect(user);

        assertApproxEqAbs(collected, 2 * collectedUser, _DELTA_, "collected should be twice as much as user collected");
    }

    function testRedeems_Ok() public virtual {
        uint256 amount = 100 * ONE_SCALE;
        //(this)-> first user, (user)-> second user, (newOwner)->third user
        //first user issues with 100 * ONE_SCALE and other users issue with 50 * ONE_SCALE
        //first user uses collect() twice (before maturity, after maturity)
        //second user uses collect() once (after maturity he collect yield then redeem PT)
        //third user never use collect()  (after maturity, he redeems PT with YT)
        uint256 issued = _issue({from: address(this), to: address(this), underlyingAmount: amount});
        // user issues 1/2 amount
        deal(address(underlying), user, amount / 2, true);
        _issue({from: user, to: user, underlyingAmount: amount / 2});
        deal(address(underlying), newOwner, amount / 2, true);
        _issue({from: newOwner, to: newOwner, underlyingAmount: amount / 2});
        _simulateScaleIncrease(); // scale increase

        // collect yield only
        (uint256 yieldBeforeMaturity, ) = _collect(address(this));
        vm.warp(uint32(_maturity));
        _simulateScaleIncrease(); // scale increase
        (uint256 yieldAfterMaturity, ) = _collect(address(this));
        // redeem all PT
        uint256 redeemed = _redeem({
            from: address(this),
            to: address(this),
            principalAmount: issued,
            caller: address(this)
        });
        uint256 collected = yieldBeforeMaturity + yieldAfterMaturity;
        (uint256 yield, ) = _collect(user);
        uint256 yBal = yt.balanceOf(newOwner); // ~= issued / 2 (sometimes 1 wei less due to rounding error)
        // redeem all PT+YT
        uint256 withdrawn = _redeemWithYT({from: newOwner, to: newOwner, amount: yBal, caller: newOwner});
        assertApproxEqAbs(
            collected, // yield(before maturity) + yield(after maturity)
            2 * yield,
            _DELTA_,
            "total yield amount should not be changed"
        );
        assertApproxEqAbs(
            redeemed + _convertToUnderlying(collected, adapter.scale()),
            withdrawn * 2,
            _DELTA_ * 2,
            "sum of yield + principal portion + redeemed should be equal to 1 PT + 1 YT = 1 Target"
        );
    }

    function testTransferYT_Ok() public virtual {
        uint256 amount = 100 * ONE_SCALE;

        // this issues
        _issue({from: address(this), to: address(this), underlyingAmount: amount});
        // user issues 1/2 amount
        deal(address(underlying), user, amount / 2, true);
        uint256 issued = _issue({from: user, to: user, underlyingAmount: amount / 2});

        _simulateScaleIncrease();
        vm.prank(user);
        yt.transfer(address(this), issued);
        // uncalimed yield should be proportional to YT balance
        uint256 unclaimed = tranche.unclaimedYields(address(this));
        assertGt(unclaimed, 0, "unclaimed yield should be greater than 0");
        assertApproxEqAbs(
            unclaimed,
            2 * tranche.unclaimedYields(user),
            2,
            "uncalimed yield should be twice as much as user"
        );

        (uint256 collectedUser, ) = _collect(user);
        (uint256 collected, ) = _collect(address(this));
        assertApproxEqAbs(
            collected,
            2 * collectedUser,
            _DELTA_,
            "collected yield by this contract should be twice as much as one collected by user"
        );
        assertGt(collected, 0, "collected should be greater than 0");
        assertEq(tranche.unclaimedYields(address(this)), 0, "unclaimed yield should be 0 after collect");
        assertEq(tranche.unclaimedYields(user), 0, "unclaimed yield should be 0 after collect");
    }
}

abstract contract ScenarioLSTBaseTest is ScenarioBaseTest {
    address charlie = makeAddr("charlie");

    function testRedeemsWithYT_ScaleIncrease_Ok() public override {
        deal(address(underlying), charlie, 1_000 * ONE_SCALE, false);
        _issue({from: charlie, to: charlie, underlyingAmount: 1_000 * ONE_SCALE});

        super.testRedeemsWithYT_ScaleIncrease_Ok();
    }

    function testRedeemsWithYT_ScaleDecrease_Ok() public override {
        // note: ensure that LST adapter has enough available eth
        // deposit large amount of eth to LST adapter
        deal(address(underlying), charlie, 1_000 * ONE_SCALE, false);
        _issue({from: charlie, to: charlie, underlyingAmount: 1_000 * ONE_SCALE});

        // See ScenarioBaseTest.testRedeemsWithYT_ScaleDecrease_Ok

        uint256 amount = 2 * ONE_SCALE;
        // this issues
        _issue({from: address(this), to: address(this), underlyingAmount: 2 * amount});
        // user issues 2x amount
        deal(address(underlying), user, amount, true);
        uint256 issued = _issue({from: user, to: user, underlyingAmount: amount});
        // scale decrease
        _simulateScaleDecrease();

        // this redeems half
        uint256 withdrawn1 = _redeemWithYT({
            from: address(this),
            to: address(this),
            amount: issued,
            caller: address(this)
        });
        // user redeems same amount
        // underlying withdrawn should be same
        uint256 withdrawn2 = _redeemWithYT({from: user, to: user, amount: issued, caller: user});
        assertEq(withdrawn2, withdrawn1, "withdrawn1 == withdrawn2");

        // this redeems half again
        _redeemWithYT({from: address(this), to: address(this), amount: issued, caller: address(this)});
    }

    function _testCollects_Ok(uint32 newTimestamp) public override {
        // note: ensure that LST adapter has enough available eth
        // deposit large amount of eth to LST adapter
        deal(address(underlying), charlie, 10_000 * ONE_SCALE, false);
        _issue({from: charlie, to: charlie, underlyingAmount: 10_000 * ONE_SCALE});

        super._testCollects_Ok(newTimestamp);
    }

    function testRedeems_Ok() public override {
        // note: ensure that LST adapter has enough available eth
        // deposit large amount of eth to LST adapter
        deal(address(underlying), charlie, 10_000 * ONE_SCALE, false);
        _issue({from: charlie, to: charlie, underlyingAmount: 10_000 * ONE_SCALE});

        super.testRedeems_Ok();
    }
}
