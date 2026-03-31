import { expect } from "chai";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { MarketLens, PolyToken } from "../typechain-types";

describe("MarketLens", function () {
  let marketLens: MarketLens;
  let polyToken: PolyToken;
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let user3: SignerWithAddress;

  const STAKE = ethers.parseEther("100");
  const ONE_DAY = 24 * 60 * 60;

  // Helper: deploy fresh contracts before each test
  beforeEach(async function () {
    [owner, user1, user2, user3] = await ethers.getSigners();

    const PolyTokenFactory = await ethers.getContractFactory("PolyToken");
    polyToken = await PolyTokenFactory.deploy();

    const MarketLensFactory = await ethers.getContractFactory("MarketLens");
    marketLens = await MarketLensFactory.deploy(await polyToken.getAddress());

    // Mint tokens to users and approve MarketLens to spend them
    await polyToken.mint(user1.address, ethers.parseEther("10000"));
    await polyToken.mint(user2.address, ethers.parseEther("10000"));
    await polyToken.mint(user3.address, ethers.parseEther("10000"));

    await polyToken.connect(user1).approve(await marketLens.getAddress(), ethers.MaxUint256);
    await polyToken.connect(user2).approve(await marketLens.getAddress(), ethers.MaxUint256);
    await polyToken.connect(user3).approve(await marketLens.getAddress(), ethers.MaxUint256);
    await polyToken.approve(await marketLens.getAddress(), ethers.MaxUint256);
  });

  // Helper: create a question that ends in 1 day
  async function createQuestion(endOffset = ONE_DAY) {
    const endTimestamp = (await time.latest()) + endOffset;
    await marketLens.createQuestion(
      "Will ETH hit $10k?",
      "Ethereum price prediction",
      "ipfs://imageHash",
      "https://resolver.com",
      endTimestamp
    );
    return endTimestamp;
  }

  // ─────────────────────────────────────────────
  // createQuestion
  // ─────────────────────────────────────────────
  describe("createQuestion", function () {
    it("creates a question and stores it correctly", async function () {
      const endTimestamp = await createQuestion();
      const q = await marketLens.questions(0);

      expect(q.id).to.equal(0);
      expect(q.title).to.equal("Will ETH hit $10k?");
      expect(q.endTimestamp).to.equal(endTimestamp);
      expect(q.createdBy).to.equal(owner.address);
      expect(q.eventCompleted).to.equal(false);
    });

    it("increments totalQuestions", async function () {
      expect(await marketLens.totalQuestions()).to.equal(0);
      await createQuestion();
      expect(await marketLens.totalQuestions()).to.equal(1);
      await createQuestion();
      expect(await marketLens.totalQuestions()).to.equal(2);
    });

    it("emits QuestionCreated event", async function () {
      const endTimestamp = (await time.latest()) + ONE_DAY;
      await expect(
        marketLens.createQuestion("Test", "Desc", "hash", "url", endTimestamp)
      )
        .to.emit(marketLens, "QuestionCreated")
        .withArgs(0, "Test", owner.address, endTimestamp);
    });

    it("reverts if called by non-owner", async function () {
      const endTimestamp = (await time.latest()) + ONE_DAY;
      await expect(
        marketLens.connect(user1).createQuestion("Test", "Desc", "hash", "url", endTimestamp)
      ).to.be.revertedWith("MarketLens: Unauthorized");
    });

    it("reverts if end time is in the past", async function () {
      const pastTimestamp = (await time.latest()) - 1;
      await expect(
        marketLens.createQuestion("Test", "Desc", "hash", "url", pastTimestamp)
      ).to.be.revertedWith("End time must be in future");
    });
  });

  // ─────────────────────────────────────────────
  // placeBet
  // ─────────────────────────────────────────────
  describe("placeBet", function () {
    beforeEach(async function () {
      await createQuestion();
    });

    it("places a YES bet and updates state", async function () {
      await marketLens.connect(user1).placeBet(0, STAKE, true);
      const bet = await marketLens.userBets(0, user1.address);
      const q = await marketLens.questions(0);

      expect(bet.amount).to.equal(STAKE);
      expect(bet.isYes).to.equal(true);
      expect(q.totalYesAmount).to.equal(STAKE);
      expect(q.totalAmount).to.equal(STAKE);
    });

    it("places a NO bet and updates state", async function () {
      await marketLens.connect(user1).placeBet(0, STAKE, false);
      const q = await marketLens.questions(0);

      expect(q.totalNoAmount).to.equal(STAKE);
    });

    it("allows adding more to the same side", async function () {
      await marketLens.connect(user1).placeBet(0, STAKE, true);
      await marketLens.connect(user1).placeBet(0, STAKE, true);
      const bet = await marketLens.userBets(0, user1.address);
      expect(bet.amount).to.equal(STAKE * 2n);
    });

    it("emits BetPlaced event", async function () {
      await expect(marketLens.connect(user1).placeBet(0, STAKE, true))
        .to.emit(marketLens, "BetPlaced")
        .withArgs(0, user1.address, true, STAKE);
    });

    it("reverts if user tries to switch sides", async function () {
      await marketLens.connect(user1).placeBet(0, STAKE, true);
      await expect(
        marketLens.connect(user1).placeBet(0, STAKE, false)
      ).to.be.revertedWith("Cannot change bet side");
    });

    it("reverts on invalid question ID", async function () {
      await expect(
        marketLens.connect(user1).placeBet(99, STAKE, true)
      ).to.be.revertedWith("Invalid question ID");
    });

    it("reverts if amount is zero", async function () {
      await expect(
        marketLens.connect(user1).placeBet(0, 0, true)
      ).to.be.revertedWith("Amount must be greater than 0");
    });

    it("reverts if market is already resolved", async function () {
      await time.increase(ONE_DAY + 1);
      await marketLens.resolveMarket(0, true);
      await expect(
        marketLens.connect(user1).placeBet(0, STAKE, true)
      ).to.be.revertedWith("Market already resolved");
    });

    it("reverts if trading phase has ended", async function () {
      await time.increase(ONE_DAY + 1);
      await expect(
        marketLens.connect(user1).placeBet(0, STAKE, true)
      ).to.be.revertedWith("Trading phase ended");
    });
  });

  // ─────────────────────────────────────────────
  // resolveMarket
  // ─────────────────────────────────────────────
  describe("resolveMarket", function () {
    beforeEach(async function () {
      await createQuestion();
    });

    it("resolves a market with YES outcome", async function () {
      await time.increase(ONE_DAY + 1);
      await marketLens.resolveMarket(0, true);
      const q = await marketLens.questions(0);
      expect(q.eventCompleted).to.equal(true);
      expect(q.outcome).to.equal(true);
    });

    it("emits MarketResolved event", async function () {
      await time.increase(ONE_DAY + 1);
      await expect(marketLens.resolveMarket(0, false))
        .to.emit(marketLens, "MarketResolved")
        .withArgs(0, false);
    });

    it("reverts if called before end time", async function () {
      await expect(marketLens.resolveMarket(0, true)).to.be.revertedWith(
        "Cannot resolve before end time"
      );
    });

    it("reverts if already resolved", async function () {
      await time.increase(ONE_DAY + 1);
      await marketLens.resolveMarket(0, true);
      await expect(marketLens.resolveMarket(0, true)).to.be.revertedWith(
        "Market already resolved"
      );
    });

    it("reverts if called by non-owner", async function () {
      await time.increase(ONE_DAY + 1);
      await expect(
        marketLens.connect(user1).resolveMarket(0, true)
      ).to.be.revertedWith("MarketLens: Unauthorized");
    });
  });

  // ─────────────────────────────────────────────
  // claimPayout
  // ─────────────────────────────────────────────
  describe("claimPayout", function () {
    beforeEach(async function () {
      await createQuestion();
      // user1 bets YES 100, user2 bets NO 300
      await marketLens.connect(user1).placeBet(0, ethers.parseEther("100"), true);
      await marketLens.connect(user2).placeBet(0, ethers.parseEther("300"), false);
      await time.increase(ONE_DAY + 1);
    });

    it("pays out the winning YES bettor correctly", async function () {
      await marketLens.resolveMarket(0, true);
      const balanceBefore = await polyToken.balanceOf(user1.address);
      await marketLens.connect(user1).claimPayout(0);
      const balanceAfter = await polyToken.balanceOf(user1.address);
      // user1 staked 100, total pool is 400, so reward = 100 + (100 * 300 / 100) = 400
      expect(balanceAfter - balanceBefore).to.equal(ethers.parseEther("400"));
    });

    it("pays out the winning NO bettor correctly", async function () {
      await marketLens.resolveMarket(0, false);
      const balanceBefore = await polyToken.balanceOf(user2.address);
      await marketLens.connect(user2).claimPayout(0);
      const balanceAfter = await polyToken.balanceOf(user2.address);
      // user2 staked 300, reward = 300 + (300 * 100 / 300) = 400
      expect(balanceAfter - balanceBefore).to.equal(ethers.parseEther("400"));
    });

    it("emits PayoutClaimed event", async function () {
      await marketLens.resolveMarket(0, true);
      await expect(marketLens.connect(user1).claimPayout(0))
        .to.emit(marketLens, "PayoutClaimed")
        .withArgs(0, user1.address, ethers.parseEther("400"));
    });

    it("reverts if market not resolved", async function () {
      await expect(
        marketLens.connect(user1).claimPayout(0)
      ).to.be.revertedWith("Market not resolved yet");
    });

    it("reverts if user did not bet", async function () {
      await marketLens.resolveMarket(0, true);
      await expect(
        marketLens.connect(user3).claimPayout(0)
      ).to.be.revertedWith("No bet placed");
    });

    it("reverts if user bet on losing side", async function () {
      await marketLens.resolveMarket(0, true); // YES wins
      await expect(
        marketLens.connect(user2).claimPayout(0) // user2 bet NO
      ).to.be.revertedWith("Did not win this bet");
    });

    it("reverts on double claim", async function () {
      await marketLens.resolveMarket(0, true);
      await marketLens.connect(user1).claimPayout(0);
      await expect(
        marketLens.connect(user1).claimPayout(0)
      ).to.be.revertedWith("Already claimed");
    });
  });

  // ─────────────────────────────────────────────
  // getProbabilities
  // ─────────────────────────────────────────────
  describe("getProbabilities", function () {
    beforeEach(async function () {
      await createQuestion();
    });

    it("returns 50/50 when no bets placed", async function () {
      const [yes, no] = await marketLens.getProbabilities(0);
      expect(yes).to.equal(50);
      expect(no).to.equal(50);
    });

    it("returns correct probabilities with bets", async function () {
      await marketLens.connect(user1).placeBet(0, ethers.parseEther("75"), true);
      await marketLens.connect(user2).placeBet(0, ethers.parseEther("25"), false);
      const [yes, no] = await marketLens.getProbabilities(0);
      expect(yes).to.equal(7500);
      expect(no).to.equal(2500);
    });
  });

  // ─────────────────────────────────────────────
  // createPrivateBet
  // ─────────────────────────────────────────────
  describe("createPrivateBet", function () {
    it("creates a private bet and stores it correctly", async function () {
      await marketLens.connect(user1).createPrivateBet("Who wins the match?", STAKE);
      const pb = await marketLens.privateBets(0);

      expect(pb.creator).to.equal(user1.address);
      expect(pb.stake).to.equal(STAKE);
      expect(pb.description).to.equal("Who wins the match?");
      expect(pb.isJoined).to.equal(false);
      expect(pb.resolved).to.equal(false);
    });

    it("transfers stake from creator to contract", async function () {
      const balanceBefore = await polyToken.balanceOf(user1.address);
      await marketLens.connect(user1).createPrivateBet("Test bet", STAKE);
      const balanceAfter = await polyToken.balanceOf(user1.address);
      expect(balanceBefore - balanceAfter).to.equal(STAKE);
    });

    it("emits PrivateBetCreated event", async function () {
      await expect(marketLens.connect(user1).createPrivateBet("Test", STAKE))
        .to.emit(marketLens, "PrivateBetCreated")
        .withArgs(0, user1.address, STAKE);
    });

    it("increments totalPrivateBets", async function () {
      expect(await marketLens.totalPrivateBets()).to.equal(0);
      await marketLens.connect(user1).createPrivateBet("Test", STAKE);
      expect(await marketLens.totalPrivateBets()).to.equal(1);
    });
  });

  // ─────────────────────────────────────────────
  // joinPrivateBet
  // ─────────────────────────────────────────────
  describe("joinPrivateBet", function () {
    beforeEach(async function () {
      await marketLens.connect(user1).createPrivateBet("Test bet", STAKE);
    });

    it("allows opponent to join and updates state", async function () {
      await marketLens.connect(user2).joinPrivateBet(0);
      const pb = await marketLens.privateBets(0);
      expect(pb.opponent).to.equal(user2.address);
      expect(pb.isJoined).to.equal(true);
    });

    it("transfers stake from opponent to contract", async function () {
      const balanceBefore = await polyToken.balanceOf(user2.address);
      await marketLens.connect(user2).joinPrivateBet(0);
      const balanceAfter = await polyToken.balanceOf(user2.address);
      expect(balanceBefore - balanceAfter).to.equal(STAKE);
    });

    it("emits PrivateBetJoined event", async function () {
      await expect(marketLens.connect(user2).joinPrivateBet(0))
        .to.emit(marketLens, "PrivateBetJoined")
        .withArgs(0, user2.address);
    });

    it("reverts if creator tries to join their own bet", async function () {
      await expect(
        marketLens.connect(user1).joinPrivateBet(0)
      ).to.be.revertedWith("Cannot bet against yourself");
    });

    it("reverts if bet already has an opponent", async function () {
      await marketLens.connect(user2).joinPrivateBet(0);
      await expect(
        marketLens.connect(user3).joinPrivateBet(0)
      ).to.be.revertedWith("Bet already has an opponent");
    });
  });

  // ─────────────────────────────────────────────
  // agreeWinner (mutual-sign resolution)
  // ─────────────────────────────────────────────
  describe("agreeWinner", function () {
    beforeEach(async function () {
      await marketLens.connect(user1).createPrivateBet("Test bet", STAKE);
      await marketLens.connect(user2).joinPrivateBet(0);
    });

    it("does not pay out when only one party has voted", async function () {
      await marketLens.connect(user1).agreeWinner(0, user1.address);
      const pb = await marketLens.privateBets(0);
      expect(pb.resolved).to.equal(false);
    });

    it("pays out when both parties agree on the same winner", async function () {
      const balanceBefore = await polyToken.balanceOf(user1.address);
      await marketLens.connect(user1).agreeWinner(0, user1.address);
      await marketLens.connect(user2).agreeWinner(0, user1.address);
      const balanceAfter = await polyToken.balanceOf(user1.address);

      expect(balanceAfter - balanceBefore).to.equal(STAKE * 2n);
      const pb = await marketLens.privateBets(0);
      expect(pb.resolved).to.equal(true);
    });

    it("does not pay out when parties disagree", async function () {
      await marketLens.connect(user1).agreeWinner(0, user1.address);
      await marketLens.connect(user2).agreeWinner(0, user2.address); // disagrees
      const pb = await marketLens.privateBets(0);
      expect(pb.resolved).to.equal(false);
    });

    it("emits PrivateBetWinnerVote on each vote", async function () {
      await expect(marketLens.connect(user1).agreeWinner(0, user1.address))
        .to.emit(marketLens, "PrivateBetWinnerVote")
        .withArgs(0, user1.address, user1.address);
    });

    it("emits PrivateBetResolved when both agree", async function () {
      await marketLens.connect(user1).agreeWinner(0, user2.address);
      await expect(marketLens.connect(user2).agreeWinner(0, user2.address))
        .to.emit(marketLens, "PrivateBetResolved")
        .withArgs(0, user2.address, STAKE * 2n);
    });

    it("reverts if bet has no opponent yet", async function () {
      await marketLens.connect(user3).createPrivateBet("Unjoined bet", STAKE);
      await expect(
        marketLens.connect(user3).agreeWinner(1, user3.address)
      ).to.be.revertedWith("Bet has no opponent yet");
    });

    it("reverts if a non-participant calls it", async function () {
      await expect(
        marketLens.connect(user3).agreeWinner(0, user1.address)
      ).to.be.revertedWith("Not a participant");
    });

    it("reverts if already resolved", async function () {
      await marketLens.connect(user1).agreeWinner(0, user1.address);
      await marketLens.connect(user2).agreeWinner(0, user1.address);
      await expect(
        marketLens.connect(user1).agreeWinner(0, user1.address)
      ).to.be.revertedWith("Bet already resolved");
    });

    it("reverts if winner is not a participant", async function () {
      await expect(
        marketLens.connect(user1).agreeWinner(0, user3.address)
      ).to.be.revertedWith("Winner must be a participant");
    });
  });

  // ─────────────────────────────────────────────
  // cancelPrivateBet
  // ─────────────────────────────────────────────
  describe("cancelPrivateBet", function () {
    beforeEach(async function () {
      await marketLens.connect(user1).createPrivateBet("Test bet", STAKE);
    });

    it("refunds the creator and marks bet as cancelled", async function () {
      const balanceBefore = await polyToken.balanceOf(user1.address);
      await marketLens.connect(user1).cancelPrivateBet(0);
      const balanceAfter = await polyToken.balanceOf(user1.address);

      expect(balanceAfter - balanceBefore).to.equal(STAKE);
      const pb = await marketLens.privateBets(0);
      expect(pb.cancelled).to.equal(true);
    });

    it("emits PrivateBetCancelled event", async function () {
      await expect(marketLens.connect(user1).cancelPrivateBet(0))
        .to.emit(marketLens, "PrivateBetCancelled")
        .withArgs(0, user1.address);
    });

    it("reverts if called by non-creator", async function () {
      await expect(
        marketLens.connect(user2).cancelPrivateBet(0)
      ).to.be.revertedWith("Only creator can cancel");
    });

    it("reverts if opponent has already joined", async function () {
      await marketLens.connect(user2).joinPrivateBet(0);
      await expect(
        marketLens.connect(user1).cancelPrivateBet(0)
      ).to.be.revertedWith("Cannot cancel opponent already joined");
    });

    it("reverts if already cancelled", async function () {
      await marketLens.connect(user1).cancelPrivateBet(0);
      await expect(
        marketLens.connect(user1).cancelPrivateBet(0)
      ).to.be.revertedWith("Already cancelled");
    });
  });
});