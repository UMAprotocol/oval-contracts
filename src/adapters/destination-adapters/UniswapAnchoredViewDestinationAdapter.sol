// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

import {DecimalLib} from "../lib/DecimalLib.sol";
import {IUniswapAnchoredView} from "../../interfaces/compound/IUniswapAnchoredView.sol";
import {IOVAL} from "../../interfaces/IOval.sol";

/**
 * @title UniswapAnchoredViewDestinationAdapter contract to expose OVAL data via the UniswapAnchoredView interface.
 * @dev Note that this contract is diffrent to most other destination adapters in that it is not an instance of OVAL
 * via the DiamondRootOVAL contract & inhieretence structure. Rather, this contract has a number of sub OVALs
 * that it uses to return the correct price for each cToken. This is needed as the UniswapAnchoredView interface is a
 * one to many relationship with cTokens, and so we need to be able to return the correct price for each cToken.
 */

contract UniswapAnchoredViewDestinationAdapter is Ownable, IUniswapAnchoredView {
    mapping(address => address) public cTokenToOVAL;
    mapping(address => uint8) public cTokenToDecimal;

    IUniswapAnchoredView public immutable uniswapAnchoredViewSource;

    event BaseSourceSet(address indexed source);
    event OVALSet(address indexed cToken, uint8 indexed decimals, address indexed oval);

    constructor(IUniswapAnchoredView _source) Ownable() {
        uniswapAnchoredViewSource = _source;

        emit BaseSourceSet(address(_source));
    }

    /**
     * @notice Enables the owner to set mapping between cTokens and OVALs. This is done for each supported cToken.
     * @param cToken The cToken to set the OVAL for.
     * @param oval The OVAL to set for the cToken.
     */
    function setOVAL(address cToken, address oval) public onlyOwner {
        cTokenToOVAL[cToken] = oval;
        IUniswapAnchoredView.TokenConfig memory tokenConfig = uniswapAnchoredViewSource.getTokenConfigByCToken(cToken);

        // Price feed in UniswapAnchoredView is scaled to (36 - underlying decimals).
        uint8 decimals = 36 - DecimalLib.deriveDecimals(tokenConfig.baseUnit);
        cTokenToDecimal[cToken] = decimals;

        emit OVALSet(cToken, decimals, oval);
    }

    /**
     * @notice Returns the price of the underlying asset of a cToken. Note if the cToken is not supported by this contract
     * it will return the price from the UniswapAnchoredView source. This enables this contract to work with a subset
     * of cTokens supported by the canonical UniswapAnchoredView contract.
     * @param cToken The cToken to get the underlying price of.
     * @return The price of the underlying asset of the cToken.
     */
    function getUnderlyingPrice(address cToken) external view returns (uint256) {
        if (cTokenToOVAL[cToken] == address(0)) {
            return uniswapAnchoredViewSource.getUnderlyingPrice(cToken);
        }
        (int256 answer,) = IOVAL(cTokenToOVAL[cToken]).internalLatestData();
        return DecimalLib.convertDecimals(uint256(answer), 18, cTokenToDecimal[cToken]);
    }

    // Here for interface compatibility, but not supported.
    function getTokenConfigByCToken(address /*cToken*/ ) external pure returns (TokenConfig memory) {
        revert("Not supported");
    }
}
