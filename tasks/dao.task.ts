import { task } from "hardhat/config";

task("deposit", "Deposits user tokens")
  .addParam("daoaddr", "The address of dao contract")
  .addParam("amount", "The amount of tokens to deposit")
  .setAction(async ({ daoaddr: daoAddress, amount }, hre) => {
    const value = hre.ethers.utils.parseUnits(amount);
    const dao = await hre.ethers.getContractAt("DAO", daoAddress);
    await dao.deposit(value);
    console.log(`Deposited ${amount} tokens`);
  });

task("addProposal", "Deposits user tokens")
  .addParam("daoaddr", "The address of dao contract")
  .addParam("recipientaddr", "The address of target contract")
  .addParam("calldata", "Proposal call data")
  .addParam("description", "Proposal description")
  .setAction(async ({ daoaddr: daoAddress, recipientaddr: recipientAddress, calldata, description }, hre) => {
    const dao = await hre.ethers.getContractAt("DAO", daoAddress);
    await dao.addProposal(recipientAddress, calldata, description);
    console.log(`Proposal "${description}" has been added`);
  });

task("vote", "Adds a vote for or against the proposal")
  .addParam("daoaddr", "The address of dao contract")
  .addParam("proposalid", "The proposal id")
  .addParam("isfor", "Is vote for proposal")
  .setAction(async ({ daoaddr: daoAddress, proposalid: proposalId, isfor: isVoteForProposal }, hre) => {
    const dao = await hre.ethers.getContractAt("DAO", daoAddress);
    await dao.vote(proposalId, isVoteForProposal);
    console.log(`Voted ${isVoteForProposal ? "for" : "against"} proposal ${proposalId}`);
  });

task("finish", "Finishes voting")
  .addParam("daoaddr", "The address of dao contract")
  .addParam("proposalid", "The proposal id")
  .setAction(async ({ daoaddr: daoAddress, proposalid: proposalId }, hre) => {
    const dao = await hre.ethers.getContractAt("DAO", daoAddress);
    await dao.finish(proposalId);
    console.log(`Voting for the proposal ${proposalId} has been finished`);
  });
