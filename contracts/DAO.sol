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

    struct Proposal {
        // is id redundant or is it better to duplicate id inside the structure (considering that it is used as the mapping key)?
        uint proposalId;
        bytes callData; // calldata to be passed to a call
        address recipient;
        bytes32 descriptionHash;
        uint endDate; // The timestamp when the proposal will be available for execution
        uint votesFor; // number of votes for the proposal
        uint votesAgainst; // number of votes against the proposal
        bool isActive; // whether the proposal has been in process fo voting
        mapping(address => bool) participants;
    }

    struct Voter {
        uint deposit;
        uint withdrawTime;
    }

    /// @dev _currentProposalId => Proposal mapping of proposals
    mapping (uint => Proposal) private _proposals;

    mapping (address => Voter) private _voters;

    enum ProposalResult {
        Success,
        ExecutionError,
        NotEnoughVotesReject,
        VotedAgainstReject
    }

    event Deposited(address indexed from, uint amount);
    event ProposalAdded(uint indexed proposalId, address indexed recipient, string description);
    event Voted(uint indexed proposalId, address indexed voter, bool isVoteForProposal);
    event VotingFinished(uint indexed proposalId, ProposalResult status);
    event Withdrawn(address indexed recipient, uint amount);

    constructor(address _chairPerson, address _votingToken, uint _minQuorumPercentage, uint _debatingPeriodDuration) {
        chairPerson = _chairPerson;
        voteToken = IERC20(_votingToken);
        quorumPercentage = _minQuorumPercentage;
        debatePeriod = _debatingPeriodDuration;
    }

    function deposit(uint amount) external {
        require(amount > 0, "Not valid amount");

        voteToken.safeTransferFrom(msg.sender, address(this), amount);
        _voters[msg.sender].deposit += amount;

        emit Deposited(msg.sender, amount);
    }

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
