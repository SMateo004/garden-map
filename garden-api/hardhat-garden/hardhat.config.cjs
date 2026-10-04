require("@nomicfoundation/hardhat-toolbox");
const { vars } = require("hardhat/config");

/**
 * Claves y URLs: se guardan con `npx hardhat vars set <NOMBRE>` (quedan en la
 * carpeta de configuración del usuario, fuera del repo), nunca en un archivo
 * de esta carpeta ni pegadas en un chat. Ver DEPLOY-MAINNET.md.
 *
 *   GARDEN_DEPLOYER_KEY  clave privada del wallet que despliega (queda como owner y recorder)
 *   POLYGON_RPC_URL      RPC de la red principal (Alchemy); hay uno público por defecto
 *   AMOY_RPC_URL         RPC de la testnet Amoy (opcional)
 *   ETHERSCAN_API_KEY    API key de Etherscan v2 (sirve para polygonscan.com)
 */
const deployerKey = vars.get("GARDEN_DEPLOYER_KEY", "");
const accounts = deployerKey ? [deployerKey] : [];

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    solidity: {
        version: "0.8.24",
        settings: {
            optimizer: { enabled: true, runs: 1000 },
            evmVersion: "shanghai",
        },
    },
    networks: {
        polygon: {
            url: vars.get("POLYGON_RPC_URL", "https://polygon-bor-rpc.publicnode.com"),
            accounts,
            chainId: 137,
        },
        amoy: {
            url: vars.get("AMOY_RPC_URL", "https://polygon-amoy-bor-rpc.publicnode.com"),
            accounts,
            chainId: 80002,
        },
    },
    etherscan: {
        // Etherscan API v2: una sola key para todas las redes (Polygon PoS y Amoy incluidas).
        apiKey: vars.get("ETHERSCAN_API_KEY", ""),
    },
    sourcify: { enabled: false },
};
