// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

library StringHelper {
    /// @notice checks if a string is a substring of another string
    /// @param a the main string
    /// @param b the substring to check
    function isSubstring(string memory a, string memory b) public pure returns (bool) {
        bytes memory bytesMain = bytes(a);
        bytes memory bytesSub = bytes(b);

        // Check if the subString is empty or if its length is greater than mainString
        if (bytesSub.length == 0 || bytesSub.length > bytesMain.length) {
            return false;
        }

        uint256 j;
        for (uint256 i; i <= bytesMain.length - bytesSub.length; i++) {
            bool found = true;
            for (j = 0; j < bytesSub.length; j++) {
                if (bytesMain[i + j] != bytesSub[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                return true;
            }
        }
        return false;
    }
}
