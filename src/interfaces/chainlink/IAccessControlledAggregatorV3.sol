// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IAggregatorV3} from "./IAggregatorV3.sol";

interface IAccessControlledAggregatorV3 is IAggregatorV3 {
    function owner() external view returns (address);

    function addAccess(address _user) external;
}
