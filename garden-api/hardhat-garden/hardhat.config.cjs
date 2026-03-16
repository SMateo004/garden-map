require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    solidity: {
        version: "0.8.20",
        settings: {
            optimizer: {
                enabled: true,
                runs: 1000,
            },
            viaIR: true,
        },
    },
    networks: {
        amoy: {
            url: process.env.BLOCKCHAIN_RPC_URL || "https://rpc-amoy.polygon.technology",
            accounts: process.env.BLOCKCHAIN_PRIVATE_KEY ? [process.env.BLOCKCHAIN_PRIVATE_KEY] : [],
            chainId: 80002,
        },
    },
};
