/**
 * GardenEscrow v3 + GardenProfiles v2 — se corren con `npm test` (red local de hardhat).
 */
const { expect } = require("chai");
const { ethers } = require("hardhat");

const uuidToBytes16 = (u) => "0x" + u.replace(/-/g, "");
const BID = uuidToBytes16("8f14e45f-ceea-467a-9575-1a2b3c4d5e6f");
const CLIENT = ethers.id("client-ref");
const CAREGIVER = ethers.id("caregiver-ref");
const PASEO = 1, HOSPEDAJE = 2;
const ACTIVE = 1, COMPLETED = 2, CANCELLED = 3, RESOLVED = 4;

describe("GardenEscrow v3", function () {
    let escrow, owner, recorder, other;

    beforeEach(async () => {
        [owner, recorder, other] = await ethers.getSigners();
        escrow = await (await ethers.getContractFactory("GardenEscrow")).deploy(recorder.address);
    });

    const record = (id = BID, signer = recorder) =>
        escrow.connect(signer).recordBooking(id, CLIENT, CAREGIVER, PASEO, 3150, 1_790_000_000, 1_790_003_600, 1_790_007_200);

    it("owner y recorder quedan configurados; no acepta POL", async () => {
        expect(await escrow.owner()).to.equal(owner.address);
        expect(await escrow.recorder()).to.equal(recorder.address);
        expect(await escrow.VERSION()).to.equal(3n);
        await expect(owner.sendTransaction({ to: await escrow.getAddress(), value: 1n })).to.be.reverted;
    });

    it("solo el recorder escribe (ni siquiera el owner)", async () => {
        await expect(record(BID, owner)).to.be.revertedWithCustomError(escrow, "NotRecorder");
        await expect(record(BID, other)).to.be.revertedWithCustomError(escrow, "NotRecorder");
    });

    it("el owner rota el recorder; no se puede renunciar al owner", async () => {
        await expect(escrow.connect(other).setRecorder(other.address))
            .to.be.revertedWithCustomError(escrow, "OwnableUnauthorizedAccount");
        await expect(escrow.setRecorder(other.address)).to.emit(escrow, "RecorderChanged")
            .withArgs(recorder.address, other.address);
        await expect(record()).to.be.revertedWithCustomError(escrow, "NotRecorder");
        await expect(record(BID, other)).to.emit(escrow, "BookingRecorded");
        await expect(escrow.setRecorder(ethers.ZeroAddress)).to.be.revertedWithCustomError(escrow, "ZeroAddress");
        await expect(escrow.renounceOwnership()).to.be.revertedWithCustomError(escrow, "RenounceDisabled");
    });

    it("la transferencia de owner es en dos pasos", async () => {
        await escrow.transferOwnership(other.address);
        expect(await escrow.owner()).to.equal(owner.address);
        await escrow.connect(other).acceptOwnership();
        expect(await escrow.owner()).to.equal(other.address);
    });

    it("registra la reserva una sola vez, con evento buscable por uuid", async () => {
        await expect(record()).to.emit(escrow, "BookingRecorded")
            .withArgs(BID, CLIENT, CAREGIVER, PASEO, 3150, 1_790_000_000, 1_790_003_600, 1_790_007_200);
        const b = await escrow.getBooking(BID);
        expect(b.status).to.equal(ACTIVE);
        expect(b.amountCents).to.equal(3150n);
        expect(await escrow.totalBookings()).to.equal(1n);
        await expect(record()).to.be.revertedWithCustomError(escrow, "AlreadyRecorded").withArgs(BID);

        const logs = await escrow.queryFilter(escrow.filters.BookingRecorded(BID));
        expect(logs).to.have.length(1);
    });

    it("valida entradas", async () => {
        const r = escrow.connect(recorder);
        await expect(r.recordBooking("0x" + "00".repeat(16), CLIENT, CAREGIVER, PASEO, 1, 1, 1, 1))
            .to.be.revertedWithCustomError(escrow, "InvalidInput");
        await expect(r.recordBooking(BID, ethers.ZeroHash, CAREGIVER, PASEO, 1, 1, 1, 1))
            .to.be.revertedWithCustomError(escrow, "InvalidInput");
        await expect(r.recordBooking(BID, CLIENT, CAREGIVER, 0, 1, 1, 1, 1))
            .to.be.revertedWithCustomError(escrow, "InvalidInput");
        await expect(r.recordBooking(BID, CLIENT, CAREGIVER, PASEO, 1, 1, 10, 5))
            .to.be.revertedWithCustomError(escrow, "InvalidInput");
        await expect(r.recordBooking(BID, CLIENT, CAREGIVER, 9, 1, 1, 1, 1)).to.be.reverted; // enum fuera de rango
    });

    it("finaliza con calificación y suma reputación; 0 = sin calificar no suma", async () => {
        const BID2 = uuidToBytes16("00000000-0000-4000-8000-000000000002");
        await record();
        await record(BID2);
        await expect(escrow.connect(recorder).finalizeBooking(BID, 6)).to.be.revertedWithCustomError(escrow, "InvalidInput");
        await expect(escrow.connect(recorder).finalizeBooking(BID, 4)).to.emit(escrow, "BookingFinalized").withArgs(BID, 4);
        await escrow.connect(recorder).finalizeBooking(BID2, 0);
        expect(await escrow.getReputation(CAREGIVER)).to.deep.equal([4n, 1n]);
        expect((await escrow.getBooking(BID)).status).to.equal(COMPLETED);
        await expect(escrow.connect(recorder).finalizeBooking(BID, 5))
            .to.be.revertedWithCustomError(escrow, "NotActive").withArgs(BID, COMPLETED);
    });

    it("cancela con código numérico y no permite operar sobre reservas desconocidas", async () => {
        await expect(escrow.connect(recorder).cancelBooking(BID, 1, 0))
            .to.be.revertedWithCustomError(escrow, "UnknownBooking");
        await record();
        await expect(escrow.connect(recorder).cancelBooking(BID, 8, 0)).to.be.revertedWithCustomError(escrow, "InvalidInput");
        await expect(escrow.connect(recorder).cancelBooking(BID, 2, 3150))
            .to.emit(escrow, "BookingCancelled").withArgs(BID, 2, 3150);
        expect((await escrow.getBooking(BID)).status).to.equal(CANCELLED);
    });

    it("el veredicto se acepta sobre una reserva cancelada (no-show) y una apelación lo reemplaza", async () => {
        await record();
        await escrow.connect(recorder).cancelBooking(BID, 6, 0);
        await expect(escrow.connect(recorder).resolveDispute(BID, 2, 0, 3150))
            .to.emit(escrow, "DisputeResolved").withArgs(BID, 2, 0, 3150);
        await expect(escrow.connect(recorder).resolveDispute(BID, 1, 2500, 0)).to.emit(escrow, "DisputeResolved");
        const b = await escrow.getBooking(BID);
        expect(b.status).to.equal(RESOLVED);
        expect(b.verdict).to.equal(1);
        await expect(escrow.connect(recorder).resolveDispute(BID, 0, 0, 0)).to.be.revertedWithCustomError(escrow, "InvalidInput");
    });

    it("extiende paseos (minutos) y hospedajes (días) solo si está activa", async () => {
        await record();
        await expect(escrow.connect(recorder).extendBooking(BID, 1, 30, 4500))
            .to.emit(escrow, "BookingExtended").withArgs(BID, 1, 30, 4500, 1_790_007_200 + 1800);
        await escrow.connect(recorder).extendBooking(BID, 2, 1, 9000);
        const b = await escrow.getBooking(BID);
        expect(b.endTime).to.equal(BigInt(1_790_007_200 + 1800 + 86400));
        expect(b.amountCents).to.equal(9000n);
        await expect(escrow.connect(recorder).extendBooking(BID, 0, 1, 1)).to.be.revertedWithCustomError(escrow, "InvalidInput");
        await escrow.connect(recorder).finalizeBooking(BID, 5);
        await expect(escrow.connect(recorder).extendBooking(BID, 1, 10, 1)).to.be.revertedWithCustomError(escrow, "NotActive");
    });

    it("hospedaje de varios días se registra igual", async () => {
        await expect(escrow.connect(recorder).recordBooking(BID, CLIENT, CAREGIVER, HOSPEDAJE, 22000, 1, 100, 100 + 3 * 86400))
            .to.emit(escrow, "BookingRecorded");
    });
});

