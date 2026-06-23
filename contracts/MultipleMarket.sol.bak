// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MultiOutcomeMarket is ReentrancyGuard {
    address public owner;
    IERC20 public collateralToken;
    uint256 public totalMarkets;

    struct Market {
        uint256 id;
        string title;
        string description;
        string imageHash;
        string resolverUrl;
        uint256 endTimestamp;
        uint256 createdAt;
        uint256 totalAmount;
        bool resolved;
        uint256 winningOutcome;   
        address createdBy;
        string[] outcomeLabels;   
        uint256[] outcomeTotals;  
    }

    struct UserBet {
        uint256 outcomeIndex; // which outcome they bet on
        uint256 amount;       // how much they staked
        bool claimed;
    }

    mapping(uint256 => Market) public markets;
    // marketId => userAddress => UserBet
    mapping(uint256 => mapping(address => UserBet)) public userBets;

    event MarketCreated(
        uint256 indexed id,
        string title,
        address indexed createdBy,
        uint256 endTimestamp,
        uint256 outcomeCount
    );
    event BetPlaced(
        uint256 indexed marketId,
        address indexed user,
        uint256 outcomeIndex,
        uint256 amount
    );
    event MarketResolved(
        uint256 indexed marketId,
        uint256 winningOutcome
    );
    event PayoutClaimed(
        uint256 indexed marketId,
        address indexed user,
        uint256 amount
    );

    constructor(address _collateralToken) {
        owner = msg.sender;
        collateralToken = IERC20(_collateralToken);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "MultiOutcome: Unauthorized");
        _;
    }


    function createMarket(
        string memory _title,
        string memory _description,
        string memory _imageHash,
        string memory _resolverUrl,
        uint256 _endTimestamp,
        string[] memory _outcomeLabels
    ) external onlyOwner {
        require(_endTimestamp > block.timestamp, "End time must be in future");
        require(_outcomeLabels.length >= 2, "Need at least 2 outcomes");
        require(_outcomeLabels.length <= 10, "Max 10 outcomes");

        uint256 marketId = totalMarkets++;
        Market storage m = markets[marketId];

        m.id            = marketId;
        m.title         = _title;
        m.description   = _description;
        m.imageHash     = _imageHash;
        m.resolverUrl   = _resolverUrl;
        m.endTimestamp  = _endTimestamp;
        m.createdAt     = block.timestamp;
        m.resolved      = false;
        m.winningOutcome = 0;
        m.createdBy     = msg.sender;
        m.totalAmount   = 0;

        // Store outcome labels and initialise totals to 0
        for (uint256 i = 0; i < _outcomeLabels.length; i++) {
            m.outcomeLabels.push(_outcomeLabels[i]);
            m.outcomeTotals.push(0);
        }

        emit MarketCreated(marketId, _title, msg.sender, _endTimestamp, _outcomeLabels.length);
    }


    function placeBet(
        uint256 _marketId,
        uint256 _outcomeIndex,
        uint256 _amount
    ) external nonReentrant {
        Market storage m = markets[_marketId];

        require(_marketId < totalMarkets, "Invalid market ID");
        require(block.timestamp < m.endTimestamp, "Trading phase ended");
        require(!m.resolved, "Market already resolved");
        require(_amount > 0, "Amount must be greater than 0");
        require(_outcomeIndex < m.outcomeLabels.length, "Invalid outcome index");

        // Users can only bet on one outcome — prevent changing sides
        UserBet storage ub = userBets[_marketId][msg.sender];
        require(
            ub.amount == 0 || ub.outcomeIndex == _outcomeIndex,
            "Cannot change your chosen outcome"
        );

        // CEI: transfer tokens first
        bool success = collateralToken.transferFrom(msg.sender, address(this), _amount);
        require(success, "Token transfer failed");

        // Update user bet
        ub.amount       += _amount;
        ub.outcomeIndex  = _outcomeIndex;

        // Update market totals
        m.outcomeTotals[_outcomeIndex] += _amount;
        m.totalAmount                  += _amount;

        emit BetPlaced(_marketId, msg.sender, _outcomeIndex, _amount);
    }

    function resolveMarket(
        uint256 _marketId,
        uint256 _winningOutcome
    ) external onlyOwner {
        Market storage m = markets[_marketId];

        require(!m.resolved, "Already resolved");
        require(block.timestamp >= m.endTimestamp, "Cannot resolve before end time");
        require(_winningOutcome < m.outcomeLabels.length, "Invalid outcome index");

        // CEI: state before event
        m.resolved       = true;
        m.winningOutcome = _winningOutcome;

        emit MarketResolved(_marketId, _winningOutcome);
    }

    function claimPayout(uint256 _marketId) external nonReentrant {
        Market storage m = markets[_marketId];
        UserBet storage ub = userBets[_marketId][msg.sender];

        require(m.resolved, "Market not resolved yet");
        require(ub.amount > 0, "No bet placed");
        require(!ub.claimed, "Already claimed");
        require(ub.outcomeIndex == m.winningOutcome, "Did not win this market");

        uint256 winnerPool = m.outcomeTotals[m.winningOutcome];
        require(winnerPool > 0, "No winners");

        // Winner gets back their stake + proportional share of losing pools
        // reward = (userStake / winnerPool) * totalPool
        uint256 reward = (ub.amount * m.totalAmount) / winnerPool;

        // CEI: mark claimed before transfer
        ub.claimed = true;

        bool success = collateralToken.transfer(msg.sender, reward);
        require(success, "Payout transfer failed");

        emit PayoutClaimed(_marketId, msg.sender, reward);
    }


    /**
     * @dev Returns probability of each outcome as a percentage (0-100).
     *      Returns equal split if no bets placed yet.
     */
    function getProbabilities(uint256 _marketId)
        public
        view
        returns (uint256[] memory probs)
    {
        Market storage m = markets[_marketId];
        uint256 count = m.outcomeLabels.length;
        probs = new uint256[](count);

        if (m.totalAmount == 0) {
            // Equal probability before any bets
            for (uint256 i = 0; i < count; i++) {
                probs[i] = 100 / count;
            }
            return probs;
        }

        for (uint256 i = 0; i < count; i++) {
            probs[i] = (m.outcomeTotals[i] * 100) / m.totalAmount;
        }
    }

    function getOutcomeLabels(uint256 _marketId)
        public
        view
        returns (string[] memory)
    {
        return markets[_marketId].outcomeLabels;
    }


    function getOutcomeTotals(uint256 _marketId)
        public
        view
        returns (uint256[] memory)
    {
        return markets[_marketId].outcomeTotals;
    }

    function getUserBet(uint256 _marketId, address _user)
        public
        view
        returns (uint256 outcomeIndex, uint256 amount, bool claimed)
    {
        UserBet storage ub = userBets[_marketId][_user];
        return (ub.outcomeIndex, ub.amount, ub.claimed);
    }
}