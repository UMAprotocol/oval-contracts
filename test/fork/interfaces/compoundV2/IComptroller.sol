// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

interface IComptroller {
    function admin() external view returns (address);

    function oracle() external view returns (address);

    function _setPriceOracle(address newOracle) external returns (uint256);
}
