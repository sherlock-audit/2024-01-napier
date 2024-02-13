// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {BaseTestLSTAdapter, Cast} from "./BaseTestLSTAdapter.t.sol";

import {IERC4626} from "@openzeppelin/contracts@4.9.3/interfaces/IERC4626.sol";
import {ERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";
import {IFrxETHMinter} from "src/adapters/frax/interfaces/IFrxETHMinter.sol";
import {IFraxEtherRedemptionQueue} from "src/adapters/frax/interfaces/IFraxEtherRedemptionQueue.sol";

import {SFrxETHAdapter, BaseLSTAdapter} from "src/adapters/frax/SFrxETHAdapter.sol";
import "src/Constants.sol" as Constants;

contract TestSFrxETHAdapter is BaseTestLSTAdapter {
    using Cast for *;

    uint256 constant FORKED_AT = 19_000_000;

    /// @dev FraxEther redemption queue contract https://etherscan.io/address/0x82bA8da44Cd5261762e629dd5c605b17715727bd
    IFraxEtherRedemptionQueue constant REDEMPTION_QUEUE =
        IFraxEtherRedemptionQueue(0x82bA8da44Cd5261762e629dd5c605b17715727bd);

    /// @dev FraxEther minter contract
    IFrxETHMinter constant FRXETH_MINTER = IFrxETHMinter(0xbAFA44EFE7901E04E39Dad13167D089C559c1138);

    function setUp() public override {
        vm.createSelectFork("mainnet", FORKED_AT);
        super.setUp();
        testAdapterHasNoFundLeft();

        vm.label(address(REDEMPTION_QUEUE), "redemptionQueue");
        vm.label(address(FRXETH_MINTER), "frxETHMinter");
        vm.label(Constants.FRXETH, "frxETH");
        vm.label(Constants.STAKED_FRXETH, "sfrxETH");
    }

    function _deployAdapter() internal override {
        vm.prank(owner);
        adapter = new SFrxETHAdapter(rebalancer);
        underlying = ERC20(Constants.WETH);
        target = ERC20(address(adapter));
        LST = ERC20(Constants.STAKED_FRXETH);
    }

    function testScale() public override {
        // when totalSupply is 0, scale should be 1e18
        assertEq(adapter.scale(), 1e18, "scale should be 1e18");
    }

    //////////////////////////////////////////////////////////////////////////////
    // Deposit
    //////////////////////////////////////////////////////////////////////////////

    function testPrefundedDeposit() public override {
        // setup
        // The stake amount is caped at 95% of the available ETH at the time of the stake.
        // Target buffer is 10% of the total value of the adapter.

        // transfer WETH to the adapter contract prior as it would be done by Tranche
        uint256 wethFundedAmount = 65115;
        _fundAdapterUnderlying(wethFundedAmount);

        vm.prank(user);
        (uint256 underlyingUsed, uint256 sharesMinted) = adapter.prefundedDeposit();

        uint256 expectedShares = wethFundedAmount; // when totalSupply is 0, 1 share = 1 WETH
        assertEq(wethFundedAmount, underlyingUsed, "user provided WETH amount !~= actual WETH used");
        assertEq(sharesMinted, expectedShares, "actual shares minted !~= expected shares minted");
        assertEq(target.balanceOf(user), sharesMinted, "balanceOfUser !~= shares minted");
        testAdapterHasNoFundLeft();
        assertApproxEqRel(
            adapter.into().bufferPresentPercentage(),
            0.1 * 1e18,
            0.0001 * 1e18, // 0.01% tolerance
            "present buffer percentage should be 10%"
        );
        assertApproxEqAbs(
            adapter.into().bufferEth(),
            wethFundedAmount / 10,
            10,
            "bufferEth should be 10% of WETH funded"
        );
        uint256 balance = LST.balanceOf(address(adapter));
        uint256 balanceInFrxEth = IERC4626(Constants.STAKED_FRXETH).convertToAssets(balance);
        assertApproxEqAbs(
            balanceInFrxEth,
            (wethFundedAmount * 90) / 100,
            10,
            "amount of LST minted should be 90% of WETH funded"
        );
    }

    /// @notice Scenario:
    /// - Initial issuance of esfrxETH
    /// - There is no withdrawal queue
    /// - Target buffer percentage is very low (e.g. 2%)
    function testPrefundedDeposit_WhenExceedMaxStake() public override {
        // Setup
        // set the target buffer percentage to 2%.
        vm.prank(rebalancer);
        adapter.into().setTargetBufferPercentage(0.02 * 1e18); // 2%
        // transfer WETH to the adapter contract prior as it would be done by Tranche
        uint256 wethFundedAmount = 52121115;
        _fundAdapterUnderlying(wethFundedAmount);

        // Execution
        vm.prank(user);
        (uint256 underlyingUsed, uint256 shares) = adapter.prefundedDeposit();

        uint256 expectedShares = wethFundedAmount; // when totalSupply is 0, 1 share = 1 WETH
        assertEq(wethFundedAmount, underlyingUsed, "user provided WETH amount !~= actual WETH used");
        assertEq(shares, expectedShares, "actual shares minted !~= expected shares minted");
        assertEq(target.balanceOf(user), shares, "balanceOfUser !~= shaes minted");
        testAdapterHasNoFundLeft();
        assertApproxEqRel(
            adapter.into().bufferPresentPercentage(),
            0.05 * 1e18,
            0.0001 * 1e18, // 0.01% tolerance
            "present buffer percentage should be 5% instead of 2%"
        );
        assertApproxEqAbs(
            adapter.into().bufferEth(),
            (wethFundedAmount * 5) / 100,
            10,
            "bufferEth should be capped at 5% of the available ETH instead of 2% of the available ETH"
        );
        uint256 balance = LST.balanceOf(address(adapter));
        uint256 balanceInFrxEth = IERC4626(Constants.STAKED_FRXETH).convertToAssets(balance);
        assertApproxEqAbs(
            balanceInFrxEth,
            (wethFundedAmount * 95) / 100,
            10,
            "amount of LST minted should be 95 % of WETH funded instead of 98% of the available ETH"
        );
    }

    //////////////////////////////////////////////////////////////////////////////
    // Request withdrawal
    //////////////////////////////////////////////////////////////////////////////

    function testRequestWithdrawal() public override {
        // Setup
        // 1. Mint some sfrxETH and shares.
        // 2. Ensure present buffer percentage is less than the target percentage.
        {
            _fundAdapterUnderlying(40 ether);
            adapter.prefundedDeposit(); // Mint some sfrxETH.
            vm.prank(rebalancer);
            adapter.into().setTargetBufferPercentage(0.6 * 1e18); // 60%
        }
        uint256 totalAssetsPrior = adapter.into().totalAssets();
        uint256 expectedId = REDEMPTION_QUEUE.redemptionQueueState().nextNftId;
        uint256 sfrxEthBalance = LST.balanceOf(address(adapter));

        uint256 unclaimedFeesPrior = REDEMPTION_QUEUE.redemptionQueueAccounting().unclaimedFees; // Frax charges a fee for withdrawal requests.
        // Execution
        vm.prank(rebalancer);
        adapter.into().requestWithdrawal();
        uint256 sfrxEthBalanceDiff = sfrxEthBalance - LST.balanceOf(address(adapter));
        uint256 redemptionFee = REDEMPTION_QUEUE.redemptionQueueAccounting().unclaimedFees - unclaimedFeesPrior;

        // Assertions
        assertNotEq(expectedId, 0, "requestId should not be 0");
        assertEq(REDEMPTION_QUEUE.ownerOf(expectedId), address(adapter), "adapter should own the ticket");
        assertEq(adapter.into().requestId(), expectedId, "requestId should be set");
        assertGt(adapter.into().withdrawalQueueEth(), 0, "withdrawalQueueEth should be greater than 0");
        assertApproxEqAbs(
            // Frax charges a fee for withdrawal requests.
            adapter.into().withdrawalQueueEth() + redemptionFee,
            IERC4626(Constants.STAKED_FRXETH).convertToAssets(sfrxEthBalanceDiff),
            10,
            "Pending withdrawal should be less than balance diff"
        );
        assertApproxEqAbs(
            adapter.into().totalAssets(),
            totalAssetsPrior - redemptionFee,
            2,
            "totalAssets should decrease by fee taken by Frax"
        );
        testAdapterHasNoFundLeft();
    }

    function testRequestWithdrawalAll() public override {
        _fundAdapterUnderlying(2 ether);
        adapter.prefundedDeposit(); // Mint some sfrxETH.

        uint256 expectedId = REDEMPTION_QUEUE.redemptionQueueState().nextNftId;
        uint256 sfrxEthBalance = LST.balanceOf(address(adapter));
        uint256 unclaimedFeesPrior = REDEMPTION_QUEUE.redemptionQueueAccounting().unclaimedFees; // Frax charges a fee for withdrawal requests.

        // Execution
        vm.prank(rebalancer);
        adapter.into().requestWithdrawalAll();
        uint256 sfrxEthBalanceDiff = sfrxEthBalance - LST.balanceOf(address(adapter));
        uint256 redemptionFee = REDEMPTION_QUEUE.redemptionQueueAccounting().unclaimedFees - unclaimedFeesPrior;

        // Assertions
        assertEq(LST.balanceOf(address(adapter)), 0, "adapter should have no sfrxETH");
        assertApproxEqAbs(
            adapter.into().withdrawalQueueEth() + redemptionFee,
            IERC4626(Constants.STAKED_FRXETH).convertToAssets(sfrxEthBalanceDiff),
            10,
            "Pending withdrawal should be less than previous LST balance"
        );
        assertEq(adapter.into().requestId(), expectedId, "requestId should be set");
        testAdapterHasNoFundLeft();
    }

    //////////////////////////////////////////////////////////////////////////////
    // Claim withdrawal
    //////////////////////////////////////////////////////////////////////////////

    function testClaimWithdrawal() public override {
        // Setup
        {
            // 1. Mint some sfrxETH and shares.
            _fundAdapterUnderlying(40 ether);
            adapter.prefundedDeposit(); // Mint some sfrxETH.

            // 2. Request withdrawal.
            vm.prank(rebalancer);
            adapter.into().setTargetBufferPercentage(0.3 * 1e18); // 30%
            vm.prank(rebalancer);
            adapter.into().requestWithdrawal();
        }
        uint256 requestId = adapter.into().requestId();
        uint256 bufferPrior = adapter.into().bufferEth();
        IFraxEtherRedemptionQueue.RedemptionQueueItem memory nftInfo = REDEMPTION_QUEUE.nftInformation(requestId);

        // 3. Wait until the request is matured.
        vm.warp(nftInfo.maturity);

        // Execution
        // sfrxETH share price will increase over time because it distributes rewards based on timestamp.
        uint256 scalePrior = adapter.scale();
        adapter.into().claimWithdrawal();

        // Assertions
        assertEq(REDEMPTION_QUEUE.nftInformation(requestId).hasBeenRedeemed, true, "NFT should be redeemed");
        assertEq(adapter.into().requestId(), 0, "requestId should be reset");
        assertEq(adapter.into().withdrawalQueueEth(), 0, "withdrawalQueueEth should be reset");
        assertEq(
            underlying.balanceOf(address(adapter)) - bufferPrior,
            nftInfo.amount,
            "WETH balance should increase by claimed amount"
        );
        assertEq(adapter.scale(), scalePrior, "scale should not change");
        testAdapterHasNoFundLeft();
    }

    function testFuzzClaimWithdrawal() public {}
}
