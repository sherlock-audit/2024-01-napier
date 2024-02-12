// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {RouterSwapBaseTest} from "../../shared/Swap.t.sol";

import {Errors} from "src/libs/Errors.sol";
import {NapierPool} from "src/NapierPool.sol";
import {MockFakePool} from "../../mocks/MockFakePool.sol";

contract RouterSwapPtForUnderlyingUnitTest is RouterSwapBaseTest {
    address receiver = makeAddr("receiver");

    /// @dev Initial user balances
    uint256 ptBalance;

    function setUp() public override {
        super.setUp();
        // Set initial user balances
        ptBalance = 100 * ONE_UNDERLYING;
        dealPts(address(this), ptBalance, false);
    }

    function test_swapPtForUnderlying() public virtual whenMaturityNotPassed {
        uint256 underlyingOut = router.swapPtForUnderlying({
            pool: address(pool),
            index: 0,
            ptInDesired: 10 * ONE_UNDERLYING,
            underlyingOutMin: 8 * ONE_UNDERLYING,
            recipient: receiver,
            deadline: block.timestamp
        });
        assertEq(
            pts[0].balanceOf(address(this)), ptBalance - 10 * ONE_UNDERLYING, "pt should be transferred from sender"
        );
        assertGe(underlyingOut, 8 * ONE_UNDERLYING, "underlyingOut should be gt underlyingOutMin");
        assertEq(underlying.balanceOf(receiver), underlyingOut, "underlyingOut should be transferred to recipient");
        assertNoFundLeftInPoolSwapRouter();
    }

    function test_RevertIf_PoolZeroAmounts() public virtual whenMaturityNotPassed {
        vm.expectRevert(Errors.PoolZeroAmountsOutput.selector);
        // To test this case, use small amount of underlying to mock attackers who want swap for free.
        router.swapPtForUnderlying({
            pool: address(pool),
            index: 0,
            ptInDesired: 1,
            underlyingOutMin: 1,
            recipient: receiver,
            deadline: block.timestamp
        });
    }

    function test_RevertIf_DeadlinePassed() public virtual override {
        vm.expectRevert(Errors.RouterTransactionTooOld.selector);
        router.swapPtForUnderlying({
            pool: address(pool),
            index: 0,
            ptInDesired: 10 * ONE_UNDERLYING,
            underlyingOutMin: 1 * ONE_UNDERLYING,
            recipient: address(this),
            deadline: block.timestamp - 1 // expired
        });
    }

    function test_RevertIf_PoolNotExist() public override {
        MockFakePool fakePool = new MockFakePool();
        vm.expectRevert(Errors.RouterPoolNotFound.selector);
        router.swapPtForUnderlying({
            pool: address(fakePool),
            index: 0,
            ptInDesired: 10 * ONE_UNDERLYING,
            underlyingOutMin: 1 * ONE_UNDERLYING,
            recipient: address(this),
            deadline: block.timestamp
        });
    }

    function test_RevertIf_PtNotExist() public virtual override {
        vm.expectRevert(stdError.indexOOBError);
        router.swapPtForUnderlying({
            pool: address(pool),
            index: 3, // pt index out of bound
            ptInDesired: 10 * ONE_UNDERLYING,
            underlyingOutMin: 1 * ONE_UNDERLYING,
            recipient: address(this),
            deadline: block.timestamp
        });
    }

    function test_RevertIf_SlippageTooHigh() public virtual override {
        vm.expectRevert(Errors.RouterInsufficientUnderlyingOut.selector);
        router.swapPtForUnderlying({
            pool: address(pool),
            index: 1,
            ptInDesired: 1 * ONE_UNDERLYING,
            underlyingOutMin: 100 * ONE_UNDERLYING, // too high
            recipient: address(this),
            deadline: block.timestamp
        });
    }

    function test_RevertIf_Reentrant() public virtual override {
        dealPts(receiver, 1e18, true);
        _approvePts(receiver, address(router), 1e18);
        _expectRevertIf_Reentrant(
            receiver,
            abi.encodeWithSelector(
                router.swapPtForUnderlying.selector,
                address(pool),
                1,
                10 * ONE_UNDERLYING,
                8 * ONE_UNDERLYING,
                receiver,
                block.timestamp
            )
        );
        vm.prank(receiver); // receiver of the callback on swapPtForUnderlying
        pool.swapPtForUnderlying(0, 10, receiver, abi.encode(NapierPool.swapPtForUnderlying.selector, pts[0]));
    }
}

