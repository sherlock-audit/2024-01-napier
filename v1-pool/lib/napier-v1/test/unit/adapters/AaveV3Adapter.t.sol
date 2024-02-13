// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTestAdapter} from "./BaseTestAdapter.t.sol";

import {ERC4626} from "@openzeppelin/contracts@4.9.3/token/ERC20/extensions/ERC4626.sol";
import {AaveV3Adapter} from "src/adapters/aaveV3/AaveV3Adapter.sol";
import {IRewardsController} from "src/adapters/aaveV3/interfaces/IRewardsController.sol";
import {IPool} from "src/adapters/aaveV3/interfaces/IPool.sol";
import {ILendingPoolAddressesProvider} from "src/adapters/aaveV3/interfaces/ILendingPoolAddressesProvider.sol";

import {IBaseAdapter} from "src/interfaces/IBaseAdapter.sol";
import {ERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/utils/SafeERC20.sol";

import {WETH, AAVEV3_POOL_ADDRESSES_PROVIDER, AWETH, DAI} from "src/Constants.sol";

contract TestAaveV3Adapter is BaseTestAdapter {
    using Cast for *;
    using SafeERC20 for ERC20;

    uint256 constant FORKED_AT = 17_850_000;

    uint256 constant WETHBalanceBefore = 100;
    uint256 constant CETHBalanceBefore = 100;

    /// @notice AaveV3 reward controller address on mainnet
    address rewardsController = 0x8164Cc65827dcFe994AB23944CBC90e0aa80bFcb;

    /// @notice AaveV3 pool address on mainnet
    address pool;

    event RewardClaimed(address[] rewardAddress, uint256[] amount);

    function setUp() public override {
        vm.createSelectFork("mainnet", FORKED_AT);
        super.setUp();
        pool = ILendingPoolAddressesProvider(AAVEV3_POOL_ADDRESSES_PROVIDER).getPool();

        _fundUser();
        testAdapterHasNoFundLeft();
    }

    function _fundUser() internal {}

    function _deployAdapter() internal override {
        vm.prank(owner);
        adapter = new AaveV3Adapter(WETH, AWETH, address(0xABCD), rewardsController);
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
        deal(address(adapter), address(adapter), fundedAmount, true);
        deal(AWETH, address(adapter), 300, true);
        deal(WETH, pool, 400, false);
    }

    function testImmutableVariables() public {
        assertEq(adapter.underlying(), WETH, "underlying should be WETH");
        assertEq(adapter.target(), address(adapter), "target is adapter itself");
    }

    function testChangeRewardRecipient_Ok() public {
        vm.prank(owner);
        adapter.toAaveV3Adapter().changeRewardRecipient(address(0x1234));
    }

    function testChangeRewardRecipient_RevertIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        adapter.toAaveV3Adapter().changeRewardRecipient(address(0x5678));
    }

    function testClaimRewards_Emit_Ok() public {
        // prepare
        _fundAdapterUnderlying(1 ether);
        vm.prank(user);
        adapter.prefundedDeposit();
        uint256[] memory claimedAmounts = new uint256[](1);
        claimedAmounts[0] = 1e5;
        address[] memory rewardsList = new address[](1);
        rewardsList[0] = DAI;
        vm.mockCall(
            address(rewardsController),
            abi.encodeWithSelector(IRewardsController.claimAllRewards.selector),
            abi.encode(rewardsList, claimedAmounts)
        );
        // execution
        vm.expectEmit();
        emit RewardClaimed(rewardsList, claimedAmounts);
        adapter.toAaveV3Adapter().claimRewards();
    }

    function testPrefundedDeposit() public override {
        // 0) transfer WETH to the adapter contract prior as it would be done by Tranche
        uint256 WETHFundedAmount = WETHBalanceBefore;
        _fundAdapterUnderlying(WETHFundedAmount);

        // 1) call prefundedDeposit to wrap to AWETH, and check expected return amount
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

    function testPrefundedRedeem() public override {
        uint256 WETHFundedAmount = WETHBalanceBefore;
        _fundAdapterUnderlying(WETHFundedAmount);

        vm.prank(user);
        (, uint256 sharesMinted) = adapter.prefundedDeposit();
        vm.prank(user);
        ERC20(address(adapter)).safeTransfer(address(adapter), sharesMinted);
        (uint256 amountWithdrawn, uint256 sharesRedeemed) = adapter.prefundedRedeem(user);
        uint256 expectedWETHRedeemed = (WETHFundedAmount * adapter.scale()) / 1e18;
        assertEq(
            WETHFundedAmount,
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

    function testPrefundedDepositFailed() public {
        uint256 firstDepositAmount = WETHBalanceBefore;
        _fundAdapterUnderlying(firstDepositAmount);
        vm.prank(newOwner);
        adapter.prefundedDeposit();

        //scale Increase
        _simulateScaleIncrease();

        //when scale is greater than 1e18, 1 underlying -> 0 target because we round down in calculation.
        //if someone deposit only 1 underlying and scale is greater than 1e18, he can't receive any target token.
        deal(WETH, address(adapter), 1, false);
        vm.prank(user);
        vm.expectRevert("ZERO_SHARES");
        adapter.prefundedDeposit();
    }

    function testPrefundedRedeemFailed() public {
        uint256 firstDepositAmount = WETHBalanceBefore;
        _fundAdapterUnderlying(firstDepositAmount);
        vm.prank(newOwner);
        adapter.prefundedDeposit();

        uint256 WETHFundedAmount = 1;
        deal(WETH, address(adapter), 1, false);
        vm.prank(user);
        adapter.prefundedDeposit();

        //scale decrease
        _simulateScaleDecrease();

        //when scale is smaller than 1e18, 1 target -> 0 underlying because we round down in calculation.
        //if someone redeem only 1 target and scale is smaller than 1e18, he can't receive any underlying token.
        vm.prank(user);
        ERC20(address(adapter)).safeTransfer(address(adapter), WETHFundedAmount);
        vm.expectRevert("ZERO_ASSETS");
        adapter.prefundedRedeem(user);
    }

    function testScale() public override {
        uint256 scaleFromAdapter = adapter.scale();
        uint256 scaleFromWETH = ERC4626(address(adapter)).convertToAssets(WAD);
        assertEq(scaleFromAdapter, scaleFromWETH, "scaleFromAdapter !~= scaleFromWETH");
    }

    function _simulateScaleIncrease() internal {
        uint256 amount = 200 ether;
        deal(WETH, address(adapter), amount, false);
        _approve(WETH, address(adapter), pool, amount);
        vm.prank(address(adapter));
        IPool(pool).supply(WETH, amount, address(adapter), 0);
    }

    function _simulateScaleDecrease() internal {
        uint256 atokenBalance = IERC20(AWETH).balanceOf(address(adapter));
        vm.prank(address(adapter));
        IPool(pool).withdraw(WETH, atokenBalance / 2, address(0x1234));
    }

    function testDeposit_Revert() public {
        vm.expectRevert(AaveV3Adapter.NotImplemented.selector);
        adapter.toAaveV3Adapter().deposit(100, user);
    }

    function testMint_Revert() public {
        vm.expectRevert(AaveV3Adapter.NotImplemented.selector);
        adapter.toAaveV3Adapter().mint(100, user);
    }

    function testWithdraw_Revert() public {
        vm.expectRevert(AaveV3Adapter.NotImplemented.selector);
        adapter.toAaveV3Adapter().withdraw(100, user, user);
    }

    function testRedeem_Revert() public {
        vm.expectRevert(AaveV3Adapter.NotImplemented.selector);
        adapter.toAaveV3Adapter().redeem(100, user, user);
    }

    function testTotalAsset() public {
        uint256 WETHFundedAmount = WETHBalanceBefore;
        _fundAdapterUnderlying(WETHFundedAmount);

        vm.prank(user);
        adapter.prefundedDeposit();
        uint256 totalAssets = adapter.toAaveV3Adapter().totalAssets();
        assertEq(totalAssets, WETHFundedAmount, "totalAssets !~= expectedAmount");
    }
}

library Cast {
    function toAaveV3Adapter(IBaseAdapter adapter) internal pure returns (AaveV3Adapter) {
        return AaveV3Adapter(address(adapter));
    }
}
