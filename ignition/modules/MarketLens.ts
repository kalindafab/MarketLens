import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("MarketLensModule", (m) => {
  
  const polyToken = m.contract("PolyToken");
  const marketLens = m.contract("MarketLens", [polyToken]);

  return { polyToken, marketLens };
});