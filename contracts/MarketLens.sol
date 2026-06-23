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

    event QuestionCreated(uint256 indexed id, string title, address indexed createdBy, uint256 endTimestamp);
    event BetPlaced(uint256 indexed questionId, address indexed user, bool isYes, uint256 amount);
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

        q.id               = questionId;
        q.title            = _title;
        q.description      = _description;
        q.creatorImageHash = _creatorImageHash;
        q.resolverUrl      = _resolverUrl;
        q.createdAt        = block.timestamp;
        q.endTimestamp     = _endTimestamp;
        q.createdBy        = msg.sender;
        q.eventCompleted   = false;

        emit QuestionCreated(questionId, _title, msg.sender, _endTimestamp);
    }
    function createPrivateQuestion(
        string memory _title,
        string memory _description,
        string memory _creatorImageHash,
        string memory _resolverUrl,
        uint256 _endTimestamp
    ) external {
        require(_endTimestamp > block.timestamp, "End time must be in future");

        uint256 questionId = totalQuestions++;
        Question storage q = questions[questionId];

        q.id               = questionId;
        q.title            = _title;
        q.description      = string(abi.encodePacked("[PRIVATE] ", _description));
        q.creatorImageHash = _creatorImageHash;
        q.resolverUrl      = _resolverUrl;
        q.createdAt        = block.timestamp;
        q.endTimestamp     = _endTimestamp;
        q.createdBy        = msg.sender;
        q.eventCompleted   = false;

        emit QuestionCreated(questionId, _title, msg.sender, _endTimestamp);
    }
    function placeBet(
        uint256 _questionId,
        uint256 _amount,
        bool _isYes
    ) external nonReentrant {
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
        userBet.isYes   = _isYes;

        if (_isYes) { q.totalYesAmount += _amount; }
        else        { q.totalNoAmount  += _amount; }
        q.totalAmount += _amount;

        emit BetPlaced(_questionId, msg.sender, _isYes, _amount);
    }
    function resolveMarket(uint256 _questionId, bool _outcome) external onlyOwner {
        Question storage q = questions[_questionId];
        require(!q.eventCompleted, "Market already resolved");
        require(block.timestamp >= q.endTimestamp, "Cannot resolve before end time");

        q.outcome        = _outcome;
        q.eventCompleted = true;

        emit MarketResolved(_questionId, _outcome);
    }
    function resolvePrivateMarket(uint256 _questionId, bool _outcome) external {
        Question storage q = questions[_questionId];
        require(!q.eventCompleted, "Market already resolved");
        require(block.timestamp >= q.endTimestamp, "Cannot resolve before end time");
        require(
            msg.sender == owner || msg.sender == q.createdBy,
            "Only admin or market creator can resolve"
        );

        q.outcome        = _outcome;
        q.eventCompleted = true;

        emit MarketResolved(_questionId, _outcome);
    }

    function claimPayout(uint256 _questionId) external nonReentrant {
        Question storage q       = questions[_questionId];
        Bet storage       userBet = userBets[_questionId][msg.sender];

        require(q.eventCompleted, "Market not resolved yet");
        require(userBet.amount > 0, "No bet placed");
        require(!userBet.claimed, "Already claimed");
        require(userBet.isYes == q.outcome, "Did not win this bet");

        uint256 reward;
        if (q.outcome) {
            require(q.totalYesAmount > 0, "No yes bets");
            reward = userBet.amount + (userBet.amount * q.totalNoAmount) / q.totalYesAmount;
        } else {
            require(q.totalNoAmount > 0, "No no bets");
            reward = userBet.amount + (userBet.amount * q.totalYesAmount) / q.totalNoAmount;
        }

        userBet.claimed = true;
        bool success = collateralToken.transfer(msg.sender, reward);
        require(success, "Payout transfer failed");

        emit PayoutClaimed(_questionId, msg.sender, reward);
    }
    function getProbabilities(uint256 _questionId)
        public view returns (uint256 yesProb, uint256 noProb)
    {
        Question storage q = questions[_questionId];
        if (q.totalAmount == 0) return (50, 50);
        yesProb = (q.totalYesAmount * 10000) / q.totalAmount;
        noProb  = (q.totalNoAmount  * 10000) / q.totalAmount;
    }

   
    function createPrivateBet(
        string memory _question,
        string memory _description,
        uint256 _stake
    ) external {
        require(_stake > 0, "Stake must be > 0");

        collateralToken.transferFrom(msg.sender, address(this), _stake);

        uint256 betId       = totalPrivateBets++;
        PrivateBet storage pb = privateBets[betId];

        pb.id          = betId;
        pb.creator     = msg.sender;
        pb.question    = _question;
        pb.description = _description;
        pb.stake       = _stake;
        pb.isJoined    = false;
        pb.resolved    = false;
        pb.cancelled   = false;
        pb.createdAt   = block.timestamp;

        emit PrivateBetCreated(betId, msg.sender, _question, _stake);
    }

    function joinPrivateBet(uint256 _betId) external {
        PrivateBet storage pb = privateBets[_betId];

        require(!pb.isJoined,            "Bet already has opponent");
        require(msg.sender != pb.creator, "Cannot bet against yourself");
        require(!pb.cancelled,           "Bet was cancelled");
        require(!pb.resolved,            "Bet already resolved");

        collateralToken.transferFrom(msg.sender, address(this), pb.stake);

        pb.opponent = msg.sender;
        pb.isJoined = true;

        emit PrivateBetJoined(_betId, msg.sender);
    }

    function voteOnPrivateBet(uint256 _betId, bool _vote) external {
        PrivateBet storage pb = privateBets[_betId];

        require(pb.isJoined,   "Bet not started");
        require(!pb.resolved,  "Bet already resolved");
        require(!pb.cancelled, "Bet was cancelled");

        bool isCreator  = (msg.sender == pb.creator);
        bool isOpponent = (msg.sender == pb.opponent);
        require(isCreator || isOpponent, "Not a participant");

        if (isCreator) {
            require(!pb.creatorVoted, "Already voted");
            pb.creatorVote  = _vote;
            pb.creatorVoted = true;
        } else {
            require(!pb.opponentVoted, "Already voted");
            pb.opponentVote  = _vote;
            pb.opponentVoted = true;
        }

        emit PrivateBetVote(_betId, msg.sender, _vote);

        if (pb.creatorVoted && pb.opponentVoted) {
            _resolvePrivateBet(_betId);
        }
    }

    function _resolvePrivateBet(uint256 _betId) internal {
        PrivateBet storage pb = privateBets[_betId];

        require(pb.creatorVoted && pb.opponentVoted, "Both must vote");
        require(!pb.resolved, "Already resolved");

        bool finalOutcome = (pb.creatorVote == pb.opponentVote)
            ? pb.creatorVote
            : pb.creatorVote; // disagreement defaults to creator — admin can override

        pb.outcome  = finalOutcome;
        pb.resolved = true;

        address winner = (pb.creatorVote == finalOutcome) ? pb.creator : pb.opponent;
        pb.winner = winner;

        uint256 totalPayout = pb.stake * 2;
        collateralToken.transfer(winner, totalPayout);

        emit PrivateBetResolved(_betId, finalOutcome, winner, totalPayout);
    }

    function resolvePrivateBetManual(uint256 _betId, bool _outcome) external onlyOwner {
        PrivateBet storage pb = privateBets[_betId];

        require(pb.isJoined,   "Bet not started");
        require(!pb.resolved,  "Already resolved");
        require(!pb.cancelled, "Bet was cancelled");

        pb.outcome  = _outcome;
        pb.resolved = true;

        address winner = (pb.creatorVote == _outcome) ? pb.creator : pb.opponent;
        pb.winner  = winner;

        uint256 totalPayout = pb.stake * 2;
        collateralToken.transfer(winner, totalPayout);

        emit PrivateBetResolved(_betId, _outcome, winner, totalPayout);
    }

    function cancelPrivateBet(uint256 _betId) external {
        PrivateBet storage pb = privateBets[_betId];

        require(msg.sender == pb.creator, "Only creator can cancel");
        require(!pb.isJoined,  "Cannot cancel after opponent joined");
        require(!pb.resolved,  "Already resolved");
        require(!pb.cancelled, "Already cancelled");

        pb.cancelled = true;
        collateralToken.transfer(pb.creator, pb.stake);

        emit PrivateBetCancelled(_betId, pb.creator);
    }

    function getPrivateBet(uint256 _betId) external view returns (
        uint256 id,
        address creator,
        address opponent,
        string memory question,
        string memory description,
        uint256 stake,
        bool isJoined,
        bool resolved,
        bool cancelled
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
            pb.cancelled
        );
    }

    function getPrivateBetResult(uint256 _betId) external view returns (
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
            pb.outcome,
            pb.creatorVote,
            pb.opponentVote,
            pb.creatorVoted,
            pb.opponentVoted,
            pb.winner,
            pb.createdAt
        );
    }
    function sellBet(uint256 _questionId) external nonReentrant {
    Question storage q       = questions[_questionId];
    Bet storage       userBet = userBets[_questionId][msg.sender];

    require(_questionId < totalQuestions, "Invalid question ID");
    require(!q.eventCompleted, "Market already resolved");
    require(block.timestamp < q.endTimestamp, "Market has ended");
    require(userBet.amount > 0, "No bet to sell");
    require(!userBet.claimed, "Already claimed");

    uint256 stakeAmount = userBet.amount;
    bool    wasYes      = userBet.isYes;

    
    uint256 sidePool    = wasYes ? q.totalYesAmount : q.totalNoAmount;
    uint256 sellValue   = (stakeAmount * q.totalAmount * 95) / (sidePool * 100);

  
    if (sellValue > q.totalAmount) sellValue = q.totalAmount;

  
    if (wasYes) {
        q.totalYesAmount -= stakeAmount;
    } else {
        q.totalNoAmount  -= stakeAmount;
    }
    q.totalAmount -= stakeAmount;

   
    userBet.amount  = 0;
    userBet.claimed = true;

   
    bool success = collateralToken.transfer(msg.sender, sellValue);
    require(success, "Refund failed");

    emit BetPlaced(_questionId, msg.sender, wasYes, 0);
}


function getSellValue(uint256 _questionId, address _user)
    external view returns (uint256 sellValue, uint256 originalStake)
{
    Question storage q       = questions[_questionId];
    Bet storage       userBet = userBets[_questionId][_user];

    if (userBet.amount == 0) return (0, 0);

    originalStake = userBet.amount;
    uint256 sidePool = userBet.isYes ? q.totalYesAmount : q.totalNoAmount;
    if (sidePool == 0 || q.totalAmount == 0) return (originalStake, originalStake);

    sellValue = (originalStake * q.totalAmount * 95) / (sidePool * 100);
    if (sellValue > q.totalAmount) sellValue = q.totalAmount;
}
}