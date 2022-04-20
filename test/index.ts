import { expect } from "chai";
import { ethers, network } from "hardhat";
import { BigNumber, Contract } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

const toBigNumber = (amount: number): BigNumber => ethers.utils.parseUnits(amount.toString());

const ZERO_ADDRESS = ethers.constants.AddressZero;

async function increaseTime(seconds: number) {
  await ethers.provider.send("evm_increaseTime", [seconds]);
  await ethers.provider.send("evm_mine", []);
}

interface Proposal {
  recipientAddress: string;
  callData: string;
  description: string;
}

describe("DAO", () => {
  const tokenInitialSupply = toBigNumber(100);
  const accountBalance = toBigNumber(30);
  const depositAmount = toBigNumber(25);
  const quorumPercentage = 40; // 40%
  const debatingPeriodDuration = 3 * 24 * 60 * 60; // 3 days
  const proposalId = 1;

  let proposal: Proposal;

  let dao: Contract,
    votingToken: Contract,
    owner: SignerWithAddress,
    chairPerson: SignerWithAddress,
    voter1: SignerWithAddress,
    voter2: SignerWithAddress,
    voter3: SignerWithAddress,
    daoAddress: string,
    chairAddress: string,
    voter1Address: string,
    voter2Address: string,
    voter3Address: string;

  let clean: any; // snapshot

  before(async () => {
    [owner, chairPerson, voter1, voter2, voter3] = await ethers.getSigners();
    chairAddress = chairPerson.address;
    voter1Address = voter1.address;
    voter2Address = voter2.address;
    voter3Address = voter3.address;

    // --- token deployment ---
    const tokenContractFactory = await ethers.getContractFactory("Token");
    votingToken = await tokenContractFactory.deploy("Voting Token", "VTT", tokenInitialSupply);
    await votingToken.deployed();
    await votingToken.transfer(voter1Address, accountBalance);
    await votingToken.transfer(voter2Address, accountBalance);
    await votingToken.transfer(voter3Address, accountBalance);

    // --- DAO deployment ---
    const daoContractFactory = await ethers.getContractFactory("DAO");
    dao = await daoContractFactory.deploy(chairAddress, votingToken.address, quorumPercentage, debatingPeriodDuration);
    await dao.deployed();
    daoAddress = dao.address;
    await votingToken.connect(voter1).approve(daoAddress, accountBalance);
    await votingToken.connect(voter2).approve(daoAddress, accountBalance);
    await votingToken.connect(voter3).approve(daoAddress, accountBalance);

    // --- prepare proposal ---
    const targetContractInterface = votingToken.interface;
    const callData = targetContractInterface.encodeFunctionData("mint", [owner.address, tokenInitialSupply]);
    proposal = {
      recipientAddress: votingToken.address,
      callData,
      description: "Let's mint 100 more tokens to the owner",
    };

    clean = await network.provider.request({ method: "evm_snapshot", params: [] });
  });

  afterEach(async () => {
    await network.provider.request({ method: "evm_revert", params: [clean] });
    clean = await network.provider.request({ method: "evm_snapshot", params: [] });
  });

  describe("[deposit]", () => {
    it("Should revert when deposit price is zero", async () => {
      await expect(dao.connect(voter1).deposit(0)).to.be.revertedWith("Not valid amount");
    });

    it("Should deposit user tokens to the contract", async () => {
      await expect(dao.connect(voter1).deposit(depositAmount))
        .to.emit(dao, "Deposited")
        .withArgs(voter1Address, depositAmount);

      expect(await votingToken.balanceOf(voter1Address)).to.equal(accountBalance.sub(depositAmount));
      expect(await votingToken.balanceOf(daoAddress)).to.equal(depositAmount);
    });
  });

  describe("[addProposal]", () => {
    it("Should revert when chair person is not the same as sender", async () => {
      await expect(dao.connect(voter1).addProposal(
        proposal.recipientAddress, proposal.callData, proposal.description,
      )).to.be.revertedWith("Not enough permissions");
    });

    it("Should revert when proposal recipient is zero address", async () => {
      await expect(dao.connect(chairPerson).addProposal(
        ZERO_ADDRESS, proposal.callData, proposal.description,
      )).to.be.revertedWith("Not valid address");
    });

    it("Should add a proposal", async () => {
      await expect(dao.connect(chairPerson).addProposal(proposal.recipientAddress, proposal.callData, proposal.description))
        .to.emit(dao, "ProposalAdded")
        .withArgs(proposalId, proposal.recipientAddress, proposal.description);

      /* // ----- example how to get event timestamp (not needed here) ------
      const provider = await ethers.provider;
      const iface = dao.interface;
      const logs = await provider.getLogs({ address: daoAddress });
      const decodedLogs = logs.map(log => iface.parseLog(log));
      console.log(decodedLogs);
      const block = await ethers.provider.getBlock(logs[0].blockHash);
      console.log(block.timestamp); */
    });
  });

  describe("[vote]", () => {
    beforeEach(async () => {
      await dao.connect(chairPerson).addProposal(proposal.recipientAddress, proposal.callData, proposal.description);
      await dao.connect(voter1).deposit(depositAmount);
    });

    it("Should revert when user didn't make a deposit", async () => {
      await expect(dao.connect(voter2).vote(proposalId, true)).to.be.revertedWith("Voters should deposit some amount first");
    });

    it("Should revert when proposal is not exist", async () => {
      await expect(dao.connect(voter1).vote(2, false)).to.be.revertedWith("Proposal is not active or not exist");
    });

    it("Should revert when user has already voted for the proposal", async () => {
      await dao.connect(voter1).vote(proposalId, true);
      await expect(dao.connect(voter1).vote(proposalId, false)).to.be.revertedWith("Already voted");
    });

    it("Should add a user votes to the proposal", async () => {
      const isVoteFor = true;
      await expect(dao.connect(voter1).vote(proposalId, isVoteFor))
        .to.emit(dao, "Voted")
        .withArgs(proposalId, voter1Address, isVoteFor);
    });
  });

  describe("[finish]", () => {
    beforeEach(async () => {
      await dao.connect(chairPerson).addProposal(proposal.recipientAddress, proposal.callData, proposal.description);
      await dao.connect(voter1).deposit(depositAmount);
      const isVoteFor = false;
      await dao.connect(voter1).vote(proposalId, isVoteFor);
    });

    it("Should revert when proposal is not exist", async () => {
      await expect(dao.finish(2)).to.be.revertedWith("Proposal is not active or not exist");
    });

    it("Should revert when voting period is not over yet", async () => {
      await expect(dao.finish(proposalId)).to.be.revertedWith("Voting cannot be finished now");
    });

    it("Should unsuccessfully finish the voting when the number of votes is less than quorum", async () => {
      await increaseTime(debatingPeriodDuration + 1);
      const isSuccess = false;

      await expect(dao.finish(proposalId))
        .to.emit(dao, "VotingFinished")
        .withArgs(proposalId, isSuccess, "Not enough votes");
    });

    it("Should unsuccessfully finish the voting when the number of votes for proposal is less than against", async () => {
      const isVoteFor = true;
      await dao.connect(voter2).deposit(depositAmount);
      await dao.connect(voter2).vote(proposalId, isVoteFor);
      await increaseTime(debatingPeriodDuration + 1);

      const isSuccess = false;
      await expect(dao.finish(proposalId))
        .to.emit(dao, "VotingFinished")
        .withArgs(proposalId, isSuccess, "The majority voted against");
    });

    it("Should unsuccessfully finish the voting when proposal has been not executed", async () => {
      const isVoteFor = true;
      await dao.connect(voter2).deposit(depositAmount.add(5));
      await dao.connect(voter2).vote(proposalId, isVoteFor);
      await increaseTime(debatingPeriodDuration + 1);

      const isSuccess = false;
      await expect(dao.finish(proposalId))
        .to.emit(dao, "VotingFinished")
        .withArgs(proposalId, isSuccess, "Proposal execution error");
    });

    it("Should successfully finish the voting and execute the proposal", async () => {
      const daoRole = ethers.utils.id("DAO_ROLE");
      await votingToken.grantRole(daoRole, daoAddress);

      const isVoteFor = true;
      await dao.connect(voter2).deposit(depositAmount.add(5));
      await dao.connect(voter2).vote(proposalId, isVoteFor);
      await increaseTime(debatingPeriodDuration + 1);

      const isSuccess = true;
      await expect(dao.finish(proposalId))
        .to.emit(dao, "VotingFinished")
        .withArgs(proposalId, isSuccess, "");

      // checks that proposal has been executed
      expect(await votingToken.totalSupply()).to.equal(tokenInitialSupply.mul(2));
      expect(await votingToken.balanceOf(owner.address)).to.equal(toBigNumber(110));
    });
  });

  describe("[withdraw]", () => {
    beforeEach(async () => {
      await dao.connect(chairPerson).addProposal(proposal.recipientAddress, proposal.callData, proposal.description);

      const isVoteFor = true;
      await dao.connect(voter1).deposit(depositAmount);
      await dao.connect(voter1).vote(proposalId, isVoteFor);
      await dao.connect(voter2).deposit(depositAmount);
    });

    it("Should revert when user didn't make a deposit", async () => {
      await expect(dao.connect(voter3).withdraw()).to.be.revertedWith("Voters should deposit some amount first");
    });

    it("Should revert when user participates in still active votings", async () => {
      await expect(dao.connect(voter1).withdraw()).to.be.revertedWith("Voters with an active proposal cannot withdraw");
    });

    it("Should withdraw tokens", async () => {
      await increaseTime(debatingPeriodDuration + 1);
      // await dao.finish(proposalId);

      await expect(dao.connect(voter1).withdraw())
        .to.emit(dao, "Withdrawn")
        .withArgs(voter1Address, depositAmount);

      expect(await votingToken.balanceOf(voter1Address)).to.equal(accountBalance);
      expect(await votingToken.balanceOf(daoAddress)).to.equal(depositAmount); // from voter2

      await dao.connect(voter2).withdraw();
      expect(await votingToken.balanceOf(voter2Address)).to.equal(accountBalance);
      expect(await votingToken.balanceOf(daoAddress)).to.equal(0);
    });
  });

  describe("After voting has been finished", () => {
    beforeEach(async () => {
      // const daoRole = ethers.utils.id("DAO_ROLE");
      // await votingToken.grantRole(daoRole, daoAddress);
      await dao.connect(chairPerson).addProposal(proposal.recipientAddress, proposal.callData, proposal.description);

      const isVoteFor = true;
      await dao.connect(voter1).deposit(depositAmount);
      await dao.connect(voter1).vote(proposalId, isVoteFor);
      await dao.connect(voter2).deposit(depositAmount);
      await dao.connect(voter2).vote(proposalId, isVoteFor);

      await increaseTime(debatingPeriodDuration + 1);
      await dao.finish(proposalId);
    });

    it("[vote] Should revert when proposal has been already finished", async () => {
      await dao.connect(voter3).deposit(depositAmount);
      await expect(dao.connect(voter3).vote(proposalId, false)).to.be.revertedWith("Proposal is not active or not exist");
    });

    it("[finish] Should revert when proposal has been already finished", async () => {
      await expect(dao.finish(proposalId)).to.be.revertedWith("Proposal is not active or not exist");
    });

  });

  describe("admin", () => {
    it("[updateDebatingPeriod] Should set a new debating period", async () => {
      const newDebatePeriod = 5 * 24 * 60 * 60; // 5 days;

      await dao.updateDebatePeriod(newDebatePeriod);
      expect(await dao.debatePeriod()).to.equal(newDebatePeriod);
    });
  });

});
