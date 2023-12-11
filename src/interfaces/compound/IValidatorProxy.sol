// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

interface IValidatorProxy {
    function getAggregators() external view returns (address current, bool hasProposal, address proposed);
}
