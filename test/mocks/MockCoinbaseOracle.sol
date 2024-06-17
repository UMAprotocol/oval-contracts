// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {CoinbaseOracle} from "../../src/oracles/CoinbaseOracle.sol";

contract MockCoinbaseOracle is CoinbaseOracle {
    address public customReporter;

    constructor(address _customReporter) {
        customReporter = _customReporter;
    }

    function reporter() public view override returns (address) {
        return customReporter;
    }
}
