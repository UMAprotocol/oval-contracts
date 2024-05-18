// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";

contract PermissionProxy is Ownable, Multicall {
    error SenderNotApproved(address sender);
    error CallFailed(address destination, uint256 value, bytes callData);

    event SenderSet(address sender, bool allowed);

    mapping (address => bool) senders;

    function setSender(address sender, bool allowed) external onlyOwner {
        senders[sender] = allowed;
        emit SenderSet(sender, allowed);
    }

    function execute(address destination, uint256 value, bytes memory callData) external returns (bytes memory) {
        if (!senders[msg.sender]) {
            revert SenderNotApproved(msg.sender);
        }

        (bool success, bytes memory returnData) = destination.call{ value: value }(callData);
        
        if (!success) {
            revert CallFailed(destination, value, callData);
        }

        return returnData;
    }
}
