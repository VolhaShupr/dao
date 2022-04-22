//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DAO is Ownable {

    using SafeERC20 for IERC20;

    IERC20 public voteToken;
    address public chairPerson;
    uint public quorumPercentage;
    uint public debatePeriod;

    uint private _currentProposalId;

    /**
    * @dev Proposal structure
    * `callData` Call data to be passed to a call
    * `recipient` Target contract address
    * `descriptionHash` Hash of proposal description
    * `endDate` The timestamp when the proposal will be available for execution
    * `votesFor` The number of votes for the proposal
    * `votesAgainst` The number of votes against the proposal
    * `isActive` Whether the proposal is available for voting
    * `voter => bool` Mapping of the proposal voters
    */
    struct Proposal {
        // is id redundant or is it better to duplicate it inside the structure (considering that id is used as the mapping key)?
        uint proposalId;
        bytes callData;
        address recipient;
        bytes32 descriptionHash;
        uint endDate;
        uint votesFor;
        uint votesAgainst;
        bool isActive;
        mapping(address => bool) participants;
    }

    /**
    * @dev Voter data structure
    * `deposit` Voter's deposited amount
    * `withdrawTime` Date from which voter's deposit is available for withdrawal
    */
    struct Voter {
        uint deposit;
        uint withdrawTime;
    }

    /// @dev _currentProposalId => Proposal Mapping of proposals
    mapping (uint => Proposal) private _proposals;

    /// @dev voter address => Voter info Mapping of participants
    mapping (address => Voter) private _voters;

    enum ProposalResult {
        Success,
        ExecutionError,
        NotEnoughVotesReject,
        VotedAgainstReject
    }

    /**
    * @dev Emitted when participant deposits some amount of tokens
    * @param from Address from which the deposit was made
    * @param amount Amount of deposit
    */
    event Deposited(address indexed from, uint amount);

    /**
    * @dev Emitted when chair person adds a new proposal
    * @param proposalId Proposal id
    * @param recipient Target contract
    * @param description Description of the proposal
    */
    event ProposalAdded(uint indexed proposalId, address indexed recipient, string description);

    /**
    * @dev Emitted when participant votes for or against the proposal
    * @param proposalId Proposal id
    * @param voter Voter address
    * @param isVoteForProposal Whether the vote is for or against the proposal
    */
    event Voted(uint indexed proposalId, address indexed voter, bool isVoteForProposal);

    /**
    * @dev Emitted when voting is finished
    * @param proposalId Proposal id
    * @param status Proposal result
    */
    event VotingFinished(uint indexed proposalId, ProposalResult status);

    /**
    * @dev Emitted when participant withdraws deposited amount
    * @param recipient Tokens recipient address
    * @param amount Withdrawal amount
    */
    event Withdrawn(address indexed recipient, uint amount);

    /// @dev Initializes the contract by setting a `chairPerson`, `voteToken` `quorumPercentage` and `debatePeriod`
    constructor(address _chairPerson, address _votingToken, uint _minQuorumPercentage, uint _debatingPeriodDuration) {
        chairPerson = _chairPerson;
        voteToken = IERC20(_votingToken);
        quorumPercentage = _minQuorumPercentage;
        debatePeriod = _debatingPeriodDuration;
    }

    /**
    * @dev Transfers sender's tokens to the contract
    * @param amount Amount of tokens to deposit
    *
    * Requirements:
    * - `amount` cannot be the zero
    *
    * Emits a {Deposited} event
    */
    function deposit(uint amount) external {
        require(amount > 0, "Not valid amount");

        voteToken.safeTransferFrom(msg.sender, address(this), amount);
        _voters[msg.sender].deposit += amount;

        emit Deposited(msg.sender, amount);
    }

    /**
    * @dev Adds a new proposal
    * @param recipient Target contract
    * @param callData Call data for the target contract
    * @param description Proposal description
    *
    * Requirements:
    * - msg.sender should be a chair person address
    * - `recipient` cannot be the zero address
    *
    * Emits a {ProposalAdded} event
    */
    function addProposal(address recipient, bytes calldata callData, string calldata description) external {
        require(chairPerson == msg.sender, "Not enough permissions");
        require(recipient != address(0), "Not valid target address");

        _currentProposalId = _currentProposalId + 1;
        Proposal storage proposal = _proposals[_currentProposalId];
        proposal.proposalId = _currentProposalId;
        proposal.callData = callData;
        proposal.recipient = recipient;
        proposal.descriptionHash = keccak256(bytes(description));
        proposal.endDate = block.timestamp + debatePeriod;
        proposal.isActive = true;

        emit ProposalAdded(_currentProposalId, recipient, description);
    }

    /**
    * @dev Stores msg.sender vote
    * @param proposalId Proposal id
    * @param isVoteForProposal Whether the vote is for or against the proposal
    *
    * Requirements:
    * - msg.sender should have deposited tokens on the contract balance
    * - proposal should exist and be active
    * - msg.sender is allowed to vote for the same proposal only once
    *
    * Emits a {Voted} event
    */
    function vote(uint proposalId, bool isVoteForProposal) external {
        Voter storage voter = _voters[msg.sender];
        uint senderDeposit = voter.deposit;
        require(senderDeposit > 0, "Voters should deposit some amount first");

        Proposal storage proposal = _proposals[proposalId];
        require(proposal.proposalId > 0 && proposal.endDate > block.timestamp, "Proposal is not active or doesn't exist");
        require(!proposal.participants[msg.sender], "Already voted");

        proposal.participants[msg.sender] = true;

        // condition returns `false` when debate period for a new proposal has been updated to the shorter one
        if (proposal.endDate > voter.withdrawTime) {
            voter.withdrawTime = proposal.endDate;
        }

        if (isVoteForProposal) {
            proposal.votesFor += senderDeposit;
        } else {
            proposal.votesAgainst += senderDeposit;
        }

        emit Voted(proposalId, msg.sender, isVoteForProposal);
    }

    /**
    * @dev Finishes the voting on the proposal and executes the proposal
    * @param proposalId Proposal id
    *
    * Requirements:
    * - proposal should exist and be active
    * - proposal debate period should be completed
    *
    * Proposal should be executed when:
    * - the total number of votes exceeds the quorum
    * - more votes for the proposal than against
    *
    * Emits a {VotingFinished} event
    */
    function finish(uint proposalId) external {
        Proposal storage proposal = _proposals[proposalId];
        require(proposal.proposalId > 0 && proposal.isActive, "Proposal is not active or doesn't exist");
        require(proposal.endDate <= block.timestamp, "Voting cannot be finished now");

        proposal.isActive = false;

        ProposalResult proposalResult;
        uint quorum = voteToken.totalSupply() * quorumPercentage / 100;

        if ((proposal.votesFor + proposal.votesAgainst) <= quorum) {
            proposalResult = ProposalResult.NotEnoughVotesReject;
        } else if (proposal.votesFor <= proposal.votesAgainst) {
            proposalResult = ProposalResult.VotedAgainstReject;
        } else {
            (bool success, ) = proposal.recipient.call(proposal.callData);
            proposalResult = success ? ProposalResult.Success : ProposalResult.ExecutionError;
        }

        emit VotingFinished(proposal.proposalId, proposalResult);
    }

    /**
    * @dev Transfers tokens from the contract to tokens initial owner
    *
    * Requirements:
    * - msg.sender should have some tokens on the contract balance
    * - all the proposals, in which msg.sender participates, should be finished
    *
    * Emits a {Withdrawn} event
    */
    function withdraw() external {
        Voter storage voter = _voters[msg.sender];
        uint userDeposit = voter.deposit;

        require(userDeposit > 0, "Voters should deposit some amount first");
        require(block.timestamp > voter.withdrawTime, "Voters with an active proposal cannot withdraw");

        voter.deposit = 0;
        voteToken.safeTransfer(msg.sender, userDeposit);

        emit Withdrawn(msg.sender, userDeposit);
    }

    /**
    * @dev Sets a new value of the debate period
    * @param newDebatePeriod New duration of debates in seconds
    */
    function updateDebatePeriod(uint newDebatePeriod) external onlyOwner {
        debatePeriod = newDebatePeriod;
    }

    /**
    * @dev Sets a new value of the quorum
    * @param newQuorumPercentage New quorum value in percent
    */
    function updateQuorumPercentage(uint newQuorumPercentage) external onlyOwner {
        quorumPercentage = newQuorumPercentage;
    }

    /**
    * @dev Sets a new chair person
    * @param newChairPerson New chair person address
    */
    function updateChairPerson(address newChairPerson) external onlyOwner {
        chairPerson = newChairPerson;
    }
}
