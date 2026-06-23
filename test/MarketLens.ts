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

  beforeEach(async function () {
    [owner, user1, user2, user3] = await ethers.getSigners();

    const PolyTokenFactory = await ethers.getContractFactory("PolyToken");
    polyToken = await PolyTokenFactory.deploy();

    const MarketLensFactory = await ethers.getContractFactory("MarketLens");
    marketLens = await MarketLensFactory.deploy(await polyToken.getAddress());

    await polyToken.mint(user1.address, ethers.parseEther("10000"));
    await polyToken.mint(user2.address, ethers.parseEther("10000"));
    await polyToken.mint(user3.address, ethers.parseEther("10000"));

    await polyToken.connect(user1).approve(await marketLens.getAddress(), ethers.MaxUint256);
    await polyToken.connect(user2).approve(await marketLens.getAddress(), ethers.MaxUint256);
    await polyToken.connect(user3).approve(await marketLens.getAddress(), ethers.MaxUint256);
    await polyToken.approve(await marketLens.getAddress(), ethers.MaxUint256);
  });

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
  // createPrivateQuestion
  // ─────────────────────────────────────────────
  describe("createPrivateQuestion", function () {
    it("allows any user to create a private question", async function () {
      const endTimestamp = (await time.latest()) + ONE_DAY;
      await marketLens.connect(user1).createPrivateQuestion(
        "Will it rain?",
        "Private weather bet",
        "ipfs://hash",
        "https://resolver.com",
        endTimestamp
      );
      const q = await marketLens.questions(0);
      expect(q.createdBy).to.equal(user1.address);
      expect(q.title).to.equal("Will it rain?");
    });

    it("prepends [PRIVATE] to the description", async function () {
      const endTimestamp = (await time.latest()) + ONE_DAY;
      await marketLens.connect(user1).createPrivateQuestion(
        "Will it rain?",
        "Private weather bet",
        "ipfs://hash",
        "https://resolver.com",
        endTimestamp
      );
      const q = await marketLens.questions(0);
      expect(q.description).to.include("[PRIVATE]");
    });

    it("increments totalQuestions", async function () {
      const endTimestamp = (await time.latest()) + ONE_DAY;
      await marketLens.connect(user1).createPrivateQuestion(
        "Test", "Desc", "hash", "url", endTimestamp
      );
      expect(await marketLens.totalQuestions()).to.equal(1);
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
  // sellBet
  // ─────────────────────────────────────────────
  describe("sellBet", function () {
    beforeEach(async function () {
      await createQuestion();
    });

    it("reverts if user has no bet to sell", async function () {
      await expect(
        marketLens.connect(user1).sellBet(0)
      ).to.be.revertedWith("No bet to sell");
    });

    it("refunds full stake when user is the only bettor (50/50 pool)", async function () {
      await marketLens.connect(user1).placeBet(0, STAKE, true);

      const balanceBefore = await polyToken.balanceOf(user1.address);
      await marketLens.connect(user1).sellBet(0);
      const balanceAfter = await polyToken.balanceOf(user1.address);

      // sidePool == totalAmount == STAKE → sellValue = STAKE * STAKE * 95 / (STAKE * 100) = STAKE * 0.95
      const expected = (STAKE * 95n) / 100n;
      expect(balanceAfter - balanceBefore).to.equal(expected);
    });

    it("clears the user's bet after selling", async function () {
      await marketLens.connect(user1).placeBet(0, STAKE, true);
      await marketLens.connect(user1).sellBet(0);

      const bet = await marketLens.userBets(0, user1.address);
      expect(bet.amount).to.equal(0);
      expect(bet.claimed).to.equal(true);
    });

    it("removes the stake from the side pool and total pool", async function () {
      await marketLens.connect(user1).placeBet(0, STAKE, true);
      await marketLens.connect(user2).placeBet(0, STAKE, false);

      await marketLens.connect(user1).sellBet(0);

      const q = await marketLens.questions(0);
      expect(q.totalYesAmount).to.equal(0);
      expect(q.totalNoAmount).to.equal(STAKE);
      expect(q.totalAmount).to.equal(STAKE);
    });

    it("pays more than original stake when selling side has minority pool (profit)", async function () {
      // user1 bets 50 YES, user2 bets 150 NO → YES side is the minority (1:4 of total)
      const yesStake = ethers.parseEther("50");
      const noStake  = ethers.parseEther("150");
      await marketLens.connect(user1).placeBet(0, yesStake, true);
      await marketLens.connect(user2).placeBet(0, noStake, false);

      const [sellValue, originalStake] = await marketLens.getSellValue(0, user1.address);

      expect(originalStake).to.equal(yesStake);
      // sellValue = yesStake * totalAmount * 95 / (yesPool * 100)
      //           = 50 * 200 * 95 / (50 * 100) = 19000/100 = 190
      expect(sellValue).to.be.gt(originalStake);
    });

    it("pays less than original stake when selling side has majority pool (loss)", async function () {
      // user1 bets 150 YES, user2 bets 50 NO → YES side is the majority
      const yesStake = ethers.parseEther("150");
      const noStake  = ethers.parseEther("50");
      await marketLens.connect(user1).placeBet(0, yesStake, true);
      await marketLens.connect(user2).placeBet(0, noStake, false);

      const [sellValue, originalStake] = await marketLens.getSellValue(0, user1.address);

      expect(originalStake).to.equal(yesStake);
      expect(sellValue).to.be.lt(originalStake);
    });

    it("getSellValue returns (0,0) when user has no bet", async function () {
      const [sellValue, originalStake] = await marketLens.getSellValue(0, user1.address);
      expect(sellValue).to.equal(0);
      expect(originalStake).to.equal(0);
    });

    it("reverts if market has already resolved", async function () {
      await marketLens.connect(user1).placeBet(0, STAKE, true);
      await time.increase(ONE_DAY + 1);
      await marketLens.resolveMarket(0, true);

      await expect(
        marketLens.connect(user1).sellBet(0)
      ).to.be.revertedWith("Market already resolved");
    });

    it("reverts if market has ended (deadline passed) even if not resolved", async function () {
      await marketLens.connect(user1).placeBet(0, STAKE, true);
      await time.increase(ONE_DAY + 1);

      await expect(
        marketLens.connect(user1).sellBet(0)
      ).to.be.revertedWith("Market has ended");
    });

    it("reverts on double sell", async function () {
      await marketLens.connect(user1).placeBet(0, STAKE, true);
      await marketLens.connect(user1).sellBet(0);

      await expect(
        marketLens.connect(user1).sellBet(0)
      ).to.be.revertedWith("No bet to sell");
    });

    it("emits BetPlaced event with 0 amount on sell", async function () {
      await marketLens.connect(user1).placeBet(0, STAKE, true);
      await expect(marketLens.connect(user1).sellBet(0))
        .to.emit(marketLens, "BetPlaced")
        .withArgs(0, user1.address, true, 0);
    });

    it("updates probabilities after a sell", async function () {
      await marketLens.connect(user1).placeBet(0, STAKE, true);
      await marketLens.connect(user2).placeBet(0, STAKE, false);

      // Before sell: 50/50
      let [yes, no] = await marketLens.getProbabilities(0);
      expect(yes).to.equal(5000);
      expect(no).to.equal(5000);

      // user1 sells their YES position entirely
      await marketLens.connect(user1).sellBet(0);

      // Now only NO pool remains → 100% NO
      [yes, no] = await marketLens.getProbabilities(0);
      expect(no).to.equal(10000);
      expect(yes).to.equal(0);
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

    it("reverts if called by non-owner on a public market", async function () {
      await time.increase(ONE_DAY + 1);
      await expect(
        marketLens.connect(user1).resolveMarket(0, true)
      ).to.be.revertedWith("MarketLens: Unauthorized");
    });
  });

  // ─────────────────────────────────────────────
  // resolvePrivateMarket
  // ─────────────────────────────────────────────
  describe("resolvePrivateMarket", function () {
    let endTimestamp: number;

    beforeEach(async function () {
      endTimestamp = (await time.latest()) + ONE_DAY;
      await marketLens.connect(user1).createPrivateQuestion(
        "Private market", "Desc", "hash", "url", endTimestamp
      );
    });

    it("allows the creator to resolve their own private market", async function () {
      await time.increase(ONE_DAY + 1);
      await marketLens.connect(user1).resolvePrivateMarket(0, true);
      const q = await marketLens.questions(0);
      expect(q.eventCompleted).to.equal(true);
      expect(q.outcome).to.equal(true);
    });

    it("allows the owner to resolve a private market", async function () {
      await time.increase(ONE_DAY + 1);
      await marketLens.resolvePrivateMarket(0, false);
      const q = await marketLens.questions(0);
      expect(q.eventCompleted).to.equal(true);
    });

    it("reverts if called by someone who is neither owner nor creator", async function () {
      await time.increase(ONE_DAY + 1);
      await expect(
        marketLens.connect(user2).resolvePrivateMarket(0, true)
      ).to.be.revertedWith("MarketLens: Unauthorized");
    });

    it("reverts if called before end time", async function () {
      await expect(
        marketLens.connect(user1).resolvePrivateMarket(0, true)
      ).to.be.revertedWith("Cannot resolve before end time");
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

    it("reverts if user sold their position before resolution", async function () {
      // user1 sells before market ends
      await marketLens.connect(user1).sellBet(0);
      await time.increase(ONE_DAY + 1);
      await marketLens.resolveMarket(0, true);

      await expect(
        marketLens.connect(user1).claimPayout(0)
      ).to.be.revertedWith("No bet placed");
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
      expect(yes).to.equal(5000);
      expect(no).to.equal(5000);
    });

    it("returns correct probabilities with bets", async function () {
      await marketLens.connect(user1).placeBet(0, ethers.parseEther("75"), true);
      await marketLens.connect(user2).placeBet(0, ethers.parseEther("25"), false);
      const [yes, no] = await marketLens.getProbabilities(0);
      expect(yes).to.equal(7500);
      expect(no).to.equal(2500);
    });
  });
});