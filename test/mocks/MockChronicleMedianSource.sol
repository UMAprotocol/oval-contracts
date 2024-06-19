// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IMedian} from "../../src/interfaces/chronicle/IMedian.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract MockChronicleMedianSource is IMedian, Ownable {
    uint256 public value;
    uint32 public ageValue;

    function age() external view returns (uint32) {
        return ageValue;
    }

    function read() external view returns (uint256) {
        return value;
    }

    function peek() external view returns (uint256, bool) {
        return (value, true);
    }

    function setLatestSourceData(uint256 _value, uint32 _age) public onlyOwner {
        value = _value;
        ageValue = _age;
    }

    function kiss(address) external override {}
}
