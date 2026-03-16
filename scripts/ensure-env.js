/**
 * Crea garden-api/.env desde .env.example si no existe.
 * Uso: node scripts/ensure-env.js
 */

const fs = require('fs');
const path = require('path');

const apiDir = path.join(__dirname, '..', 'garden-api');
const envPath = path.join(apiDir, '.env');
const examplePath = path.join(apiDir, '.env.example');

if (!fs.existsSync(envPath) && fs.existsSync(examplePath)) {
  fs.copyFileSync(examplePath, envPath);
  console.log('Creado garden-api/.env desde .env.example');
} else if (fs.existsSync(envPath)) {
  console.log('garden-api/.env ya existe');
} else {
  console.log('No se encontró garden-api/.env.example');
  process.exit(1);
}
