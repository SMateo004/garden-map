/**
 * Mide el gas real de desplegar y de cada operación en la red local de hardhat
 * y lo traduce a POL para un rango de precios de gas de Polygon PoS.
 *
 *   npm run gas
 *   npx hardhat run scripts/estimate-gas.cjs --network polygon   # usa el precio de gas actual (solo lectura)
 */
const { ethers, network } = require("hardhat");
const { randomUUID, randomBytes } = require("crypto");

const b16 = () => "0x" + randomUUID().replace(/-/g, "");
const ref = () => "0x" + randomBytes(32).toString("hex");

async function gasOf(txPromise) {
    const receipt = await (await txPromise).wait();
    return receipt.gasUsed;
}

async function measureLocally() {
    const [deployer] = await ethers.getSigners();
    const results = [];
    const escrowF = await ethers.getContractFactory("GardenEscrow");
    const profilesF = await ethers.getContractFactory("GardenProfiles");
    const escrow = await escrowF.deploy(deployer.address);
    const profiles = await profilesF.deploy(deployer.address);
    results.push(["Deploy GardenEscrow", (await escrow.deploymentTransaction().wait()).gasUsed]);
    results.push(["Deploy GardenProfiles", (await profiles.deploymentTransaction().wait()).gasUsed]);

    const now = Math.floor(Date.now() / 1000);
    const caregiver = ref();
    const ids = [b16(), b16(), b16(), b16()];
    for (const id of ids) {
        const g = await gasOf(escrow.recordBooking(id, ref(), caregiver, 1, 4550, now, now + 3600, now + 7200));
        if (id === ids[0]) results.push(["recordBooking (pago)", g]);
    }
    results.push(["extendBooking (extensión)", await gasOf(escrow.extendBooking(ids[0], 1, 30, 6000))]);
    results.push(["finalizeBooking (con calificación)", await gasOf(escrow.finalizeBooking(ids[0], 5))]);
    results.push(["cancelBooking", await gasOf(escrow.cancelBooking(ids[1], 1, 4550))]);
    results.push(["resolveDispute", await gasOf(escrow.resolveDispute(ids[2], 1, 3600, 0))]);
    results.push(["syncProfile (alta)", await gasOf(profiles.syncProfile(ref(), 1, false))]);
    const u = ref();
    await profiles.syncProfile(u, 2, false);
    results.push(["syncProfile (verificación)", await gasOf(profiles.syncProfile(u, 2, true))]);
    return results;
}

async function main() {
    // Siempre se mide en una red local efímera para no gastar nada.
    const results = network.name === "hardhat" ? await measureLocally() : null;
    let currentGwei = null;
    if (network.name !== "hardhat") {
        const block = await ethers.provider.getBlock("latest");
        const tip = BigInt(await ethers.provider.send("eth_maxPriorityFeePerGas", []));
        currentGwei = Number(ethers.formatUnits(block.baseFeePerGas + tip, "gwei"));
        console.log(`Precio de gas actual en ${network.name}: ~${currentGwei.toFixed(1)} gwei (base + propina)`);
        console.log("Para los gas units corre `npm run gas` (red local).");
        return;
    }
    const prices = [30, 50, 100, 300];
    console.log(`\n${"Operación".padEnd(38)}${"gas".padStart(10)}  ` + prices.map((p) => `${p} gwei`.padStart(12)).join(""));
    for (const [label, gas] of results) {
        const cols = prices.map((p) => (Number(gas) * p / 1e9).toFixed(5).padStart(12)).join("");
        console.log(`${label.padEnd(38)}${gas.toString().padStart(10)}  ${cols}`);
    }
    console.log("\nValores en POL. Una reserva típica = recordBooking + finalizeBooking (o cancel / resolveDispute).");
}

main().catch((e) => { console.error(e); process.exitCode = 1; });
