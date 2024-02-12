// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../Base.t.sol";

import {SafeCast} from "@openzeppelin/contracts@4.9.3/utils/math/SafeCast.sol";
import {FaultyCallbackReceiver} from "../mocks/FaultyCallbackReceiver.sol";
import {CallbackInputType, AddLiquidityInput} from "../shared/CallbackInputType.sol";

import {IQuoter} from "src/interfaces/IQuoter.sol";

abstract contract SwapBaseTest is Base {
    using SafeCast for uint256;
    using SafeCast for uint128;

    /// @dev Authorized address to set up test liquidity
    /// Should be used only for test setup
    address mockDepositor = makeAddr("mockDepositor");

    function _basePoolAddLiquidity(uint256[3] memory amountsIn, uint256 minLiquidity, address receiver)
        public
        virtual
        returns (uint256)
    {
        for (uint256 i = 0; i < amountsIn.length; i++) {
            deal(address(pts[i]), mockDepositor, amountsIn[i], true);
        }
        _approvePts(mockDepositor, address(tricrypto), type(uint256).max);
        vm.prank(mockDepositor);
        return tricrypto.add_liquidity(amountsIn, minLiquidity, false, receiver);
    }

    function _addLiquidity(address recipient, uint256 underlyingIn, uint256 baseLptIn)
        public
        virtual
        returns (uint256 liquidity)
    {
        // Hack: Overwrite the sender's code with MockCallbackReceiver to receive callback from pool
        if (mockDepositor.code.length == 0) _deployMockCallbackReceiverTo(mockDepositor);

        deal(address(underlying), mockDepositor, underlyingIn, false);
        deal(address(tricrypto), mockDepositor, baseLptIn, false);

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

    /// @param preTotalUnderlying total underlying before swap
    /// @param underlyingToAccount underlying amount to account. positive if swapper receives underlying
    /// @param protocolFeeIn protocol fee in underlying that is taken on the swap
    function assertUnderlyingReserveAfterSwap(
        uint256 preTotalUnderlying,
        int256 underlyingToAccount,
        uint256 protocolFeeIn
    ) internal {
        assertApproxEqAbs(
            pool.totalUnderlying().toInt256(),
            // subtract protocol fee and underlying to account
            (preTotalUnderlying - protocolFeeIn).toInt256() - underlyingToAccount,
            3,
            "[accounting] underlying reserve should be equal to preTotalUnderlying - protocolFeeIn - underlyingToAccount"
        );
    }
}

abstract contract PoolSwapBaseTest is SwapBaseTest {
    uint256 preTotalBaseLpt;
    uint256 preTotalUnderlying;

    function setUp() public virtual {
        maturity = block.timestamp + 365 days;
        _deployAdaptersAndPrincipalTokens();
        _deployCurveV2Pool();
        _deployNapierPool();
        _deployNapierRouter();

        _label();

        _setUpLiquidity();

        _approve(tricrypto, address(this), address(pool), type(uint256).max);
        _approve(underlying, address(this), address(pool), type(uint256).max);
        _approvePts(address(this), address(pool), type(uint256).max);
    }

    function _setUpLiquidity() internal virtual {
        uint256 underlyingIn = 3000 * ONE_UNDERLYING;
        uint256 ptIn = 1000 * ONE_UNDERLYING;
        uint256 baseLptIn = 1000 * 1e18;

        // at initialisation, 1:1:1 of pts issues 1:1 = pt:baseLpt
        _basePoolAddLiquidity([ptIn, ptIn, ptIn], baseLptIn, mockDepositor);

        // add initial liquidity to setup swap tests
        _addLiquidity(mockDepositor, underlyingIn, baseLptIn);

        assertEq(pool.totalBaseLpt(), baseLptIn);
        assertEq(pool.totalUnderlying(), underlyingIn);
        preTotalBaseLpt = baseLptIn;
        preTotalUnderlying = underlyingIn;
        // baseLpt proportion = 1/2
    }
}

abstract contract RouterSwapBaseTest is PoolSwapBaseTest {
    function setUp() public virtual override {
        super.setUp();

        _approve(underlying, address(this), address(router), type(uint256).max);
        _approve(tricrypto, address(this), address(router), type(uint256).max);
        _approvePts(address(this), address(router), type(uint256).max);
    }

    function _setUpLiquidity() internal virtual override {
        uint256 underlyingIn = 3000 * ONE_UNDERLYING;
        uint256 ptIn = 1000 * ONE_UNDERLYING;

        // add initial liquidity to setup swap tests
        _issueAndAddLiquidities({recipient: mockDepositor, underlyingIn: underlyingIn, uIssues: [ptIn, ptIn, ptIn]});

        preTotalBaseLpt = pool.totalBaseLpt();
        preTotalUnderlying = pool.totalUnderlying();
        // tricrypto proportion = 1/2
    }

    function _expectRevertIf_Reentrant(address faultyReceiver, bytes memory callData) internal {
        _deployFaultyCallbackReceiverTo(faultyReceiver);
        FaultyCallbackReceiver(faultyReceiver).setReentrancyCall(callData, true);
        FaultyCallbackReceiver(faultyReceiver).setCaller(address(router));
        vm.expectRevert("ReentrancyGuard: reentrant call");
    }

    function test_RevertIf_PoolNotExist() public virtual;

    function test_RevertIf_DeadlinePassed() public virtual;

    function test_RevertIf_PtNotExist() public virtual;

    function test_RevertIf_SlippageTooHigh() public virtual;

    function test_RevertIf_Reentrant() public virtual;
}

abstract contract PoolSwapFuzzTest is PoolSwapBaseTest {
    /// @dev add liquidity to BasePool
    modifier setUpRandomBasePoolReserves(uint256[3] memory amounts) {
        _basePoolAddLiquidity(amounts, 0, mockDepositor);
        _;
    }

    /// @param index index of the pt to swap
    /// @param ptsToBasePool amount of pts to deposit to base pool before swap
    /// @param timestamp timestamp when swap is executed
    struct SwapFuzzInput {
        uint256 index;
        uint256[3] ptsToBasePool;
        uint256 timestamp;
    }

    modifier boundSwapFuzzInput(SwapFuzzInput memory input) {
        input.index = bound(input.index, 0, N_COINS - 1); // 0 <= index < N_COINS
        input.ptsToBasePool = bound(input.ptsToBasePool, ONE_UNDERLYING, 1_000 * ONE_UNDERLYING);
        // timestamp [block.timestamp, maturity - 1]
        input.timestamp = bound(input.timestamp, block.timestamp, maturity - 1);
        _;
    }

    /// @param ptsToBasePool amount of pts to deposit to base pool before swap
    /// @param timestamp timestamp when swap is executed
    struct RandomBasePoolReservesFuzzInput {
        uint256[3] ptsToBasePool;
        uint256 timestamp;
    }

    modifier boundRandomBasePoolReservesFuzzInput(RandomBasePoolReservesFuzzInput memory input) {
        input.ptsToBasePool = bound(input.ptsToBasePool, ONE_UNDERLYING / 1e6, 100 * ONE_UNDERLYING);
        // timestamp [block.timestamp, maturity - 1]
        input.timestamp = bound(input.timestamp, block.timestamp, maturity - 1);
        _;
    }

    /// @dev set up random reserve state in NapierPool
    modifier setUpRandomReserves(uint256[3] memory amounts) {
        uint256 minted = _basePoolAddLiquidity(amounts, 0, mockDepositor);

        _approve(tricrypto, mockDepositor, address(pool), type(uint256).max);
        vm.prank(mockDepositor);
        try pool.swapExactBaseLpTokenForUnderlying(minted, mockDepositor) {}
        catch (bytes memory reason) {
            vm.assume(false);
        }
        _;
    }

    struct AmountFuzzInput {
        uint256 value;
    }

    modifier boundPtDesired(SwapFuzzInput memory swapInput, AmountFuzzInput memory input) {
        // if reserve on pool is less than ptIn, revert with ProportionTooHigh
        input.value = bound(input.value, 100, swapInput.ptsToBasePool[swapInput.index]);
        _;
    }
}

contract RouterSwapFuzzTest is PoolSwapFuzzTest {
    IQuoter quoter;

    function setUp() public virtual override {
        super.setUp();
        quoter = IQuoter(_deployQuoter());

        _approve(underlying, address(this), address(router), type(uint256).max);
        _approve(tricrypto, address(this), address(router), type(uint256).max);
        _approvePts(address(this), address(router), type(uint256).max);
    }

    function _setUpLiquidity() internal virtual override {
        uint256 underlyingIn = 3000 * ONE_UNDERLYING;
        uint256 ptIn = 1000 * ONE_UNDERLYING;

        // add initial liquidity to setup swap tests
        _issueAndAddLiquidities({
            recipient: makeAddr("depositor"),
            underlyingIn: underlyingIn,
            uIssues: [ptIn, ptIn, ptIn]
        });

        preTotalBaseLpt = pool.totalBaseLpt();
        preTotalUnderlying = pool.totalUnderlying();
        // tricrypto proportion = 1/2
    }

    /// @dev For swap with yt and underlying, pt price should be at a great discount.
    /// @dev This modifier set up pool state that pt price is much discounted.
    modifier pushUpUnderlyingPrice(uint256[3] memory amounts) {
        console2.log("pool state before swap", tricrypto.balanceOf(address(pool)), underlying.balanceOf(address(pool)));
        uint256 minted = _basePoolAddLiquidity(amounts, 0, mockDepositor);
        _approve(tricrypto, mockDepositor, address(pool), type(uint256).max);
        vm.prank(mockDepositor);
        try pool.swapExactBaseLpTokenForUnderlying(minted, mockDepositor) {}
        catch (bytes memory reason) {
            vm.assume(false);
        }
        pool.skim();
        console2.log("pool state after swap", tricrypto.balanceOf(address(pool)), underlying.balanceOf(address(pool)));
        _;
    }
}
