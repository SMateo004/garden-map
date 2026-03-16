/**
 * Test de carga: 1000 registros de cuidador contra POST /api/auth/caregiver/register.
 *
 * Uso: con la API corriendo (npm run dev), en otra terminal:
 *   npm run load-test:register
 *   LOAD_TEST_BASE_URL=http://localhost:3000 npm run load-test:register
 *
 * Opcional: LOAD_TEST_CONCURRENCY=50 LOAD_TEST_TOTAL=1000
 */

const BASE_URL = process.env.LOAD_TEST_BASE_URL ?? 'http://localhost:3000';
const TOTAL = Math.min(Number(process.env.LOAD_TEST_TOTAL) || 1000, 10000);
const CONCURRENCY = Math.min(Number(process.env.LOAD_TEST_CONCURRENCY) || 50, 200);
const ENDPOINT = `${BASE_URL}/api/auth/caregiver/register`;

/** Cuerpo mínimo válido para registro cuidador (email y phone únicos por índice) */
function bodyForIndex(i: number) {
  const n = 70000000 + (i % 1000000); // 8 dígitos para +591 (1M slots)
  const phone = `+591${n}`;
  return {
    user: {
      email: `carga.${i}@loadtest.garden.local`,
      password: 'password123',
      firstName: 'Carga',
      lastName: `User${i}`,
      phone,
      country: 'Bolivia',
      city: 'Santa Cruz',
      isOver18: true,
    },
    profile: {
      servicesOffered: ['HOSPEDAJE'],
      photos: [
        'https://placehold.co/800x600?text=Foto1',
        'https://placehold.co/800x600?text=Foto2',
        'https://placehold.co/800x600?text=Foto3',
        'https://placehold.co/800x600?text=Foto4',
      ],
    },
  };
}

async function runOne(index: number): Promise<{ status: number; durationMs: number; ok: boolean }> {
  const start = performance.now();
  try {
    const res = await fetch(ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(bodyForIndex(index)),
    });
    const durationMs = Math.round(performance.now() - start);
    return { status: res.status, durationMs, ok: res.ok };
  } catch (err) {
    const durationMs = Math.round(performance.now() - start);
    return { status: 0, durationMs, ok: false };
  }
}

async function runInBatches(): Promise<
  { status: number; durationMs: number; ok: boolean }[]
> {
  const results: { status: number; durationMs: number; ok: boolean }[] = [];
  for (let offset = 0; offset < TOTAL; offset += CONCURRENCY) {
    const batchSize = Math.min(CONCURRENCY, TOTAL - offset);
    const batch = await Promise.all(
      Array.from({ length: batchSize }, (_, j) => runOne(offset + j))
    );
    results.push(...batch);
  }
  return results;
}

function percentile(sorted: number[], p: number): number {
  if (sorted.length === 0) return 0;
  const i = (p / 100) * (sorted.length - 1);
  const lo = Math.floor(i);
  const hi = Math.ceil(i);
  return lo === hi ? sorted[lo]! : sorted[lo]! + (i - lo) * (sorted[hi]! - sorted[lo]!);
}

function main() {
  console.log('Load test: caregiver register');
  console.log(`  Base URL:    ${BASE_URL}`);
  console.log(`  Endpoint:   ${ENDPOINT}`);
  console.log(`  Total:      ${TOTAL}`);
  console.log(`  Concurrency: ${CONCURRENCY}`);
  console.log('Running...\n');

  const startWall = Date.now();
  runInBatches().then((results) => {
    const wallMs = Date.now() - startWall;

    const byStatus: Record<number, number> = {};
    const durations: number[] = [];
    let success = 0;
    let failed = 0;
    for (const r of results) {
      byStatus[r.status] = (byStatus[r.status] ?? 0) + 1;
      if (r.ok) success++;
      else failed++;
      if (r.durationMs > 0) durations.push(r.durationMs);
    }
    durations.sort((a, b) => a - b);

    console.log('--- Resultados ---');
    console.log(`Total peticiones: ${results.length}`);
    console.log(`Éxito (2xx):      ${success}`);
    console.log(`Fallidas:         ${failed}`);
    console.log(`Tiempo total:     ${wallMs} ms`);
    console.log(`RPS (aprox):      ${(results.length / (wallMs / 1000)).toFixed(1)}`);
    console.log('\nStatus codes:');
    Object.entries(byStatus)
      .sort(([a], [b]) => Number(a) - Number(b))
      .forEach(([code, count]) => console.log(`  ${code}: ${count}`));
    if (durations.length > 0) {
      console.log('\nLatencia (ms):');
      console.log(`  p50: ${Math.round(percentile(durations, 50))}`);
      console.log(`  p95: ${Math.round(percentile(durations, 95))}`);
      console.log(`  p99: ${Math.round(percentile(durations, 99))}`);
    }
  });
}

main();
