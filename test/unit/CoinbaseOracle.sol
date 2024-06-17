import {CommonTest} from "../Common.sol";
import {IAggregatorV3} from "src/interfaces/chainlink/IAggregatorV3.sol";
import {CoinbaseOracle} from "src/oracles/CoinbaseOracle.sol";
import {MockCoinbaseOracle} from "../mocks/MockCoinbaseOracle.sol";

contract CoinbaseOracleTest is CommonTest {
    CoinbaseOracle public coinbaseOracle;
    address public constant coinbaseProdReporter = 0xfCEAdAFab14d46e20144F48824d0C09B1a03F2BC;

    address public reporter;
    uint256 public reporterPk;

    string[] public tickers;

    function setUp() public {
        coinbaseOracle = new CoinbaseOracle();
        tickers = new string[](13);
        tickers[0] = "BTC";
        tickers[1] = "ETH";
        tickers[2] = "XTZ";
        tickers[3] = "DAI";
        tickers[4] = "REP";
        tickers[5] = "ZRX";
        tickers[6] = "BAT";
        tickers[7] = "KNC";
        tickers[8] = "LINK";
        tickers[9] = "COMP";
        tickers[10] = "UNI";
        tickers[11] = "GRT";
        tickers[12] = "SNX";

        (address _reporter, uint256 _reporterPk) = makeAddrAndKey("reporter");
        reporter = _reporter;
        reporterPk = _reporterPk;
        coinbaseOracle = new CoinbaseOracle();
    }

    function testPushPricesProd() public {
        coinbaseOracle = new CoinbaseOracle();
        string[] memory fetchCommands = new string[](3);
        fetchCommands[0] = "node";
        fetchCommands[1] = "--no-warnings";
        fetchCommands[2] = "./scripts/src/coinbase/fetchData.js";

        // Fetch is optional, feel free to uncomment the following line
        // if commented, the test will use the data from ./scripts/src/coinbase/data.json
        // If you want to fetch the data, you need to have a valid .env file in scripts/ folder (see readme.md)
        // vm.ffi(fetchCommands);

        for (uint256 i = 0; i < tickers.length; i++) {
            string[] memory readCommands = new string[](4);
            readCommands[0] = "node";
            readCommands[1] = "--no-warnings";
            readCommands[2] = "./scripts/src/coinbase/readData.js";
            readCommands[3] = tickers[i];
            bytes memory apiData = vm.ffi(readCommands);

            (bytes memory data, bytes memory signature) = abi.decode(apiData, (bytes, bytes));

            (
                ,
                /* string memory kind */
                // e.g. "prices"
                uint256 timestamp, // e.g. 1629350000
                string memory ticker, // e.g. "BTC"
                uint256 price // 6 decimals
            ) = abi.decode(data, (string, uint256, string, uint256));

            coinbaseOracle.pushPrice(data, signature);

            (
                ,
                /* uint80 roundId */
                int256 answer,
                uint256 updatedAt
            ) = coinbaseOracle.latestRoundData(ticker);

            assertEq(uint256(answer), price);
            assertEq(updatedAt, timestamp);
        }
    }

    function testPushPriceETH() public {
        coinbaseOracle = new MockCoinbaseOracle(reporter);
        _testPushPrice(tickers[1], 10e6);
    }

    function testPushPriceBTC() public {
        coinbaseOracle = new MockCoinbaseOracle(reporter);
        _testPushPrice(tickers[0], 20e6);
    }

    function testPushPriceBothTickers() public {
        coinbaseOracle = new MockCoinbaseOracle(reporter);
        _testPushPrice(tickers[1], 10e6);
        vm.warp(block.timestamp + 1);
        _testPushPrice(tickers[0], 20e6);
    }

    function _testPushPrice(string memory ticker, uint256 price) internal {
        string memory kind = "prices";
        uint256 timestamp = block.timestamp;

        bytes memory encodedData = abi.encode(kind, timestamp, ticker, price);

        bytes32 hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(encodedData)));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(reporterPk, hash);

        bytes memory signature = abi.encode(r, s, v);

        coinbaseOracle.pushPrice(encodedData, signature);

        (, int256 answer, uint256 updatedAt) = coinbaseOracle.latestRoundData(ticker);

        assertEq(uint256(answer), price);
        assertEq(updatedAt, timestamp);
    }
}
