// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {CommonTest} from "../../Common.sol";
import {UniswapAnchoredViewSourceAdapter} from
    "../../../src/adapters/source-adapters/UniswapAnchoredViewSourceAdapter.sol";
import {UniswapAnchoredViewDestinationAdapter} from
    "../../../src/adapters/destination-adapters/UniswapAnchoredViewDestinationAdapter.sol";
import {IUniswapAnchoredView} from "../../../src/interfaces/compound/IUniswapAnchoredView.sol";
import {BaseDestinationAdapter} from "../../../src/adapters/destination-adapters/BaseDestinationAdapter.sol";
import {BaseController} from "../../../src/controllers/BaseController.sol";
import {IAggregatorV3} from "../../../src/interfaces/chainlink/IAggregatorV3.sol";
import {IAccessControlledAggregatorV3} from "../../../src/interfaces/chainlink/IAccessControlledAggregatorV3.sol";
import {ICToken} from "../../../src/interfaces/compound/ICToken.sol";
import {IValidatorProxy} from "../../../src/interfaces/compound/IValidatorProxy.sol";

import {IComptroller} from "../interfaces/compoundV2/IComptroller.sol";

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

interface Usdc is IERC20 {
    function mint(address _to, uint256 _amount) external returns (bool);
}

// Juicy liquidation: https://etherscan.io/tx/0xb955a078b9b2a73e111033a3e77142b5768f5729285279d56eff641e43060555

contract TestedOval is BaseController, UniswapAnchoredViewSourceAdapter, BaseDestinationAdapter {
    constructor(IUniswapAnchoredView source, address cToken)
        UniswapAnchoredViewSourceAdapter(source, cToken)
        BaseController()
        BaseDestinationAdapter()
    {}
}

