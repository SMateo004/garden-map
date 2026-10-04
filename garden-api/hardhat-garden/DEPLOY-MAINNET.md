# Registro on-chain en Polygon PoS (red principal): guía de despliegue

Pasos para que Sai despliegue los contratos y active el registro en producción.
Nada de esto lo hace Claude: las claves privadas **nunca** se pegan en un chat,
un PR ni un archivo de este repo.

## Qué se despliega

| Contrato | Qué guarda | Strings |
|---|---|---|
| `GardenEscrow` v3 | Reserva (uuid como `bytes16`), referencia seudónima de dueño y cuidador (`bytes32`), tipo de servicio, monto en centavos, fechas, cierre (calificación 0-5, cancelación con código, veredicto) y extensiones | Ninguno |
| `GardenProfiles` v2 | Referencia seudónima, rol y si la identidad está verificada | Ninguno |

- **Owner** (Ownable2Step): el wallet que despliega. Puede cambiar el `recorder`; no puede renunciar.
- **Recorder**: el único que escribe registros (el wallet de `BLOCKCHAIN_PRIVATE_KEY` en Render).
  Si su clave se filtra, el owner pone otro recorder y el historial se conserva.
- No tienen funciones `payable` ni `receive`: si alguien les manda POL, la transacción se revierte.
- 12 tests: `npm test`.

## Costo estimado (medido con `npm run gas`)

El 4-oct-2026 el gas en Polygon PoS estaba en ~250 gwei de base + 30 de propina (≈ 280 gwei).

| Operación | Gas | POL a 300 gwei | POL a 500 gwei |
|---|---:|---:|---:|
| Deploy de los dos contratos | 1.860.558 | 0,56 | 0,93 |
| Pago registrado (`recordBooking`) | 141.439 | 0,042 | 0,071 |
| Servicio completado (`finalizeBooking`) | 77.969 | 0,023 | 0,039 |
| Cancelación / veredicto | ~32.000 | 0,010 | 0,016 |
| Extensión | 38.071 | 0,011 | 0,019 |
| Alta de perfil (cada usuario nuevo) | 71.333 | 0,021 | 0,036 |
| Verificación de perfil | 31.839 | 0,010 | 0,016 |

- **Una reserva completa** (pago + cierre) ≈ **0,066 POL** a 300 gwei.
- Ejemplo con 100 reservas y 100 altas por mes ≈ **9 POL/mes**. Con el volumen de julio a septiembre
  (15 reservas pagadas en 3 meses) es menos de 1 POL/mes.
- **Cuánto fondear**: ~2 POL para el deploy (el script exige saldo para el peor caso de gas) +
  **10 POL** para operar. La alerta por correo salta debajo de 3 POL (`BLOCKCHAIN_LOW_BALANCE_POL`).
  Sin saldo no se pierde nada: los registros quedan en cola y salen solos al recargar.
- Mira el precio del POL del día para pasarlo a dólares o bolivianos; acá no lo fijamos.

## Pasos

### 1. Wallet nueva para la red principal

No reutilices el wallet de Amoy (`0xF9e6…215d`): su clave estuvo en varios `.env`.
Crea una cuenta nueva en MetaMask (o cualquier wallet), exporta la clave privada y guárdala
**solo** en el gestor de contraseñas. Fondéala con ~12 POL en la red **Polygon PoS** (desde un
exchange, retiro por la red "Polygon").

### 2. Preparar hardhat (en tu máquina)

```bash
cd garden-api/hardhat-garden
npm ci
npm test
npx hardhat vars set GARDEN_DEPLOYER_KEY      # pega la clave cuando la pida (no queda en el repo)
npx hardhat vars set ETHERSCAN_API_KEY        # etherscan.io → API Keys (la v2 sirve para polygonscan)
npx hardhat vars set POLYGON_RPC_URL          # opcional: URL de Alchemy para "Polygon PoS Mainnet"
```

