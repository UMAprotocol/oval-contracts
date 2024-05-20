// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title BaseFactory This is the base contract for all Oval factories. It manages the maxTraversal and default
 * unlockers used by all Oval factories.
 * @dev Derived contracts should implement a create method with the parameters needed to instantiate that flavor of
 * Oval.
 */
contract BaseFactory is Ownable {
    uint256 public immutable MAX_TRAVERSAL;
    address[] public defaultUnlockers;

    event DefaultUnlockersSet(address[] defaultUnlockers);
    event OvalDeployed(
        address indexed deployer,
        address indexed oval,
        uint256 indexed lockWindow,
        uint256 maxTraversal,
        address owner,
        address[] unlockers
    );

    constructor(uint256 _maxTraversal, address[] memory _defaultUnlockers) {
        MAX_TRAVERSAL = _maxTraversal;
        setDefaultUnlockers(_defaultUnlockers);
    }

    /**
     * @notice Enables the owner to set the default unlockers that will be passed to all Oval instances created by this
     * contract.
     * @dev This and the owner, itself, is the only mutable portion of this factory.
     * @param _defaultUnlockers default unlockers that will be used to instantiate new Oval instances.
     */
    function setDefaultUnlockers(address[] memory _defaultUnlockers) public onlyOwner {
        defaultUnlockers = _defaultUnlockers;
        emit DefaultUnlockersSet(_defaultUnlockers);
    }
}
