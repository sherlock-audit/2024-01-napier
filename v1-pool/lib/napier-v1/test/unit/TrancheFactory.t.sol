// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../Fixtures.sol";

import {ITrancheFactory} from "src/interfaces/ITrancheFactory.sol";

import "src/Constants.sol";
import {Tranche} from "src/Tranche.sol";
import {TrancheFactory} from "src/TrancheFactory.sol";

import {MockERC20} from "../mocks/MockERC20.sol";
import {MockAdapter} from "../mocks/MockAdapter.sol";

contract TestTrancheFactory is CompleteFixture {
    function setUp() public virtual override {
        vm.warp(365 days);
        _maturity = uint32(block.timestamp + 30 days);
        _tilt = 10;
        _issuanceFee = 100;

        underlying = new MockERC20("Underlying", "U", 6);
        target = new MockERC20("Target", "T", 6);
        super.setUp();
    }

    function _deployTranche() internal virtual override {
        // Do nothing
    }

    function _deployAdapter() internal virtual override {
        vm.prank(owner);
        adapter = new MockAdapter(address(address(underlying)), address(target));
    }

    function _postDeploy() internal override {}

    function testSetUp_Ok() public virtual {
        assertTrue(factory.management() == management);
    }

    function testTrancheCreationHash() public {
        assertEq(factory.TRANCHE_CREATION_HASH(), hashInitCode(type(Tranche).creationCode));
    }

    function testFuzz_TrancheFor(address _adapter, uint256 _maturity) public virtual {
        vm.assume(_adapter != address(0) && _maturity != 0);
        bytes32 salt = keccak256(abi.encode(_adapter, _maturity));
        address expected = computeCreate2Address(salt, hashInitCode(type(Tranche).creationCode), address(factory));
        //assert
        assertEq(factory.trancheFor(_adapter, _maturity), expected, "CREATE2 address mismatch");
    }

    function testDeployTranche_Ok() public virtual {
        vm.prank(management);
        address deployed = factory.deployTranche(address(adapter), _maturity, _tilt, _issuanceFee);
        TrancheFactory.TrancheInitArgs memory args = factory.args();
        // assert
        // deployed address
        assertEq(factory.trancheFor(address(adapter), _maturity), deployed, "CREATE2 address mismatch");
        // temporary storage
        assertEq(factory.tranches(address(adapter), _maturity), deployed, "tranche is registered");
        assertEq(args.adapter, address(0), "adapter should be 0-value");
        assertEq(args.maturity, 0, "maturity should be 0-value");
        assertEq(args.tilt, 0, "tilt should be 0-value");
        assertEq(args.issuanceFee, 0, "issuanceFee should be 0-value");
        assertEq(args.yt, address(0), "yt should be 0-value");
        assertEq(args.management, management, "management should remain the same");
    }

    function testDeployTranche_RevertIfSeriesAlreadyExists() public virtual {
        // setup
        vm.startPrank(management);
        factory.deployTranche(address(adapter), _maturity, _tilt, _issuanceFee);
        // execution and assert
        vm.expectRevert(ITrancheFactory.TrancheAlreadyExists.selector);
        factory.deployTranche(address(adapter), _maturity, _tilt, _issuanceFee);
        vm.stopPrank();
    }

    function testDeployTranche_RevertIfCallerIsNotManagement() public virtual {
        vm.expectRevert(ITrancheFactory.OnlyManagement.selector);
        factory.deployTranche(address(adapter), _maturity, _tilt, _issuanceFee);
    }

    function testDeployTranche_RevertIfAdapterZeroAddress() public virtual {
        vm.expectRevert(ITrancheFactory.ZeroAddress.selector);
        vm.prank(management);
        factory.deployTranche(address(0), _maturity, _tilt, _issuanceFee);
    }

    function testFuzz_DeployTranche_RevertIfMaturityIsPast(uint32 _newTimestamp) public virtual {
        // setup
        vm.warp(_newTimestamp);
        vm.assume(_maturity <= block.timestamp);
        // execution and assert
        vm.prank(management);
        vm.expectRevert(ITrancheFactory.MaturityInvalid.selector);
        factory.deployTranche(address(adapter), _maturity, _tilt, _issuanceFee);
    }

    function testFuzz_DeployTranche_RevertIfTiltTooHigh(uint48 _tilt) public virtual {
        vm.assume(_tilt > MAX_BPS);
        vm.prank(management);
        vm.expectRevert(ITrancheFactory.TiltTooHigh.selector);
        factory.deployTranche(address(adapter), _maturity, _tilt, _issuanceFee);
    }

    function testFuzz_DeployTranche_RevertIfIssueanceFeeTooHigh(uint16 _ifee) public virtual {
        vm.assume(_ifee > MAX_BPS);
        vm.prank(management);
        vm.expectRevert(ITrancheFactory.IssueanceFeeTooHigh.selector);
        factory.deployTranche(address(adapter), _maturity, _tilt, _ifee);
    }

    ///////////////////////////////////////////////////////////////////////
    // VIRTUAL FUNCTIONS
    ///////////////////////////////////////////////////////////////////////

    // Doesn't need to be implemented for this test

    /// @dev simulate a scale increase
    /// this is used for simulating sunny day condition of Principal Token
    function _simulateScaleIncrease() internal override {}

    /// @dev simulate a scale decrease
    /// this is used for simulating not sunny day condition of Principal Token
    function _simulateScaleDecrease() internal override {}
}
