// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Base} from "../../Base.t.sol";

import {IERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/IERC20.sol";
import {ITrancheFactory} from "@napier/napier-v1/src/interfaces/ITrancheFactory.sol";
import {IPoolFactory} from "src/interfaces/IPoolFactory.sol";
import {IWETH9} from "src/interfaces/external/IWETH9.sol";
import {Errors} from "src/libs/Errors.sol";
import {PeripheryPayments} from "src/base/PeripheryPayments.sol";
// Target contracts
import {TrancheRouter} from "src/TrancheRouter.sol";
import {NapierRouter} from "src/NapierRouter.sol";

/// @dev expose internal functions for testing
abstract contract IRouterPaymentsHarness is PeripheryPayments {
    function exposed_pay(address tokenIn, address payer, address recipient, uint256 value) external payable virtual;
}

contract TrancheRouterPaymentsHarness is TrancheRouter {
    constructor(ITrancheFactory _factory, IWETH9 _WETH9) TrancheRouter(_factory, _WETH9) {}

    function exposed_pay(address tokenIn, address payer, address recipient, uint256 value) external payable {
        _pay(tokenIn, payer, recipient, value);
    }
}

contract NapierRouterPaymentsHarness is NapierRouter {
    constructor(IPoolFactory _factory, IWETH9 _WETH9) NapierRouter(_factory, _WETH9) {}

    function exposed_pay(address tokenIn, address payer, address recipient, uint256 value) external payable {
        _pay(tokenIn, payer, recipient, value);
    }
}

/// @dev Test cases for PeripheryPayments
/// @dev Override setUp() to set up the target contract
abstract contract PaymentTest is Base {
    using Cast for *;

    address caller = address(0xCAFE);
    address receiver = address(0xBEEF);

    /// @dev target contract
    address routerAddress;

    function setUp() public virtual {
        _deployWETH();
        _deployAdaptersAndPrincipalTokens();
        _deployCurveV2Pool();
        _deployNapierPool();
        router = new NapierRouterPaymentsHarness(poolFactory, weth);
        trancheRouter = new TrancheRouterPaymentsHarness(trancheFactory, weth);

        _label();
    }

    /// @dev Router should not have any fund left
    function assertNoFundLeftInRouters() public virtual {
        assertNoFundLeftInPoolSwapRouter();
        assertNoFundLeftInTrancheRouter();
    }

    function test_refundETH() public {
        deal(routerAddress, 100);

        uint256 expected = caller.balance + 100;
        vm.prank(caller);
        routerAddress.into().refundETH();

        assertNoFundLeftInRouters();
        assertEq(caller.balance, expected, "receiver should receive ether");

        vm.prank(caller);
        routerAddress.into().refundETH();
        assertEq(caller.balance, expected, "receiver should receive ether");
    }

    function test_unwrapWETH9() public {
        deal(address(weth), routerAddress, 1 ether, false);
        deal(address(weth), 1 ether);

        uint256 amountMinimum = 1;
        vm.prank(caller);
        routerAddress.into().unwrapWETH9(amountMinimum, receiver);

        assertNoFundLeftInRouters();
        assertEq(receiver.balance, 1 ether, "receiver should receive ether");
    }

    function test_unwrapWETH9_ZeroETH() public {
        deal(address(weth), routerAddress, 100, false);
        deal(address(weth), 100);

        vm.prank(caller);
        routerAddress.into().unwrapWETH9(100, receiver);
        assertEq(receiver.balance, 100, "receiver should receive 100 ether");

        vm.prank(caller);
        routerAddress.into().unwrapWETH9(0, receiver);
        assertEq(receiver.balance, 100, "receiver should receive 0 ether");
    }

    function test_unwrapWETH9_RevertWhen_InsufficientWETH() public {
        deal(address(weth), routerAddress, 1 ether, false);
        deal(address(weth), 1 ether);

        vm.expectRevert(Errors.RouterInsufficientWETH.selector);
        routerAddress.into().unwrapWETH9(1 ether + 1, receiver);
    }

    function test_unwrapETH9_RevertWhen_FailedToSendEther() public {
        deal(address(weth), routerAddress, 1 ether, false);
        deal(address(weth), 1 ether);

        vm.expectRevert(Errors.FailedToSendEther.selector);
        routerAddress.into().unwrapWETH9(1, address(this));
    }

    function test_sweepToken() public {
        deal(address(underlying), routerAddress, 100, false);

        uint256 amountMinimum = 1;
        vm.prank(caller);
        routerAddress.into().sweepToken(address(underlying), amountMinimum, receiver);

        assertNoFundLeftInRouters();
        assertEq(underlying.balanceOf(receiver), 100, "receiver should receive token");

        vm.prank(caller);
        routerAddress.into().sweepToken(address(underlying), 0, receiver);
        assertEq(underlying.balanceOf(receiver), 100, "receiver should receive token");
    }

    function test_sweepTokens() public {
        deal(address(underlying), routerAddress, 100, false);
        deal(address(targets[0]), routerAddress, 1000, false);

        address[] memory tokens = new address[](2);
        tokens[0] = address(underlying);
        tokens[1] = address(targets[0]);
        uint256[] memory minimums = new uint256[](2);
        minimums[0] = 1;
        minimums[1] = 1000;

        vm.prank(caller);
        routerAddress.into().sweepTokens(tokens, minimums, receiver);

        assertNoFundLeftInRouters();
        assertEq(underlying.balanceOf(receiver), 100, "receiver should receive token[0]");
        assertEq(targets[0].balanceOf(receiver), 1000, "receiver should receive token[1]");
    }

    function test_sweepTokens_RevertWhen_LenthMismatch() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(underlying);
        tokens[1] = address(targets[0]);
        uint256[] memory minimums = new uint256[](1);
        minimums[0] = 1;

        vm.expectRevert();
        vm.prank(caller);
        routerAddress.into().sweepTokens(tokens, minimums, receiver);
    }

    function test_sweepToken_RevertWhen_InsufficientTokenBalance() public {
        deal(address(underlying), routerAddress, 1 ether, false);

        vm.expectRevert(Errors.RouterInsufficientTokenBalance.selector);
        routerAddress.into().sweepToken(address(underlying), 1 ether + 1, address(this));
    }

    /// forge-config: default.fuzz.runs = 10
    function test_pay_WhenETHPayment_WhenEnoughBalance(address payer) public {
        routerAddress.into().exposed_pay{value: 1000}(address(weth), payer, receiver, 1000);
        assertEq(weth.balanceOf(receiver), 1000, "receiver should receive token");
    }

    /// forge-config: default.fuzz.runs = 10
    function test_pay_WhenETHPayment_Revert_WhenNotEnoughBalance(address payer) public {
        vm.assume(payer != address(routerAddress) && payer != receiver && payer != address(0));

        vm.expectRevert(Errors.RouterInconsistentWETHPayment.selector);
        routerAddress.into().exposed_pay{value: 999}(address(weth), payer, receiver, 1000); // expect 1000 wei but send 999 wei
    }

    /// forge-config: default.fuzz.runs = 10
    function test_pay_WhenWETHPayment(address payer) public {
        _test_pay_WhenERC20Payment(weth, payer);
    }

    /// forge-config: default.fuzz.runs = 10
    function test_pay_WhenERC20Payment(address payer) public {
        _test_pay_WhenERC20Payment(underlying, payer);
    }

    /// @notice Test pay() function when WETH or ERC20 is used as payment
    function _test_pay_WhenERC20Payment(IERC20 token, address payer) internal {
        vm.assume(payer != address(routerAddress) && payer != receiver && payer != address(0));

        deal(address(token), payer, 1000, false); // payer has 1000 wei
        vm.prank(payer);
        token.approve(address(routerAddress), 1000);

        routerAddress.into().exposed_pay(address(token), payer, receiver, 1000);
        assertEq(token.balanceOf(receiver), 1000, "receiver should receive token");
    }
}

contract TrancheRouterPaymentTest is PaymentTest {
    function setUp() public override {
        super.setUp();
        routerAddress = address(trancheRouter);
    }
}

contract NapierRouterPaymentTest is PaymentTest {
    function setUp() public override {
        super.setUp();
        routerAddress = address(router);
    }
}

library Cast {
    function into(address router) internal pure returns (IRouterPaymentsHarness) {
        return IRouterPaymentsHarness(payable(router));
    }
}
