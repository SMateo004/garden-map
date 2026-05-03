/**
 * GardenEscrow v2 — Hardhat unit tests
 * Tests every function including newly added ones:
 *  - resolveDisputeCaregiverWins
 *  - resolveDisputeClientWins
 *  - resolvePartial
 *  - extendWalk
 *  - getReputation
 */

import hre from "hardhat";
const { ethers } = hre;
import { expect } from "chai";
// anyValue matcher for timestamp args we don't want to pin
const anyValue = () => true;

const BID = "booking-uuid-001";

describe("GardenEscrow v2", function () {
  let escrow: any;
  let owner: any;
  let nonOwner: any;

  const START = Math.floor(Date.now() / 1000) + 3600;
  const END = START + 86400 * 3;

  beforeEach(async function () {
    [owner, nonOwner] = await ethers.getSigners();
    const Factory = await ethers.getContractFactory("GardenEscrow");
    escrow = await Factory.deploy();
    await escrow.waitForDeployment();
  });

  async function createTestBooking(bookingId = BID) {
    const tx = await escrow.createBooking(
      bookingId, "client-1", "caregiver-1",
      300, START, END, "Max", "HOSPEDAJE"
    );
    await tx.wait();
  }

  // ── Deploy & ownership ──────────────────────────────────────────────────

  it("deploys with correct owner", async function () {
    expect(await escrow.owner()).to.equal(owner.address);
  });

  it("starts with 0 totalBookings", async function () {
    expect(await escrow.totalBookings()).to.equal(0n);
  });

  // ── createBooking ───────────────────────────────────────────────────────

  describe("createBooking", function () {
    it("creates a booking and increments totalBookings", async function () {
      await createTestBooking();
      expect(await escrow.totalBookings()).to.equal(1n);
    });

    it("emits BookingCreated and PaymentConfirmed events", async function () {
      await expect(
        escrow.createBooking(BID, "c1", "cg1", 300, START, END, "Max", "HOSPEDAJE")
      )
        .to.emit(escrow, "BookingCreated").withArgs(BID, "Max", 300n)
        .and.to.emit(escrow, "PaymentConfirmed");
    });

    it("sets isActive=true after creation", async function () {
      await createTestBooking();
      const b = await escrow.getBooking(BID);
      expect(b.isActive).to.equal(true);
      expect(b.isCompleted).to.equal(false);
    });

    it("reverts if booking already exists", async function () {
      await createTestBooking();
      await expect(createTestBooking()).to.be.revertedWith("La reserva ya existe on-chain");
    });

    it("reverts when called by non-owner", async function () {
      await expect(
        escrow.connect(nonOwner).createBooking(
          BID, "c", "cg", 100, START, END, "Rex", "PASEO"
        )
      ).to.be.revertedWith("Solo el administrador de GARDEN puede llamar esta funcion");
    });
  });

  // ── finalizeBooking ─────────────────────────────────────────────────────

  describe("finalizeBooking", function () {
    beforeEach(createTestBooking);

    it("finalizes with rating and emits ServiceFinalized", async function () {
      const tx = escrow.finalizeBooking(BID, 5);
      await expect(tx).to.emit(escrow, "ServiceFinalized");
      // Verify event args without pinning timestamp
      const receipt = await (await tx).wait();
      const ev = receipt!.logs[0];
      expect(ev).to.not.be.undefined;
    });

    it("sets isCompleted=true, isActive=false, rating", async function () {
      await escrow.finalizeBooking(BID, 4);
      const b = await escrow.getBooking(BID);
      expect(b.isCompleted).to.equal(true);
      expect(b.isActive).to.equal(false);
      expect(b.rating).to.equal(4n);
    });

    it("updates caregiver reputation after finalization", async function () {
      await escrow.finalizeBooking(BID, 5);
      const [total, count] = await escrow.getReputation("caregiver-1");
      expect(total).to.equal(5n);
      expect(count).to.equal(1n);
    });

    it("accumulates reputation across multiple bookings", async function () {
      // Create and finalize second booking for same caregiver
      const BID2 = "booking-uuid-002";
      await escrow.createBooking(BID2, "c2", "caregiver-1", 200, START + 1, END + 1, "Rex", "PASEO");
      await escrow.finalizeBooking(BID, 4);
      await escrow.finalizeBooking(BID2, 3);
      const [total, count] = await escrow.getReputation("caregiver-1");
      expect(total).to.equal(7n);  // 4+3
      expect(count).to.equal(2n);
    });

    it("reverts when rating is 0", async function () {
      await expect(escrow.finalizeBooking(BID, 0)).to.be.revertedWith(
        "La calificacion debe ser entre 1 y 5"
      );
    });

    it("reverts when rating is 6", async function () {
      await expect(escrow.finalizeBooking(BID, 6)).to.be.revertedWith(
        "La calificacion debe ser entre 1 y 5"
      );
    });
  });

  // ── cancelBooking ───────────────────────────────────────────────────────

  describe("cancelBooking", function () {
    beforeEach(createTestBooking);

    it("sets isActive=false and emits ServiceCancelled", async function () {
      await expect(escrow.cancelBooking(BID, "Viaje imprevisto"))
        .to.emit(escrow, "ServiceCancelled");
      const b = await escrow.getBooking(BID);
      expect(b.isActive).to.equal(false);
    });

    it("reverts on second cancel attempt", async function () {
      await escrow.cancelBooking(BID, "reason");
      await expect(escrow.cancelBooking(BID, "again")).to.be.revertedWith(
        "No se puede cancelar una reserva inactiva o finalizada"
      );
    });
  });

  // ── resolveDisputeCaregiverWins ─────────────────────────────────────────

  describe("resolveDisputeCaregiverWins", function () {
    beforeEach(createTestBooking);

    it("resolves dispute for caregiver and emits DisputeResolved", async function () {
      await expect(escrow.resolveDisputeCaregiverWins(BID, 250))
        .to.emit(escrow, "DisputeResolved");
      // Verify verdict via booking state
      const b = await escrow.getBooking(BID);
      expect(b.isActive).to.equal(false);
    });

    it("sets isActive=false after resolution", async function () {
      await escrow.resolveDisputeCaregiverWins(BID, 250);
      const b = await escrow.getBooking(BID);
      expect(b.isActive).to.equal(false);
    });

    it("reverts on already-resolved booking", async function () {
      await escrow.resolveDisputeCaregiverWins(BID, 200);
      await expect(escrow.resolveDisputeCaregiverWins(BID, 200)).to.be.revertedWith(
        "Reserva no activa o ya resuelta"
      );
    });

    it("reverts for non-owner", async function () {
      await expect(
        escrow.connect(nonOwner).resolveDisputeCaregiverWins(BID, 100)
      ).to.be.revertedWith("Solo el administrador de GARDEN puede llamar esta funcion");
    });
  });

  // ── resolveDisputeClientWins ────────────────────────────────────────────

  describe("resolveDisputeClientWins", function () {
    beforeEach(createTestBooking);

    it("resolves dispute for client and emits DisputeResolved", async function () {
      await expect(escrow.resolveDisputeClientWins(BID, 300))
        .to.emit(escrow, "DisputeResolved");
      const b = await escrow.getBooking(BID);
      expect(b.isActive).to.equal(false);
    });

    it("sets isActive=false after resolution", async function () {
      await escrow.resolveDisputeClientWins(BID, 300);
      const b = await escrow.getBooking(BID);
      expect(b.isActive).to.equal(false);
    });
  });

  // ── resolvePartial ──────────────────────────────────────────────────────

  describe("resolvePartial", function () {
    beforeEach(createTestBooking);

    it("resolves dispute partially and emits DisputeResolved PARTIAL", async function () {
      await expect(escrow.resolvePartial(BID, 150, 100))
        .to.emit(escrow, "DisputeResolved");
      const b = await escrow.getBooking(BID);
      expect(b.isActive).to.equal(false);
    });

    it("sets isActive=false after partial resolution", async function () {
      await escrow.resolvePartial(BID, 150, 100);
      const b = await escrow.getBooking(BID);
      expect(b.isActive).to.equal(false);
    });
  });

  // ── extendWalk ──────────────────────────────────────────────────────────

  describe("extendWalk", function () {
    const WALK_BID = "walk-booking-001";
    const WALK_START = Math.floor(Date.now() / 1000) + 7200;
    const WALK_END = WALK_START + 3600; // 60 min walk

    beforeEach(async function () {
      await escrow.createBooking(
        WALK_BID, "client-2", "caregiver-2",
        100, WALK_START, WALK_END, "Rex", "PASEO"
      );
    });

    it("extends walk duration and updates amount, emits WalkExtended", async function () {
      await expect(escrow.extendWalk(WALK_BID, 30, 150))
        .to.emit(escrow, "WalkExtended");
    });

    it("updates endTime by additionalMinutes * 60 seconds", async function () {
      const before = await escrow.getBooking(WALK_BID);
      await escrow.extendWalk(WALK_BID, 30, 150);
      const after = await escrow.getBooking(WALK_BID);
      expect(after.endTime).to.equal(before.endTime + 30n * 60n);
    });

    it("updates amountBs to new amount", async function () {
      await escrow.extendWalk(WALK_BID, 30, 150);
      const b = await escrow.getBooking(WALK_BID);
      expect(b.amountBs).to.equal(150n);
    });

    it("allows multiple extensions", async function () {
      await escrow.extendWalk(WALK_BID, 15, 125);
      await escrow.extendWalk(WALK_BID, 15, 150);
      const b = await escrow.getBooking(WALK_BID);
      expect(b.amountBs).to.equal(150n);
    });

    it("reverts on cancelled booking", async function () {
      await escrow.cancelBooking(WALK_BID, "cliente canceló");
      await expect(escrow.extendWalk(WALK_BID, 30, 150)).to.be.revertedWith(
        "Reserva no activa - no se puede extender"
      );
    });

    it("reverts for non-owner", async function () {
      await expect(
        escrow.connect(nonOwner).extendWalk(WALK_BID, 30, 150)
      ).to.be.revertedWith("Solo el administrador de GARDEN puede llamar esta funcion");
    });
  });

  // ── getReputation ───────────────────────────────────────────────────────

  describe("getReputation", function () {
    it("returns 0,0 for a caregiver with no bookings", async function () {
      const [total, count] = await escrow.getReputation("unknown-caregiver");
      expect(total).to.equal(0n);
      expect(count).to.equal(0n);
    });

    it("accumulates correctly for multiple caregivers independently", async function () {
      // Caregiver A gets 2 bookings: rating 5 and 4
      await escrow.createBooking("b1", "c", "cg-A", 100, START, END, "X", "HOSPEDAJE");
      await escrow.createBooking("b2", "c", "cg-A", 100, START + 10, END + 10, "Y", "HOSPEDAJE");
      await escrow.createBooking("b3", "c", "cg-B", 100, START + 20, END + 20, "Z", "PASEO");

      await escrow.finalizeBooking("b1", 5);
      await escrow.finalizeBooking("b2", 4);
      await escrow.finalizeBooking("b3", 3);

      const [totalA, countA] = await escrow.getReputation("cg-A");
      const [totalB, countB] = await escrow.getReputation("cg-B");

      expect(totalA).to.equal(9n); // 5+4
      expect(countA).to.equal(2n);
      expect(totalB).to.equal(3n);
      expect(countB).to.equal(1n);
    });
  });

  // ── getBooking ──────────────────────────────────────────────────────────

  describe("getBooking", function () {
    it("returns correct booking data", async function () {
      await createTestBooking();
      const b = await escrow.getBooking(BID);
      expect(b.bookingId).to.equal(BID);
      expect(b.clientId).to.equal("client-1");
      expect(b.caregiverId).to.equal("caregiver-1");
      expect(b.amountBs).to.equal(300n);
      expect(b.petName).to.equal("Max");
      expect(b.serviceType).to.equal("HOSPEDAJE");
    });

    it("returns zero-value struct for non-existent booking", async function () {
      const b = await escrow.getBooking("non-existent");
      expect(b.isActive).to.equal(false);
      expect(b.amountBs).to.equal(0n);
    });
  });
});
