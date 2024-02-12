// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../Base.t.sol";
import {FaultyCallbackReceiver} from "../mocks/FaultyCallbackReceiver.sol";
import {CallbackInputType, AddLiquidityInput} from "../shared/CallbackInputType.sol";

abstract contract LiquidityBaseTest is Base {
    /// @dev Authorized address to set up test liquidity
    /// Should be used only for test setup
    address mockDepositor = makeAddr("mockDepositor");

    function setUp() public virtual {
        maturity = block.timestamp + 365 days;
        _deployAdaptersAndPrincipalTokens();
        _deployCurveV2Pool();
        _deployNapierPool();
        _deployNapierRouter();

        _deployMockCallbackReceiverTo(mockDepositor);
        _label();
    }

    modifier whenZeroTotalSupply() virtual {
        _;
    }

    modifier whenNonZeroTotalSupply() virtual {
        _;
    }

    function _setUpNapierPoolLiquidity(address recipient, uint256 underlyingIn, uint256 baseLptIn)
        public
        returns (uint256)
    {
        deal(address(underlying), mockDepositor, underlyingIn, true);
        deal(address(tricrypto), mockDepositor, baseLptIn, true);

        vm.prank(mockDepositor);
        return pool.addLiquidity(
            underlyingIn,
            baseLptIn,
            recipient,
            abi.encode(
                CallbackInputType.AddLiquidity, AddLiquidityInput({underlying: underlying, tricrypto: tricrypto})
            )
        );
    }

    function _expectRevertIf_Reentrant(address faultyReceiver, bytes memory callData) public virtual {
        // Set up initial liquidity on NapierPool
        // At this point, Curve pool doesn't have any liquidity
        _setUpNapierPoolLiquidity(address(this), 1000 * ONE_UNDERLYING, 1000 * 1e18);
        // Mock Curve pool to return non-zero aomunt. The amount is not important.
        vm.mockCall(
            address(tricrypto),
            abi.encodeWithSelector(CurveTricryptoOptimizedWETH.calc_token_amount.selector),
            abi.encode(1e18)
        );
        // Deploy faulty callback receiver
        _deployFaultyCallbackReceiverTo(faultyReceiver);
        // Set reentrancy call
        FaultyCallbackReceiver(faultyReceiver).setReentrancyCall(callData, true);
        // reentrancy should not be possible because of ReentrancyGuard
        vm.expectRevert("ReentrancyGuard: reentrant call");
    }
}

abstract contract PoolAddLiquidityBaseUnitTest is LiquidityBaseTest {
    function test_RevertIf_Reentrant() public virtual;

    function test_RevertIf_DeadlinePassed() public virtual;

    function test_WhenZeroTotalSupply() public virtual;

    function test_RevertWhen_LessThanMinLiquidity() public virtual;

    function test_WhenAddProportionally() public virtual;

    function test_WhenAddBaseLptImbalance() public virtual;

    function test_WhenAddUnderlyingImbalance() public virtual;
}

abstract contract PoolRemoveLiquidityBaseUnitTest is LiquidityBaseTest {
    function test_RevertIf_Reentrant() public virtual;

    function test_RevertWhen_RemoveZeroLiquidity() public virtual;

    function test_RevertWhen_RemoveZeroAmount() public virtual;

    function test_RemoveProportionally() public virtual;
}

abstract contract RouterLiquidityBaseUnitTest is LiquidityBaseTest {
    /// @dev Initial balances
    uint256 baseLptBalance;
    uint256 ptBalance;
    uint256 uBalance;

    address receiver = makeAddr("receiver");

    function setUp() public virtual override {
        super.setUp();

        _approvePts(address(this), address(router), type(uint256).max);
        _approve(underlying, address(this), address(router), type(uint256).max);

        baseLptBalance = 1000 * 1e18;
        ptBalance = 1000 * ONE_UNDERLYING;
        uBalance = 3000 * ONE_UNDERLYING;

        deal(address(tricrypto), address(this), baseLptBalance, false);
        dealPts(address(this), ptBalance, false);
        deal(address(underlying), address(this), uBalance, false);
    }

    function _expectRevertIf_Reentrant(address faultyReceiver, bytes memory callData) public virtual override {
        // Set up initial liquidity on NapierPool
        // At this point, Curve pool doesn't have any liquidity
        _setUpNapierPoolLiquidity(address(this), 1000 * ONE_UNDERLYING, 1000 * 1e18);
        // Mock Curve pool to return non-zero aomunt. The amount is not important.
        vm.mockCall(
            address(tricrypto),
            abi.encodeWithSelector(CurveTricryptoOptimizedWETH.calc_token_amount.selector),
            abi.encode(1e18)
        );
        // Deploy faulty callback receiver
        _deployFaultyCallbackReceiverTo(faultyReceiver);
        // Set reentrancy call
        FaultyCallbackReceiver(faultyReceiver).setReentrancyCall(callData, true);
        FaultyCallbackReceiver(faultyReceiver).setCaller(address(router));
        // reentrancy should not be possible because of ReentrancyGuard
        vm.expectRevert("ReentrancyGuard: reentrant call");
    }

    /// @dev Helper function to deposit liquidity to NapierPool and Curve Pool
    /// Note: Principal Token is minted by cheatcode.
    /// Doesn't work for testing interaction with Tranche mechanism. Use _issueAndAddLiquidities instead.
    function _setUpAllLiquidity(address recipient, uint256 underlyingIn, uint256 ptIn) public returns (uint256) {
        deal(address(underlying), mockDepositor, underlyingIn, true);
        dealPts(mockDepositor, ptIn, true);

        _approvePts(mockDepositor, address(tricrypto), type(uint256).max);
        vm.prank(mockDepositor);
        uint256 baseLptMinted = tricrypto.add_liquidity([ptIn, ptIn, ptIn], 0);
        vm.prank(mockDepositor);
        return pool.addLiquidity(
            underlyingIn,
            baseLptMinted,
            recipient,
            abi.encode(
                CallbackInputType.AddLiquidity, AddLiquidityInput({underlying: underlying, tricrypto: tricrypto})
            )
        );
    }

    function test_RevertIf_Reentrant() public virtual;

    function test_RevertIf_PoolNotExist() public virtual;

    function test_RevertIf_DeadlinePassed() public virtual;
}

abstract contract RouterAddLiquidityTest is RouterLiquidityBaseUnitTest {
    function test_RevertIf_MaturityPassed() public virtual;

    function test_RevertIf_InsufficientLpOut() public virtual;
}

abstract contract RouterRemoveLiquidityBaseUnitTest is RouterLiquidityBaseUnitTest {
    function setUp() public virtual override {
        super.setUp();
        // approve router to spend liquidity tokens
        _approve(pool, address(this), address(router), type(uint256).max);
    }
    // To be implemented by inheriting test contracts
    // function test_RevertIf_InsufficientTokenOut() public virtual;
}
