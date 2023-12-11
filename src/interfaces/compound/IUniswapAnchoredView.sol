pragma solidity 0.8.17;

interface IUniswapAnchoredView {
    enum PriceSource {
        FIXED_ETH,
        FIXED_USD,
        REPORTER
    }

    struct TokenConfig {
        address cToken;
        address underlying;
        bytes32 symbolHash;
        uint256 baseUnit;
        PriceSource priceSource;
        uint256 fixedPrice;
        address uniswapMarket;
        address reporter; // This is what we care about
        uint256 reporterMultiplier;
        bool isUniswapReversed;
    }

    function getUnderlyingPrice(address cToken) external view returns (uint256);

    function getTokenConfigByCToken(address cToken) external view returns (TokenConfig memory);
}