/// @notice Underlying is WETH
contract RouterSwapPtForEthUnitTest is RouterSwapPtForUnderlyingUnitTest {
    function _deployUnderlying() internal override {
        _deployWETH();
        underlying = weth;
        uDecimals = 18;
        ONE_UNDERLYING = 1e18;
    }

    function test_RevertIf_Reentrant() public virtual override {
        dealPts(receiver, 1e18, true);
        _approvePts(receiver, address(router), 1e18);
        _expectRevertIf_Reentrant(
            receiver,
            abi.encodeWithSelector(
                router.swapPtForUnderlying.selector,
                address(pool),
                1,
                1 * ONE_UNDERLYING,
                8 * ONE_UNDERLYING,
                receiver,
                block.timestamp
            )
        );
        vm.prank(receiver); // receiver of the callback on swapPtForUnderlying
        pool.swapPtForUnderlying(0, 10, receiver, abi.encode(NapierPool.swapPtForUnderlying.selector, pts[0]));
    }

    /// @dev swap pt for weth and then unwrap it to native ether
    function test_swapPtForUnderlying() public override whenMaturityNotPassed {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(
            router.swapPtForUnderlying,
            // note: receiver is router itself
            (address(pool), 0, 10 * ONE_UNDERLYING, 8 * ONE_UNDERLYING, address(router), block.timestamp)
        );
        data[1] = abi.encodeCall(router.unwrapWETH9, (8 * ONE_UNDERLYING, receiver));
        // execution
        uint256 _before = gasleft();
        bytes[] memory ret = router.multicall(data);
        console2.log("gas usage: ", _before - gasleft());

        uint256 underlyingOut = abi.decode(ret[0], (uint256));

        assertEq(
            pts[0].balanceOf(address(this)), ptBalance - 10 * ONE_UNDERLYING, "pt should be transferred from sender"
        );
        assertGe(underlyingOut, 8 * ONE_UNDERLYING, "underlyingOut should be gt underlyingOutMin");
        assertEq(receiver.balance, underlyingOut, "ether should be transferred to recipient");
        assertNoFundLeftInPoolSwapRouter();
    }

    function test_RevertIf_PoolZeroAmounts() public override whenMaturityNotPassed {
        // underlying decimal is 18, so it is same with baseLpt decimal
        // Somehow if users use small amount of pt for swapping free, it would be reverted with `Loss` while tricrypto.addLiquidity
        // if users use large amount of pt, they would receive above 1 underlying token.
    }
}

