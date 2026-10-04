import { Router } from 'express';
import { blockchainService, networkInfo } from '../../services/blockchain.service.js';
import { recordsSince } from '../../services/chain-registry.service.js';

/**
 * GET /api/blockchain/info — datos públicos del registro on-chain: red,
 * contratos y desde cuándo se registran las reservas. Los usa la app para no
 * tener direcciones ni nombres de red fijos en el código (antes "Datos de la
 * cuenta" mostraba un contrato viejo y "Polygon Amoy Testnet" escritos a mano).
 */
const router = Router();

router.get('/info', async (_req, res) => {
  const readiness = await blockchainService.checkReady();
  const expected = process.env.BLOCKCHAIN_CHAIN_ID ? Number(process.env.BLOCKCHAIN_CHAIN_ID) : null;
  const net = networkInfo(readiness.chainId ?? expected);
  const escrow = process.env.BLOCKCHAIN_CONTRACT_ADDRESS || null;
  const profiles = process.env.BLOCKCHAIN_PROFILES_ADDRESS || null;
  res.json({
    success: true,
    data: {
      active: readiness.ok,
      network: net && { chainId: net.chainId, name: net.name, label: net.label, testnet: net.testnet },
      escrowAddress: escrow,
      escrowUrl: net?.explorer && escrow ? `${net.explorer}/address/${escrow}` : null,
      profilesAddress: profiles,
      recordsSince: recordsSince().toISOString(),
    },
  });
});

export default router;
