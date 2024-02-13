// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {BaseTestAdapter} from "./BaseTestAdapter.t.sol";
import {MA3WETHAdapter} from "src/adapters/morphoAaveV3/MA3WETHAdapter.sol";

import {IBaseAdapter} from "src/interfaces/IBaseAdapter.sol";
import {BaseAdapter} from "src/BaseAdapter.sol";
import {ERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";
import {IMa3WETH} from "src/adapters/morphoAaveV3/interfaces/IMa3WETH.sol";
import {IMorpho} from "src/adapters/morphoAaveV3/interfaces/IMorpho.sol";
import {WETH, MA3WETH, MORPHO_AAVE_V3, AWETH, MORPHO} from "src/Constants.sol";

contract TestMa3WETHAdapter is BaseTestAdapter {
    using Cast for *;

    uint256 constant FORKED_AT = 17_951_000;
    // @notice Morpho Aave V3 rewards handler contract address on mainnet
    address constant MORPHO_REWARDS_DISTRIBUTOR = 0x3B14E5C73e0A56D607A8688098326fD4b4292135;
    uint256 constant WETHBalanceBefore = 100;
    uint256 constant Ma3WETHBalanceBefore = 100;

    struct Distribution {
        address account;
        uint256 claimable;
    }

    Distribution[] distribution;

    event RewardClaimed(address[] rewardAddress, uint256[] amount);

    function setUp() public override {
        vm.createSelectFork("mainnet", FORKED_AT);
        super.setUp();
        _fundUser();
        testAdapterHasNoFundLeft();
    }

    function _fundUser() internal {}

    function _deployAdapter() internal override {
        vm.prank(owner);
        adapter = new MA3WETHAdapter(address(newOwner), MORPHO_REWARDS_DISTRIBUTOR);
        underlying = ERC20(WETH);
        target = ERC20(address(adapter));
    }

    function testAdapterHasNoFundLeft() internal override {
        // make sure that the adapter's balance is zero prior to any function call in the tests
        assertEq(underlying.balanceOf(address(adapter)), 0, "adapter is expected to have no WETH left, but has some");
        assertEq(target.balanceOf(address(adapter)), 0, "adapter is expected to have no MA3WETH left, but has some");
    }

    function _fundAdapterUnderlying(uint256 fundedAmount) internal {
        deal(WETH, address(adapter), fundedAmount, false);
    }

    function _fundAdapterTarget(uint256 fundedAmount) internal {
        deal(address(adapter), address(adapter), fundedAmount);
        deal(MA3WETH, address(adapter), fundedAmount);
    }

    function testImmutableVariables() public {
        assertEq(adapter.underlying(), WETH, "underlying should be WETH");
        assertEq(adapter.target(), address(adapter), "target is adapter itself");
    }

    function testChangeRewardRecipient_Ok() public {
        vm.prank(owner);
        adapter.toMA3WETHAdatper().changeRewardRecipient(address(0x1234));
    }

    function testChangeRewardRecipient_RevertIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        adapter.toMA3WETHAdatper().changeRewardRecipient(address(0x5678));
    }

    function testPrefundedDeposit() public override {
        // 0) transfer WETH to the adapter contract prior as it would be done by Tranche
        uint256 WETHFundedAmount = WETHBalanceBefore;
        _fundAdapterUnderlying(WETHFundedAmount);

        // 1) call prefundedDeposit to wrap to Ma3WETH, and check expected return amount
        uint256 expectedMa3WETHMinted = (WETHFundedAmount * 1e18) / adapter.scale();
        vm.prank(user);
        (uint256 underlyingUsed, uint256 sharesMinted) = adapter.prefundedDeposit();
        assertApproxEqAbs(
            WETHFundedAmount,
            underlyingUsed,
            2,
            "user provided WETH amount !~= actual WETH used on prefundedDeposit()"
        );
        assertEq(
            sharesMinted,
            expectedMa3WETHMinted,
            "actual Ma3WETH minted !~= expected Ma3WETH minted on prefundedDeposit()"
        );

        // 2) check that Ma3WETH is successfully minted
        testAdapterHasNoFundLeft();
        assertEq(target.balanceOf(user), sharesMinted, "balanceOfUser !~= expectedMa3WETHBalanceAfter");
    }

    function testPrefundedRedeem() public override {
        // 0) transfer Ma3WETH and WMa3WETH to the adapter contract prior as it would be done by Tranche
        uint256 Ma3WETHFundedAmount = Ma3WETHBalanceBefore;
        _fundAdapterTarget(Ma3WETHFundedAmount);

        // 1) call prefundedRedeem to unwrap Ma3WETH to WETH, and check expected return amount
        (uint256 amountWithdrawn, uint256 sharesRedeemed) = adapter.prefundedRedeem(user);
        uint256 expectedWETHRedeemed = (Ma3WETHFundedAmount * adapter.scale()) / 1e18;
        assertEq(
            Ma3WETHFundedAmount,
            sharesRedeemed,
            "user provided Ma3WETH amount !~= actual Ma3WETH withdrawn on testPrefundedRedeem()"
        );
        assertEq(
            amountWithdrawn,
            expectedWETHRedeemed,
            "actual WETH redeemed !~= expected WETH redeemed on testPrefundedRedeem()"
        );

        // 2) check that Ma3WETH is successfully burned
        testAdapterHasNoFundLeft();
        assertEq(underlying.balanceOf(user), amountWithdrawn, "WETHBalanceAfter !~= amountWithdrawn");
    }

    function testClaimRewards_Emit_Ok() public {
        // prepare
        _fundAdapterUnderlying(1 ether);
        vm.prank(user);
        adapter.prefundedDeposit();
        uint256[] memory claimedAmounts = new uint256[](1);
        claimedAmounts[0] = 1e5;
        address[] memory rewardsList = new address[](1);
        rewardsList[0] = AWETH;
        vm.mockCall(
            address(MORPHO_AAVE_V3),
            abi.encodeWithSelector(IMorpho.claimRewards.selector),
            abi.encode(rewardsList, claimedAmounts)
        );
        // execution
        vm.expectEmit();
        emit RewardClaimed(rewardsList, claimedAmounts);
        adapter.toMA3WETHAdatper().claimRewards();
    }

    function testClaimMorpho_Failed() public {
        bytes32[] memory proofs;
        proofs = new bytes32[](1);
        proofs[0] = 0x487d69de69b00bee68ca3451cd8f3d878c63ea33137b773134abe79d42148e17;
        vm.expectRevert();
        adapter.toMA3WETHAdatper().claimMorpho(238129106812057026277, proofs);
    }

    function testClaimMorpho_Ok() public {
        bytes32[] memory proofs;

        //for test claiming MORPHO rewards, we made mockAdapter and deployed contract to  0x58B61d71A801BEffe49Ed1A8E01A908be965Ca1B
        // address(0x58B61d71A801BEffe49Ed1A8E01A908be965Ca1B) claimed MORPHO rewards at block.number == 17951251 on mainnet.
        vm.prank(owner);
        deployCodeTo(
            "MA3WETHAdapter.sol",
            abi.encode(newOwner, MORPHO_REWARDS_DISTRIBUTOR),
            0x58B61d71A801BEffe49Ed1A8E01A908be965Ca1B
        );
        BaseAdapter mockAdapter = MA3WETHAdapter(0x58B61d71A801BEffe49Ed1A8E01A908be965Ca1B);

        // merkle proof for claming MORPHO.
        // Followed proofs are from 0x38b3d3f030e417e9462049760a3cf2dc02d6116148f6de6b86ea3c8aa64bce5e transaction.
        proofs = new bytes32[](12);
        proofs[0] = 0x487d69de69b00bee68ca3451cd8f3d878c63ea33137b773134abe79d42148e17;
        proofs[1] = 0xcfbe8a47d4da77295725fa9641128c3d7519f5765efd40e8c13acc2c550dcb22;
        proofs[2] = 0xf1e77fb191e3c5de666375d731a69b490b76443394c264e2df559d13577660d4;
        proofs[3] = 0x92c33f1066cbf1ccacde03558df5e121672ac95987a3c28215fa83a455bece30;
        proofs[4] = 0xa24b1dc21b1e8607f4e6aff48cfa581ad4a4a1c65e8c70ce23d344b45c576a13;
        proofs[5] = 0x2819ce52346a3a9a5d689f6549563de7e0021372f644d688a4f0f50d8388c9c1;
        proofs[6] = 0x9d0415921819e79f4782840e7429b4ac2a65d4545b763f09a51db3450a19e619;
        proofs[7] = 0x554222476d02772578a7f44ececf47030800763299bd96bd72241402e453e713;
        proofs[8] = 0x8cd0e4f1d7c7aad1e296307d0711418af95fe36ff17986a8b2312efd16a93478;
        proofs[9] = 0xf3e1ee6d647748c6977ad0221184ef8653dfbd934c0ddb83d4ee8ac631c2af51;
        proofs[10] = 0xbe35b1247470f0ea53b17d6e779651b3f0a20687284f39d2c264e5744143bbd3;
        proofs[11] = 0x0208867c641f19f70ec7b9609472bb44a20e34d3d251016385ce3fc6bc8a8715;

        mockAdapter.toMA3WETHAdatper().claimMorpho(238129106812057026277, proofs);
        uint256 morphoRewards = ERC20(MORPHO).balanceOf(address(mockAdapter));
        assertEq(morphoRewards, 238129106812057026277, "Rewarded MORPHO amount != Claimed amount");
    }

    function testDecimal() public {
        assertEq(18, adapter.toMA3WETHAdatper().decimals(), "WMA3WETH decimals != 18");
    }

    function testScale() public override {
        uint256 scaleFromAdapter = adapter.scale();
        uint256 scaleFromWETH = IMa3WETH(MA3WETH).convertToAssets(WAD);
        assertEq(scaleFromAdapter, scaleFromWETH, "scaleFromAdapter !~= scaleFromWETH");
    }
}

library Cast {
    function toMA3WETHAdatper(IBaseAdapter adapter) internal pure returns (MA3WETHAdapter) {
        return MA3WETHAdapter(address(adapter));
    }
}
