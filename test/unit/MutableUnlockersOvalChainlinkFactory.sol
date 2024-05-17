import {MutableUnlockersOvalChainlinkFactory} from "../../src/factories/MutableUnlockersOvalChainlinkFactory.sol";
import {OvalChainlinkMutableUnlocker} from "../../src/factories/MutableUnlockersOvalChainlinkFactory.sol";
import {IAggregatorV3Source} from "../../src/interfaces/chainlink/IAggregatorV3Source.sol";
import {MockChainlinkV3Aggregator} from "../mocks/MockChainlinkV3Aggregator.sol";
import {CommonTest} from "../Common.sol";

contract MutableUnlockersOvalChainlinkFactoryTest is CommonTest {
    MutableUnlockersOvalChainlinkFactory factory;
    MockChainlinkV3Aggregator mockSource;
    address[] unlockers;
    uint256 lockWindow = 300;
    uint256 maxTraversal = 15;

    function setUp() public {
        mockSource = new MockChainlinkV3Aggregator(8, 420);
        unlockers.push(address(0x123));
        factory = new MutableUnlockersOvalChainlinkFactory();
    }

    function testCreateMutableUnlockerOvalChainlink() public {
        address owner = address(this);
        address created = factory.createMutableUnlockerOvalChainlink(
            IAggregatorV3Source(address(mockSource)), lockWindow, maxTraversal, owner, unlockers
        );

        assertTrue(created != address(0)); // Check if the address is set, non-zero.

        OvalChainlinkMutableUnlocker instance = OvalChainlinkMutableUnlocker(created);
        assertTrue(instance.lockWindow() == lockWindow);
        assertTrue(instance.maxTraversal() == maxTraversal);

        // Check if the unlockers are set correctly
        for (uint256 i = 0; i < unlockers.length; i++) {
            assertTrue(instance.canUnlock(unlockers[i], 0));
        }
        assertFalse(instance.canUnlock(address(0x456), 0)); // Check if a random address cannot unlock
    }

    function testOwnerCanChangeUnlockers() public {
        address owner = address(this);
        address created = factory.createMutableUnlockerOvalChainlink(
            IAggregatorV3Source(address(mockSource)), lockWindow, maxTraversal, owner, unlockers
        );
        OvalChainlinkMutableUnlocker instance = OvalChainlinkMutableUnlocker(created);

        address newUnlocker = address(0x789);
        instance.setUnlocker(newUnlocker, true); // Correct method to add unlockers
        assertTrue(instance.canUnlock(newUnlocker, 0));

        instance.setUnlocker(address(0x123), false); // Correct method to remove unlockers
        assertFalse(instance.canUnlock(address(0x123), 0));
    }
}
