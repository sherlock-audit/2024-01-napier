pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Base} from "../Base.t.sol";
import {Properties} from "./Properties.sol";
import {BaseHandler} from "@napier/napier-v1/test/invariant/handlers/BaseHandler.sol";
import {Errors} from "src/libs/Errors.sol";

import {NapierPoolHandler} from "./handlers/NapierPoolHandler.sol";
import {TricryptoHandler} from "./handlers/TricryptoHandler.sol";
import {TimestampStore} from "@napier/napier-v1/test/invariant/TimestampStore.sol";
import {TricryptoStore} from "./TricryptoStore.sol";
import {NapierPoolStore} from "./NapierPoolStore.sol";

contract InvariantTest is Base {
    NapierPoolHandler internal napierPoolHandler;
    TricryptoHandler internal tricryptoHandler;
    TimestampStore internal timestampStore;
    TricryptoStore internal tricryptoStore;
    NapierPoolStore internal napierPoolStore;

    modifier useCurrentTimestamp() {
        vm.warp(timestampStore.currentTimestamp());
        _;
    }

    function setUp() public {
        maturity = block.timestamp + 365 days;
        _deployAdaptersAndPrincipalTokens();
        _deployCurveV2Pool();
        _deployNapierPool();
        _deployNapierRouter();
        _deployWETH();

        _label();

        timestampStore = new TimestampStore();
        tricryptoStore = new TricryptoStore();
        napierPoolStore = new NapierPoolStore();
        napierPoolHandler = new NapierPoolHandler(pool, napierPoolStore, tricryptoStore, timestampStore);
        tricryptoHandler = new TricryptoHandler(tricrypto, pts, tricryptoStore, timestampStore);

        // Target only the handlers for invariant testing (to avoid getting reverts).
        targetContract(address(napierPoolHandler));
        targetContract(address(tricryptoHandler));
        excludeArtifact("MockCallbackReceiver");

        // Prevent these contracts from being fuzzed as `msg.sender`.
        // Some contracts should be excluded from fuzzing because some handlers overwrite code
        // of callbacker, which would cause the invariant tests to break.
        excludeSender(address(this)); // invariant tests
        excludeSender(address(pool));
        excludeSender(address(underlying));
        excludeSender(address(pts[0]));
        excludeSender(address(pts[1]));
        excludeSender(address(pts[2]));
        excludeSender(address(router));
        excludeSender(address(timestampStore));
        excludeSender(address(tricryptoStore));
        excludeSender(address(napierPoolStore));

        // Dev: Ensure that invariant tests run more reliably by depositing initial liquidity to Tricrypto pool.
        // Tricrypto pool would be initialized with equal amounts of each token.
        address firstRecipient = address(0xbabe);
        _tricrypto_addLiquidity({
            sender: address(this),
            ptsIn: [1_000_000 * ONE_UNDERLYING, 1_000_000 * ONE_UNDERLYING, 1_000_000 * ONE_UNDERLYING],
            to: firstRecipient
        });
        tricryptoStore.addRecipient(firstRecipient);
    }

    /// @dev Adds liquidity to the Tricrypto pool.
    function _tricrypto_addLiquidity(address sender, uint256[3] memory ptsIn, address to) internal {
        // approve principal tokens
        for (uint256 i = 0; i < 3; i++) {
            deal(address(pts[i]), sender, ptsIn[i], true);
            pts[i].approve(address(tricrypto), ptsIn[i]);
        }
        vm.prank(sender);
        tricrypto.add_liquidity(ptsIn, 0, false, to);
    }

    /////// Invariant Tests ///////

    function invariant_poolSolvency() public useCurrentTimestamp {
        uint256 ghost_sumSkimmedUnderlyings = napierPoolStore.ghost_sumSkimmedUnderlyings(); // In thoery this is equal to sum of the protocol fees collected by Napier governance.
        uint256 ghost_sumProtocolFees = napierPoolStore.ghost_sumProtocolFees(); // In theory this is equal to the sum of protocol fees collected and to be collected by Napier governance.

        uint256 totalUnderlying = pool.totalUnderlying();

        // Note: Assertion will fail when fuzzer sets the recipient of an operation to the `pool` contract.

        // In theory, `ghost_sumSkimmedUnderlyings` should be less than or qual to `ghost_sumProtocolFees`.
        // However, due to precision loss, `ghost_sumSkimmedUnderlyings` may be some wei greater than `ghost_sumProtocolFees`.
        // So in some casese, `totalUnderlying` + `ghost_sumSkimmedUnderlyings` may be greater than `ghost_sumProtocolFees`.
        // In this case, we just check that the pool has enough underlying balance.
        if (totalUnderlying + ghost_sumProtocolFees > ghost_sumSkimmedUnderlyings) {
            assertGe(
                underlying.balanceOf(address(pool)),
                totalUnderlying + ghost_sumProtocolFees - ghost_sumSkimmedUnderlyings,
                Properties.P_01
            );
        }
        assertGe(underlying.balanceOf(address(pool)), totalUnderlying, Properties.P_01);
        assertEq(tricrypto.balanceOf(address(pool)), pool.totalBaseLpt(), Properties.P_02);
    }

    function invariant_callSummary() public view {
        console2.log("Call summary:");
        console2.log("-------------------");
        address[] memory targets = targetContracts();
        for (uint256 i = 0; i < targets.length; i++) {
            BaseHandler(targets[i]).callSummary();
        }
    }
}
