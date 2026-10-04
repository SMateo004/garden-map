/**
 * Despliega GardenEscrow v3 y GardenProfiles v2 y los verifica en Polygonscan.
 *
 *   npm run deploy:amoy      # ensayo en la testnet
 *   npm run deploy:polygon   # red principal (cuesta POL real)
 *
 * El wallet de GARDEN_DEPLOYER_KEY queda como owner y como recorder. Para que
 * el recorder sea otro wallet: RECORDER_ADDRESS=0x... npm run deploy:polygon
 * Guarda direcciones, txs y bloque en deployments/<red>.json (sin secretos).
 * Pasos completos en DEPLOY-MAINNET.md.
 */
const fs = require("fs");
const path = require("path");
const hre = require("hardhat");
const { ethers, network } = hre;

const EXPLORER = { polygon: "https://polygonscan.com", amoy: "https://amoy.polygonscan.com" };
// Polygon exige una propina mínima (~25-30 gwei); ethers por defecto propone 1 gwei
// y la tx puede quedar colgada. Mismo cálculo que usa la API (blockchain.service.ts).
const MIN_TIP_GWEI = { polygon: 30n, amoy: 25n };

async function feeOverrides() {
    const block = await ethers.provider.getBlock("latest");
    let tip = ethers.parseUnits(String(MIN_TIP_GWEI[network.name] ?? 2n), "gwei");
    try {
        const suggested = BigInt(await ethers.provider.send("eth_maxPriorityFeePerGas", []));
        if (suggested > tip) tip = suggested;
    } catch { /* RPC sin ese método: queda el mínimo */ }
    return { maxPriorityFeePerGas: tip, maxFeePerGas: block.baseFeePerGas * 2n + tip };
}

async function main() {
    if (!EXPLORER[network.name]) throw new Error(`Usa --network polygon o --network amoy (recibí ${network.name})`);
    const [deployer] = await ethers.getSigners();
    if (!deployer) throw new Error("Falta GARDEN_DEPLOYER_KEY: npx hardhat vars set GARDEN_DEPLOYER_KEY");
    const { chainId } = await ethers.provider.getNetwork();
    const recorder = process.env.RECORDER_ADDRESS || deployer.address;
    if (!ethers.isAddress(recorder)) throw new Error(`RECORDER_ADDRESS inválida: ${recorder}`);

    const balance = await ethers.provider.getBalance(deployer.address);
    const fees = await feeOverrides();
    console.log(`Red:       ${network.name} (chainId ${chainId})`);
    console.log(`Deployer:  ${deployer.address}  (owner)`);
    console.log(`Recorder:  ${recorder}`);
    console.log(`Saldo:     ${ethers.formatEther(balance)} POL`);
    console.log(`Gas:       maxFee ${ethers.formatUnits(fees.maxFeePerGas, "gwei")} gwei, propina ${ethers.formatUnits(fees.maxPriorityFeePerGas, "gwei")} gwei`);

    const escrowF = await ethers.getContractFactory("GardenEscrow");
    const profilesF = await ethers.getContractFactory("GardenProfiles");
    const deployGas =
        (await ethers.provider.estimateGas(await escrowF.getDeployTransaction(recorder))) +
        (await ethers.provider.estimateGas(await profilesF.getDeployTransaction(recorder)));
    const maxCost = deployGas * fees.maxFeePerGas;
    console.log(`Costo máx. del deploy: ${ethers.formatEther(maxCost)} POL (${deployGas} gas)`);
    if (balance < maxCost) throw new Error("Saldo insuficiente para el deploy. Fondea el wallet y vuelve a correr.");

    console.log("\nDesplegando GardenEscrow v3...");
    const escrow = await escrowF.deploy(recorder, fees);
    const escrowTx = escrow.deploymentTransaction();
    const escrowReceipt = await escrowTx.wait(3);
    console.log("Desplegando GardenProfiles v2...");
    const profiles = await profilesF.deploy(recorder, await feeOverrides());
    const profilesTx = profiles.deploymentTransaction();
    const profilesReceipt = await profilesTx.wait(3);

    const out = {
        network: network.name,
        chainId: Number(chainId),
        deployedAt: new Date().toISOString(),
        owner: deployer.address,
        recorder,
        GardenEscrow: { address: await escrow.getAddress(), version: 3, tx: escrowTx.hash, block: escrowReceipt.blockNumber },
        GardenProfiles: { address: await profiles.getAddress(), version: 2, tx: profilesTx.hash, block: profilesReceipt.blockNumber },
    };
    const dir = path.join(__dirname, "..", "deployments");
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, `${network.name}.json`), JSON.stringify(out, null, 2) + "\n");

    const spent = escrowReceipt.gasUsed * escrowReceipt.gasPrice + profilesReceipt.gasUsed * profilesReceipt.gasPrice;
    console.log(`\nListo. Gastado: ${ethers.formatEther(spent)} POL`);
    console.log(`  GardenEscrow:   ${out.GardenEscrow.address}  ${EXPLORER[network.name]}/address/${out.GardenEscrow.address}`);
    console.log(`  GardenProfiles: ${out.GardenProfiles.address}  ${EXPLORER[network.name]}/address/${out.GardenProfiles.address}`);
    console.log(`  Guardado en deployments/${network.name}.json`);

    if (hre.config.etherscan.apiKey) {
        console.log("\nVerificando código en Polygonscan...");
        for (const [name, address] of [["GardenEscrow", out.GardenEscrow.address], ["GardenProfiles", out.GardenProfiles.address]]) {
            try {
                await hre.run("verify:verify", { address, constructorArguments: [recorder] });
            } catch (e) {
                console.warn(`  No se pudo verificar ${name} ahora: ${e.message}`);
                console.warn(`  Reintenta: npx hardhat verify --network ${network.name} ${address} ${recorder}`);
            }
        }
    } else {
        console.log("\nSin ETHERSCAN_API_KEY: verifica después con");
        console.log(`  npx hardhat verify --network ${network.name} ${out.GardenEscrow.address} ${recorder}`);
        console.log(`  npx hardhat verify --network ${network.name} ${out.GardenProfiles.address} ${recorder}`);
    }

    console.log("\nVariables para Render:");
    console.log(`  BLOCKCHAIN_CHAIN_ID=${chainId}`);
    console.log(`  BLOCKCHAIN_CONTRACT_ADDRESS=${out.GardenEscrow.address}`);
    console.log(`  BLOCKCHAIN_PROFILES_ADDRESS=${out.GardenProfiles.address}`);
    console.log(`  BLOCKCHAIN_DEPLOY_BLOCK=${escrowReceipt.blockNumber}`);
}

main().catch((e) => { console.error("\nDeploy fallido:", e.message ?? e); process.exitCode = 1; });
