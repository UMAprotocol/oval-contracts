// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IAaveOracle {
    function setAssetSources(address[] calldata assets, address[] calldata sources) external;
    function setFallbackOracle(address fallbackOracle) external;
    function getAssetPrice(address asset) external view returns (uint256);
    function getAssetsPrices(address[] calldata assets) external view returns (uint256[] memory);
    function getSourceOfAsset(address asset) external view returns (address);
    function getFallbackOracle() external view returns (address);
    function owner() external view returns (address);
}
