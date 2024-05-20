// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {MergedPriceFeedAdapterWithRounds} from
    "redstone-oracles-monorepo/packages/on-chain-relayer/contracts/price-feeds/with-rounds/MergedPriceFeedAdapterWithRounds.sol";

/**
 * @title RedstonePriceFeedWithRounds
 * @dev A contract that extends MergedPriceFeedAdapterWithRounds to provide price feed functionality with rounds.
 */
contract RedstonePriceFeedWithRounds is MergedPriceFeedAdapterWithRounds {
    // The ID of the data feed
    bytes32 private immutable dataFeedId;

    /**
     * @notice Constructor to set the data feed ID.
     * @param _dataFeedId The ID of the data feed.
     */
    constructor(bytes32 _dataFeedId) {
        dataFeedId = _dataFeedId;
    }

    /**
     * @notice Gets the data feed ID.
     * @return The data feed ID.
     */
    function getDataFeedId() public view override returns (bytes32) {
        return dataFeedId;
    }

    /**
     * @notice Gets the data service ID.
     * @return A string representing the data service ID.
     */
    function getDataServiceId() public pure override returns (string memory) {
        return "redstone-primary-prod";
    }

    /**
     * @notice Gets the threshold for the unique signers.
     * @return The number of unique signers required.
     */
    function getUniqueSignersThreshold() public pure override returns (uint8) {
        return 3;
    }

    /**
     * @notice Gets the index of an authorized signer based on their address.
     * @param signerAddress The address of the signer.
     * @return The index of the authorized signer.
     * @dev Reverts if the signer is not authorized.
     */
    function getAuthorisedSignerIndex(address signerAddress) public view virtual override returns (uint8) {
        if (signerAddress == 0x8BB8F32Df04c8b654987DAaeD53D6B6091e3B774) {
            return 0;
        } else if (signerAddress == 0xdEB22f54738d54976C4c0fe5ce6d408E40d88499) {
            return 1;
        } else if (signerAddress == 0x51Ce04Be4b3E32572C4Ec9135221d0691Ba7d202) {
            return 2;
        } else if (signerAddress == 0xDD682daEC5A90dD295d14DA4b0bec9281017b5bE) {
            return 3;
        } else if (signerAddress == 0x9c5AE89C4Af6aA32cE58588DBaF90d18a855B6de) {
            return 4;
        } else {
            revert SignerNotAuthorised(signerAddress);
        }
    }
}
