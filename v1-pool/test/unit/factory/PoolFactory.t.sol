// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {CurveTricryptoOptimizedWETH} from "src/interfaces/external/CurveTricryptoOptimizedWETH.sol";
import {CurveTricryptoFactory} from "src/interfaces/external/CurveTricryptoFactory.sol";
import {IERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/IERC20.sol";

import {IPoolFactory} from "src/interfaces/IPoolFactory.sol";
import {PoolFactory} from "src/PoolFactory.sol";
import {NapierPool} from "src/NapierPool.sol";
import {Errors} from "src/libs/Errors.sol";
import {sd, ln, intoInt256} from "@prb/math/SD59x18.sol"; // used for logarithm operation

import "forge-std/Test.sol";
import {Base} from "../../Base.t.sol";

contract PoolFactoryUnitTest is Base {
    function setUp() public {
        maturity = block.timestamp + 365 days;
        _deployAdaptersAndPrincipalTokens();
        _deployCurveV2Pool();
        poolFactory = new PoolFactory(address(curveFactory), owner);

        _label();
    }

    function test_constructor() public virtual {
        assertEq(poolFactory.owner(), address(owner));
        assertEq(address(poolFactory.curveTricryptoFactory()), address(curveFactory));
        assertEq(poolFactory.POOL_CREATION_HASH(), hashInitCode(type(NapierPool).creationCode));
    }

    function testFuzz_poolFor(address _basePool, address _underlying) public virtual {
        vm.assume(_basePool != address(0) && _underlying != address(0));

        bytes32 salt = keccak256(abi.encode(_basePool, _underlying));
        address expected =
            computeCreate2Address(salt, hashInitCode(type(NapierPool).creationCode), address(poolFactory));
        //assert
        assertEq(poolFactory.poolFor(_basePool, _underlying), expected, "CREATE2 address mismatch");
    }

    // ABI encoder v2 will revert if the upper bits are dirty
    function testFuzz_poolFor_RevertWhen_DirtyBits(address _basePool, address _underlying, uint256 random)
        public
        virtual
    {
        vm.assume(_basePool != address(0) && _underlying != address(0));
        vm.expectRevert();
        (bool s,) = address(poolFactory).staticcall(
            abi.encodeWithSelector(
                poolFactory.poolFor.selector,
                (uint256(keccak256(abi.encodePacked(random))) << 160) | uint256(uint160(_basePool)),
                (uint256(keccak256(abi.encodePacked(random))) << 160) | uint256(uint160(_underlying))
            )
        );
        s;
    }

    function test_deployPool() public virtual {
        IPoolFactory.PoolConfig memory _poolConfig = IPoolFactory.PoolConfig({
            initialAnchor: 1.2 * 1e18,
            scalarRoot: 8 * 1e18,
            lnFeeRateRoot: 0.000995 * 1e18,
            protocolFeePercent: 80,
            feeRecipient: feeRecipient
        });
        // deploy
        vm.prank(owner);
        address pool = poolFactory.deploy(address(tricrypto), address(underlying), _poolConfig);
        // assert
        assertEq(poolFactory.getPoolAssets(pool).basePool, address(tricrypto), "basePool address mismatch");
        assertEq(poolFactory.getPoolAssets(pool).underlying, address(underlying), "underlying address mismatch");
        assertEq(
            poolFactory.getPoolAssets(pool).principalTokens[0], address(pts[0]), "principalTokens[0] address mismatch"
        );
        assertEq(
            poolFactory.getPoolAssets(pool).principalTokens[1], address(pts[1]), "principalTokens[1] address mismatch"
        );
        assertEq(
            poolFactory.getPoolAssets(pool).principalTokens[2], address(pts[2]), "principalTokens[2] address mismatch"
        );
        assertEq(poolFactory.args().assets.basePool, address(0), "should be 0-value");
        assertEq(poolFactory.args().assets.underlying, address(0), "should be 0-value");
        assertEq(poolFactory.args().assets.principalTokens[0], address(0), "should be 0-value");
        assertEq(poolFactory.args().assets.principalTokens[1], address(0), "should be 0-value");
        assertEq(poolFactory.args().assets.principalTokens[2], address(0), "should be 0-value");
    }

    function test_deployPool_RevertIf_UnderlyingMismatch() public virtual {
        address _invalidUnderlying = address(0x123);
        vm.expectRevert(Errors.FactoryUnderlyingMismatch.selector);
        vm.prank(owner);
        poolFactory.deploy(address(tricrypto), _invalidUnderlying, poolConfig);
    }

    function test_deployPool_RevertIf_UnderlyingMismatch(uint256 index, address invalidUnderlying) public virtual {
        vm.assume(invalidUnderlying != address(underlying));
        index = _bound(index, 0, 2);
        vm.mockCall(
            address(pts[index]), abi.encodeWithSelector(pts[index].underlying.selector), abi.encode(invalidUnderlying)
        );
        vm.expectRevert(Errors.FactoryUnderlyingMismatch.selector);
        vm.prank(owner);
        poolFactory.deploy(address(tricrypto), address(underlying), poolConfig);
    }

    function test_deployPool_RevertIf_MaturityMismatch() public virtual {
        vm.mockCall(address(pts[0]), abi.encodeWithSelector(pts[0].maturity.selector), abi.encode(1 + maturity));
        vm.expectRevert(Errors.FactoryMaturityMismatch.selector);
        vm.prank(owner);
        poolFactory.deploy(address(tricrypto), address(underlying), poolConfig);
    }

    function test_deployPool_RevertIf_MaturityMismatch(uint256 index, uint256 invalidMaturity) public virtual {
        vm.assume(invalidMaturity != maturity);
        index = _bound(index, 0, 2);
        vm.mockCall(
            address(pts[index]), abi.encodeWithSelector(pts[index].maturity.selector), abi.encode(invalidMaturity)
        );
        vm.expectRevert(Errors.FactoryMaturityMismatch.selector);
        vm.prank(owner);
        poolFactory.deploy(address(tricrypto), address(underlying), poolConfig);
    }

    function test_deployPool_RevertIf_AlreadyExists() public virtual {
        test_deployPool();
        vm.expectRevert(Errors.FactoryPoolAlreadyExists.selector);
        vm.prank(owner);
        poolFactory.deploy(address(tricrypto), address(underlying), poolConfig);
    }

    function test_deployPool_RevertIf_NotOwner() public virtual {
        vm.expectRevert("Ownable: caller is not the owner");
        poolFactory.deploy(address(tricrypto), address(underlying), poolConfig);
    }

    function test_deployPool_RevertIf_LnFeeRateRootTooHigh() public virtual {
        vm.expectRevert(Errors.LnFeeRateRootTooHigh.selector);
        poolConfig.lnFeeRateRoot = uint80(uint256(ln(sd(1.05 * 1e18)).intoInt256())) + 1; // ln(1.05) +1
        vm.prank(owner);
        poolFactory.deploy(address(tricrypto), address(underlying), poolConfig);
    }

    function test_deployPool_RevertIf_ProtocolFeePercent() public virtual {
        vm.expectRevert(Errors.ProtocolFeePercentTooHigh.selector);
        poolConfig.protocolFeePercent = 101;
        vm.prank(owner);
        poolFactory.deploy(address(tricrypto), address(underlying), poolConfig);
    }

    function test_deployPool_RevertIf_InitialAnchorTooLow() public virtual {
        vm.expectRevert(Errors.InitialAnchorTooLow.selector);
        poolConfig.initialAnchor = 1e18 - 1;
        vm.prank(owner);
        poolFactory.deploy(address(tricrypto), address(underlying), poolConfig);
    }

    function test_authorizeCallbackReceiver() public virtual {
        address callbackReceiver = address(0x123);
        vm.prank(owner);
        poolFactory.authorizeCallbackReceiver(callbackReceiver);
        assertTrue(poolFactory.isCallbackReceiverAuthorized(callbackReceiver), "callbackReceiver not authorized");
    }

    function test_revokeCallbackReceiver() public virtual {
        address callbackReceiver = address(0x123);
        vm.startPrank(owner);
        poolFactory.authorizeCallbackReceiver(callbackReceiver);
        poolFactory.revokeCallbackReceiver(callbackReceiver);
        vm.stopPrank();
        // assert
        assertFalse(poolFactory.isCallbackReceiverAuthorized(callbackReceiver), "callbackReceiver still authorized");
    }

    function test_authorizeAndRevoke_RevertIf_NotOwner() public virtual {
        address callbackReceiver = address(0x123);
        vm.expectRevert("Ownable: caller is not the owner");
        poolFactory.authorizeCallbackReceiver(callbackReceiver);

        vm.expectRevert("Ownable: caller is not the owner");
        poolFactory.revokeCallbackReceiver(callbackReceiver);
    }
}
