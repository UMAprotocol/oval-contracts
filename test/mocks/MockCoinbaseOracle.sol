// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {CoinbaseOracle} from "../../src/oracles/CoinbaseOracle.sol";

contract MockCoinbaseOracle is CoinbaseOracle {
    constructor(address _customReporter) {
        reporter = _customReporter;
    }
}
