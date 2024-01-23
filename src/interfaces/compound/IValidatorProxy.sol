// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

interface IValidatorProxy {
    function getAggregators() external view returns (address current, bool hasProposal, address proposed);
}
