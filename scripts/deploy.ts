import { ethers } from "hardhat";

async function main() {
  const daoContractFactory = await ethers.getContractFactory("DAO");
  const daoContract = await daoContractFactory.deploy();

  await daoContract.deployed();

  console.log("DAO contract deployed to:", daoContract.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
