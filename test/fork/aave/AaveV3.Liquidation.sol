// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {CommonTest} from "../../Common.sol";

import {ImmutableController} from "../../../src/controllers/ImmutableController.sol";
import {ChainlinkSourceAdapter} from "../../../src/adapters/source-adapters/ChainlinkSourceAdapter.sol";
import {ChainlinkDestinationAdapter} from "../../../src/adapters/destination-adapters/ChainlinkDestinationAdapter.sol";
import {IAggregatorV3Source} from "../../../src/interfaces/chainlink/IAggregatorV3Source.sol";

import {ILendingPool} from "../interfaces/aave/ILendingPool.sol";
import {IAaveOracle} from "../interfaces/aave/IAaveOracle.sol";

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

interface Usdc is IERC20 {
    function mint(address _to, uint256 _amount) external returns (bool);
}

contract TestedOval is ImmutableController, ChainlinkSourceAdapter, ChainlinkDestinationAdapter {
    constructor(IAggregatorV3Source source, uint8 decimals, address[] memory unlockers)
        ChainlinkSourceAdapter(source)
        ImmutableController(60, 10, unlockers, 86400)
        ChainlinkDestinationAdapter(decimals)
    {}
}

contract Aave3LiquidationTest is CommonTest {
    uint256 amountToMint = 10000e6;
    ILendingPool lendingPool = ILendingPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    Usdc usdcDebtAsset = Usdc(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC
    IERC20 collateralAsset = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH
    address user = 0xb8618D9D13e2BAA299bb726b413fF66418efbBD0;

    IAaveOracle aaveOracle = IAaveOracle(0x54586bE62E3c3580375aE3723C145253060Ca0C2); // Aave v3 oracle

    // The oracle was updated in the block below. The tx hash is the transaction right after the oracle is updated.
    // If we want to back run the oracle we want to replace this transaction with our actions in the tests.
    uint256 oracleUpdateBlock = 18018927;
    bytes32 postOracleUpdateTx = 0x33ada9fb50abfbf29b59647328bd5fff5121ec04ec43a64f1540de0c898dfd6f;

    IAggregatorV3Source sourceChainlinkOracle;
    TestedOval oval;

    function setUp() public {
        vm.createSelectFork("mainnet", oracleUpdateBlock - 1); // Rolling to the block before the oracle update to start off all tests.
        sourceChainlinkOracle = IAggregatorV3Source(aaveOracle.getSourceOfAsset(address(collateralAsset)));
    }

    function testUserPositionHealth() public {
        // We start before applying the oracle update. At this location the position should still be healthy.
        assertTrue(isPositionHealthy());
        vm.rollFork(postOracleUpdateTx); // Right after the oracle update the position should be underwater.
        assertFalse(isPositionHealthy());
    }

    function testCanExecuteStandardLiquidation() public {
        //Show that we can execute the liquidation within the fork. Roll to right after the oracle update and execute.
        vm.rollFork(postOracleUpdateTx);
        seedLiquidator();
        vm.prank(liquidator);
        lendingPool.liquidationCall(address(collateralAsset), address(usdcDebtAsset), user, type(uint256).max, false);

        assertTrue(usdcDebtAsset.balanceOf(liquidator) < amountToMint); // Some amount of USDC spent on the liquidation
        assertTrue(collateralAsset.balanceOf(liquidator) > 0); // Some amount of WETH received from the liquidation

        (,,,,, uint256 healthFactorAfter) = lendingPool.getUserAccountData(user);
        assertTrue(healthFactorAfter > 1e18); // Health factor should be greater than 1 after liquidation.
    }

    function testCanReplaceSourceAndExecuteLiquidation() public {
        seedLiquidator();
        createOvalAndUnlock();
        setOvalAsAaveSource();
        updateChainlinkToLatestValue();

        // Even though the chainlink oracle is up to date, Oval is not. This means an attempted liquidation
        // will fail because Oval price is stale.
        vm.prank(liquidator);
        vm.expectRevert(bytes("45")); // 45 corresponds with position health being above 1.
        lendingPool.liquidationCall(address(collateralAsset), address(usdcDebtAsset), user, type(uint256).max, false);

        //Now, unlock Oval and show that the liquidation can be executed.
        vm.prank(permissionedUnlocker);
        oval.unlockLatestValue();
        (, int256 latestAnswer,, uint256 latestTimestamp,) = sourceChainlinkOracle.latestRoundData();
        assertTrue(oval.latestAnswer() == latestAnswer);
        assertTrue(oval.latestTimestamp() == latestTimestamp);
        assertTrue(aaveOracle.getAssetPrice(address(collateralAsset)) == uint256(oval.latestAnswer()));
        assertFalse(isPositionHealthy()); // Post update but pre-liquidation position should be underwater.

        vm.prank(liquidator); // Run the liquidation from the liquidator.
        lendingPool.liquidationCall(address(collateralAsset), address(usdcDebtAsset), user, type(uint256).max, false);
        assertTrue(isPositionHealthy()); // Post liquidation position should be healthy again.
    }

    function testOvalGracefullyFallsBackToSourceIfNoUnlockApplied() public {
        seedLiquidator();
        createOvalAndUnlock();
        setOvalAsAaveSource();
        updateChainlinkToLatestValue();

        // Even though the chainlink oracle is up to date, Oval is not. This means an attempted liquidation
        // will fail because Oval price is stale.
        vm.prank(liquidator);
        vm.expectRevert(bytes("45")); // 45 corresponds with position health being above 1.
        lendingPool.liquidationCall(address(collateralAsset), address(usdcDebtAsset), user, type(uint256).max, false);

        // To show that we can gracefully fall back to the source oracle, we will not unlock Oval and
        // rather advance time past the lock window. This will cause Oval to fall back to the source
        // oracle and the liquidation will succeed without Oval being unlocked.
        vm.warp(block.timestamp + oval.lockWindow() + 1);

        // We should see the accessors return the same values, even though the internal values are different.
        (, int256 latestAnswer,, uint256 latestTimestamp,) = sourceChainlinkOracle.latestRoundData();
        assertTrue(oval.latestAnswer() == latestAnswer);
        assertTrue(oval.latestTimestamp() == latestTimestamp);
        assertFalse(isPositionHealthy()); // Post update but pre-liquidation position should be underwater.

        // Now, run the liquidation. It should succeed without Oval being unlocked due to the fallback.
        vm.prank(liquidator);
        lendingPool.liquidationCall(address(collateralAsset), address(usdcDebtAsset), user, type(uint256).max, false);
        assertTrue(isPositionHealthy()); // Post liquidation position should be healthy again.
    }

    function seedLiquidator() public {
        assertTrue(usdcDebtAsset.balanceOf(liquidator) == 0);
        vm.prank(0x5B6122C109B78C6755486966148C1D70a50A47D7); // Prank a known USDC Minter.
        usdcDebtAsset.mint(liquidator, amountToMint);
        assertTrue(usdcDebtAsset.balanceOf(liquidator) == amountToMint);
        assertTrue(collateralAsset.balanceOf(liquidator) == 0);

        vm.prank(liquidator);
        usdcDebtAsset.approve(address(lendingPool), amountToMint);
    }

    function createOvalAndUnlock() public {
        address[] memory unlockers = new address[](1);
        unlockers[0] = permissionedUnlocker;
        oval = new TestedOval(sourceChainlinkOracle, 8, unlockers);
        // pull the latest price into the Oval and check it matches with the source oracle.
        vm.prank(permissionedUnlocker);
        oval.unlockLatestValue();
        (, int256 latestAnswer,, uint256 latestTimestamp,) = sourceChainlinkOracle.latestRoundData();
        assertTrue(latestAnswer == oval.latestAnswer());
        assertTrue(latestTimestamp == oval.latestTimestamp());
    }

    function setOvalAsAaveSource() public {
        // Set Oval as the source oracle for the WETH asset for Aave.
        address[] memory assets = new address[](1);
        assets[0] = address(collateralAsset);
        address[] memory sources = new address[](1);
        sources[0] = address(oval);
        vm.prank(0xEE56e2B3D491590B5b31738cC34d5232F378a8D5); // Prank ACLAdmin.
        aaveOracle.setAssetSources(assets, sources);
    }

    function updateChainlinkToLatestValue() public {
        // Apply the chainlink update within chainlink. This wont affect Oval price until it is unlocked.
        (, int256 answerBefore,, uint256 timestampBefore,) = sourceChainlinkOracle.latestRoundData();
        vm.rollFork(postOracleUpdateTx);
        (, int256 answerAfter,, uint256 timestampAfter,) = sourceChainlinkOracle.latestRoundData();

        // Values have changed in chainlink but is stale within Oval.
        assertTrue(answerBefore != answerAfter && timestampBefore != timestampAfter);
        assertTrue(oval.latestAnswer() == answerBefore && oval.latestTimestamp() == timestampBefore);
        assertTrue(oval.latestAnswer() != answerAfter && oval.latestTimestamp() != timestampAfter);
        // Aave oracle should match Oval, not the source oracle.
        (, int256 latestAnswer,,,) = sourceChainlinkOracle.latestRoundData();
        assertTrue(aaveOracle.getAssetPrice(address(collateralAsset)) == uint256(oval.latestAnswer()));
        assertTrue(aaveOracle.getAssetPrice(address(collateralAsset)) != uint256(latestAnswer));
    }

    function isPositionHealthy() public view returns (bool) {
        (,,,,, uint256 healthFactorAfter) = lendingPool.getUserAccountData(user);
        return healthFactorAfter > 1e18;
    }
}
