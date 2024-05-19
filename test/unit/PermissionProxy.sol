// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {CommonTest} from "../Common.sol";
import {PermissionProxy} from "../../src/factories/PermissionProxy.sol";

contract PermissionProxyTest is CommonTest {
    PermissionProxy permissionProxy;
    address mockAddress = address(0xdeadbeef);
    bytes testCallData = abi.encodeWithSignature("foo()");
    uint256 testValue = 1;
    bytes returnData = abi.encode(uint256(7));

    function setUp() public {
        permissionProxy = new PermissionProxy();
        permissionProxy.setSender(account1, true);
    }

    function testSenderPermissions() public {
        vm.prank(account2);
        vm.expectRevert(abi.encodeWithSelector(PermissionProxy.SenderNotApproved.selector, account2));
        permissionProxy.execute(mockAddress, testValue, testCallData);

        vm.prank(account1);
        vm.mockCall(mockAddress, testValue, testCallData, abi.encode(uint256(7)));
        vm.expectCall(mockAddress, testValue, testCallData);
        bytes memory actualReturnValue = permissionProxy.execute(mockAddress, testValue, testCallData);
        assertEq0(actualReturnValue, returnData);
    }

    function testCallFailed() public {
        vm.prank(account1);
        vm.mockCallRevert(mockAddress, testValue, testCallData, "");
        vm.expectRevert(abi.encodeWithSelector(PermissionProxy.CallFailed.selector, mockAddress, testValue, testCallData));
        permissionProxy.execute(mockAddress, testValue, testCallData);
    }

    function testSetSender() public {
        permissionProxy.transferOwnership(owner);

        vm.startPrank(owner);
        permissionProxy.setSender(account2, true);
        permissionProxy.setSender(account1, false);
        vm.stopPrank();

        assertTrue(!permissionProxy.senders(account1));
        assertTrue(permissionProxy.senders(account2));
    }
}
