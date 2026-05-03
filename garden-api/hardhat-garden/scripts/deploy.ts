/**
 * Deploy GardenEscrow v2 to Polygon Amoy.
 *
 * Usage:
 *   cd hardhat-garden
 *   npx hardhat run scripts/deploy.ts --network amoy
 *
 * After deployment:
 *  1. Copy the printed contract address.
 *  2. Update BLOCKCHAIN_CONTRACT_ADDRESS in garden-api/.env
 *  3. Restart the API server.
 *
 * Pre-requisite: wallet must have ≥ 0.05 MATIC on Amoy testnet.
 * Faucet: https://www.alchemy.com/faucets/polygon-amoy
 */

import hre from "hardhat";
const { ethers } = hre;

async function main() {
    const [deployer] = await ethers.getSigners();

    const balance = await ethers.provider.getBalance(deployer.address);
    console.log(`Deploying GardenEscrow v2 from: ${deployer.address}`);
    console.log(`Wallet balance: ${ethers.formatEther(balance)} MATIC`);

    if (balance < ethers.parseEther("0.02")) {
        throw new Error(
            `Insufficient MATIC balance (${ethers.formatEther(balance)} MATIC). ` +
            `Need at least 0.02 MATIC. ` +
            `Get testnet tokens from: https://www.alchemy.com/faucets/polygon-amoy`
        );
    }

    console.log("\nDeploying GardenEscrow v2...");
    const GardenEscrow = await ethers.getContractFactory("GardenEscrow");
    const escrow = await GardenEscrow.deploy();

    await escrow.waitForDeployment();

    const address = await escrow.getAddress();
    const deployTx = escrow.deploymentTransaction();
    console.log(`\n✅ GardenEscrow v2 deployed!`);
    console.log(`   Contract address: ${address}`);
    console.log(`   Deploy tx hash:   ${deployTx?.hash}`);
    console.log(`   Block explorer:   https://amoy.polygonscan.com/address/${address}`);

    console.log(`\n📝 Next steps:`);
    console.log(`   1. Update BLOCKCHAIN_CONTRACT_ADDRESS=${address} in garden-api/.env`);
    console.log(`   2. Restart the API server`);
    console.log(`   3. Optionally verify: npx hardhat verify --network amoy ${address}`);
}

main().catch((error) => {
    console.error("\n❌ Deployment failed:", error.message ?? error);
    process.exitCode = 1;
});
