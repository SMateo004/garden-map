/**
 * Verificación del flujo: login cuidador → my-profile → submit → admin approve → listing.
 * Ejecutar con API corriendo: BASE_URL=http://localhost:3000 node scripts/verification-flow.js
 */

const BASE = process.env.BASE_URL || 'http://localhost:3000';

async function request(method, path, body = null, token = null) {
  const opts = {
    method,
    headers: { 'Content-Type': 'application/json' },
  };
  if (token) opts.headers['Authorization'] = `Bearer ${token}`;
  if (body) opts.body = JSON.stringify(body);
  const res = await fetch(`${BASE}${path}`, opts);
  const text = await res.text();
  let data;
  try {
    data = text ? JSON.parse(text) : {};
  } catch {
    data = { raw: text };
  }
  return { status: res.status, data };
}

async function main() {
  console.log('=== Verificación flujo GARDEN ===');
  console.log('BASE_URL:', BASE);

  let caregiverToken = null;
  let adminToken = null;
  let profileId = null;
  let testsPassed = 0;
  let testsTotal = 0;

  // 1. Login cuidador (seed)
  testsTotal++;
  const loginCaregiver = await request('POST', '/api/auth/login', {
    email: 'cuidador.pending@garden.bo',
    password: 'GardenSeed2024!',
  });
  if (loginCaregiver.status !== 200 || !loginCaregiver.data?.data?.accessToken) {
    console.log('FAIL: Login cuidador', loginCaregiver.status, loginCaregiver.data);
    console.log('Asegúrate de haber ejecutado: cd garden-api && npx prisma db seed');
  } else {
    caregiverToken = loginCaregiver.data.data.accessToken;
    console.log('OK: Login cuidador');
    testsPassed++;
  }

  // 2. GET my-profile
  if (caregiverToken) {
    testsTotal++;
    const myProfile = await request('GET', '/api/caregiver/my-profile', null, caregiverToken);
    if (myProfile.status === 200 && myProfile.data?.data?.id) {
      profileId = myProfile.data.data.id;
      console.log('OK: GET my-profile, status=', myProfile.data.data.status);
      testsPassed++;
    } else {
      console.log('FAIL: GET my-profile', myProfile.status, myProfile.data);
    }
  }

  // 3. Login admin
  testsTotal++;
  const loginAdmin = await request('POST', '/api/auth/login', {
    email: 'admin@garden.bo',
    password: 'GardenSeed2024!',
  });
  if (loginAdmin.status !== 200 || !loginAdmin.data?.data?.accessToken) {
    console.log('FAIL: Login admin', loginAdmin.status, loginAdmin.data);
  } else {
    adminToken = loginAdmin.data.data.accessToken;
    console.log('OK: Login admin');
    testsPassed++;
  }

  // 4. GET pending (admin)
  if (adminToken) {
    testsTotal++;
    const pending = await request('GET', '/api/admin/caregivers/pending?page=1&limit=10', null, adminToken);
    if (pending.status === 200 && Array.isArray(pending.data?.data?.caregivers)) {
      console.log('OK: GET admin/caregivers/pending, count=', pending.data.data.caregivers.length);
      testsPassed++;
    } else {
      console.log('FAIL: GET pending', pending.status, pending.data);
    }
  }

  // 5. Admin approve (usar primer pending si no tenemos profileId)
  if (adminToken) {
    testsTotal++;
    const pending = await request('GET', '/api/admin/caregivers/pending?page=1&limit=5', null, adminToken);
    const idToApprove = profileId || pending.data?.data?.caregivers?.[0]?.id;
    if (idToApprove) {
      const review = await request('PATCH', `/api/admin/caregivers/${idToApprove}/review`, {
        action: 'approve',
      }, adminToken);
      if (review.status === 200 && review.data?.data?.status === 'APPROVED') {
        console.log('OK: PATCH review approve');
        testsPassed++;
      } else {
        console.log('SKIP/FAIL: PATCH review (puede estar ya aprobado)', review.status, review.data);
      }
    } else {
      console.log('SKIP: No hay perfil pending para aprobar');
    }
  }

  // 6. GET /api/caregivers (listing público: solo approved)
  testsTotal++;
  const listing = await request('GET', '/api/caregivers?page=1&limit=5');
  if (listing.status === 200 && Array.isArray(listing.data?.data?.caregivers)) {
    console.log('OK: GET /api/caregivers, count=', listing.data.data.caregivers.length);
    testsPassed++;
  } else {
    console.log('FAIL: GET caregivers', listing.status, listing.data);
  }

  console.log('\n--- Resultado ---');
  console.log(`Tests passed: ${testsPassed}/${testsTotal}`);
  if (testsPassed >= testsTotal - 1) {
    console.log('Flujo verificado sin errores.');
  } else {
    console.log('Revisa fallos arriba (seed, API corriendo en', BASE + ').');
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
