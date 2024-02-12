// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import {Base} from "../../Base.t.sol";

import {CallbackType, CallbackDataTypes} from "src/libs/CallbackDataTypes.sol";
import {Errors} from "src/libs/Errors.sol";

contract RouterCallbackTest is Base {
    function setUp() public virtual {
        maturity = block.timestamp + 365 days;
        _deployAdaptersAndPrincipalTokens();
        _deployCurveV2Pool();
        _deployNapierPool();
        _deployNapierRouter();

        _label();
    }

    function testFuzz_swapCallback_RevertIf_NotPool(address caller) public {
        vm.assume(caller != address(pool));
        vm.prank(caller);

        vm.expectRevert(Errors.RouterCallbackNotNapierPool.selector);
        router.swapCallback(
            -1000,
            2000,
            abi.encode(
                CallbackType.SwapPtForUnderlying,
                underlying,
                tricrypto,
                CallbackDataTypes.SwapPtForUnderlyingData({payer: msg.sender, pt: pts[0]})
            )
        );

        vm.expectRevert(Errors.RouterCallbackNotNapierPool.selector);
        router.swapCallback(
            -1000,
            2000,
            abi.encode(
                CallbackType.SwapUnderlyingForPt,
                underlying,
                tricrypto,
                CallbackDataTypes.SwapUnderlyingForPtData({payer: msg.sender, underlyingInMax: type(uint256).max})
            )
        );
    }

    function testFuzz_mintCallback_RevertIf_NotPool(address caller) public {
        vm.assume(caller != address(pool));
        vm.prank(caller);
        vm.expectRevert(Errors.RouterCallbackNotNapierPool.selector);
        router.mintCallback(
            1000,
            2000,
            abi.encode(
                CallbackType.AddLiquidityPts,
                CallbackDataTypes.AddLiquidityData({
                    payer: msg.sender,
                    underlying: address(underlying),
                    basePool: address(tricrypto)
                })
            )
        );
    }
}
