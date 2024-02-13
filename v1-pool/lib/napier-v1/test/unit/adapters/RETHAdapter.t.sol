// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {BaseTestAdapter} from "./BaseTestAdapter.t.sol";
import {RocketPoolHelper} from "../../utils/RocketPoolHelper.sol";

import {RETHAdapter} from "src/adapters/rocketPool/RETHAdapter.sol";

import {ERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";
import {IWETH9} from "src/interfaces/IWETH9.sol";
import {IRocketDepositPool} from "src/adapters/rocketPool/interfaces/IRocketDepositPool.sol";
import {IRocketStorage} from "src/adapters/rocketPool/interfaces/IRocketStorage.sol";
import {IRocketTokenRETH} from "src/adapters/rocketPool/interfaces/IRocketTokenRETH.sol";
import {IRocketDAOProtocolSettingsDeposit} from "src/adapters/rocketPool/interfaces/IRocketDAOProtocolSettingsDeposit.sol";
import {WETH, RETH} from "src/Constants.sol";

contract TestRETHAdapter is BaseTestAdapter {
    uint256 constant FORKED_AT = 17_330_000;

    /// @notice Rocket Pool Address storage https://www.codeslaw.app/contracts/ethereum/0x1d8f8f00cfa6758d7be78336684788fb0ee0fa46
    address constant ROCKET_STORAGE = 0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46;

    uint256 constant wEthBalanceBefore = 10 ether;
    uint256 constant rEthBalanceBefore = 10 ether;

    function setUp() public override {
        vm.createSelectFork("mainnet", FORKED_AT);
        super.setUp();
        _fundUser();
        testAdapterHasNoFundLeft();

        vm.label(ROCKET_STORAGE, "RP_Storage");
        vm.label(RocketPoolHelper.getRocketPoolModuleAddress("rocketDepositPool"), "RP_DepositPool");
        vm.label(RocketPoolHelper.getRocketPoolModuleAddress("rocketDAOProtocolSettingsDeposit"), "RP_DepositSettings");
    }

    function _fundUser() internal {}

    function _deployAdapter() internal override {
        vm.prank(owner);
        adapter = new RETHAdapter(ROCKET_STORAGE);
        underlying = ERC20(WETH);
        target = ERC20(RETH);
    }

    function testAdapterHasNoFundLeft() internal override {
        // make sure that the adapter's balance is zero prior to any function call in the tests
        assertEq(underlying.balanceOf(address(adapter)), 0, "adapter is expected to have no WETH left, but has some");
        assertEq(address(adapter).balance, 0, "adapter is expected to have no WETH left, but has some");
        assertEq(target.balanceOf(address(adapter)), 0, "adapter is expected to have no rETH left, but has some");
    }

    function _fundAdapterUnderlying(uint256 fundedAmount) internal {
        // IWETH9(WETH).deposit{value: fundedAmount}();
        // WETH.totalSupply() returns address(this).balance indeed. `adjust=true` doesn't work here
        deal(WETH, address(adapter), fundedAmount, false);
    }

    function _fundAdapterTarget(uint256 fundedAmount) internal {
        deal(RETH, address(adapter), fundedAmount, true);
    }

    function testPrefundedDeposit() public override {
        // 0) transfer WETH to the adapter contract prior as it would be done by Tranche
        uint256 wEthFundedAmount = wEthBalanceBefore;
        _fundAdapterUnderlying(wEthFundedAmount);

        // 1) call prefundedDeposit to wrap to rETH, and check expected return amount
        uint256 expectedREthMinted = IRocketTokenRETH(RETH).getRethValue(
            // NOTE: RocketPool deducts deposit fee from the user's deposit amount
            wEthFundedAmount - RocketPoolHelper.getDepositFee(wEthFundedAmount)
        );
        vm.prank(user);
        (uint256 underlyingUsed, uint256 sharesMinted) = adapter.prefundedDeposit();
        assertApproxEqAbs(
            wEthFundedAmount,
            underlyingUsed,
            2,
            "user provided WETH amount !~= actual WETH used on prefundedDeposit()"
        );
        assertEq(sharesMinted, expectedREthMinted, "actual rETH minted !~= expected rETH minted on prefundedDeposit()");

        // 2) check that rETH is successfully minted
        testAdapterHasNoFundLeft();
        assertEq(target.balanceOf(user), sharesMinted, "balanceOfUser !~= expectedRETHBalanceAfter");
    }

    function testPrefundedRedeem() public override {
        // 0) transfer rETH to the adapter contract prior as it would be done by Tranche
        uint256 rEthFundedAmount = rEthBalanceBefore;
        _fundAdapterTarget(rEthFundedAmount);

        // 1) call prefundedRedeem to unwrap rETH to WETH, and check expected return amount
        (uint256 amountWithdrawn, uint256 sharesRedeemed) = adapter.prefundedRedeem(user);
        uint256 expectedWEthRedeemed = IRocketTokenRETH(RETH).getEthValue(rEthFundedAmount);
        assertEq(
            rEthFundedAmount,
            sharesRedeemed,
            "user provided rETH amount !~= actual rETH withdrawn on testPrefundedRedeem()"
        );
        assertEq(
            amountWithdrawn,
            expectedWEthRedeemed,
            "actual WETH redeemed !~= expected WETH redeemed on testPrefundedRedeem()"
        );

        // 2) check that rETH is successfully burned
        testAdapterHasNoFundLeft();
        assertEq(underlying.balanceOf(user), amountWithdrawn, "wETHBalanceAfter !~= amountWithdrawn");
    }

    function testScale() public override {
        uint256 scaleFromAdapter = adapter.scale();
        uint256 scaleFromWETH = IRocketTokenRETH(RETH).getExchangeRate();

        assertEq(scaleFromAdapter, scaleFromWETH, "scaleFromAdapter !~= scaleFromWETH");
    }

    function testRecoverETH_Ok() public {
        deal(address(adapter), 1 ether);
        vm.prank(owner);
        RETHAdapter(payable(address(adapter))).recoverETH(address(0xbabe));
        assertEq(address(0xbabe).balance, 1 ether);
    }

    function testRecoverETH_RevertIfReceiverIsNeitherWETHOrRETH() public {
        deal(address(0xcafe), 1 ether);
        vm.prank(address(0xcafe));
        vm.expectRevert(RETHAdapter.OnlyWETHOrRETH.selector);
        payable(address(adapter)).transfer(1 ether);
    }

    function testRecoverETH_RevertIfRecipientRevert() public {
        deal(address(adapter), 1 ether);
        vm.prank(owner);
        vm.expectRevert(RETHAdapter.SendETHFailed.selector);
        RETHAdapter(payable(address(adapter))).recoverETH(address(this)); // this contract reverts on receive
    }

    function testOnlyOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        RETHAdapter(payable(address(adapter))).recoverETH(address(0xbabe));
    }
}
