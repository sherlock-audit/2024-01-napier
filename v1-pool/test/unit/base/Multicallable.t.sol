// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import {MockMulticallable} from "./../../mocks/MockMulticallable.sol";

/// Taken and modified from: Solady Multicallableable.t.sol
contract MulticallableTest is Test {
    MockMulticallable multicall;

    function setUp() public {
        multicall = new MockMulticallable();
    }

    function test_RevertWithMessage(string memory revertMessage) public {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSelector(MockMulticallable.revertsWithString.selector, revertMessage);
        vm.expectRevert(bytes(revertMessage));
        multicall.multicall(data);
    }

    function test_RevertWithMessage() public {
        test_RevertWithMessage("Milady");
    }

    function test_RevertWithCustomError() public {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSelector(MockMulticallable.revertsWithCustomError.selector);
        vm.expectRevert(MockMulticallable.CustomError.selector);
        multicall.multicall(data);
    }

    function test_RevertWithNothing() public {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSelector(MockMulticallable.revertsWithNothing.selector);
        vm.expectRevert();
        multicall.multicall(data);
    }

    function test_ReturnDataIsProperlyEncoded(uint256 a0, uint256 b0, uint256 a1, uint256 b1) public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(MockMulticallable.returnsTuple.selector, a0, b0);
        data[1] = abi.encodeWithSelector(MockMulticallable.returnsTuple.selector, a1, b1);
        bytes[] memory returnedData = multicall.multicall(data);
        MockMulticallable.Tuple memory t0 = abi.decode(returnedData[0], (MockMulticallable.Tuple));
        MockMulticallable.Tuple memory t1 = abi.decode(returnedData[1], (MockMulticallable.Tuple));
        assertEq(t0.a, a0);
        assertEq(t0.b, b0);
        assertEq(t1.a, a1);
        assertEq(t1.b, b1);
    }

    function test_ReturnDataIsProperlyEncoded(string memory sIn0, string memory sIn1, uint256 n) public {
        n = n % 2;
        bytes[] memory dataIn = new bytes[](n);
        if (n > 0) {
            dataIn[0] = abi.encodeWithSelector(MockMulticallable.returnsString.selector, sIn0);
        }
        if (n > 1) {
            dataIn[1] = abi.encodeWithSelector(MockMulticallable.returnsString.selector, sIn1);
        }
        bytes[] memory dataOut = multicall.multicall(dataIn);
        if (n > 0) {
            assertEq(abi.decode(dataOut[0], (string)), sIn0);
        }
        if (n > 1) {
            assertEq(abi.decode(dataOut[1], (string)), sIn1);
        }
    }

    function test_ReturnDataIsProperlyEncoded() public {
        test_ReturnDataIsProperlyEncoded(0, 1, 2, 3);
    }

    function test_Benchmark() public {
        unchecked {
            bytes[] memory data = new bytes[](10);
            for (uint256 i; i != data.length; ++i) {
                data[i] = abi.encodeWithSelector(MockMulticallable.returnsTuple.selector, i, i + 1);
            }
            bytes[] memory returnedData = multicall.multicall(data);
            assertEq(returnedData.length, data.length);
        }
    }

    function test_WithNoData() public {
        bytes[] memory data = new bytes[](0);
        assertEq(multicall.multicall(data).length, 0);
    }

    function test_PreservesMsgSender() public {
        address caller = address(uint160(0xbeef));
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSelector(MockMulticallable.returnsSender.selector);
        vm.prank(caller);
        address returnedAddress = abi.decode(multicall.multicall(data)[0], (address));
        assertEq(caller, returnedAddress);
    }
}