contract RouterSwapUnderlyingForPtUnitTest is RouterSwapBaseTest {
    address receiver = makeAddr("receiver");

    /// @dev Initial user balances
    uint256 uBalance;

    function setUp() public override {
        super.setUp();

        uBalance = 300 * ONE_UNDERLYING;
        deal(address(underlying), address(this), uBalance, false);
    }

    function test_swapUnderlyingForPt() public virtual whenMaturityNotPassed {
        uint256 underlyingIn = router.swapUnderlyingForPt({
            pool: address(pool),
            index: 0,
            ptOutDesired: 10 * ONE_UNDERLYING,
            underlyingInMax: 15 * ONE_UNDERLYING,
            recipient: receiver,
            deadline: block.timestamp
        });
        assertApproxEqRel(
            pts[0].balanceOf(receiver), 10 * ONE_UNDERLYING, 0.05 * 1e18, "pt should be transferred to receiver"
        );
        assertLt(underlyingIn, 15 * ONE_UNDERLYING, "underlyingIn should be lt underlyingInMax");
        assertEq(
            underlying.balanceOf(address(this)),
            uBalance - underlyingIn,
            "underlyingIn should be transferred from sender"
        );
        assertNoFundLeftInPoolSwapRouter();
    }

    function test_RevertIf_PoolZeroAmounts() public virtual whenMaturityNotPassed {
        vm.expectRevert(Errors.PoolZeroAmountsInput.selector);
        // To test this case, use small amount of underlying to mock attackers who want swap for free.
        router.swapUnderlyingForPt({
            pool: address(pool),
            index: 0,
            ptOutDesired: 1,
            underlyingInMax: 1,
            recipient: receiver,
            deadline: block.timestamp
        });
    }

    function test_RevertIf_DeadlinePassed() public virtual override {
        vm.expectRevert(Errors.RouterTransactionTooOld.selector);
        router.swapUnderlyingForPt({
            pool: address(pool),
            index: 0,
            ptOutDesired: 10 * ONE_UNDERLYING,
            underlyingInMax: 15 * ONE_UNDERLYING,
            recipient: receiver,
            deadline: block.timestamp - 1
        });
    }

    function test_RevertIf_PoolNotExist() public override {
        MockFakePool fakePool = new MockFakePool();
        vm.expectRevert(Errors.RouterPoolNotFound.selector);
        router.swapUnderlyingForPt({
            pool: address(fakePool),
            index: 0,
            ptOutDesired: 10 * ONE_UNDERLYING,
            underlyingInMax: 15 * ONE_UNDERLYING,
            recipient: receiver,
            deadline: block.timestamp
        });
    }

    function test_RevertIf_PtNotExist() public virtual override {
        vm.expectRevert(stdError.indexOOBError);
        router.swapUnderlyingForPt({
            pool: address(pool),
            index: 3, // pt index out of bound
            ptOutDesired: 10 * ONE_UNDERLYING,
            underlyingInMax: 15 * ONE_UNDERLYING,
            recipient: receiver,
            deadline: block.timestamp + 10
        });
    }

    function test_RevertIf_SlippageTooHigh() public virtual override {
        vm.expectRevert(Errors.RouterExceededLimitUnderlyingIn.selector);
        router.swapUnderlyingForPt({
            pool: address(pool),
            index: 0,
            ptOutDesired: 10 * ONE_UNDERLYING,
            underlyingInMax: 7 * ONE_UNDERLYING,
            recipient: receiver,
            deadline: block.timestamp
        });
    }

    function test_RevertIf_Reentrant() public virtual override {
        dealPts(receiver, 1e18, true);
        _approvePts(receiver, address(router), 1e18);
        _expectRevertIf_Reentrant(
            receiver,
            abi.encodeWithSelector(
                router.swapUnderlyingForPt.selector,
                address(pool),
                0,
                10 * ONE_UNDERLYING,
                15 * ONE_UNDERLYING,
                receiver,
                block.timestamp
            )
        );
        vm.prank(receiver); // receiver of the callback on swapPtForUnderlying
        pool.swapPtForUnderlying(0, 10, receiver, abi.encode(NapierPool.swapPtForUnderlying.selector, pts[0]));
    }
}

