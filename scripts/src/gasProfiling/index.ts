import { compoundBorrow } from "./compoundBorrow";
import { compoundLiquidation } from "./compoundLiquidation";
import { aaveV2Liquidation } from "./aaveV2Liquidation";
import { aaveV3Liquidation } from "./aaveV3Liquidation";
import { aaveV2Borrow } from "./aaveV2Borrow";
import { aaveV3Borrow } from "./aaveV3Borrow";

const main = async () => {
  console.log("Running gas profiling ...\n");

  await compoundBorrow();
  await compoundLiquidation();
  await aaveV2Liquidation();
  await aaveV3Liquidation();
  await aaveV2Borrow();
  await aaveV3Borrow();
};

main().then(
  () => {
    process.exit(0);
  },
  (err) => {
    console.error(err);
    process.exit(1);
  }
);
