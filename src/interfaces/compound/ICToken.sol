pragma solidity 0.8.17;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

interface ICToken is IERC20 {
    function decimals() external view returns (uint8);

    function liquidateBorrow(address borrower, uint256 repayAmount, address cTokenCollateral)
        external
        returns (uint256);

    function borrowBalanceCurrent(address account) external returns (uint256);

    function comptroller() external view returns (address);
}
