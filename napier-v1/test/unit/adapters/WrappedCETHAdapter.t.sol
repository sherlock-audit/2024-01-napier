// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {BaseTestAdapter} from "./BaseTestAdapter.t.sol";

import {WrappedCETHAdapter} from "src/adapters/compoundV2/WrappedCETHAdapter.sol";
import {CompoundV2BaseAdapter} from "src/adapters/compoundV2/CompoundV2BaseAdapter.sol";

import {IBaseAdapter} from "src/interfaces/IBaseAdapter.sol";
import {ERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";
import {IWETH9} from "src/interfaces/IWETH9.sol";
import {ICETHToken} from "src/adapters/compoundV2/interfaces/ICETHToken.sol";
import {ICToken} from "src/adapters/compoundV2/interfaces/ICToken.sol";
import {CETH, WETH, COMP, COMPTROLLER} from "src/Constants.sol";

contract TestWrappedCETHAdapter is BaseTestAdapter {
    using Cast for *;
    uint256 constant FORKED_AT = 17_230_000;

    uint256 constant WETHBalanceBefore = 100;
    uint256 constant CETHBalanceBefore = 100;

    function setUp() public override {
        vm.createSelectFork("mainnet", FORKED_AT);
        super.setUp();
        _fundUser();
        testAdapterHasNoFundLeft();
    }

    function _fundUser() internal {}

    function _deployAdapter() internal override {
        vm.prank(owner);
        adapter = new WrappedCETHAdapter(address(0xABCD));
        underlying = ERC20(WETH);
        target = ERC20(address(adapter));
    }

    function testAdapterHasNoFundLeft() internal override {
        // make sure that the adapter's balance is zero prior to any function call in the tests
        assertEq(underlying.balanceOf(address(adapter)), 0, "adapter is expected to have no WETH left, but has some");
        assertEq(address(adapter).balance, 0, "adapter is expected to have no WETH left, but has some");
        assertEq(target.balanceOf(address(adapter)), 0, "adapter is expected to have no CETH left, but has some");
    }

    function _fundAdapterUnderlying(uint256 fundedAmount) internal {
        deal(WETH, address(adapter), fundedAmount, false);
    }

    function _fundAdapterTarget(uint256 fundedAmount) internal {
        deal(address(adapter), address(adapter), fundedAmount);
        deal(CETH, address(adapter), fundedAmount);
    }

    function testImmutableVariables() public {
        assertEq(adapter.underlying(), WETH, "underlying should be WETH");
        assertEq(adapter.target(), address(adapter), "target is adapter itself");
    }

    function testDecimal() public {
        assertEq(8, adapter.toCETHAdapter().decimals(), "WCETH decimals != 8");
    }

    function testChangeRewardRecipient_Ok() public {
        vm.prank(owner);
        adapter.toCETHAdapter().changeRewardRecipient(address(0x1234));
    }

    function testChangeRewardRecipient_RevertIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        adapter.toCETHAdapter().changeRewardRecipient(address(0x5678));
    }

    function testPrefundedDeposit() public override {
        // 0) transfer WETH to the adapter contract prior as it would be done by Tranche
        uint256 WETHFundedAmount = WETHBalanceBefore;
        _fundAdapterUnderlying(WETHFundedAmount);

        // 1) call prefundedDeposit to wrap to CETH, and check expected return amount
        uint256 expectedCETHMinted = (WETHFundedAmount * 1e18) / adapter.scale();
        vm.prank(user);
        (uint256 underlyingUsed, uint256 sharesMinted) = adapter.prefundedDeposit();
        assertApproxEqAbs(
            WETHFundedAmount,
            underlyingUsed,
            2,
            "user provided WETH amount !~= actual WETH used on prefundedDeposit()"
        );
        assertEq(sharesMinted, expectedCETHMinted, "actual CETH minted !~= expected CETH minted on prefundedDeposit()");

        // 2) check that CETH is successfully minted
        testAdapterHasNoFundLeft();
        assertEq(target.balanceOf(user), sharesMinted, "balanceOfUser !~= expectedCETHBalanceAfter");
    }

    function testPrefundedRedeemFailed() public {
        uint256 CETHFundedAmount = CETHBalanceBefore;
        _fundAdapterTarget(CETHFundedAmount);
        vm.mockCall(address(CETH), abi.encodeWithSelector(ICToken.redeem.selector), abi.encode(1));
        vm.prank(user);
        vm.expectRevert(CompoundV2BaseAdapter.RedeemFailed.selector);
        adapter.prefundedRedeem(user);
    }

    function testPrefundedRedeem() public override {
        // 0) transfer CETH and WCETH to the adapter contract prior as it would be done by Tranche
        uint256 CETHFundedAmount = CETHBalanceBefore;
        _fundAdapterTarget(CETHFundedAmount);

        // 1) call prefundedRedeem to unwrap CETH to WETH, and check expected return amount
        (uint256 amountWithdrawn, uint256 sharesRedeemed) = adapter.prefundedRedeem(user);
        uint256 expectedWETHRedeemed = (CETHFundedAmount * adapter.scale()) / 1e18;
        assertEq(
            CETHFundedAmount,
            sharesRedeemed,
            "user provided CETH amount !~= actual CETH withdrawn on testPrefundedRedeem()"
        );
        assertEq(
            amountWithdrawn,
            expectedWETHRedeemed,
            "actual WETH redeemed !~= expected WETH redeemed on testPrefundedRedeem()"
        );

        // 2) check that CETH is successfully burned
        testAdapterHasNoFundLeft();
        assertEq(underlying.balanceOf(user), amountWithdrawn, "WETHBalanceAfter !~= amountWithdrawn");
    }

    function testClaimRewards_Ok() public {
        // prepare
        _fundAdapterUnderlying(1 ether);
        vm.prank(user);
        adapter.prefundedDeposit();
        // prepare COMP reward
        skip(100 days);
        _overwriteWithOneKey(COMPTROLLER, "compAccrued(address)", address(adapter), 1e5); // adapter accrue COMP rewards
        // execution
        adapter.toCETHAdapter().claimRewards();

        address rewardRecipient = adapter.toCETHAdapter().rewardRecipient();
        assertEq(ERC20(COMP).balanceOf(rewardRecipient), 1e5, "should have COMP balance");
    }

    function testRecoverETH_RevertIfRecipientRevert() public {
        deal(address(adapter), 1 ether);
        vm.prank(owner);
        vm.expectRevert(CompoundV2BaseAdapter.SendETHFailed.selector);
        adapter.toCETHAdapter().recoverETH(address(this)); // this contract reverts on receive
    }

    function testRecoverETH_Ok() public {
        deal(address(adapter), 1 ether);
        vm.prank(owner);
        adapter.toCETHAdapter().recoverETH(address(0xbabe));
        assertEq(address(0xbabe).balance, 1 ether);
    }

    function testScale() public override {
        uint256 scaleFromAdapter = adapter.scale();
        uint256 scaleFromCompound = ICETHToken(CETH).exchangeRateCurrent();
        assertEq(scaleFromAdapter, scaleFromCompound, "scaleFromAdapter !~= scaleFromCompound");
    }

    function testFuzz_scale(uint32 jumpBlocks) public {
        vm.roll(block.number + jumpBlocks);
        uint256 scaleFromAdapter = adapter.scale();
        uint256 scaleFromCompound = ICETHToken(CETH).exchangeRateCurrent();
        assertEq(scaleFromAdapter, scaleFromCompound, "scaleFromAdapter !~= scaleFromCompound");
    }
}

library Cast {
    function toCETHAdapter(IBaseAdapter adapter) internal pure returns (WrappedCETHAdapter) {
        return WrappedCETHAdapter(payable(address(adapter)));
    }
}