describe("GardenProfiles v2", function () {
    let profiles, owner, recorder;
    const USER = ethers.id("user-ref");

    beforeEach(async () => {
        [owner, recorder] = await ethers.getSigners();
        profiles = await (await ethers.getContractFactory("GardenProfiles")).deploy(recorder.address);
    });

    it("sincroniza rol y verificación sin datos personales", async () => {
        await expect(profiles.connect(owner).syncProfile(USER, 1, false)).to.be.revertedWithCustomError(profiles, "NotRecorder");
        await expect(profiles.connect(recorder).syncProfile(USER, 0, false)).to.be.revertedWithCustomError(profiles, "InvalidInput");
        await expect(profiles.connect(recorder).syncProfile(USER, 2, false)).to.emit(profiles, "ProfileSynced").withArgs(USER, 2, false);
        const first = await profiles.getProfile(USER);
        await profiles.connect(recorder).syncProfile(USER, 2, true);
        const p = await profiles.getProfile(USER);
        expect(p.verified).to.equal(true);
        expect(p.joinedAt).to.equal(first.joinedAt);
        expect(await profiles.totalProfiles()).to.equal(1n);
        expect(await profiles.isUserVerified(USER)).to.equal(true);
        await expect(owner.sendTransaction({ to: await profiles.getAddress(), value: 1n })).to.be.reverted;
    });
});
