// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";

/**
 * @title PermissionProxy is a proxy that allows extends the permissions given to it to a configurable set
 * of addresses.
 * @dev The intended use case for this contract is to add this as a single unlocker to oval contracts, allowing the
 * owner of this contract to delegate that permission to many different unlocker addresses.
 */
contract PermissionProxy is Ownable, Multicall {
    error SenderNotApproved(address sender);
    error CallFailed(address target, uint256 value, bytes callData);

    event SenderSet(address sender, bool allowed);

    mapping (address => bool) public senders;

    /**
     * @notice Enables or disables a sender.
     * @param sender the sender to enable or disable.
     * @param allowed whether the sender should be allowed.
     */
    function setSender(address sender, bool allowed) external onlyOwner {
        senders[sender] = allowed;
        emit SenderSet(sender, allowed);
    }

        /**
     * @notice Executes a call from this contract.
     * @dev Can only be called by an allowed sender.
     * @param target the address to call.
     * @param value the value to send.
     * @param callData the calldata to use for the call.
     * @return the data returned by the external call.
     * 
     */
    function execute(address target, uint256 value, bytes memory callData) external returns (bytes memory) {
        if (!senders[msg.sender]) {
            revert SenderNotApproved(msg.sender);
        }

        (bool success, bytes memory returnData) = target.call{ value: value }(callData);
        
        if (!success) {
            revert CallFailed(target, value, callData);
        }

        return returnData;
    }
}