contract CompoundV2LiquidationTest is CommonTest {
    uint256 amountToMint = 150000e6;

    IERC20 collateralAsset = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH
    Usdc usdcDebtAsset = Usdc(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC
    ICToken public cUSDC = ICToken(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
    ICToken public cETH = ICToken(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);

    address borrower = 0xFeECA8db8b5f4Efdb16BA43d3D06ad2F568a52E3;

    IComptroller comptroller = IComptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);
    IUniswapAnchoredView compoundOracle = IUniswapAnchoredView(0x50ce56A3239671Ab62f185704Caedf626352741e);

    // The oracle was updated in the block below. The tx hash is the transaction right after the oracle is updated.
    // If we want to back run the oracle we want to replace this transaction with our actions in the tests.
    uint256 oracleUpdateBlock = 18115158;
    bytes32 postOracleUpdateTx = 0xb955a078b9b2a73e111033a3e77142b5768f5729285279d56eff641e43060555;

    IAccessControlledAggregatorV3 sourceChainlinkOracle;
    UniswapAnchoredViewDestinationAdapter DestinationAdapter;
    UniswapAnchoredViewSourceAdapter sourceAdapter;
    TestedOval oval;

    function setUp() public {
        vm.createSelectFork("mainnet", oracleUpdateBlock - 1); // Rolling to the block before the oracle update to start off all tests.
    }

    function testCanExecuteStandardLiquidation() public {
        //Show that we can execute the liquidation within the fork. Roll to right after the oracle update and execute.
        uint256 borrowBalance = cUSDC.borrowBalanceCurrent(borrower);
        uint256 liquidatbleAmount = borrowBalance / 2; // 50% liquidation threshold is the max in Compound.

        // Show that the price moves after the oracle update.
        uint256 priceBefore = compoundOracle.getUnderlyingPrice(address(cETH));

        vm.rollFork(postOracleUpdateTx);

        uint256 priceAfter = compoundOracle.getUnderlyingPrice(address(cETH));
        assertTrue(priceBefore > priceAfter); // Price has decreased.
        seedLiquidator();
        vm.prank(liquidator);
        cUSDC.liquidateBorrow(borrower, liquidatbleAmount, address(cETH));

        assertTrue(cUSDC.borrowBalanceCurrent(borrower) < borrowBalance); // Borrower's debt has decreased (liquidated)
        assertTrue(usdcDebtAsset.balanceOf(liquidator) < amountToMint); // Some amount of USDC spent on the liquidation
        assertTrue(cETH.balanceOf(liquidator) > 0); // Some amount of cETH received from the liquidation
    }

    function testCanReplaceSourceAndExecuteLiquidation() public {
        createOvalAndUnlock();
        setOvalAsCompoundSource();
        updateChainlinkToLatestValue();

        // insure config is correct
        assertTrue(IComptroller(cUSDC.comptroller()).oracle() == address(DestinationAdapter));

        vm.prank(sourceChainlinkOracle.owner());
        sourceChainlinkOracle.addAccess(address(oval));

        // Fetch the current borrowed balance.
        uint256 borrowBalance = cUSDC.borrowBalanceCurrent(borrower);
        uint256 liquidatbleAmount = borrowBalance / 2; // 50% liquidation threshold is the max in Compound.

        // At this point Oval has a stale price in it. Initiating a liquidation should be a no op. Source oracle
        // should have a different price to Oval.
        uint256 ovalPriceBefore = uint256(getSetCompoundOracle().getUnderlyingPrice(address(cETH)));
        uint256 sourcePriceBefore = uint256(compoundOracle.getUnderlyingPrice(address(cETH)));
        assertTrue(ovalPriceBefore != sourcePriceBefore);
        seedLiquidator();
        vm.prank(liquidator);
        cUSDC.liquidateBorrow(borrower, liquidatbleAmount, address(cETH));
        assertTrue(cUSDC.borrowBalanceCurrent(borrower) == borrowBalance);

        // Unlock Oval then initiate the liquidation. This time, we should be able to liquidate as per usual.

        vm.prank(permissionedUnlocker);
        oval.unlockLatestValue();

        uint256 ovalPriceAfter = uint256(getSetCompoundOracle().getUnderlyingPrice(address(cETH)));
        assertTrue(ovalPriceAfter < ovalPriceBefore); // Price has changed in Oval due to calling unlockLatestValue

        vm.prank(liquidator);
        cUSDC.liquidateBorrow(borrower, liquidatbleAmount, address(cETH));
        assertTrue(cUSDC.borrowBalanceCurrent(borrower) < borrowBalance); // Debt should not changed. Liquidation was a no op.
        assertTrue(usdcDebtAsset.balanceOf(liquidator) < amountToMint); // Some amount of USDC spent on the liquidation
        assertTrue(cETH.balanceOf(liquidator) > 0); // Some amount of cETH received from the liquidation
    }

    function testOvalGracefullyFallsBackToSourceIfNoUnlockApplied() public {
        createOvalAndUnlock();
        setOvalAsCompoundSource();
        updateChainlinkToLatestValue();

        vm.prank(sourceChainlinkOracle.owner());
        sourceChainlinkOracle.addAccess(address(oval));

        // Fetch the current borrowed balance.
        uint256 borrowBalance = cUSDC.borrowBalanceCurrent(borrower);
        uint256 liquidatbleAmount = borrowBalance / 2; // 50% liquidation threshold is the max in Compound.

        // At this point Oval has a stale price in it. Initiating a liquidation should be a no op.
        seedLiquidator();
        vm.prank(liquidator);
        cUSDC.liquidateBorrow(borrower, liquidatbleAmount, address(cETH));
        assertTrue(cUSDC.borrowBalanceCurrent(borrower) == borrowBalance);

        // To show that we can gracefully fall back to the source oracle, we will not unlock Oval and
        // rather advance time past the lock window. This will cause Oval to fall back to the source
        // oracle and the liquidation will succeed without Oval being unlocked.
        vm.warp(block.timestamp + oval.lockWindow() + 1);

        // We should see the accessors return the same values, even though the internal values are different.
        assertTrue(
            getSetCompoundOracle().getUnderlyingPrice(address(cETH)) == compoundOracle.getUnderlyingPrice(address(cETH)),
            "2"
        );

        // Now, run the liquidation. It should succeed without Oval being unlocked due to the fallback.
        vm.prank(liquidator);
        cUSDC.liquidateBorrow(borrower, liquidatbleAmount, address(cETH));
        assertTrue(cUSDC.borrowBalanceCurrent(borrower) < borrowBalance); // Debt should not changed. Liquidation was a no op.
        assertTrue(usdcDebtAsset.balanceOf(liquidator) < amountToMint); // Some amount of USDC spent on the liquidation
        assertTrue(cETH.balanceOf(liquidator) > 0); // Some amount of cETH received from the liquidation
    }

    function seedLiquidator() public {
        assertTrue(usdcDebtAsset.balanceOf(liquidator) == 0);
        vm.prank(0x5B6122C109B78C6755486966148C1D70a50A47D7); // Prank a known USDC Minter.
        usdcDebtAsset.mint(liquidator, amountToMint);
        assertTrue(usdcDebtAsset.balanceOf(liquidator) == amountToMint);
        assertTrue(collateralAsset.balanceOf(liquidator) == 0);

        vm.prank(liquidator);
        usdcDebtAsset.approve(address(cUSDC), amountToMint);
    }

    function createOvalAndUnlock() public {
        DestinationAdapter = new UniswapAnchoredViewDestinationAdapter(getSetCompoundOracle());
        oval = new TestedOval(getSetCompoundOracle(), address(cETH));
        DestinationAdapter.setOval(address(cETH), address(oval));
        assertTrue(DestinationAdapter.cTokenToOval(address(cETH)) == address(oval));
        assertTrue(DestinationAdapter.cTokenToDecimal(address(cETH)) == 18); // (36 - 18 ETH decimals).
        oval.setUnlocker(permissionedUnlocker, true);
        sourceChainlinkOracle = IAccessControlledAggregatorV3(address(oval.aggregator()));
        vm.prank(sourceChainlinkOracle.owner());
        sourceChainlinkOracle.addAccess(address(oval));
        // pull the latest price into Oval and check it matches with the source oracle.
        vm.prank(permissionedUnlocker);
        oval.unlockLatestValue();
        assertTrue(
            getSetCompoundOracle().getUnderlyingPrice(address(cETH)) == compoundOracle.getUnderlyingPrice(address(cETH))
        );
    }

    function setOvalAsCompoundSource() public {
        vm.prank(comptroller.admin());
        comptroller._setPriceOracle(address(DestinationAdapter));
        assertTrue(comptroller.oracle() == address(DestinationAdapter));
    }

    function updateChainlinkToLatestValue() public {
        // Apply the chainlink update within chainlink. This wont affect Oval price until it is unlocked.
        uint256 answerFromOvalBefore = uint256(getSetCompoundOracle().getUnderlyingPrice(address(cETH)));
        uint256 answerFromChainlinkBefore = uint256(compoundOracle.getUnderlyingPrice(address(cETH)));
        vm.rollFork(postOracleUpdateTx);
        vm.prank(sourceChainlinkOracle.owner());
        sourceChainlinkOracle.addAccess(address(oval));
        uint256 answerFromOvalAfter = uint256(getSetCompoundOracle().getUnderlyingPrice(address(cETH)));
        uint256 answerFromChainlinkAfter = uint256(compoundOracle.getUnderlyingPrice(address(cETH)));

        // Values have changed in chainlink but is stale within Oval.

        assertTrue(answerFromOvalBefore == answerFromOvalAfter); // Price has not changed in Oval.
        assertTrue(answerFromChainlinkBefore != answerFromChainlinkAfter); // Price has changed within Chainlink.
        assertTrue(DestinationAdapter.getUnderlyingPrice(address(cETH)) == answerFromOvalBefore); // destination adapter has not updated yet and should be the same as Oval.
    }

    function getSetCompoundOracle() public view returns (IUniswapAnchoredView) {
        return IUniswapAnchoredView(comptroller.oracle());
    }
}