contract RouterSwapEthForPtUnitTest is RouterSwapUnderlyingForPtUnitTest {
    function _deployUnderlying() internal override {
        _deployWETH();
        underlying = weth;
        uDecimals = 18;
        ONE_UNDERLYING = 1e18;
    }

    function test_RevertIf_Reentrant() public virtual override {
        dealPts(receiver, 1e18, true);
        _approvePts(receiver, address(router), 1e18);
        _expectRevertIf_Reentrant(
            receiver,
            abi.encodeWithSelector(
                router.swapUnderlyingForPt.selector,
                address(pool),
                0,
                10 * ONE_UNDERLYING,
                15 * ONE_UNDERLYING,
                receiver,
                block.timestamp
            )
        );
        vm.prank(receiver); // receiver of the callback on swapPtForUnderlying
        pool.swapPtForUnderlying(0, 10, receiver, abi.encode(NapierPool.swapPtForUnderlying.selector, pts[0]));
    }

    receive() external payable {
        // receive ether from router
        require(msg.sender == address(router) || msg.sender == address(weth), "do not accept ether");
    }

    ///@dev swap native ether for pt
    function test_swapUnderlyingForPt() public override whenMaturityNotPassed {
        uint256 etherBalanceBefore = address(this).balance;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(
            router.swapUnderlyingForPt, (address(pool), 1, 10 * 1e18, 15 ether, receiver, block.timestamp)
        );
        data[1] = abi.encodeCall(router.refundETH, ());
        // execution
        uint256 _before = gasleft();
        bytes[] memory ret = router.multicall{value: 15 ether}(data);
        console2.log("gas usage: ", _before - gasleft());

        uint256 ethIn = abi.decode(ret[0], (uint256));

        assertApproxEqRel(pts[1].balanceOf(receiver), 10 * 1e18, 0.05 * 1e18, "pt should be transferred to receiver");
        assertLt(ethIn, 15 ether, "ethIn should be lt underlyingInMax");
        assertEq(address(this).balance, etherBalanceBefore - ethIn, "ethIn should be transferred from sender");
        assertNoFundLeftInPoolSwapRouter();
    }
}

contract RouterSwapYtForUnderlyingUnitTest is RouterSwapBaseTest {
    address receiver = makeAddr("receiver");

    /// @dev Initial user balances of Principal and Yield tokens
    uint256[3] pyBalances;

    function setUp() public override {
        super.setUp();
        // mint pt and yt
        address whale = makeAddr("whale");
        deal(address(underlying), whale, 300 * ONE_UNDERLYING, false);
        for (uint256 i = 0; i < N_COINS; i++) {
            _approve(underlying, whale, address(pts[i]), type(uint256).max);
            vm.prank(whale);
            pyBalances[i] = pts[i].issue(address(this), 100 * ONE_UNDERLYING);
            // approve router to spend yt
            _approve(yts[i], address(this), address(router), type(uint256).max);
        }
    }

    function test_swapYtForUnderlying(uint256 i, uint256 cscale) public virtual {
        vm.warp(block.timestamp + 30 days);
        i = bound(i, 0, N_COINS - 1);
        uint256 scale = adapters[i].scale();
        cscale = bound(cscale, scale, scale * 180 / 100); // if scale decreases, it will revert with `RouterInsufficientUnderlyingOut`
        // mock scale change
        vm.mockCall(address(adapters[i]), abi.encodeWithSelector(adapters[i].scale.selector), abi.encode(cscale));
        // execution
        uint256 underlyingOut = router.swapYtForUnderlying({
            pool: address(pool),
            index: 0,
            ytIn: 10 * ONE_UNDERLYING,
            underlyingOutMin: 1 * ONE_UNDERLYING,
            recipient: receiver,
            deadline: block.timestamp
        });
        assertApproxEqRel(
            yts[0].balanceOf(address(this)),
            pyBalances[0] - 10 * ONE_UNDERLYING,
            0.05 * 1e18,
            "yt should be transferred from sender"
        );
        assertGe(underlyingOut, 1 * ONE_UNDERLYING, "underlyingOut should be gt underlyingOutMin");
        assertEq(underlying.balanceOf(receiver), underlyingOut, "underlyingOut should be transferred to recipient");
        assertNoFundLeftInPoolSwapRouter();
        vm.clearMockedCalls();
    }

    function test_RevertIf_InsufficientRedeemedUnderlying() public whenMaturityNotPassed {
        // mock insufficient underlying redeemed by adapter
        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(adapters[0].prefundedRedeem.selector),
            abi.encode(5.0 * ONE_UNDERLYING, 10 * 1e18)
        );
        vm.expectRevert(Errors.RouterInsufficientUnderlyingRepay.selector);
        router.swapYtForUnderlying({
            pool: address(pool),
            index: 0,
            ytIn: 10 * ONE_UNDERLYING,
            underlyingOutMin: 1 * ONE_UNDERLYING,
            recipient: receiver,
            deadline: block.timestamp
        });
        vm.clearMockedCalls();
    }

    function test_RevertIf_SlippageTooHigh() public virtual override {
        vm.expectRevert(Errors.RouterInsufficientUnderlyingOut.selector);
        router.swapYtForUnderlying({
            pool: address(pool),
            index: 0,
            ytIn: 10 * ONE_UNDERLYING,
            underlyingOutMin: 8 * ONE_UNDERLYING,
            recipient: receiver,
            deadline: block.timestamp
        });
    }

    function test_RevertIf_DeadlinePassed() public virtual override {
        vm.expectRevert(Errors.RouterTransactionTooOld.selector);
        router.swapYtForUnderlying({
            pool: address(pool),
            index: 0,
            ytIn: 10 * ONE_UNDERLYING,
            underlyingOutMin: 1 * ONE_UNDERLYING,
            recipient: receiver,
            deadline: block.timestamp - 1
        });
    }

    function test_RevertIf_PoolNotExist() public override {
        MockFakePool fakePool = new MockFakePool();
        vm.expectRevert(Errors.RouterPoolNotFound.selector);
        router.swapYtForUnderlying({
            pool: address(fakePool),
            index: 0,
            ytIn: 10 * ONE_UNDERLYING,
            underlyingOutMin: 1 * ONE_UNDERLYING,
            recipient: receiver,
            deadline: block.timestamp
        });
    }

    function test_RevertIf_PtNotExist() public virtual override {
        vm.expectRevert(stdError.indexOOBError);
        router.swapYtForUnderlying({
            pool: address(pool),
            index: 3, // pt index out of bound
            ytIn: 10 * ONE_UNDERLYING,
            underlyingOutMin: 1 * ONE_UNDERLYING,
            recipient: receiver,
            deadline: block.timestamp
        });
    }

    function test_RevertIf_Reentrant() public virtual override {
        dealPts(receiver, 1e18, true);
        _approvePts(receiver, address(router), 1e18);
        _expectRevertIf_Reentrant(
            receiver,
            abi.encodeWithSelector(
                router.swapYtForUnderlying.selector,
                address(pool),
                0,
                10 * ONE_UNDERLYING,
                1 * ONE_UNDERLYING,
                receiver,
                block.timestamp
            )
        );
        vm.prank(receiver); // receiver of the callback on swapPtForUnderlying
        pool.swapPtForUnderlying(0, 10, receiver, abi.encode(NapierPool.swapPtForUnderlying.selector, pts[0]));
    }
}

