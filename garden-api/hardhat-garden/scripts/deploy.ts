import hardhat from "hardhat";
const { ethers } = hardhat;

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Desplegando con la cuenta:", deployer.address);

    // El nombre debe coincidir con el nombre de la clase en el contrato .sol
    const GardenEscrow = await ethers.getContractFactory("GardenEscrow");
    const escrow = await GardenEscrow.deploy();

    await escrow.waitForDeployment();

    const address = await escrow.getAddress();
    console.log("GardenEscrow desplegado en:", address);

    // Opcional: verifica en Polygonscan (Amoy)
    // npx hardhat verify --network amoy DIRECCION
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
