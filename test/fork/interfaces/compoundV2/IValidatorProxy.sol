// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

interface IValidatorProxyTest {
    function owner() external view returns (address);

    function proposeNewAggregator(address proposed) external;

    function upgradeAggregator() external;
}