contract RouterSwapYtForEthUnitTest is RouterSwapYtForUnderlyingUnitTest {
    function _deployUnderlying() internal override {
        _deployWETH();
        underlying = weth;
        uDecimals = 18;
        ONE_UNDERLYING = 1e18;
    }

    function test_RevertIf_Reentrant() public virtual override {
        dealPts(receiver, 1e18, true);
        _approvePts(receiver, address(router), 1e18);
        _expectRevertIf_Reentrant(
            receiver,
            abi.encodeWithSelector(
                router.swapYtForUnderlying.selector,
                address(pool),
                0,
                10 * ONE_UNDERLYING,
                1 * ONE_UNDERLYING,
                receiver,
                block.timestamp
            )
        );
        vm.prank(receiver); // receiver of the callback on swapPtForUnderlying
        pool.swapPtForUnderlying(0, 10, receiver, abi.encode(NapierPool.swapPtForUnderlying.selector, pts[0]));
    }

    receive() external payable {
        // receive ether from router
        require(msg.sender == address(router) || msg.sender == address(weth), "do not accept ether");
    }

    /// @dev swap yt for weth and then unwrap it to native ether
    function test_swapYtForUnderlying(uint256 i, uint256 cscale) public override {
        vm.warp(block.timestamp + 30 days);
        uint256 prevBalance = receiver.balance;
        i = bound(i, 0, N_COINS - 1);
        uint256 scale = adapters[i].scale();
        cscale = bound(cscale, scale, scale * 150 / 100);
        // mock scale change
        vm.mockCall(address(adapters[i]), abi.encodeWithSelector(adapters[i].scale.selector), abi.encode(cscale));
        // execution
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(
            router.swapYtForUnderlying,
            // note: receiver is router itself
            (address(pool), 0, 10 * ONE_UNDERLYING, 1 * ONE_UNDERLYING, address(router), block.timestamp)
        );
        data[1] = abi.encodeCall(router.unwrapWETH9, (1 * ONE_UNDERLYING, receiver));
        uint256 _before = gasleft();
        bytes[] memory ret = router.multicall(data);
        console2.log("gas usage: ", _before - gasleft());

        uint256 underlyingOut = abi.decode(ret[0], (uint256));

        assertApproxEqRel(
            yts[0].balanceOf(address(this)),
            pyBalances[0] - 10 * ONE_UNDERLYING,
            0.05 * 1e18,
            "yt should be transferred from sender"
        );
        assertGe(underlyingOut, 1 * ONE_UNDERLYING, "underlyingOut should be gt underlyingOutMin");
        assertEq(receiver.balance, prevBalance + underlyingOut, "underlyingOut should be transferred to recipient");
        assertNoFundLeftInPoolSwapRouter();
        vm.clearMockedCalls();
    }
}

