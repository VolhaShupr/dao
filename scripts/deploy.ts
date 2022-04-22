import { ethers } from "hardhat";
import * as dotenv from "dotenv";

dotenv.config();

const { CHAIR_ADDRESS, TOKEN_ADDRESS } = process.env;

async function main() {
  const chairPerson = CHAIR_ADDRESS as string;
  const votingToken = TOKEN_ADDRESS as string;
  const quorumPercentage = 40; // 40%
  const debatingPeriod = 3 * 24 * 60 * 60; // 3 days

  const daoContractFactory = await ethers.getContractFactory("DAO");
  const daoContract = await daoContractFactory.deploy(chairPerson, votingToken, quorumPercentage, debatingPeriod);

  await daoContract.deployed();

  console.log("DAO contract deployed to:", daoContract.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
