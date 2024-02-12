// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {Base} from "../Base.t.sol";
import {VyperDeployer} from "../../lib/VyperDeployer.sol";

import {IWETH9} from "src/interfaces/external/IWETH9.sol";

contract ForkTest is Base {
    /// @notice Nov-18-2023 04:45:59 PM +UTC
    /// @dev The block number at which the fork is selected.
    uint256 blockNumber = 18_600_000;
    string network = "mainnet";

    /// @dev Maximum amount of underlying that can be fuzzed. This should be properly configured.
    uint256 FUZZ_MAX_UNDERLYING = 1_000_000 * 1e6; // For USDC

    /// @dev A user to be used for testing.
    address alice = makeAddr("alice");
    uint256 initialAliceBalance;

    /// @dev The flag to indicate whether to use ETH or WETH for operations.
    bool useEth;

    function setUp() public virtual {
        // Fork Ethereum Mainnet at a specific block number.
        vm.createSelectFork({blockNumber: blockNumber, urlOrAlias: network});

        // create a new instance of VyperDeployer
        vyperDeployer = new VyperDeployer().setEvmVersion("shanghai");

        maturity = block.timestamp + 365 days;

        weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH Ethereum Mainnet
        _deployAdaptersAndPrincipalTokens();
        _deployCurveV2Pool();
        _deployNapierPool();
        _deployNapierRouter();
        _deployTrancheRouter();

        _label();

        // Set up the initial liquidity to Tricrypto and Napier Pool.
        _issueAndAddLiquidities({
            recipient: address(this),
            underlyingIn: 10_000 * ONE_UNDERLYING,
            uIssues: [10_000 * ONE_UNDERLYING, 10_000 * ONE_UNDERLYING, 10_000 * ONE_UNDERLYING]
        });

        _fund();

        vm.startPrank(alice);
    }

    /// @dev Override the function to set initial balances.
    function _fund() internal virtual {
        initialAliceBalance = 10_000_000 * ONE_UNDERLYING; // 10M
        deal(address(underlying), alice, initialAliceBalance, false); // underlying
        vm.deal(alice, initialAliceBalance); // eth
    }

    struct Params_AddLiquidity {
        uint256 timestamp;
        uint256 underlyingIn;
        uint256[3] ptsIn;
        address recipient;
    }

    modifier boundParamsAddLiquidity(Params_AddLiquidity memory params) {
        assumeNotZeroAddress(params.recipient);
        params.timestamp = _bound(params.timestamp, block.timestamp, maturity - 1);

        // Bound the input values. The bounds are chosen to be somewhat balanced.
        params.ptsIn[0] = _bound(params.ptsIn[0], ONE_UNDERLYING / 100, FUZZ_MAX_UNDERLYING);
        params.ptsIn[1] = _bound(params.ptsIn[1], params.ptsIn[0] * 2 / 3, params.ptsIn[0] * 3 / 2); // 2/3 - 3/2 of ptsIn[0]
        params.ptsIn[2] = _bound(params.ptsIn[2], params.ptsIn[0] * 2 / 3, params.ptsIn[0] * 3 / 2);
        params.underlyingIn = _bound(params.underlyingIn, ONE_UNDERLYING / 100, FUZZ_MAX_UNDERLYING); // 0.01 - 1M underlying
        _;
    }

    /// @dev Checklist:
    /// - It shouldn't leave any fund in the router.
    /// - It should issue the principal token.
    /// - It should mint the Napier Pool LP token.
    ///
    /// Given enough fuzz runs, all of the following scenarios will be fuzzed:
    /// - Multiple values for the recipient
    /// - Multiple values for the underlying amount to be issued
    /// - Timestamp before the maturity
    function testFork_AddLiquidity(Params_AddLiquidity memory params) public boundParamsAddLiquidity(params) {
        vm.warp(params.timestamp);

        // Execution
        for (uint256 i = 0; i < 3; i++) {
            params.ptsIn[i] = issue(alice, i, params.ptsIn[i], alice);
            assertEq(pts[i].balanceOf(alice), params.ptsIn[i], "AddLiquidity: Alice should receive principal token");
        }

        uint256 balanceBefore = pool.balanceOf(params.recipient);
        uint256 liquidity = addLiquidity(alice, params.underlyingIn, params.ptsIn, params.recipient, 0);
        // Assertion
        assertEq(
            liquidity,
            pool.balanceOf(params.recipient) - balanceBefore,
            "AddLiquidity: Recipient should receive liquidity tokens"
        );
    }

    struct Params_RemoveLiquidity {
        uint256 timestamp;
        uint256 liquidity;
        address recipient;
    }

    /// @dev Checklist:
    /// - It shouldn't leave any fund in the router.
    /// - It should burn the Napier Pool LP token and return the underlying and principal tokens.
    ///
    /// Given enough fuzz runs, all of the following scenarios will be fuzzed:
    /// - Multiple values for the recipient
    /// - Multiple values for liquidity to be removed
    /// - Timestamp before the maturity
    /// - Timestamp after the maturity
    function testFork_RemoveLiquidity(
        Params_AddLiquidity memory params_addLiq,
        Params_RemoveLiquidity memory params_removeLiq
    ) public {
        if (useEth) assumePayable(params_removeLiq.recipient); // make sure recipient can be payable
        assumeNotZeroAddress(params_removeLiq.recipient);

        // Add liquidity first
        params_addLiq.recipient = alice; // Alice receives the LP token here.
        testFork_AddLiquidity(params_addLiq);

        params_removeLiq.timestamp = _bound(params_removeLiq.timestamp, block.timestamp, maturity + 365 days);
        params_removeLiq.liquidity = _bound(params_removeLiq.liquidity, 10000, pool.balanceOf(alice));

        uint256 uBalance = underlyingBalanceOf(params_removeLiq.recipient);
        uint256[3] memory ptsBalance = [
            pts[0].balanceOf(params_removeLiq.recipient),
            pts[1].balanceOf(params_removeLiq.recipient),
            pts[2].balanceOf(params_removeLiq.recipient)
        ];
        // Execution
        (uint256 underlyingOut, uint256[3] memory ptsOut) =
            removeLiquidity(alice, params_removeLiq.liquidity, params_removeLiq.recipient);
        // Assertion - check the balances changes
        assertEq(
            underlyingBalanceOf(params_removeLiq.recipient),
            uBalance + underlyingOut,
            "RemoveLiquidity: Recipient should receive underlying"
        );
        for (uint256 i = 0; i < 3; i++) {
            assertEq(
                pts[i].balanceOf(params_removeLiq.recipient),
                ptsBalance[i] + ptsOut[i],
                "RemoveLiquidity: Recipient should receive principal token"
            );
        }
    }

    struct Params_Swap {
        uint256 timestamp;
        uint256 index;
        uint256 amount;
        address recipient;
    }

    modifier boundParamsSwap(Params_Swap memory params) virtual {
        if (useEth) assumePayable(params.recipient); // make sure recipient can be payable
        vm.assume(params.recipient != address(0) && params.recipient != address(pool)); // make sure recipient is not the pool itself
        params.timestamp = _bound(params.timestamp, block.timestamp, maturity - 1);
        params.index = _bound(params.index, 0, 2);
        params.amount = _bound(params.amount, ONE_UNDERLYING / 100, 1_000 * ONE_UNDERLYING); // swap large amount will revert
        _;
    }

    /// @dev Checklist:
    /// - It shouldn't leave any fund in the router.
    /// - It should perform ERC20-transfer correctly.
    /// - It should not benefit users when round-trip swapping. (i.e. swap underlying for principal token and then immediately swap back)
    ///
    /// Given enough fuzz runs, all of the following scenarios will be fuzzed:
    /// - Multiple values for the recipient
    /// - Multiple values for the amount to be swapped
    /// - Timestamp before the maturity
    function testFork_RoundTrip_SwapPt(Params_Swap memory params_swap) public boundParamsSwap(params_swap) {
        uint256 index = params_swap.index;
        vm.warp(params_swap.timestamp);

        // Swap underlying for principal token and then immediately swap back.
        // The underlying used at the first swap should be greater than the underlying back.
        uint256 underlyingIn;
        uint256 actualPtOut; // actual principal token out could be less than requested due to precision loss
        {
            // Execution
            uint256 ptBalance = pts[index].balanceOf(alice);
            underlyingIn = swapUnderlyingForPt(alice, index, params_swap.amount, alice);
            actualPtOut = pts[index].balanceOf(alice) - ptBalance;
            // Assertion - check the balances changes
            assertApproxEqRel(
                actualPtOut,
                params_swap.amount,
                // Note: Tricrypto view method doesn't return the exact amount of principal token can be withdrawn.
                0.001 * 1e18,
                "SwapPt: Alice should receive principal token"
            );
        }
        {
            // Execution
            uint256 uBalance = underlyingBalanceOf(params_swap.recipient);
            uint256 ptBalance = pts[index].balanceOf(alice);
            uint256 underlyingOut = swapPtForUnderlying(alice, index, actualPtOut, params_swap.recipient); // swap the principal token we just got
            // Assertion - check the balances changes
            assertEq(
                pts[index].balanceOf(alice),
                ptBalance - actualPtOut,
                "SwapPt: Alice should send principal token to pool"
            );
            assertEq(
                underlyingBalanceOf(params_swap.recipient),
                uBalance + underlyingOut,
                "SwapPt: Recipient should receive underlying"
            );
            // Assertion - check the round-trip
            assertGe(
                underlyingIn, underlyingOut, "SwapPt: [round-trip] underlyingIn should be greater than underlyingOut"
            );
        }
    }

    //////////////////////////////////////////////////////////////////
    // Helpers
    //////////////////////////////////////////////////////////////////

    /// @dev Helper function to get the underlying balance of an account (either ETH or ERC20).
    function underlyingBalanceOf(address account) public view returns (uint256) {
        if (useEth) return account.balance;
        else return underlying.balanceOf(account);
    }

    //////////////////////////////////////////////////////////////////
    // Functions
    //////////////////////////////////////////////////////////////////

    function addLiquidity(
        address sender,
        uint256 underlyingIn,
        uint256[3] memory ptsIn,
        address recipient,
        uint256 minLiquidity
    ) public returns (uint256) {
        changePrank(sender);
        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeCall(
            router.addLiquidity, (address(pool), underlyingIn, ptsIn, minLiquidity, recipient, block.timestamp)
        );
        data[1] = abi.encodeCall(router.sweepToken, (address(tricrypto), 0, sender));
        uint256 value;
        if (useEth) {
            // make sure recipient can be payable
            value = underlyingIn; // set value to `underlyingIn` if useEth
            data[2] = abi.encodeCall(router.refundETH, ());
        } else {
            underlying.approve(address(router), underlyingIn);
            data[2] = abi.encodeCall(router.sweepToken, (address(weth), 0, sender));
        }
        for (uint256 i = 0; i < 3; i++) {
            pts[i].approve(address(router), ptsIn[i]);
        }
        bytes[] memory ret = router.multicall{value: value}(data);
        uint256 liquidity = abi.decode(ret[0], (uint256));

        if (recipient != address(router)) assertNoFundLeftInPoolSwapRouter();
        assertReserveBalanceMatch();

        return liquidity;
    }

    function removeLiquidity(address sender, uint256 liquidity, address recipient)
        public
        returns (uint256 underlyingOut, uint256[3] memory ptsOut)
    {
        changePrank(sender);
        pool.approve(address(router), liquidity);
        if (useEth) {
            // make sure recipient can be payable
            bytes[] memory data = new bytes[](3);
            data[0] = abi.encodeCall(
                router.removeLiquidity,
                // set recipient to router if useEth
                (address(pool), liquidity, 0, [uint256(0), 0, 0], address(router), block.timestamp)
            );
            address[] memory tokens = new address[](3);
            (tokens[0], tokens[1], tokens[2]) = (address(pts[0]), address(pts[1]), address(pts[2])); // principal tokens
            data[1] = abi.encodeCall(router.sweepTokens, (tokens, new uint256[](3), recipient));
            data[2] = abi.encodeCall(router.unwrapWETH9, (0, recipient));
            // batch call
            bytes[] memory ret = router.multicall(data);
            (underlyingOut, ptsOut) = abi.decode(ret[0], (uint256, uint256[3]));
        } else {
            (underlyingOut, ptsOut) =
                router.removeLiquidity(address(pool), liquidity, 0, [uint256(0), 0, 0], recipient, block.timestamp);
        }
        // Assertion
        assertReserveBalanceMatch();
        if (recipient != address(router)) assertNoFundLeftInPoolSwapRouter();
    }

    function swapPtForUnderlying(address sender, uint256 index, uint256 amount, address recipient)
        public
        returns (uint256 underlyingOut)
    {
        changePrank(sender);
        pts[index].approve(address(router), amount);
        if (useEth) {
            bytes[] memory data = new bytes[](2);
            data[0] = abi.encodeCall(
                // set recipient to router if useEth
                router.swapPtForUnderlying,
                (address(pool), index, amount, 0, address(router), block.timestamp)
            );
            // make sure recipient can be payable
            data[1] = abi.encodeCall(router.unwrapWETH9, (0, recipient));
            bytes[] memory ret = router.multicall(data);
            underlyingOut = abi.decode(ret[0], (uint256));
        } else {
            underlyingOut = router.swapPtForUnderlying(address(pool), index, amount, 0, recipient, block.timestamp);
        }
        // Assertion
        assertReserveBalanceMatch();
        if (recipient != address(pool)) assertNoFundLeftInPoolSwapRouter();
    }

    function swapUnderlyingForPt(address sender, uint256 index, uint256 ptDesired, address recipient)
        public
        returns (uint256 underlyingIn)
    {
        changePrank(sender);
        uint256 maxIn = ptDesired * 15 / 10;
        underlying.approve(address(router), type(uint256).max);
        if (useEth) {
            bytes[] memory data = new bytes[](2);
            data[0] = abi.encodeCall(
                // set recipient to router if useEth
                router.swapUnderlyingForPt,
                (address(pool), index, ptDesired, maxIn, recipient, block.timestamp)
            );
            data[1] = abi.encodeCall(router.refundETH, ());
            // In most cases, `ptDesired` eth would be enough to swap `ptDesired` principal token.
            bytes[] memory ret = router.multicall{value: maxIn}(data);
            underlyingIn = abi.decode(ret[0], (uint256));
        } else {
            underlyingIn =
                router.swapUnderlyingForPt(address(pool), index, ptDesired, maxIn, recipient, block.timestamp);
        }
        // Assertion
        assertReserveBalanceMatch();
        if (recipient != address(pool)) assertNoFundLeftInPoolSwapRouter();
    }

    function issue(address sender, uint256 index, uint256 underlyingAmount, address recipient)
        public
        returns (uint256)
    {
        changePrank(sender);

        uint256 value;
        if (useEth) value = underlyingAmount;
        else underlying.approve(address(trancheRouter), underlyingAmount);

        uint256 issued = trancheRouter.issue{value: value}({
            adapter: address(adapters[index]),
            maturity: maturity,
            to: recipient,
            underlyingAmount: underlyingAmount
        });
        if (recipient != address(trancheRouter)) assertNoFundLeftInTrancheRouter();
        return issued;
    }
}