contract RouterSwapUnderlyingForYtUnitTest is RouterSwapBaseTest {
    address receiver = makeAddr("receiver");

    /// @dev Initial user balances
    uint256 uBalance;

    function setUp() public virtual override {
        super.setUp();

        uBalance = 300 * ONE_UNDERLYING;
        deal(address(underlying), address(this), uBalance, false);
    }

    function test_swapUnderlyingForYt(uint256 i, uint256 cscale) public virtual {
        vm.warp(block.timestamp + 20 days);
        i = bound(i, 0, N_COINS - 1);
        uint256 scale = adapters[i].scale();
        cscale = bound(cscale, scale * 90 / 100, scale * 180 / 100);
        // mock scale change
        vm.mockCall(address(adapters[i]), abi.encodeWithSelector(adapters[i].scale.selector), abi.encode(cscale));
        // execution
        uint256 _before = gasleft();
        uint256 underlyingSpent = router.swapUnderlyingForYt({
            pool: address(pool),
            index: i,
            ytOutDesired: 10 * ONE_UNDERLYING,
            underlyingInMax: 15 * ONE_UNDERLYING,
            recipient: receiver,
            deadline: block.timestamp
        });
        console2.log("gas usage: ", _before - gasleft());
        assertApproxEqRel(
            yts[i].balanceOf(receiver), 10 * ONE_UNDERLYING, 0.05 * 1e18, "yt should be transferred to receiver"
        );
        assertEq(
            underlying.balanceOf(address(this)), uBalance - underlyingSpent, "underlyingIn should be spent from sender"
        );
        assertNoFundLeftInPoolSwapRouter();
        vm.clearMockedCalls();
    }

    function test_RevertIf_InsufficientPtRepay() public whenMaturityNotPassed {
        test_RevertIf_InsufficientPtRepay(0, 100 * ONE_UNDERLYING);
    }

    function test_RevertIf_InsufficientPtRepay(uint256 i, uint256 ytOutDesired) public {
        i = bound(i, 0, N_COINS - 1);
        ytOutDesired = bound(ytOutDesired, 10, uBalance);
        // mock insufficient pt issue
        vm.mockCall(
            address(pts[i]),
            abi.encodeWithSelector(pts[i].issue.selector),
            abi.encode(ytOutDesired - 10) // issue less than ytOutDesired
        );
        vm.expectRevert(Errors.RouterInsufficientPtRepay.selector);
        router.swapUnderlyingForYt({
            pool: address(pool),
            index: i,
            ytOutDesired: ytOutDesired,
            underlyingInMax: type(uint256).max,
            recipient: receiver,
            deadline: block.timestamp
        });
        vm.clearMockedCalls();
    }

    function test_RevertIf_DeadlinePassed() public virtual override {
        vm.expectRevert(Errors.RouterTransactionTooOld.selector);
        router.swapUnderlyingForYt({
            pool: address(pool),
            index: 0,
            ytOutDesired: 10 * ONE_UNDERLYING,
            underlyingInMax: 10 * ONE_UNDERLYING,
            recipient: receiver,
            deadline: block.timestamp - 1
        });
    }

    function test_RevertIf_PtNotExist() public virtual override {
        vm.expectRevert(stdError.indexOOBError);
        router.swapUnderlyingForYt({
            pool: address(pool),
            index: 3, // pt index out of bound
            ytOutDesired: 10 * ONE_UNDERLYING,
            underlyingInMax: 10 * ONE_UNDERLYING,
            recipient: receiver,
            deadline: block.timestamp
        });
    }

    function test_RevertIf_SlippageTooHigh() public virtual override {
        vm.expectRevert(Errors.RouterExceededLimitUnderlyingIn.selector);
        router.swapUnderlyingForYt({
            pool: address(pool),
            index: 2,
            ytOutDesired: 10 * ONE_UNDERLYING,
            underlyingInMax: ONE_UNDERLYING / 100, // too small
            recipient: receiver,
            deadline: block.timestamp
        });
    }

    function test_RevertIf_Reentrant() public virtual override {
        // TODO
    }

    function test_RevertIf_PoolNotExist() public virtual override {
        MockFakePool fakePool = new MockFakePool();
        vm.expectRevert(Errors.RouterPoolNotFound.selector);
        router.swapUnderlyingForYt({
            pool: address(fakePool),
            index: 0,
            ytOutDesired: 100 * ONE_UNDERLYING,
            underlyingInMax: 10 * ONE_UNDERLYING,
            recipient: receiver,
            deadline: block.timestamp
        });
    }
}

