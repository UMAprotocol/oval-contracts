// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import {IPyth} from "../../interfaces/pyth/IPyth.sol";
import {IOval} from "../../interfaces/IOval.sol";
import {DecimalLib} from "../lib/DecimalLib.sol";

/**
 * @notice PythDestinationAdapter contract to expose Oval data via the standard pyth interface.
 */
contract PythDestinationAdapter is Ownable, IPyth {
    mapping(bytes32 => IOval) public idToOval;
    mapping(bytes32 => uint8) public idToDecimal;
    mapping(bytes32 => uint256) public idToValidTimePeriod;

    IPyth public immutable basePythProvider;

    event BaseSourceSet(address indexed sourceOracle);
    event OvalSet(bytes32 indexed id, uint8 indexed decimals, uint256 validTimePeriod, address indexed oval);

    constructor(IPyth _basePythProvider) {
        basePythProvider = _basePythProvider;

        emit BaseSourceSet(address(_basePythProvider));
    }

    /**
     * @notice Enables the owner to set mapping between pyth identifiers and Ovals. Done for each identifier.
     * @param id The pyth identifier to set the Oval for.
     * @param decimals The number of decimals for the identifier.
     * @param validTimePeriod The number of seconds that a price is valid for.
     * @param oval The Oval to set for the identifier.
     */
    function setOval(bytes32 id, uint8 decimals, uint256 validTimePeriod, IOval oval) public onlyOwner {
        idToOval[id] = oval;
        idToDecimal[id] = decimals;
        idToValidTimePeriod[id] = validTimePeriod;

        emit OvalSet(id, decimals, validTimePeriod, address(oval));
    }

    /**
     * @notice Returns the price for the given identifier. This function does not care if the price is too old.
     * @param id The pyth identifier to get the price for.
     * @return price the standard pyth price struct.
     */
    function getPriceUnsafe(bytes32 id) public view returns (Price memory) {
        if (address(idToOval[id]) == address(0)) {
            return basePythProvider.getPriceUnsafe(id);
        }
        (int256 answer, uint256 timestamp,) = idToOval[id].internalLatestData();
        return Price({
            price: SafeCast.toInt64(DecimalLib.convertDecimals(answer, 18, idToDecimal[id])),
            conf: 0,
            expo: -int32(uint32(idToDecimal[id])),
            publishTime: timestamp
        });
    }

    /**
     * @notice Function to get price.
     * @dev in pyth, this function reverts if the returned price isn't older than a configurable number of seconds.
     * idToValidTimePeriod[id] is that number of seconds in this contract.
     * @param id The pyth identifier to get the price for.
     * @return price the standard pyth price struct.
     */
    function getPrice(bytes32 id) external view returns (Price memory) {
        if (address(idToOval[id]) == address(0)) {
            return basePythProvider.getPrice(id);
        }
        Price memory price = getPriceUnsafe(id);
        require(_diff(block.timestamp, price.publishTime) <= idToValidTimePeriod[id], "Not within valid window");
        return price;
    }

    // Internal function to get absolute difference between two numbers. This implementation replicates diff function
    // logic from AbstractPyth contract used in Pyth oracle:
    // https://github.com/pyth-network/pyth-sdk-solidity/blob/c24b3e0173a5715c875ae035c20e063cb900f481/AbstractPyth.sol#L79
    function _diff(uint256 x, uint256 y) internal pure returns (uint256) {
        if (x > y) return x - y;
        return y - x;
    }
}
