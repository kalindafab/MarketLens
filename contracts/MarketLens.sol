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
        address creator;
        address opponent;
        uint256 stake;
        bool isJoined;
        bool resolved;
        bool cancelled;
        string description;
        // Mutual-sign resolution: both parties must agree on the same winner
        address creatorAgreedWinner;
        address opponentAgreedWinner;
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
    event PrivateBetCreated(uint256 indexed betId, address creator, uint256 stake);
    event PrivateBetJoined(uint256 indexed betId, address opponent);
    event PrivateBetWinnerVote(uint256 indexed betId, address voter, address votedFor);
    event PrivateBetResolved(uint256 indexed betId, address winner, uint256 payout);
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

    function createPrivateBet(string memory _description, uint256 _stake) external {
        // FIX: was polyToken.transferFrom — polyToken was never declared
        collateralToken.transferFrom(msg.sender, address(this), _stake);

        uint256 betId = totalPrivateBets++;
        PrivateBet storage pb = privateBets[betId];
        pb.creator = msg.sender;
        pb.stake = _stake;
        pb.description = _description;

        emit PrivateBetCreated(betId, msg.sender, _stake);
    }

    function joinPrivateBet(uint256 _betId) external {
        PrivateBet storage pb = privateBets[_betId];
        require(!pb.isJoined, "Bet already has an opponent");
        require(msg.sender != pb.creator, "Cannot bet against yourself");

        // FIX: was polyToken.transferFrom — polyToken was never declared
        collateralToken.transferFrom(msg.sender, address(this), pb.stake);

        pb.opponent = msg.sender;
        pb.isJoined = true;

        emit PrivateBetJoined(_betId, msg.sender);
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

    /**
     * @dev Both the creator and opponent must call this with the same _winner address.
     * The payout is only released once both parties agree — neither side can unilaterally steal funds.
     * CEI order: all state changes happen before any external transfer.
     */
    function agreeWinner(uint256 _betId, address _winner) external nonReentrant {
        PrivateBet storage pb = privateBets[_betId];

        require(pb.isJoined, "Bet has no opponent yet");
        require(!pb.resolved, "Bet already resolved");
        require(!pb.cancelled, "Bet was cancelled");
        require(
            msg.sender == pb.creator || msg.sender == pb.opponent,
            "Not a participant"
        );
        require(
            _winner == pb.creator || _winner == pb.opponent,
            "Winner must be a participant"
        );

        // Record this caller's vote
        if (msg.sender == pb.creator) {
            pb.creatorAgreedWinner = _winner;
        } else {
            pb.opponentAgreedWinner = _winner;
        }

        emit PrivateBetWinnerVote(_betId, msg.sender, _winner);

        // Only pay out when both votes are cast and agree
        if (
            pb.creatorAgreedWinner != address(0) &&
            pb.opponentAgreedWinner != address(0) &&
            pb.creatorAgreedWinner == pb.opponentAgreedWinner
        ) {
            // CEI: mark resolved before transfer
            pb.resolved = true;
            address winner = pb.creatorAgreedWinner;
            uint256 payout = pb.stake * 2;

            collateralToken.transfer(winner, payout);
            emit PrivateBetResolved(_betId, winner, payout);
        }
    }

    /**
     * @dev Creator can cancel and reclaim their stake only if no opponent has joined yet.
     * CEI: state updated before transfer.
     */
    function cancelPrivateBet(uint256 _betId) external nonReentrant {
        PrivateBet storage pb = privateBets[_betId];

        require(msg.sender == pb.creator, "Only creator can cancel");
        require(!pb.isJoined, "Cannot cancel opponent already joined");
        require(!pb.cancelled, "Already cancelled");
        require(!pb.resolved, "Already resolved");

        // CEI: update state before transfer
        pb.cancelled = true;
        uint256 refund = pb.stake;

        collateralToken.transfer(pb.creator, refund);
        emit PrivateBetCancelled(_betId, pb.creator);
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