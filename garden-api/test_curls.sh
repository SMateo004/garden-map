#!/bin/bash
cd "/Users/saimateovargas/Library/CloudStorage/OneDrive-Personal/Mateo Vargas/Proyectos/GARDEN/garden-mvp/garden-api"
TOKEN=$(npx tsx -e "import jwt from 'jsonwebtoken'; import { env } from './src/config/env.js'; console.log(jwt.sign({ userId: 'dummy', role: 'CAREGIVER' }, env.JWT_SECRET))")

echo "--- 2. Ajuste dinámico ---"
curl -s -X POST http://localhost:3000/api/agentes/precio/ajuste-dinamico \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "zona": "Equipetrol",
    "servicio": "hospedaje",
    "ocupacionUltimos30Dias": 0.78,
    "reservasUltimos7Dias": 34,
    "reservasMismoPeriodoMesAnterior": 21,
    "eventosProximos": ["Semana Santa"],
    "fechaConsulta": "2026-03-15"
  }'
echo -e "\n"

echo "--- 3. Explicar badge ---"
curl -s -X POST http://localhost:3000/api/agentes/precio/explicar-badge \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "zona": "Equipetrol",
    "porcentajeAjuste": 15,
    "motivo": "Semana Santa",
    "fechaVueltaNormal": "2026-03-24"
  }'
echo -e "\n"

echo "--- 4. Analizar calificación ---"
curl -s -X POST http://localhost:3000/api/agentes/calificacion/analizar \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "calificacionNueva": 1,
    "cuidadorId": "caregiver_456",
    "historialCalificaciones": [5,5,5,4,5,5,5,5,4,5],
    "calificacionPromedio": 4.8,
    "totalResenas": 23,
    "tiempoEnPlataforma": "8 meses",
    "duenoHistorial": [5,5,4,5]
  }'
echo -e "\n"

echo "--- 5. Analizar disputa ---"
curl -s -X POST http://localhost:3000/api/agentes/disputa/analizar \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "reserva": { "id": "res_123", "fechas": "12-14 Marzo", "monto": 250 },
    "cuidador": { "nombre": "Juan Pérez", "rating": 4.9, "disputasPrevias": 0 },
    "dueno": { "nombre": "María Gómez", "rating": 4.5, "disputasPrevias": 2 },
    "mascota": { "nombre": "Boby", "raza": "Beagle" },
    "motivoDisputa": "El dueño afirma que el perro volvió con una herida en la pata. El cuidador dice que ya venía así y mandó foto al inicio.",
    "mensajesRelevantes": [
      "Juan (12 Mar 10:00): Hola María, noto que Boby tiene una pequeña rozadura en la pata trasera. ¿Es normal?",
      "María (12 Mar 10:15): Sí, se raspó ayer jugando. No pasa nada."
    ]
  }'
echo -e "\n"
