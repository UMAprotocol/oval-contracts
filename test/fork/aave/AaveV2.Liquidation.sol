// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {CommonTest} from "../../Common.sol";

import {BaseController} from "../../../src/controllers/BaseController.sol";
import {ChainlinkSourceAdapter} from "../../../src/adapters/source-adapters/ChainlinkSourceAdapter.sol";
import {ChainlinkDestinationAdapter} from "../../../src/adapters/destination-adapters/ChainlinkDestinationAdapter.sol";
import {IAggregatorV3Source} from "../../../src/interfaces/chainlink/IAggregatorV3Source.sol";

import {ILendingPool} from "../interfaces/aave/ILendingPool.sol";
import {IAaveOracle} from "../interfaces/aave/IAaveOracle.sol";

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

interface Usdc is IERC20 {
    function mint(address _to, uint256 _amount) external returns (bool);
}

contract TestedOVAL is BaseController, ChainlinkSourceAdapter, ChainlinkDestinationAdapter {
    constructor(IAggregatorV3Source source, uint8 decimals)
        ChainlinkSourceAdapter(source)
        BaseController()
        ChainlinkDestinationAdapter(decimals)
    {}
}

contract AaveV2LiquidationTest is CommonTest {
    uint256 amountToMint = 150000e6;

    ILendingPool lendingPool = ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    IERC20 collateralAsset = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH
    Usdc usdcDebtAsset = Usdc(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC
    IERC20 susdDebtAsset = IERC20(0x57Ab1ec28D129707052df4dF418D58a2D46d5f51); // SUSD
    address user = 0x6e3AA85dB95BBA36276a37ED93B12B7AB0782aFB; // User with a position under water at this block.
    IAaveOracle aaveOracle = IAaveOracle(0xA50ba011c48153De246E5192C8f9258A2ba79Ca9); // Aave v2 Oracle

    // The oracle was updated in the block below. The tx hash is the transaction right after the oracle is updated.
    // If we want to back run the oracle we want to replace this transaction with our actions in the tests.
    uint256 oracleUpdateBlock = 17937311;
    bytes32 postOracleUpdateTx = 0xb301c4c6b010732454f1b8077665d4e8454eef13d7c994022fa3a3030f6a3aca;

    // The oracle update that creates the liquidation opportunity is the update of the SUSD price.
    IAggregatorV3Source sourceChainlinkOracle;
    TestedOVAL oval;

    function setUp() public {
        vm.createSelectFork("mainnet", oracleUpdateBlock - 1); // Rolling to the block before the oracle update to start off all tests.
        sourceChainlinkOracle = IAggregatorV3Source(aaveOracle.getSourceOfAsset(address(susdDebtAsset)));
    }

    function testUserPositionHealth() public {
        // We start before applying the oracle update. At this location the position should still be healthy.
        (,,,,, uint256 healthFactorPreUpdate) = lendingPool.getUserAccountData(user);
        assertTrue(healthFactorPreUpdate > 1e18);

        vm.rollFork(postOracleUpdateTx); // Right after the oracle update the position should be underwater.
        (,,,,, uint256 healthFactorPostUpdate) = lendingPool.getUserAccountData(user);
        assertTrue(healthFactorPostUpdate < 1e18);
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
        createOVALAndUnlock();
        setOVALAsAaveSource();
        updateChainlinkToLatestValue();

        // Even though the chainlink oracle is up to date, the OVAL is not. This means an attempted liquidation
        // will fail because the OVAL price is stale.
        (, int256 latestAnswer,, uint256 latestTimestamp,) = sourceChainlinkOracle.latestRoundData();
        assertTrue(oval.latestAnswer() != latestAnswer, "1");
        assertTrue(oval.latestTimestamp() != latestTimestamp, "2");

        vm.prank(liquidator);
        vm.expectRevert(bytes("42")); // 42 corresponds with position health being above 1.
        lendingPool.liquidationCall(address(collateralAsset), address(usdcDebtAsset), user, type(uint256).max, false);

        //Now, unlock the OVAL and show that the liquidation can be executed.
        vm.prank(permissionedUnlocker);
        oval.unlockLatestValue();
        (, int256 latestAnswerTwo,, uint256 latestTimestampTwo,) = sourceChainlinkOracle.latestRoundData();
        assertTrue(oval.latestAnswer() == latestAnswerTwo);
        assertTrue(oval.latestTimestamp() == latestTimestampTwo);
        vm.prank(liquidator);
        lendingPool.liquidationCall(address(collateralAsset), address(usdcDebtAsset), user, type(uint256).max, false);
        (,,,,, uint256 healthFactorAfter) = lendingPool.getUserAccountData(user);
        assertTrue(healthFactorAfter > 1e18); // Health factor should be greater than 1 after liquidation.
    }

    function testOVALGracefullyFallsBackToSourceIfNoUnlockApplied() public {
        seedLiquidator();
        createOVALAndUnlock();
        setOVALAsAaveSource();
        updateChainlinkToLatestValue();

        // Even though the chainlink oracle is up to date, the OVAL is not. This means an attempted liquidation
        // will fail because the OVAL price is stale.
        vm.prank(liquidator);
        vm.expectRevert(bytes("42")); // 42 corresponds with position health being above 1.
        lendingPool.liquidationCall(address(collateralAsset), address(usdcDebtAsset), user, type(uint256).max, false);

        // To show that we can gracefully fall back to the source oracle, we will not unlock the OVAL and
        // rather advance time past the lock window. This will cause the OVAL to fall back to the source
        // oracle and the liquidation will succeed without the OVAL being unlocked.
        vm.warp(block.timestamp + oval.lockWindow() + 1);

        // We should see the accessors return the same values, even though the internal values are different.
        (, int256 latestAnswer,, uint256 latestTimestamp,) = sourceChainlinkOracle.latestRoundData();
        assertTrue(oval.latestAnswer() == latestAnswer);
        assertTrue(oval.latestTimestamp() == latestTimestamp);

        // Now, run the liquidation. It should succeed without the OVAL being unlocked due to the fallback.
        vm.prank(liquidator);
        lendingPool.liquidationCall(address(collateralAsset), address(usdcDebtAsset), user, type(uint256).max, false);
        (,,,,, uint256 healthFactorAfter) = lendingPool.getUserAccountData(user);
        assertTrue(healthFactorAfter > 1e18); // Health factor should be greater than 1 after liquidation.
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

    function createOVALAndUnlock() public {
        oval = new TestedOVAL(sourceChainlinkOracle, 18);
        oval.setUnlocker(permissionedUnlocker, true);
        // pull the latest price into the OVAL and check it matches with the source oracle.
        vm.prank(permissionedUnlocker);
        oval.unlockLatestValue();
        (, int256 latestAnswer,, uint256 latestTimestamp,) = sourceChainlinkOracle.latestRoundData();
        assertTrue(latestAnswer == oval.latestAnswer());
        assertTrue(latestTimestamp == oval.latestTimestamp());
    }

    function setOVALAsAaveSource() public {
        // Set the OVAL as the source oracle for the SUSD asset for Aave.
        address[] memory assets = new address[](1);
        assets[0] = address(susdDebtAsset);
        address[] memory sources = new address[](1);
        sources[0] = address(oval);
        vm.prank(aaveOracle.owner()); // Prank AaveOracle Owner.
        aaveOracle.setAssetSources(assets, sources);
    }

    function updateChainlinkToLatestValue() public {
        // Apply the chainlink update within chainlink. This wont affect the OVAL price until it is unlocked.
        (, int256 answerBefore,, uint256 timestampBefore,) = sourceChainlinkOracle.latestRoundData();
        vm.rollFork(postOracleUpdateTx);
        (, int256 answerAfter,, uint256 timestampAfter,) = sourceChainlinkOracle.latestRoundData();

        // Values have changed in chainlink but is stale within OVAL.
        assertTrue(answerBefore != answerAfter && timestampBefore != timestampAfter);
        assertTrue(oval.latestAnswer() == answerBefore && oval.latestTimestamp() == timestampBefore);
        assertTrue(oval.latestAnswer() != answerAfter && oval.latestTimestamp() != timestampAfter);
    }
}
