// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts@4.9.3/utils/math/SafeCast.sol";
import {FixedPointMathLib} from "src/utils/FixedPointMathLib.sol";
import {MAX_BPS} from "src/Constants.sol";

abstract contract BaseTest is Test {
    using stdStorage for StdStorage;
    using FixedPointMathLib for uint256;
    using SafeCast for uint256;

    uint256 internal constant MAX_UINT128 = type(uint128).max;
    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;

    address owner = makeAddr("owner");
    address newOwner = makeAddr("newOwner");
    address management = makeAddr("management");
    address feeRecipient = makeAddr("feeRecipient");
    address user = makeAddr("user");

    mapping(address => bool) accountsExcludedFromFuzzing;

    // Taken from: lib/openzeppelin-contracts/lib/erc4626-tests/ERC4626.prop.sol

    function assertApproxGeAbs(uint256 a, uint256 b, uint256 maxDelta, string memory err) internal {
        if (!(a >= b)) {
            uint256 dt = b - a;
            if (dt > maxDelta) {
                emit log_named_string("Error", err);
                emit log("Error: a >=~ b not satisfied [uint]");
                emit log_named_uint("   Value a", a);
                emit log_named_uint("   Value b", b);
                emit log_named_uint(" Max Delta", maxDelta);
                emit log_named_uint("     Delta", dt);
                fail();
            }
        }
    }

    function assertApproxLeAbs(uint256 a, uint256 b, uint256 maxDelta, string memory err) internal {
        if (!(a <= b)) {
            uint256 dt = a - b;
            if (dt > maxDelta) {
                emit log_named_string("Error", err);
                emit log("Error: a <=~ b not satisfied [uint]");
                emit log_named_uint("   Value a", a);
                emit log_named_uint("   Value b", b);
                emit log_named_uint(" Max Delta", maxDelta);
                emit log_named_uint("     Delta", dt);
                fail();
            }
        }
    }

    function _approve(address token, address _owner, address spender, uint256 amount) internal {
        vm.prank(_owner);
        SafeERC20.forceApprove(IERC20(token), spender, amount);
    }

    /// @dev https://book.getfoundry.sh/reference/forge-std/std-storage?highlight=stds#std-storage
    /// @notice This is a helper function to set the value of a storage slot
    function _overwriteWithOneKey(address account, string memory sig, address key, uint256 value) internal {
        stdstore.target(account).sig(sig).with_key(key).checked_write(value);
    }

    /// @notice This is a helper function to set the value of a storage slot
    function _overwriteSig(address account, string memory sig, uint256 value) internal {
        stdstore.target(account).sig(sig).checked_write(value);
    }
}
