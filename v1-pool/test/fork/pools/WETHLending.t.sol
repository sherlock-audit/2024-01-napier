// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {ForkTest} from "../Fork.t.sol";

import {IERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/IERC20.sol";
import {Tranche} from "@napier/napier-v1/src/Tranche.sol";
import {YieldToken} from "@napier/napier-v1/src/YieldToken.sol";
import {IBaseAdapter} from "@napier/napier-v1/src/interfaces/IBaseAdapter.sol";
import {MockAdapter} from "@napier/napier-v1/test/mocks/MockAdapter.sol";

import {TrancheFactory} from "@napier/napier-v1/src/TrancheFactory.sol";
import {MA3WETHAdapter} from "@napier/napier-v1/src/adapters/morphoAaveV3/MA3WETHAdapter.sol";
import {WrappedCETHAdapter} from "@napier/napier-v1/src/adapters/compoundV2/WrappedCETHAdapter.sol";
import {AaveV3Adapter} from "@napier/napier-v1/src/adapters/aaveV3/AaveV3Adapter.sol";

import "@napier/napier-v1/src/Constants.sol" as Constants;

library Casts {
    function asMockAdapter(IBaseAdapter x) internal pure returns (MockAdapter) {
        return MockAdapter(address(x));
    }
}

contract WETHLending_ForkTest is ForkTest {
    using Casts for *;

    address constant MORPHO_REWARDS_DISTRIBUTOR = 0x3B14E5C73e0A56D607A8688098326fD4b4292135;
    address constant rewardsController = 0x8164Cc65827dcFe994AB23944CBC90e0aa80bFcb;

    function _label() internal override {
        super._label();
        vm.label(Constants.MA3WETH, "ma3WETHERC4626Vault");
        vm.label(Constants.MORPHO_AAVE_V3, "morphoAaveV3ETH");
        vm.label(0xeA51d7853EEFb32b6ee06b1C12E6dcCA88Be0fFE, "aaveVariableDebtWETH");
        vm.label(Constants.WETH, "WETH");
        vm.label(Constants.AAVEV3_POOL_ADDRESSES_PROVIDER, "AAVEV3_POOL_ADDRESSES_PROVIDER");
    }

    function _deployUnderlying() internal override {
        underlying = weth;
        uDecimals = 18;
        ONE_UNDERLYING = 1e18;
        FUZZ_MAX_UNDERLYING = 100 * ONE_UNDERLYING;
    }

    function _deployAdaptersAndPrincipalTokens() internal override {
        _deployUnderlying();
        trancheFactory = new TrancheFactory(owner);

        /// Hack Fix `adapters` type to be `IBaseAdapter[]`
        adapters = [
            new WrappedCETHAdapter(feeRecipient).asMockAdapter(),
            new AaveV3Adapter(Constants.WETH, Constants.AWETH, feeRecipient, rewardsController).asMockAdapter(),
            new MA3WETHAdapter(feeRecipient, MORPHO_REWARDS_DISTRIBUTOR).asMockAdapter()
        ];
        targets = [IERC20(adapters[0].target()), IERC20(adapters[1].target()), IERC20(adapters[2].target())];

        for (uint256 i = 0; i < N_COINS; i++) {
            vm.prank(owner);
            pts[i] = Tranche(trancheFactory.deployTranche(address(adapters[i]), maturity, tilt, issuanceFee));
            yts[i] = YieldToken(pts[i].yieldToken());
        }
    }

    modifier boundParamsSwap(Params_Swap memory params) override {
        if (useEth) assumePayable(params.recipient); // make sure recipient can be payable
        vm.assume(params.recipient != address(0) && params.recipient != address(pool)); // make sure recipient is not the pool itself
        params.timestamp = _bound(params.timestamp, block.timestamp, maturity - 1);
        params.index = _bound(params.index, 0, 2);
        params.amount = _bound(params.amount, ONE_UNDERLYING / 100, FUZZ_MAX_UNDERLYING); // swap large amount will revert
        _;
    }
}

contract WETHLendingETH_ForkTest is WETHLending_ForkTest {
    constructor() {
        useEth = true;
    }
}