contract RouterSwapEthForYtUnitTest is RouterSwapUnderlyingForYtUnitTest {
    function setUp() public override {
        super.setUp();

        uBalance = 300 * ONE_UNDERLYING;
        deal(address(this), uBalance);
    }

    function _deployUnderlying() internal override {
        _deployWETH();
        underlying = weth;
        uDecimals = 18;
        ONE_UNDERLYING = 1e18;
    }

    receive() external payable {
        // receive ether from router
        require(msg.sender == address(router) || msg.sender == address(weth), "do not accept ether");
    }

    function test_swapUnderlyingForYt(uint256 i, uint256 cscale) public override {
        vm.warp(block.timestamp + 30 days);
        i = bound(i, 0, N_COINS - 1);
        uint256 scale = adapters[i].scale();
        cscale = bound(cscale, scale * 90 / 100, scale * 180 / 100);
        // mock scale change
        vm.mockCall(address(adapters[i]), abi.encodeWithSelector(adapters[i].scale.selector), abi.encode(cscale));
        // execution
        uint256 _before = gasleft();
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(
            router.swapUnderlyingForYt,
            (address(pool), i, 10 * ONE_UNDERLYING, 15 * ONE_UNDERLYING, receiver, block.timestamp)
        );
        data[1] = abi.encodeCall(router.refundETH, ());
        bytes[] memory returndata = router.multicall{value: 15 * ONE_UNDERLYING}(data); // specify `underlyingMax` to be 15 ether
        uint256 underlyingSpent = abi.decode(returndata[0], (uint256));
        console2.log("gas usage: ", _before - gasleft());

        assertApproxEqRel(
            yts[i].balanceOf(receiver), 10 * ONE_UNDERLYING, 0.05 * 1e18, "yt should be transferred to receiver"
        );
        assertEq(address(this).balance, uBalance - underlyingSpent, "underlyingIn should be spent from sender");
        assertNoFundLeftInPoolSwapRouter();
        vm.clearMockedCalls();
    }
}
