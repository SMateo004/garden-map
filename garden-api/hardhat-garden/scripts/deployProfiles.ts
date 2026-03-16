import hardhat from "hardhat";
const { ethers } = hardhat;

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Desplegando GardenProfiles con la cuenta:", deployer.address);

    const GardenProfiles = await ethers.getContractFactory("GardenProfiles");
    const profiles = await GardenProfiles.deploy();

    await profiles.waitForDeployment();

    const address = await profiles.getAddress();
    console.log("GardenProfiles desplegado en:", address);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
