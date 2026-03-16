import jwt from 'jsonwebtoken';
import { env } from './src/config/env.js';

async function run() {
    const token = jwt.sign({ userId: 'dummy-id', role: 'CAREGIVER' }, env.JWT_SECRET, { expiresIn: '1h' });

    console.log("--- 2. Ajuste dinamico ---");
    let res = await fetch('http://localhost:3000/api/agentes/precio/ajuste-dinamico', {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
        body: JSON.stringify({ zona: "Equipetrol", servicio: "hospedaje", ocupacionUltimos30Dias: 0.78, reservasUltimos7Dias: 34, reservasMismoPeriodoMesAnterior: 21, eventosProximos: ["Semana Santa"], fechaConsulta: "2026-03-15" })
    });
    console.log(await res.text());

    console.log("\n--- 3. Explicar badge ---");
    res = await fetch('http://localhost:3000/api/agentes/precio/explicar-badge', {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
        body: JSON.stringify({ zona: "Equipetrol", porcentajeAjuste: 15, motivo: "Semana Santa", fechaVueltaNormal: "2026-03-24" })
    });
    console.log(await res.text());

    console.log("\n--- 4. Analizar calificacion ---");
    res = await fetch('http://localhost:3000/api/agentes/calificacion/analizar', {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
        body: JSON.stringify({ calificacionNueva: 1, cuidadorId: "caregiver_456", historialCalificaciones: [5, 5, 5, 4, 5, 5, 5, 5, 4, 5], calificacionPromedio: 4.8, totalResenas: 23, tiempoEnPlataforma: "8 meses", duenoHistorial: [5, 5, 4, 5] })
    });
    console.log(await res.text());

    console.log("\n--- 5. Analizar disputa ---");
    res = await fetch('http://localhost:3000/api/agentes/disputa/analizar', {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
        body: JSON.stringify({ reserva: { id: "res_123", fechas: "12-14 Marzo", monto: 250 }, cuidador: { nombre: "Juan Pérez", rating: 4.9, disputasPrevias: 0 }, dueno: { nombre: "María Gómez", rating: 4.5, disputasPrevias: 2 }, mascota: { nombre: "Boby", raza: "Beagle" }, motivoDisputa: "El dueño afirma que el perro volvió con una herida en la pata. El cuidador dice que ya venía así y mandó foto al inicio.", mensajesRelevantes: ["Juan (12 Mar 10:00): Hola María, noto que Boby tiene una pequeña rozadura en la pata trasera. ¿Es normal?", "María (12 Mar 10:15): Sí, se raspó ayer jugando. No pasa nada."] })
    });
    console.log(await res.text());
}
run();
