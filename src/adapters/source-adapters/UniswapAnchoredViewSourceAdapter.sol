// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {DecimalLib} from "../lib/DecimalLib.sol";
import {SnapshotSource} from "./SnapshotSource.sol";
import {IAggregatorV3Source} from "../../interfaces/chainlink/IAggregatorV3Source.sol";
import {IUniswapAnchoredView} from "../../interfaces/compound/IUniswapAnchoredView.sol";
import {IValidatorProxy} from "../../interfaces/compound/IValidatorProxy.sol";

/**
 * @title UniswapAnchoredViewSourceAdapter contract to read data from UniswapAnchoredView and standardize it for Oval.
 *
 */
abstract contract UniswapAnchoredViewSourceAdapter is SnapshotSource {
    IUniswapAnchoredView public immutable UNISWAP_ANCHORED_VIEW;
    address public immutable C_TOKEN;
    uint8 public immutable SOURCE_DECIMALS;

    IAggregatorV3Source public aggregator;

    event SourceSet(address indexed sourceOracle, address indexed cToken, uint8 indexed sourceDecimals);
    event AggregatorSet(address indexed aggregator);

    constructor(IUniswapAnchoredView _source, address _cToken) {
        UNISWAP_ANCHORED_VIEW = _source;
        C_TOKEN = _cToken;

        IUniswapAnchoredView.TokenConfig memory tokenConfig = UNISWAP_ANCHORED_VIEW.getTokenConfigByCToken(C_TOKEN);

        // Price feed in source oracle is scaled to (36 - underlying SOURCE_DECIMALS).
        SOURCE_DECIMALS = 36 - DecimalLib.deriveDecimals(tokenConfig.baseUnit);

        syncAggregatorSource();

        emit SourceSet(address(_source), _cToken, SOURCE_DECIMALS);
    }

    /**
     * @notice Syncs the aggregator stored in this contract with aggregator stored in UniswapAnchoredView contract.
     * @dev This function should be a no-op unless the aggregator in UniswapAnchoredView has changed. This enables this
     * contract ton continue functioning if the aggregator in UniswapAnchoredView is updated.
     */
    function syncAggregatorSource() public {
        IUniswapAnchoredView.TokenConfig memory tokenConfig = UNISWAP_ANCHORED_VIEW.getTokenConfigByCToken(C_TOKEN);
        (address current,,) = IValidatorProxy(tokenConfig.reporter).getAggregators();

        if (address(aggregator) == current) return; // No need to update.

        aggregator = IAggregatorV3Source(current);

        emit AggregatorSet(current);
    }

    /**
     * @notice Returns the latest data from the source.
     * @return answer The latest answer in 18 decimals.
     * @return updatedAt The timestamp of the answer.
     * @return roundId The roundId of the answer.
     */
    function getLatestSourceData() public view override returns (int256, uint256, uint256) {
        (uint80 latestRoundId,,, uint256 latestTimestamp,) = aggregator.latestRoundData();
        int256 sourcePrice = int256(UNISWAP_ANCHORED_VIEW.getUnderlyingPrice(C_TOKEN));
        return (DecimalLib.convertDecimals(sourcePrice, SOURCE_DECIMALS, 18), latestTimestamp, latestRoundId);
    }

    /**
     * @notice Tries getting latest data as of requested timestamp. If this is not possible, returns the earliest data
     * available past the requested timestamp within provided traversal limitations.
     * @dev UniswapAnchoredView does not support historical lookups so this uses SnapshotSource to get historic data.
     * @param timestamp The timestamp to try getting latest data at.
     * @param maxTraversal The maximum number of rounds to traverse when looking for historical data.
     * @return answer The answer as of requested timestamp, or earliest available data if not available, in 18 decimals.
     * @return updatedAt The timestamp of the answer.
     * @return roundId The roundId of the answer.
     */
    function tryLatestDataAt(uint256 timestamp, uint256 maxTraversal)
        public
        view
        override
        returns (int256, uint256, uint256)
    {
        Snapshot memory snapshot = _tryLatestDataAt(timestamp, maxTraversal);
        return (DecimalLib.convertDecimals(snapshot.answer, SOURCE_DECIMALS, 18), snapshot.timestamp, snapshot.roundId);
    }
}
