import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("MarketLensModule", (m) => {
  
  const collateralToken = m.contract("PolyToken");
  const marketLens = m.contract("MarketLens", [collateralToken]);

  return { collateralToken, marketLens };
});