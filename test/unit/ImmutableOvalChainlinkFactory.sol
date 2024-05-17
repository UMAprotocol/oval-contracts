import {ImmutableUnlockersOvalChainlinkFactory} from "../../src/factories/ImmutableOvalChainlinkFactory.sol";
import {OvalChainlinkImmutable} from "../../src/factories/ImmutableOvalChainlinkFactory.sol";
import {IAggregatorV3Source} from "../../src/interfaces/chainlink/IAggregatorV3Source.sol";
import {MockChainlinkV3Aggregator} from "../mocks/MockChainlinkV3Aggregator.sol";
import {CommonTest} from "../Common.sol";

contract ImmutableOvalChainlinkFactoryTest is CommonTest {
    ImmutableUnlockersOvalChainlinkFactory factory;
    MockChainlinkV3Aggregator mockSource;
    address[] unlockers;
    uint256 lockWindow = 300; // 5 minutes
    uint256 maxTraversal = 15;

    function setUp() public {
        mockSource = new MockChainlinkV3Aggregator(8, 420); // 8 decimals
        unlockers.push(address(0x123));
        factory = new ImmutableUnlockersOvalChainlinkFactory();
    }

    function testCreateImmutableOvalChainlink() public {
        address created = factory.createImmutableOvalChainlink(
            IAggregatorV3Source(address(mockSource)), lockWindow, maxTraversal, unlockers
        );

        assertTrue(created != address(0)); // Check if the address is set, non-zero.

        OvalChainlinkImmutable instance = OvalChainlinkImmutable(created);
        assertTrue(instance.lockWindow() == lockWindow);
        assertTrue(instance.maxTraversal() == maxTraversal);

        // Check if the unlockers are set correctly
        for (uint256 i = 0; i < unlockers.length; i++) {
            assertTrue(instance.canUnlock(unlockers[i], 0));
        }
        assertFalse(instance.canUnlock(address(0x456), 0)); // Check if a random address cannot unlock
    }
}
