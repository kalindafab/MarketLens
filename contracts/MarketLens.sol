// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

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
        uint256 endTimestamp;
        uint256 totalYesAmount;
        uint256 totalNoAmount;
        uint256 totalAmount;
        bool eventCompleted;
        bool outcome; 
        address createdBy;
    }


    mapping(uint256 => Question) public questions;
    
    
    mapping(uint256 => mapping(address => Bet)) public userBets;

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

    constructor(address _collateralToken) {
        owner = msg.sender;
        collateralToken = IERC20(_collateralToken);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "MarketLens: Unauthorized");
        _;
    }

    /**
     * @dev Creates a new prediction market.
     */
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
        q.endTimestamp = _endTimestamp;
        q.createdBy = msg.sender;
        q.eventCompleted = false;

        emit QuestionCreated(questionId, _title, msg.sender, _endTimestamp);
    }

    /**
     * @dev Allows users to place a bet. Users must 'approve' the contract on the ERC20 first.
     */
    function placeBet(uint256 _questionId, uint256 _amount, bool _isYes) external nonReentrant {
        Question storage q = questions[_questionId];
        require(_questionId < totalQuestions, "Invalid question ID");
        require(block.timestamp < q.endTimestamp, "Trading phase ended");
        require(!q.eventCompleted, "Market already resolved");
        require(_amount > 0, "Amount must be greater than 0");

        // Transfer tokens from user to this contract
        bool success = collateralToken.transferFrom(msg.sender, address(this), _amount);
        require(success, "Token transfer failed");

        // Update User Bet state
        Bet storage userBet = userBets[_questionId][msg.sender];
        require(userBet.amount == 0 || userBet.isYes == _isYes, "Cannot change bet side");

        userBet.amount += _amount;
        userBet.isYes = _isYes;

        // Update Global Market state
        if (_isYes) {
            q.totalYesAmount += _amount;
        } else {
            q.totalNoAmount += _amount;
        }
        q.totalAmount += _amount;

        emit BetPlaced(_questionId, msg.sender, _isYes, _amount);
    }

    /**
     * @dev Sets the outcome and completes the event.
     */
    function resolveMarket(uint256 _questionId, bool _outcome) external onlyOwner {
        Question storage q = questions[_questionId];
        require(!q.eventCompleted, "Market already resolved");
        require(block.timestamp >= q.endTimestamp, "Cannot resolve before end time");

        q.outcome = _outcome;
        q.eventCompleted = true;

        emit MarketResolved(_questionId, _outcome);
    }

    /**
     * @dev Users call this to claim their share of the losing pool if they won.
     */
    function claimPayout(uint256 _questionId) external nonReentrant {
        Question storage q = questions[_questionId];
        Bet storage userBet = userBets[_questionId][msg.sender];

        require(q.eventCompleted, "Market not resolved yet");
        require(userBet.amount > 0, "No bet placed");
        require(!userBet.claimed, "Already claimed");
        require(userBet.isYes == q.outcome, "Did not win this bet");

        uint256 reward = 0;
        if (q.outcome) { // YES won
            // Formula: UserShare = (UserYesBet / TotalYesPool) * TotalNoPool
            reward = userBet.amount + (userBet.amount * q.totalNoAmount) / q.totalYesAmount;
        } else { // NO won
            // Formula: UserShare = (UserNoBet / TotalNoPool) * TotalYesPool
            reward = userBet.amount + (userBet.amount * q.totalYesAmount) / q.totalNoAmount;
        }

        userBet.claimed = true;
        bool success = collateralToken.transfer(msg.sender, reward);
        require(success, "Payout transfer failed");

        emit PayoutClaimed(_questionId, msg.sender, reward);
    }

    /**
     * @dev View function to get the current probabilities (prices)
     */
    function getProbabilities(uint256 _questionId) public view returns (uint256 yesProb, uint256 noProb) {
        Question storage q = questions[_questionId];
        if (q.totalAmount == 0) return (50, 50);
        yesProb = (q.totalYesAmount * 100) / q.totalAmount;
        noProb = (q.totalNoAmount * 100) / q.totalAmount;
    }
}