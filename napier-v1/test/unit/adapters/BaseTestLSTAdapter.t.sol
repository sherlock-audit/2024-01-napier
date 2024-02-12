// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts@4.9.3/interfaces/IERC4626.sol";
import {BaseTestAdapter} from "./BaseTestAdapter.t.sol";
import {BaseAdapter, BaseLSTAdapter} from "src/adapters/BaseLSTAdapter.sol";

import "src/Constants.sol" as Constants;

library Cast {
    function into(BaseAdapter x) internal pure returns (BaseLSTAdapter) {
        return BaseLSTAdapter(address(x));
    }
}

abstract contract BaseTestLSTAdapter is BaseTestAdapter {
    using Cast for BaseAdapter;

    /// @notice Rebalancer of the LST adapter
    address rebalancer = makeAddr("rebalancer");

    /// @notice Liquid Staking Token (e.g. stETH, FrxETH)
    /// @dev Set in `_deployAdapter()`
    IERC20 LST;

    //////////////////////////////////////////////////////////////////////////////
    // Deposit
    //////////////////////////////////////////////////////////////////////////////

    function testPrefundedDeposit_WhenBufferIsInsufficient() public virtual {
        /// Setup
        uint256 lstBalance; // frxETH or stETH balance of the adapter contract prior to the deposit
        uint256 bufferPrior = 1 ether;
        // Make sure that the present buffer percentage is less than 10%
        {
            // Mint some LST and mock the buffer and withdrawal queue
            _fundAdapterUnderlying(40 ether);
            adapter.prefundedDeposit(); // 90% of the deposit would be converted to LST
            _storeBufferEth(bufferPrior);
            _storeWithdrawalQueueEth(bufferPrior);
            assertApproxEqAbs(
                adapter.into().bufferPresentPercentage(),
                0.053e18, // bufferPercentage ~ (1 + 1) / (40*0.9 + 1 + 1) ~ 0.053 (5.3%)
                0.01 * 1e18, // [0.043, 0.063]
                "present buffer percentage should be about 5%"
            );
            lstBalance = LST.balanceOf(address(adapter));
        }
        // transfer WETH to the adapter contract prior as it would be done by Tranche
        uint256 wethFundedAmount = 1_992_265_115;
        _fundAdapterUnderlying(wethFundedAmount + bufferPrior);

        /// Execution
        vm.prank(user);
        (uint256 underlyingUsed, uint256 sharesMinted) = adapter.prefundedDeposit();

        assertEq(wethFundedAmount, underlyingUsed, "user provided WETH amount !~= actual WETH used");
        assertEq(target.balanceOf(user), sharesMinted, "balanceOfUser !~= shares minted");
        testAdapterHasNoFundLeft();
        assertEq(LST.balanceOf(address(adapter)), lstBalance, "LST balance should not change");
        assertEq(adapter.into().bufferEth(), wethFundedAmount + bufferPrior, "buffer should increase by WETH funded");
    }

    struct PrefundedDepositParams {
        uint256 underlyingIn;
    }

    modifier boundPrefundedDepositParams(PrefundedDepositParams memory params) virtual {
        params.underlyingIn = bound(params.underlyingIn, 1_000, 1_000_000 ether);
        _;
    }

    /// @notice Fuzz test for prefundedDeposit
    /// @dev The test checks the adapter should not revert any amount of WETH provided by the user
    /// - Lido and Rocket Pool have a maximum deposit limit.
    function testFuzz_PrefundedDeposit_WhenBufferIsInsufficient(
        PrefundedDepositParams memory params
    ) public virtual boundPrefundedDepositParams(params) {
        // Setup
        uint256 underlyingIn = params.underlyingIn;
        _fundAdapterUnderlying(underlyingIn);
        // Execution
        vm.prank(user);
        (uint256 underlyingUsed, uint256 shares) = adapter.prefundedDeposit();
        // Assertion
        assertEq(underlyingUsed, underlyingIn, "underlyingUsed !~= underlyingIn");
        assertEq(target.balanceOf(user), shares, "shares !~= sharesMinted");
        testAdapterHasNoFundLeft();
    }

    /// @notice Scenario:
    /// - There is no withdrawal queue
    /// - Target buffer percentage is very low (e.g. 2%)
    function testPrefundedDeposit_WhenExceedMaxStake() public virtual;

    /// @notice Scenario:
    /// - Buffer is sufficient
    /// - There is a large withdrawal queue (e.g. 100 ETH)
    function testPrefundedDeposit_WhenBufferSufficient_WhenExceedMaxStake() public {
        // Setup
        // transfer WETH to the adapter contract prior as it would be done by Tranche
        uint256 frxEthBalance;
        uint256 bufferPrior = 1 ether;
        {
            _fundAdapterUnderlying(1 ether);
            adapter.prefundedDeposit(); // Mint some frxETH
            _storeBufferEth(bufferPrior);
            _storeWithdrawalQueueEth(100 ether); // large withdrawal queue
            frxEthBalance = LST.balanceOf(address(adapter));
        }
        uint256 wethFundedAmount = 0.09e18; // 0.09 ETH
        _fundAdapterUnderlying(wethFundedAmount + bufferPrior);

        vm.prank(user);
        (uint256 underlyingUsed, uint256 sharesMinted) = adapter.prefundedDeposit();

        assertEq(wethFundedAmount, underlyingUsed, "user provided WETH amount !~= actual WETH used");
        assertEq(target.balanceOf(user), sharesMinted, "actual shares minted !~= expected shares minted");
        assertApproxEqAbs(
            adapter.into().bufferEth(),
            ((wethFundedAmount + bufferPrior) * 5) / 100,
            10,
            "bufferEth should be 5% of available WETH"
        );
    }

    //////////////////////////////////////////////////////////////////////////////
    // Redeem
    //////////////////////////////////////////////////////////////////////////////

    function testPrefundedRedeem() public virtual override {
        // setup
        // transfer shares to the adapter contract prior as it would be done by Tranche
        uint256 shares = 1_027;
        uint256 buffer = 30_000;
        _fundAdapterTarget(shares);
        // Transfer some WETH to make sure that the adapter has enough buffer
        _storeBufferEth(buffer);

        (uint256 wethWithdrawn, uint256 sharesRedeemed) = adapter.prefundedRedeem(user);

        assertEq(shares, sharesRedeemed, "user provided shares !~= actual shares withdrawn");
        assertEq(underlying.balanceOf(user), wethWithdrawn, "balanceOfUser !~= wethWithdrawn");
        testAdapterHasNoFundLeft();
        assertEq(adapter.into().bufferEth(), buffer - wethWithdrawn, "bufferEth !~= buffer - wethWithdrawn");
    }

    function testPrefundedRedeem_RevertWhen_InsufficientBuffer() public virtual {
        _fundAdapterUnderlying(1 ether);
        (, uint256 shares) = adapter.prefundedDeposit();
        adapter.into().transfer(address(adapter), shares);
        // Cannot redeem more than the buffer
        vm.expectRevert(BaseLSTAdapter.InsufficientBuffer.selector);
        adapter.prefundedRedeem(user);
    }

    /// forge-config: default.fuzz.runs = 4000
    /// @notice Round-trip test for deposit and redeem.
    /// @dev Redeeming the minted shares immediately must not benefit the user.
    function testFuzz_RT_DepositRedeem(uint256 withdrawalQueueEth, uint256 initialDeposit, uint256 wethDeposit) public {
        // Setup
        withdrawalQueueEth = bound(withdrawalQueueEth, 0, 100_000 ether);
        initialDeposit = bound(initialDeposit, 1_000, 100_000 ether);
        wethDeposit = bound(wethDeposit, 1_000, 100_000 ether);
        _storeWithdrawalQueueEth(withdrawalQueueEth);
        // transfer WETH to the adapter contract prior as it would be done by Tranche
        _fundAdapterUnderlying(initialDeposit);
        try adapter.prefundedDeposit() {} catch {
            vm.assume(false); // ignore the case when the initial deposit is too small and the deposit fails
        }

        // Execution
        // 1. deposit WETH
        _fundAdapterUnderlying(wethDeposit + underlying.balanceOf(address(adapter)));
        (bool s, bytes memory ret) = address(adapter).call(abi.encodeCall(adapter.prefundedDeposit, ()));
        // ZeroShares error is expected only when the deposit is too small
        if (!s) assertEq(bytes4(ret), BaseLSTAdapter.ZeroShares.selector, "unexpected revert");
        vm.assume(s);
        (, uint256 shares) = abi.decode(ret, (uint256, uint256));

        // Ensure that the adapter has enough buffer
        vm.assume(adapter.into().bufferEth() >= adapter.into().previewRedeem(shares));

        // 2. immediately redeem the minted shares
        adapter.into().transfer(address(adapter), shares);
        (uint256 wethWithdrawn, uint256 sharesRedeemed) = adapter.prefundedRedeem(user);

        assertEq(sharesRedeemed, shares, "Shares redeemed should be equal to shares minted");
        assertLe(wethWithdrawn, wethDeposit, "WETH withdrawn should be less than or equal to WETH deposited");
    }

    //////////////////////////////////////////////////////////////////////////////
    // Request withdrawal
    //////////////////////////////////////////////////////////////////////////////

    function testRequestWithdrawal() public virtual;

    function testRequestWithdrawal_RevertWhen_NotRebalancer() public {
        vm.expectRevert(BaseLSTAdapter.NotRebalancer.selector);
        vm.prank(address(0xabcd));
        adapter.into().requestWithdrawal();
    }

    function testRequestWithdrawal_RevertWhen_PendingWithdrawal() public {
        // Setup
        _overwriteSig(address(adapter), "requestId()", 1); // requestId() => 1
        // Assertion
        vm.expectRevert(BaseLSTAdapter.WithdrawalPending.selector);
        vm.prank(rebalancer);
        adapter.into().requestWithdrawal();
    }

    function testRequestWithdrawal_RevertWhen_BufferTooLarge() public {
        {
            _fundAdapterUnderlying(10 ether);
            adapter.prefundedDeposit();
        }
        // Setup
        // Ensure that present buffer percentage > target buffer percentage
        _storeBufferEth(adapter.into().bufferEth() + 100); // bufferEth += 100 wei
        // Assertion
        vm.expectRevert(BaseLSTAdapter.BufferTooLarge.selector);
        vm.prank(rebalancer);
        adapter.into().requestWithdrawal();
    }

    function testRequestWithdrawalAll() public virtual;

    function testRequestWithdrawalAll_RevertWhen_NotRebalancer() public {
        vm.expectRevert(BaseLSTAdapter.NotRebalancer.selector);
        vm.prank(address(0xabcd));
        adapter.into().requestWithdrawalAll();
    }

    function testRequestWithdrawalAll_RevertWhen_PendingWithdrawal() public {
        // Setup
        _overwriteSig(address(adapter), "requestId()", 1); // requestId() => 1
        // Assertion
        vm.expectRevert(BaseLSTAdapter.WithdrawalPending.selector);
        vm.prank(rebalancer);
        adapter.into().requestWithdrawalAll();
    }

    //////////////////////////////////////////////////////////////////////////////
    // Claim withdrawal
    //////////////////////////////////////////////////////////////////////////////

    function testClaimWithdrawal() public virtual;

    function testClaimWithdrawal_RevertWhen_NoPendingWithdrawal() public {
        // Assertion
        vm.expectRevert(BaseLSTAdapter.NoPendingWithdrawal.selector);
        adapter.into().claimWithdrawal();
    }

    //////////////////////////////////////////////////////////////////////////////
    // Admin functions
    //////////////////////////////////////////////////////////////////////////////

    function testSetRebalancer() public {
        vm.prank(owner);
        adapter.into().setRebalancer(user);
        assertEq(adapter.into().rebalancer(), user, "Rebalancer not set correctly");
    }

    function testSetRebalancer_RevertWhen_NotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        adapter.into().setRebalancer(user);
    }

    function testSetTargetBufferPercentage() public {
        vm.prank(rebalancer);
        adapter.into().setTargetBufferPercentage(0.1 * 1e18);
        assertEq(adapter.into().targetBufferPercentage(), 0.1 * 1e18, "Buffer not set correctly");
    }

    function testSetTargetBufferPercentage_RevertWhen_InvalidPercentage() public {
        vm.startPrank(rebalancer);
        vm.expectRevert(BaseLSTAdapter.InvalidBufferPercentage.selector);
        adapter.into().setTargetBufferPercentage(1e18 + 1); // 100%+1
        vm.expectRevert(BaseLSTAdapter.InvalidBufferPercentage.selector);
        adapter.into().setTargetBufferPercentage(0.0001 * 1e18); // 0.01%
        vm.stopPrank();
    }

    function testSetTargetBufferPercentage_RevertWhen_NotRebalancer() public {
        vm.prank(address(0xabcd));
        vm.expectRevert(BaseLSTAdapter.NotRebalancer.selector);
        adapter.into().setTargetBufferPercentage(0.1 * 1e18);
    }

    function testDisabledEIP4626Methods() public {
        address account = address(0x123);
        vm.expectRevert(BaseLSTAdapter.NotImplemented.selector);
        adapter.into().deposit(100, account);

        vm.expectRevert(BaseLSTAdapter.NotImplemented.selector);
        adapter.into().mint(100, account);

        vm.expectRevert(BaseLSTAdapter.NotImplemented.selector);
        adapter.into().withdraw(100, account, account);

        vm.expectRevert(BaseLSTAdapter.NotImplemented.selector);
        adapter.into().redeem(100, account, account);
    }

    ////////////////////////////////////////////////////////////////////////
    // Assertions
    ////////////////////////////////////////////////////////////////////////

    function testAdapterHasNoFundLeft() internal override {
        // make sure that the adapter's balance is zero prior to any function call in the tests
        assertEq(
            underlying.balanceOf(address(adapter)),
            adapter.into().bufferEth(),
            "adapter is expected to have `bufferEth` WETH"
        );
        assertEq(address(adapter).balance, 0, "adapter is expected to have no native ETH left, but has some");
        assertEq(target.balanceOf(address(adapter)), 0, "adapter is expected to have no shares, but has some");
    }

    ////////////////////////////////////////////////////////////////////////
    // Helpers
    ////////////////////////////////////////////////////////////////////////

    function _fundAdapterTarget(uint256 fundedAmount) internal {
        deal(address(adapter), address(adapter), fundedAmount, true);
    }

    function _fundAdapterUnderlying(uint256 fundedAmount) internal {
        deal(Constants.WETH, address(adapter), fundedAmount, false);
    }

    /// @notice helper function to store `bufferEth` state variable
    /// @param bufferEth `bufferEth` to be stored in the adapter contract
    function _storeBufferEth(uint256 bufferEth) internal {
        _fundAdapterUnderlying(bufferEth);
        // bufferEth is packed in the first 128 bits of slot 10
        bytes32 value = bytes32((bufferEth << 128) | adapter.into().withdrawalQueueEth());
        vm.store(address(adapter), bytes32(uint256(10)), value);
    }

    /// @notice helper function to store `withdrawalQueueEth` state variable
    /// @param queueEth `withdrawalQueueEth` to be stored in the adapter contract
    function _storeWithdrawalQueueEth(uint256 queueEth) internal {
        // queueEth is packed in the last 128 bits of slot 10
        bytes32 value = bytes32((uint256(adapter.into().bufferEth()) << 128) | queueEth);
        vm.store(address(adapter), bytes32(uint256(10)), value);
    }
}
