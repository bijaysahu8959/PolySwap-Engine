const { ethers } = require("hardhat");

async function main() {
  const PolySwapEngine = await ethers.getContractFactory("PolySwapEngine");
  const polySwapEngine = await PolySwapEngine.deploy();

  await polySwapEngine.deployed();

  console.log("PolySwapEngine contract deployed to:", polySwapEngine.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
