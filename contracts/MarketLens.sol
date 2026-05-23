// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MarketLens is ReentrancyGuard {
    address public owner;
    IERC20 public collateralToken;

    uint256 public totalQuestions;

    struct Bet {
        uint256 amount;
        bool isYes;
        bool claimed;
    }

    struct Question {
        uint256 id;
        string title;
        string description;
        string creatorImageHash;
        string resolverUrl;
        uint256 createdAt;
        uint256 endTimestamp;
        uint256 totalYesAmount;
        uint256 totalNoAmount;
        uint256 totalAmount;
        bool eventCompleted;
        bool outcome;
        address createdBy;
    }

    struct PrivateBet {
        uint256 id;
        address creator;
        address opponent;
        string question;          
        string description;        
        uint256 stake;             
        bool isJoined;             
        bool resolved;             
        bool cancelled;            
        bool outcome;             
        bool creatorVote;         
        bool opponentVote;         
        bool creatorVoted;         
        bool opponentVoted;        
        address winner;            
        uint256 createdAt;
    }

    mapping(uint256 => Question) public questions;
    mapping(uint256 => mapping(address => Bet)) public userBets;
    mapping(uint256 => PrivateBet) public privateBets;
    uint256 public totalPrivateBets;

    event QuestionCreated(
        uint256 indexed id,
        string title,
        address indexed createdBy,
        uint256 endTimestamp
    );
    event BetPlaced(
        uint256 indexed questionId,
        address indexed user,
        bool isYes,
        uint256 amount
    );
    event MarketResolved(uint256 indexed questionId, bool outcome);
    event PayoutClaimed(uint256 indexed questionId, address indexed user, uint256 amount);
    event PrivateBetCreated(uint256 indexed betId, address indexed creator, string question, uint256 stake);
    event PrivateBetJoined(uint256 indexed betId, address indexed opponent);
    event PrivateBetVote(uint256 indexed betId, address indexed voter, bool vote);
    event PrivateBetResolved(uint256 indexed betId, bool outcome, address winner, uint256 payout);
    event PrivateBetCancelled(uint256 indexed betId, address creator);

    constructor(address _collateralToken) {
        owner = msg.sender;
        collateralToken = IERC20(_collateralToken);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "MarketLens: Unauthorized");
        _;
    }

    function createQuestion(
        string memory _title,
        string memory _description,
        string memory _creatorImageHash,
        string memory _resolverUrl,
        uint256 _endTimestamp
    ) external onlyOwner {
        require(_endTimestamp > block.timestamp, "End time must be in future");

        uint256 questionId = totalQuestions++;
        Question storage q = questions[questionId];

        q.id = questionId;
        q.title = _title;
        q.description = _description;
        q.creatorImageHash = _creatorImageHash;
        q.resolverUrl = _resolverUrl;
        q.createdAt = block.timestamp;  
        q.endTimestamp = _endTimestamp;
        
        q.createdBy = msg.sender;
        q.eventCompleted = false;

        emit QuestionCreated(questionId, _title, msg.sender, _endTimestamp);
    }

       function createPrivateBet(
        string memory _question,
        string memory _description,
        uint256 _stake
    ) external {
        require(_stake > 0, "Stake must be > 0");
        
       
        collateralToken.transferFrom(msg.sender, address(this), _stake);

        uint256 betId = totalPrivateBets++;
        PrivateBet storage pb = privateBets[betId];
        
        pb.id = betId;
        pb.creator = msg.sender;
        pb.question = _question;
        pb.description = _description;
        pb.stake = _stake;
        pb.isJoined = false;
        pb.resolved = false;
        pb.cancelled = false;
        pb.creatorVoted = false;
        pb.opponentVoted = false;
        pb.createdAt = block.timestamp;

        emit PrivateBetCreated(betId, msg.sender, _question, _stake);
    }

     function joinPrivateBet(uint256 _betId) external {
        PrivateBet storage pb = privateBets[_betId];
        
        require(!pb.isJoined, "Bet already has opponent");
        require(msg.sender != pb.creator, "Cannot bet against yourself");
        require(!pb.cancelled, "Bet was cancelled");
        require(!pb.resolved, "Bet already resolved");

        // Transfer stake from opponent
        collateralToken.transferFrom(msg.sender, address(this), pb.stake);

        pb.opponent = msg.sender;
        pb.isJoined = true;

        emit PrivateBetJoined(_betId, msg.sender);
    }
    function voteOnPrivateBet(uint256 _betId, bool _vote) external {
        PrivateBet storage pb = privateBets[_betId];
        
        require(pb.isJoined, "Bet not started");
        require(!pb.resolved, "Bet already resolved");
        require(!pb.cancelled, "Bet was cancelled");
        
        bool isCreator = (msg.sender == pb.creator);
        bool isOpponent = (msg.sender == pb.opponent);
        require(isCreator || isOpponent, "Not a participant");

        if (isCreator) {
            require(!pb.creatorVoted, "Already voted");
            pb.creatorVote = _vote;
            pb.creatorVoted = true;
        } else {
            require(!pb.opponentVoted, "Already voted");
            pb.opponentVote = _vote;
            pb.opponentVoted = true;
        }

        emit PrivateBetVote(_betId, msg.sender, _vote);

        // Check if both have voted and resolve automatically
        if (pb.creatorVoted && pb.opponentVoted) {
            _resolvePrivateBet(_betId);
        }
    }
        function _resolvePrivateBet(uint256 _betId) internal {
        PrivateBet storage pb = privateBets[_betId];
        
        require(pb.creatorVoted && pb.opponentVoted, "Both must vote");
        require(!pb.resolved, "Already resolved");
        
        // Determine outcome based on votes
        // If both agree, use that outcome
        // If disagree, outcome is random (50/50) or can be resolved by admin
        bool finalOutcome;
        
        if (pb.creatorVote == pb.opponentVote) {
            // Both agree
            finalOutcome = pb.creatorVote;
        } else {
            // Disagreement - default to creator's vote (or can be set to random)
            // Alternative: send to admin for manual resolution
            finalOutcome = pb.creatorVote;
        }
        
        pb.outcome = finalOutcome;
        
        // Determine winner
        bool creatorWon = (pb.creatorVote == finalOutcome);
        bool opponentWon = (pb.opponentVote == finalOutcome);
        
        address winner;
        if (creatorWon && opponentWon) {
            // Should never happen with different votes
            winner = pb.creator;
        } else if (creatorWon) {
            winner = pb.creator;
        } else {
            winner = pb.opponent;
        }
        
        pb.winner = winner;
        pb.resolved = true;
        
        // Send total pot (2 * stake) to winner
        uint256 totalPayout = pb.stake * 2;
        collateralToken.transfer(winner, totalPayout);
        
        emit PrivateBetResolved(_betId, finalOutcome, winner, totalPayout);
    }

    function resolvePrivateBetManual(uint256 _betId, bool _outcome) external onlyOwner {
        PrivateBet storage pb = privateBets[_betId];
        
        require(pb.isJoined, "Bet not started");
        require(!pb.resolved, "Already resolved");
        require(!pb.cancelled, "Bet was cancelled");
        
        pb.outcome = _outcome;
        
        // Determine winner based on who voted correctly
        bool creatorWon = (pb.creatorVote == _outcome);
        bool opponentWon = (pb.opponentVote == _outcome);
        
        address winner;
        if (creatorWon) {
            winner = pb.creator;
        } else if (opponentWon) {
            winner = pb.opponent;
        } else {
            // Neither voted correctly (should not happen)
            winner = pb.creator; // Default to creator
        }
        
        pb.winner = winner;
        pb.resolved = true;
        
        uint256 totalPayout = pb.stake * 2;
        collateralToken.transfer(winner, totalPayout);
        
        emit PrivateBetResolved(_betId, _outcome, winner, totalPayout);
    }

    function cancelPrivateBet(uint256 _betId) external {
        PrivateBet storage pb = privateBets[_betId];
        
        require(msg.sender == pb.creator, "Only creator can cancel");
        require(!pb.isJoined, "Cannot cancel after opponent joined");
        require(!pb.resolved, "Already resolved");
        require(!pb.cancelled, "Already cancelled");

        pb.cancelled = true;
        
        // Refund stake to creator
        collateralToken.transfer(pb.creator, pb.stake);
        
        emit PrivateBetCancelled(_betId, pb.creator);
    }

    // Helper function to get private bet details
    function getPrivateBet(uint256 _betId) external view returns (
        uint256 id,
        address creator,
        address opponent,
        string memory question,
        string memory description,
        uint256 stake,
        bool isJoined,
        bool resolved,
        bool cancelled,
        bool outcome,
        bool creatorVote,
        bool opponentVote,
        bool creatorVoted,
        bool opponentVoted,
        address winner,
        uint256 createdAt
    ) {
        PrivateBet storage pb = privateBets[_betId];
        return (
            pb.id,
            pb.creator,
            pb.opponent,
            pb.question,
            pb.description,
            pb.stake,
            pb.isJoined,
            pb.resolved,
            pb.cancelled,
            pb.outcome,
            pb.creatorVote,
            pb.opponentVote,
            pb.creatorVoted,
            pb.opponentVoted,
            pb.winner,
            pb.createdAt
        );
    }
}


    function placeBet(uint256 _questionId, uint256 _amount, bool _isYes) external nonReentrant {
        Question storage q = questions[_questionId];
        require(_questionId < totalQuestions, "Invalid question ID");
        require(!q.eventCompleted, "Market already resolved");
        require(block.timestamp < q.endTimestamp, "Trading phase ended");
        
        require(_amount > 0, "Amount must be greater than 0");

        bool success = collateralToken.transferFrom(msg.sender, address(this), _amount);
        require(success, "Token transfer failed");

        Bet storage userBet = userBets[_questionId][msg.sender];
        require(userBet.amount == 0 || userBet.isYes == _isYes, "Cannot change bet side");

        userBet.amount += _amount;
        userBet.isYes = _isYes;

        if (_isYes) {
            q.totalYesAmount += _amount;
        } else {
            q.totalNoAmount += _amount;
        }
        q.totalAmount += _amount;

        emit BetPlaced(_questionId, msg.sender, _isYes, _amount);
    }

    function resolveMarket(uint256 _questionId, bool _outcome) external onlyOwner {
        Question storage q = questions[_questionId];
        require(!q.eventCompleted, "Market already resolved");
        require(block.timestamp >= q.endTimestamp, "Cannot resolve before end time");

        q.outcome = _outcome;
        q.eventCompleted = true;

        emit MarketResolved(_questionId, _outcome);
    }

 
  
    function claimPayout(uint256 _questionId) external nonReentrant {
        Question storage q = questions[_questionId];
        Bet storage userBet = userBets[_questionId][msg.sender];

        require(q.eventCompleted, "Market not resolved yet");
        require(userBet.amount > 0, "No bet placed");
        require(!userBet.claimed, "Already claimed");
        require(userBet.isYes == q.outcome, "Did not win this bet");

        uint256 reward = 0;
        if (q.outcome) {
            require(q.totalYesAmount > 0, "No yes bets in this market");
            reward = userBet.amount + (userBet.amount * q.totalNoAmount) / q.totalYesAmount;
        } else {
            require(q.totalNoAmount > 0, "No no bets in this market");
            reward = userBet.amount + (userBet.amount * q.totalYesAmount) / q.totalNoAmount;
        }

        userBet.claimed = true;
        bool success = collateralToken.transfer(msg.sender, reward);
        require(success, "Payout transfer failed");

        emit PayoutClaimed(_questionId, msg.sender, reward);
    }

    function getProbabilities(uint256 _questionId) public view returns (uint256 yesProb, uint256 noProb) {
        Question storage q = questions[_questionId];
        if (q.totalAmount == 0) return (50, 50);
        yesProb = (q.totalYesAmount * 10000) / q.totalAmount;
        noProb = (q.totalNoAmount * 10000) / q.totalAmount;
    }
}