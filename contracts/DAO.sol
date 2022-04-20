//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/utils/Counters.sol";

// import "hardhat/console.sol";
// console.log("Changing greeting from '%s' to '%s'", greeting, _greeting);

contract DAO is Ownable {

    using SafeERC20 for IERC20;

    IERC20 public voteToken;
    address public chairPerson;
    uint public quorumPercentage;
    uint public debatePeriod;

    struct Proposal {
        uint proposalId;
        bytes callData;
        address recipient;
        string description; // todo pass in bytes hash?
        uint startDate;
        uint votesFor;
        uint votesAgainst;
        bool isActive; // todo check do we need it
        mapping(address => bool) participants;
    }

    // using Counters for Counters.Counter;
    // Counters.Counter private _currentProposalId;
    uint private _currentProposalId;

    /// @dev _currentProposalId => Proposal mapping of proposals
    mapping (uint => Proposal) private _proposals;

    mapping (address => uint) private _deposits;

    mapping (address => uint) private _latestVotes;

    event Deposited(address indexed from, uint amount);
    event ProposalAdded(uint indexed proposalId, address indexed recipient, string description);
    event Voted(uint indexed proposalId, address indexed voter, bool isVoteForProposal);
    event VotingFinished(uint indexed proposalId, bool isSuccessful, string error);
    event Withdrawn(address indexed recipient, uint amount);

    constructor(address _chairPerson, address _votingToken, uint _minQuorumPercentage, uint _debatingPeriodDuration) {
        chairPerson = _chairPerson;
        voteToken = IERC20(_votingToken);
        quorumPercentage = _minQuorumPercentage;
        debatePeriod = _debatingPeriodDuration;
    }

    function deposit(uint amount) external {
        require(amount > 0, "Not valid amount");
        // todo add the following check?
        // require(voteToken.safeTransferFrom(msg.sender, address(this), amount), "Transfer failed");
        voteToken.safeTransferFrom(msg.sender, address(this), amount);
        _deposits[msg.sender] += amount;

        emit Deposited(msg.sender, amount);
    }

    function addProposal(address recipient, bytes memory callData, string memory description) external {
        require(chairPerson == msg.sender, "Not enough permissions");
        require(recipient != address(0), "Not valid address");

//        _currentProposalId.increment();
//        uint proposalId = _currentProposalId.current();

        _currentProposalId = _currentProposalId + 1;
        Proposal storage proposal = _proposals[_currentProposalId];
        proposal.proposalId = _currentProposalId;
        proposal.callData = callData;
        proposal.recipient = recipient;
        proposal.description = description;
        proposal.startDate = block.timestamp;
        proposal.isActive = true;

        emit ProposalAdded(_currentProposalId, recipient, description);
    }

    function vote(uint proposalId, bool isVoteForProposal) external {
        uint senderDeposit = _deposits[msg.sender];
        require(senderDeposit > 0, "Voters should deposit some amount first");

        Proposal storage proposal = _proposals[proposalId];
        require(proposal.proposalId > 0 && proposal.isActive, "Proposal is not active or not exist");
        require(!proposal.participants[msg.sender], "Already voted");

        proposal.participants[msg.sender] = true;
        _latestVotes[msg.sender] = proposal.startDate;

        if (isVoteForProposal) {
            proposal.votesFor += senderDeposit;
        } else {
            proposal.votesAgainst += senderDeposit;
        }

        emit Voted(proposalId, msg.sender, isVoteForProposal);
    }

    function finish(uint proposalId) external {
        Proposal storage proposal = _proposals[proposalId];
        require(proposal.proposalId > 0 && proposal.isActive, "Proposal is not active or not exist");
        require((block.timestamp - proposal.startDate) > debatePeriod, "Voting cannot be finished now");

        uint quorum = voteToken.totalSupply() * quorumPercentage / 100;

        // todo refactor
        if ((proposal.votesFor + proposal.votesAgainst) <= quorum) {
            emit VotingFinished(proposal.proposalId, false, "Not enough votes");
        } else if (proposal.votesFor <= proposal.votesAgainst) {
            emit VotingFinished(proposal.proposalId, false, "The majority voted against");
        } else {
            (bool success,) = proposal.recipient.call(proposal.callData);
            if (!success) {
                emit VotingFinished(proposal.proposalId, false, "Proposal execution error");
            } else {
                emit VotingFinished(proposal.proposalId, true, "");
            }

        }

        proposal.isActive = false;

    }

    function withdraw() external {
        uint userDeposit = _deposits[msg.sender];
        require(userDeposit > 0, "Voters should deposit some amount first");
        require((_latestVotes[msg.sender] == 0) || (block.timestamp - _latestVotes[msg.sender] > debatePeriod), "Voters with an active proposal cannot withdraw");

        _deposits[msg.sender] = 0;
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
