// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

interface IComptroller {
    function admin() external view returns (address);

    function oracle() external view returns (address);

    function _setPriceOracle(address newOracle) external returns (uint256);
}
