// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IBaseController {
    event LockWindowSet(uint256 indexed lockWindow);
    event MaxTraversalSet(uint256 indexed maxTraversal);
    event UnlockerSet(address indexed unlocker, bool indexed allowed);
    event MaxAgeSet(uint256 indexed newMaxAge);

    function canUnlock(address caller, uint256 cachedLatestTimestamp) external view returns (bool);
}
