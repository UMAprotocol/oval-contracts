// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

interface IValidatorProxyTest {
    function owner() external view returns (address);

    function proposeNewAggregator(address proposed) external;

    function upgradeAggregator() external;
}