### 3. Ensayo en Amoy (recomendado, gratis)

Pide POL de prueba en https://faucet.polygon.technology para la misma dirección y corre
`npm run deploy:amoy`. Debe imprimir las dos direcciones y verificar el código.

### 4. Deploy en la red principal

```bash
npm run deploy:polygon
```

Imprime las direcciones, el costo real, verifica el código en polygonscan.com y guarda
`deployments/polygon.json` (sin secretos). Commitea ese archivo. Si la verificación falla
por timing, repítela con el comando que muestra el script.

### 5. Secreto de las referencias seudónimas

```bash
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

Guárdalo en el gestor de contraseñas como `BLOCKCHAIN_ID_PEPPER`. **Si se pierde**, los registros
nuevos dejan de enlazar con los anteriores de la misma persona (la reputación on-chain arranca de cero).

### 6. Variables en Render (Environment del servicio garden-api)

| Variable | Valor |
|---|---|
| `BLOCKCHAIN_ENABLED` | `true` (ya está) |
| `BLOCKCHAIN_RPC_URL` | URL de Alchemy para Polygon PoS **Mainnet** (no la de Amoy) |
| `BLOCKCHAIN_PRIVATE_KEY` | clave del wallet nuevo |
| `BLOCKCHAIN_CHAIN_ID` | `137` |
| `BLOCKCHAIN_CONTRACT_ADDRESS` | dirección de `GardenEscrow` |
| `BLOCKCHAIN_PROFILES_ADDRESS` | dirección de `GardenProfiles` |
| `BLOCKCHAIN_DEPLOY_BLOCK` | bloque que imprimió el script |
| `BLOCKCHAIN_ID_PEPPER` | el secreto del paso 5 |

**No** pongas `BLOCKCHAIN_RECORDS_SINCE`: su valor por defecto (4-oct-2026) es la fecha que dicen
los Términos. Opcionales: `BLOCKCHAIN_LOW_BALANCE_POL` (default 3), `BLOCKCHAIN_MAX_FEE_GWEI`
(default 1500: por encima, los envíos esperan sin gastar).

Al guardar, Render reinicia solo.

### 7. Verificar

1. `https://api.gardenbo.com/api/blockchain/info` → `active: true`, `chainId: 137`.
2. Panel admin → Blockchain: estado **REGISTRANDO**, red "Polygon PoS (red principal de Polygon)",
   chips Escrow v3 y Perfiles v2 en verde, saldo correcto. Si dice **EN PAUSA**, el motivo aparece ahí.
3. Logs de Render: `[Blockchain] Cola reanudada` y, en unos minutos, `[Blockchain] Registro confirmado`
   para las reservas pagadas desde el 4-oct que estaban en cola.
4. Una reserva de prueba con las cuentas `reviewer.*`: al cerrarse, su detalle muestra
   "Registrada en blockchain" con enlace a polygonscan.com. (Si creas datos de prueba nuevos,
   bórralos; lo que ya se escribió on-chain queda, pero solo son ids y montos.)

### 8. Publicar los Términos

El texto nuevo (sección 19 y relacionadas, en app y API) dice "red principal de Polygon".
Publícalo **después** del paso 7: está en la rama `legal/blockchain-mainnet`.

### 9. Opcional: owner en un wallet frío

En polygonscan.com → contrato → *Write Contract*, conectado con el wallet que desplegó:
`transferOwnership(<wallet frío>)`; luego, conectado con el wallet frío, `acceptOwnership()`.
Hazlo en los dos contratos. El servidor sigue escribiendo como recorder.

## Qué pasa mientras tanto

Hasta el paso 6, producción apunta al contrato v2 de Amoy: la API detecta que no es v3 y deja la
cola **en pausa** (no escribe, no alerta en cada intento). Los pagos se encolan igual y salen
cuando el contrato nuevo esté configurado.
