// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../shared/Swap.t.sol";

contract PoolSwapConstructorUnitTest is SwapBaseTest {
    function setUp() public {
        maturity = block.timestamp + 365 days;
        _deployAdaptersAndPrincipalTokens();
        _deployCurveV2Pool();
        _deployNapierPool();

        _label();
    }

    function test_constructor() public {
        assertEq(pool.maturity(), maturity);
        assertEq(address(pool.tricrypto()), address(tricrypto));
        assertEq(address(pool.underlying()), address(underlying));
        assertEq(pool.scalarRoot(), poolConfig.scalarRoot);
        assertEq(pool.initialAnchor(), poolConfig.initialAnchor);
        assertEq(pool.feeRecipient(), feeRecipient);
        assertEq(address(pool.factory()), address(poolFactory));
    }
}
