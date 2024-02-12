// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./BaseTest.sol";

import {ERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";
import {FixedPointMathLib} from "src/utils/FixedPointMathLib.sol";
import {SafeCast} from "@openzeppelin/contracts@4.9.3/utils/math/SafeCast.sol";

import {BaseAdapter} from "src/BaseAdapter.sol";
import {YieldToken} from "src/YieldToken.sol";
import {TrancheFactory} from "src/TrancheFactory.sol";
import {Tranche} from "src/Tranche.sol";
import {ITranche} from "src/interfaces/ITranche.sol";

import {HardhatDeployer} from "hardhat-deployer/HardhatDeployer.sol";

/// @notice helper functions to deploy Adapter
abstract contract AdapterFixture is BaseTest {
    ERC20 underlying;
    ERC20 target;

    BaseAdapter adapter;

    /// @notice 1 Underlying unit = 10^(underlying decimals)
    uint256 ONE_SCALE;
    /// @notice 1 Target unit = 10^(target decimals)
    uint256 ONE_TARGET;

    function setUp() public virtual {
        _deployAdapter();
        ONE_SCALE = 10 ** underlying.decimals();
        ONE_TARGET = 10 ** target.decimals();
        vm.label(address(underlying), "underlying");
        vm.label(address(target), "target");
        vm.label(address(adapter), "adapter");
    }

    /// @notice helper function to deploy an Adapter
    /// @dev this function is called in `setUp` and can be overridden to deploy an Adapter with custom parameters
    ///     The three variables should be set in this function:
    ///      - Set `underlying`
    ///      - Set `target`
    ///      - Deploy `adapter`
    function _deployAdapter() internal virtual;
}

/// @notice helper functions to deploy Tranche and associated contracts
abstract contract CompleteFixture is AdapterFixture {
    using FixedPointMathLib for uint256;
    using SafeCast for uint256;

    bool ENABLE_GAS_LOGGING = vm.envOr("ENABLE_GAS_LOGGING", false);
    TrancheFactory factory;
    Tranche tranche;
    YieldToken yt;

    uint256 MIN_UNDERLYING_DEPOSIT = 100;
    uint256 MAX_UNDERLYING_DEPOSIT = MAX_UINT128;

    uint256 _maturity = 3 * 365 days;
    uint256 _tilt;
    uint256 _issuanceFee;

    /// GlobalSales cache at initialization
    /// @dev must be set in `setUp`
    Tranche.GlobalScales gscalesCache;

    /// @dev error tolerance (absolute value) `|expected - actual| <= _DELTA_` used in `assertApproxEqAbs`
    /// @dev must be set in `setUp` (default value is 0)
    uint256 _DELTA_ = 0;

    /// @dev initial underlying balance of This test contract
    /// @dev must be set in `setUp`
    uint256 initialBalance;

    function setUp() public virtual override {
        super.setUp();
        factory = new TrancheFactory(management);
        _deployTranche();

        // set labels
        vm.label(address(factory), "factory");
        vm.label(address(tranche), "tranche");
        vm.label(address(yt), "yt");

        initialBalance = 100 * ONE_SCALE;

        _postDeploy();
        vm.recordLogs(); // start recording events.
        // OVERRIDE
        // - set delta if needed
        // - set maturity, tilt, issuance fee and gscalesCache
        // - approve tranche to spend underlying
        // - set initial balance
        // - fund this contract with underlying
    }

    /// @notice helper function to deploy TrancheFactory
    function _deployTrancheFactory() internal virtual {
        if (vm.envOr("OPTIMIZE", false)) {
            factory = TrancheFactory(
                HardhatDeployer.deployContract(
                    "artifacts/src/TrancheFactory.sol/TrancheFactory.json",
                    abi.encode(management),
                    HardhatDeployer.Library({
                        name: "Create2TrancheLib",
                        path: "src/Create2TrancheLib.sol",
                        libAddress: HardhatDeployer.deployContract(
                            "artifacts/src/Create2TrancheLib.sol/Create2TrancheLib.json"
                        )
                    })
                )
            );
        } else {
            factory = new TrancheFactory(management);
        }
    }

    /// @notice helper function to deploy a Tranche
    /// @dev this function is called in `setUp` and can be overridden to deploy a Tranche with custom parameters
    /// By default, devs do not need to override this function
    function _deployTranche() internal virtual {
        vm.prank(management);
        tranche = Tranche(factory.deployTranche(address(adapter), _maturity, _tilt, _issuanceFee));
        yt = YieldToken(tranche.yieldToken());
    }

    /// @notice helper function to setup `collect` tests
    /// @param caller the address of the issuer
    /// @param uDeposit the amount of underlying to deposit into the Tranche
    /// @param unclaimedYield the amount of unclaimed yield to set for the caller in the Tranche
    /// unclaimedYield is set by overwriting the `unclaimedYields` mapping with cheat codes
    function _setUpPreCollect(address caller, uint256 uDeposit, uint256 unclaimedYield) public {
        _issue(caller, caller, uDeposit);
        _overwriteWithOneKey(address(tranche), "unclaimedYields(address)", caller, unclaimedYield);
    }

    function _postDeploy() internal virtual {
        // store initial scales
        gscalesCache = tranche.getGlobalScales();

        // exclude adapter from fuzzing tests
        accountsExcludedFromFuzzing[address(adapter)] = true;
        // exclude the contract from invariant tests
        excludeContract(address(adapter));
        excludeSender(address(adapter));
    }

    ///////////////////////////////////////////////////////////////////////
    // HELPERS FOR UNDERLYING/TARGET TOKENS
    ///////////////////////////////////////////////////////////////////////

    /// @notice Converts underlying amount to shares
    /// @param amount Amount of underlying to convert
    /// @param scale Scale to use for conversion
    function _convertToShares(uint256 amount, uint256 scale) internal pure returns (uint256 shares) {
        shares = amount.mulDivDown(WAD, scale);
    }

    function _convertToSharesRoundUp(uint256 amount, uint256 scale) internal pure returns (uint256 shares) {
        shares = amount.mulDivUp(WAD, scale);
    }

    function _convertToUnderlying(uint256 shares, uint256 scale) internal pure returns (uint256 underlying) {
        underlying = shares.mulDivDown(scale, WAD);
    }

    function _calculateYieldRoundDown(
        uint256 amount,
        uint256 prevScale,
        uint256 currScale
    ) internal pure returns (uint256) {
        uint256 currShares = _convertToSharesRoundUp(amount, currScale);
        uint256 prevShares = _convertToShares(amount, prevScale);
        if (prevShares <= currShares) {
            return 0;
        }

        return prevShares - currShares;
    }

    ///////////////////////////////////////////////////////////////////////
    // HELPERS FOR TRANCHE
    ///////////////////////////////////////////////////////////////////////

    /// @notice helper function to issue PT+YT to `to` from `from`
    /// @param from the address of the issuer
    /// @param to the address of the recipient of the PT+YT
    /// @param underlyingAmount the amount of underlying to deposit into the Tranche
    /// @return issued the amount of PT(YT) issued
    function _issue(address from, address to, uint256 underlyingAmount) public returns (uint256 issued) {
        _approve(address(underlying), from, address(tranche), type(uint256).max);
        vm.prank(from);
        uint256 _before = gasleft();
        issued = tranche.issue(to, underlyingAmount);
        if (ENABLE_GAS_LOGGING) console.log("issue() gas usage: ", _before - gasleft());
    }

    function _redeem(
        address from,
        address to,
        uint256 principalAmount,
        address caller
    ) public returns (uint256 redeemed) {
        _approve(address(tranche), from, caller, type(uint256).max);
        vm.prank(caller);
        uint256 _before = gasleft();
        redeemed = tranche.redeem({principalAmount: principalAmount, to: to, from: from});
        if (ENABLE_GAS_LOGGING) console.log("redeem() gas usage: ", _before - gasleft());
    }

    function _redeemWithYT(address from, address to, uint256 amount, address caller) public returns (uint256 redeemed) {
        _approve(address(tranche), from, caller, type(uint256).max);
        _approve(address(yt), from, caller, type(uint256).max);

        vm.prank(caller);
        uint256 _before = gasleft();
        redeemed = tranche.redeemWithYT({pyAmount: amount, from: from, to: to});
        if (ENABLE_GAS_LOGGING) console.log("redeemWithYT() gas usage: ", _before - gasleft());
    }

    /// @notice helper function to collect yield
    /// @param caller the address of the collector
    /// @return collectedInTarget the amount of Target collected.
    /// @return collectedInUnderlying the amount of Underlying collected.
    function _collect(address caller) public returns (uint256 collectedInTarget, uint256 collectedInUnderlying) {
        vm.prank(caller);
        uint256 _before = gasleft();
        collectedInUnderlying = tranche.collect();
        uint256 used = _before - gasleft();
        collectedInTarget = _getCollectedInTargetFromEvent();
        if (ENABLE_GAS_LOGGING) console.log("collect() gas usage: ", used);
    }

    /// @dev helper function to get the amount of Target redeemed from the last `collect`.
    /// For this function to work, `vm.recordLogs()` must be called before the `collect` call.
    /// Fetches the last `Collect` event and returns the second argument (the amount of Target collected)
    /// @return the amount of Target collected
    function _getCollectedInTargetFromEvent() internal returns (uint256) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        require(logs.length > 0, "No logs recorded. Did you call `vm.recordLogs()`?");
        for (uint256 i = logs.length - 1; i > 0; i--) {
            bytes32 topic0 = logs[i].topics[0]; // topic0 is the event signature
            if (logs[i].emitter != address(tranche)) continue;
            // Event: Collect(address indexed, uint256)
            if (topic0 == keccak256("Collect(address,uint256)")) {
                uint256 collected = abi.decode(logs[i].data, (uint256));
                return collected;
            }
        }
        revert("Collect event not found");
    }

    /// @notice returns true if sunny day conditions are met
    function _isSunnyDay() public view returns (bool) {
        ITranche.Series memory _series = tranche.getSeries();
        uint256 oneSubTilt = MAX_BPS - _series.tilt;
        return ((_series.mscale * MAX_BPS) / _series.maxscale >= oneSubTilt);
    }

    function _isMatured(uint256 maturity) internal view returns (bool) {
        return block.timestamp >= maturity;
    }

    function _isMatured() internal view returns (bool) {
        return _isMatured(_maturity);
    }

    /// @dev Round up towards the protocol (against a user)
    function _getIssuanceFee(uint256 amount, uint256 feeBps) internal pure returns (uint256) {
        return amount.mulDivUp(feeBps, MAX_BPS);
    }

    function _getIssuanceFee(uint256 amount) internal view returns (uint256) {
        return _getIssuanceFee(amount, _issuanceFee);
    }

    function boundU32(uint32 x, uint256 min, uint256 max) internal view returns (uint32) {
        return bound(x, min, max).toUint32();
    }

    ///////////////////////////////////////////////////////////////////////
    // VIRTUAL FUNCTIONS
    ///////////////////////////////////////////////////////////////////////

    /// @dev simulate a scale increase
    /// this is used for simulating sunny day condition of Principal Token
    function _simulateScaleIncrease() internal virtual;

    /// @dev simulate a scale decrease
    /// this is used for simulating not sunny day condition of Principal Token
    function _simulateScaleDecrease() internal virtual;
}
