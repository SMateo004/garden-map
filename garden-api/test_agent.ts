import jwt from 'jsonwebtoken';

import { env } from './src/config/env.js';

async function run() {
    const token = jwt.sign({ userId: 'dummy-id', role: 'CAREGIVER' }, env.JWT_SECRET, { expiresIn: '1h' });

    const response = await fetch('http://localhost:3000/api/agentes/precio/onboarding', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({
            zona: "Equipetrol",
            servicio: "hospedaje",
            experienciaMeses: 12,
            trustScore: 95,
            precioPromedioZona: 80,
            precioMinZona: 60,
            precioMaxZona: 100
        })
    });

    const text = await response.text();
    console.log('STATUS:', response.status);
    console.log('BODY:', text);
}

run().catch(console.error);
