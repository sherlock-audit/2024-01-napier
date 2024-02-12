// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {BaseTestLSTAdapter, Cast} from "./BaseTestLSTAdapter.t.sol";

import {ERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";
import {IStETH} from "src/adapters/lido/interfaces/IStETH.sol";
import {IWithdrawalQueueERC721} from "src/adapters/lido/interfaces/IWithdrawalQueueERC721.sol";

import {StEtherAdapter} from "src/adapters/lido/StEtherAdapter.sol";
import "src/Constants.sol" as Constants;

contract TestStEtherAdapter is BaseTestLSTAdapter {
    using Cast for *;

    uint256 constant FORKED_AT = 19_000_000;

    /// @notice stETH
    IStETH constant STETH = IStETH(Constants.STETH);

    /// @dev Lido WithdrawalQueueERC721
    IWithdrawalQueueERC721 constant LIDO_WITHDRAWAL_QUEUE = IWithdrawalQueueERC721(Constants.LIDO_WITHDRAWAL_QUEUE);

    address whale = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0; // wsETH contract

    function setUp() public override {
        vm.createSelectFork("mainnet", FORKED_AT);
        super.setUp();
        testAdapterHasNoFundLeft();

        vm.label(Constants.LIDO_WITHDRAWAL_QUEUE, "stWERC721");
        vm.label(Constants.STETH, "stETH");
    }

    function _deployAdapter() internal override {
        vm.prank(owner);
        adapter = new StEtherAdapter(rebalancer);
        underlying = ERC20(Constants.WETH);
        target = ERC20(address(adapter));
        LST = ERC20(Constants.STETH);
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
        assertApproxEqAbs(
            balance,
            (wethFundedAmount * 90) / 100,
            10,
            "amount of LST minted should be 90% of WETH funded"
        );
    }

    /// @notice Scenario:
    /// - Initial issuance of estETH
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
            "bufferEth should be 5% of WETH funded instead of 2%"
        );
        uint256 balance = LST.balanceOf(address(adapter));
        assertApproxEqAbs(
            balance,
            (wethFundedAmount * 95) / 100,
            10,
            "amount of LST minted should be 95% of WETH funded instead of 98%"
        );
        testAdapterHasNoFundLeft();
    }

    //////////////////////////////////////////////////////////////////////////////
    // Request withdrawal
    //////////////////////////////////////////////////////////////////////////////

    function testRequestWithdrawal() public override {
        // Setup
        // 1. Mint some stETH and shares.
        // 2. Ensure present buffer percentage is less than the target percentage.
        {
            _fundAdapterUnderlying(40 ether);
            adapter.prefundedDeposit(); // Mint some stETH.
            vm.prank(rebalancer);
            adapter.into().setTargetBufferPercentage(0.6 * 1e18); // 60%
        }
        uint256 totalAssetsPrior = adapter.into().totalAssets();

        // Execution
        vm.prank(rebalancer);
        adapter.into().requestWithdrawal();
        uint256 requestId = adapter.into().requestId();
        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = requestId;
        IWithdrawalQueueERC721.WithdrawalRequestStatus[] memory nftInfo = LIDO_WITHDRAWAL_QUEUE.getWithdrawalStatus(
            requestIds
        );

        // Assertions
        assertNotEq(adapter.into().requestId(), 0, "requestId should be set");
        assertGt(adapter.into().withdrawalQueueEth(), 0, "withdrawalQueueEth should be greater than 0");
        assertEq(
            adapter.into().withdrawalQueueEth(),
            nftInfo[0].amountOfStETH,
            "Pending withdrawal should be the same with amountOfStETH"
        );
        assertApproxEqAbs(
            adapter.into().totalAssets(),
            totalAssetsPrior,
            2,
            "totalAssets should decrease by calculation issue taken by Lido"
        );
        testAdapterHasNoFundLeft();
    }

    function testRequestWithdrawalAll() public override {
        _fundAdapterUnderlying(2 ether);
        adapter.prefundedDeposit(); // Mint some stETH.

        // Execution
        vm.prank(rebalancer);
        adapter.into().requestWithdrawalAll();

        uint256 requestId = adapter.into().requestId();
        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = requestId;
        IWithdrawalQueueERC721.WithdrawalRequestStatus[] memory nftInfo = LIDO_WITHDRAWAL_QUEUE.getWithdrawalStatus(
            requestIds
        );

        // Assertions
        assertLe(LST.balanceOf(address(adapter)), 3, "adapter should have no stETH");
        assertEq(
            adapter.into().withdrawalQueueEth(),
            nftInfo[0].amountOfStETH,
            "Pending withdrawal should be the same with amountOfStETH value"
        );
        testAdapterHasNoFundLeft();
    }

    /// @notice Scenario: Request withdrawal more than the maximum unstake amount.
    function testRequestWithdrawalAll_WhenExceedMaxUnstake() public {
        // Setup
        vm.prank(whale);
        STETH.transfer(address(adapter), 10_000 ether);

        // Execution
        vm.prank(rebalancer);
        adapter.into().requestWithdrawalAll();

        uint256 requestId = adapter.into().requestId();
        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = requestId;
        IWithdrawalQueueERC721.WithdrawalRequestStatus[] memory nftInfo = LIDO_WITHDRAWAL_QUEUE.getWithdrawalStatus(
            requestIds
        );
        // Assertions
        assertEq(
            adapter.into().withdrawalQueueEth(),
            nftInfo[0].amountOfStETH,
            "Pending withdrawal should be the same with amountOfStETH value"
        );
        testAdapterHasNoFundLeft();
    }

    //////////////////////////////////////////////////////////////////////////////
    // Claim withdrawal
    //////////////////////////////////////////////////////////////////////////////
    function testClaimWithdrawal() public override {
        // Setup
        {
            // 1. Mint some stETH and shares.
            _fundAdapterUnderlying(40 ether);
            adapter.prefundedDeposit(); // Mint some stETH.

            // 2. Request withdrawal.
            vm.prank(rebalancer);
            adapter.into().setTargetBufferPercentage(0.3 * 1e18); // 30%
            vm.prank(rebalancer);
            adapter.into().requestWithdrawal();
        }
        uint256 requestId = adapter.into().requestId();
        uint256 bufferPrior = adapter.into().bufferEth();

        // 3. Wait until the request is matured.
        vm.prank(Constants.STETH);
        LIDO_WITHDRAWAL_QUEUE.finalize(requestId, 1e27);

        // Execution
        // stETH share price will increase over time because it distributes rewards based on timestamp.
        vm.prank(rebalancer);
        adapter.into().claimWithdrawal();

        // Assertions
        assertEq(adapter.into().requestId(), 0, "requestId should be reset");
        assertEq(adapter.into().withdrawalQueueEth(), 0, "withdrawalQueueEth should be reset");
        assertGt(
            underlying.balanceOf(address(adapter)) - bufferPrior,
            0,
            "WETH balance should be increased by claimed amount"
        );
        testAdapterHasNoFundLeft();
    }
}
