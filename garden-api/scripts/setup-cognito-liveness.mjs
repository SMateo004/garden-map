/**
 * Creates all AWS resources needed for Face Liveness detection:
 *   - Cognito Identity Pool (unauthenticated access)
 *   - IAM role for unauthenticated identities
 *   - IAM policy granting rekognition:StartFaceLivenessSession
 *   - Wires everything together
 *
 * Run: node scripts/setup-cognito-liveness.mjs
 */

import { CognitoIdentityClient, CreateIdentityPoolCommand, SetIdentityPoolRolesCommand } from '@aws-sdk/client-cognito-identity';
import { IAMClient, CreateRoleCommand, CreatePolicyCommand, AttachRolePolicyCommand, GetRoleCommand } from '@aws-sdk/client-iam';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const envPath = join(__dirname, '../.env');

// Parse .env manually
const env = {};
try {
  const raw = readFileSync(envPath, 'utf8');
  for (const line of raw.split('\n')) {
    const m = line.match(/^([^#=\s]+)=(.*)$/);
    if (m) env[m[1]] = m[2].trim().replace(/^["']|["']$/g, '');
  }
} catch {
  console.error('Could not read .env — set AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION as env vars');
  process.exit(1);
}

const region = env.AWS_REGION || process.env.AWS_DEFAULT_REGION || 'us-east-1';
const credentials = {
  accessKeyId: env.AWS_ACCESS_KEY_ID || process.env.AWS_ACCESS_KEY_ID,
  secretAccessKey: env.AWS_SECRET_ACCESS_KEY || process.env.AWS_SECRET_ACCESS_KEY,
};

if (!credentials.accessKeyId || !credentials.secretAccessKey) {
  console.error('AWS credentials not found in .env');
  process.exit(1);
}

console.log(`\n🌿 GARDEN — Configurando AWS Face Liveness\n   Region: ${region}\n`);

const cognitoClient = new CognitoIdentityClient({ region, credentials });
const iamClient = new IAMClient({ region: 'us-east-1', credentials }); // IAM is global

// ── 1. Create Identity Pool ──────────────────────────────────────────────────
console.log('1/4  Creando Cognito Identity Pool...');
let identityPoolId;
try {
  const res = await cognitoClient.send(new CreateIdentityPoolCommand({
    IdentityPoolName: 'garden_liveness',
    AllowUnauthenticatedIdentities: true,
    AllowClassicFlow: false,
  }));
  identityPoolId = res.IdentityPoolId;
  console.log(`     ✅ Identity Pool: ${identityPoolId}`);
} catch (e) {
  if (e.name === 'ResourceConflictException') {
    console.error('     ⚠️  Ya existe un pool con ese nombre — bórralo en la consola AWS y reintenta');
  } else {
    console.error('     ❌ Error:', e.message);
  }
  process.exit(1);
}

// ── 2. Create IAM Role for unauthenticated identities ───────────────────────
console.log('2/4  Creando IAM role para identidades no autenticadas...');
const trustPolicy = JSON.stringify({
  Version: '2012-10-17',
  Statement: [{
    Effect: 'Allow',
    Principal: { Federated: 'cognito-identity.amazonaws.com' },
    Action: 'sts:AssumeRoleWithWebIdentity',
    Condition: {
      StringEquals: { 'cognito-identity.amazonaws.com:aud': identityPoolId },
      'ForAnyValue:StringLike': { 'cognito-identity.amazonaws.com:amr': 'unauthenticated' },
    },
  }],
});

let roleArn;
try {
  const res = await iamClient.send(new CreateRoleCommand({
    RoleName: 'GardenLivenessUnauthRole',
    AssumeRolePolicyDocument: trustPolicy,
    Description: 'Unauthenticated access for Garden Face Liveness (Rekognition)',
  }));
  roleArn = res.Role.Arn;
  console.log(`     ✅ Role ARN: ${roleArn}`);
} catch (e) {
  if (e.name === 'EntityAlreadyExistsException') {
    console.log('     ℹ️  Role ya existe — reutilizando');
    const res = await iamClient.send(new GetRoleCommand({ RoleName: 'GardenLivenessUnauthRole' }));
    roleArn = res.Role.Arn;
    console.log(`     ✅ Role ARN: ${roleArn}`);
  } else {
    console.error('     ❌ Error:', e.message);
    process.exit(1);
  }
}

// ── 3. Create & Attach IAM Policy ───────────────────────────────────────────
console.log('3/4  Creando y adjuntando IAM policy...');
const policyDocument = JSON.stringify({
  Version: '2012-10-17',
  Statement: [{
    Effect: 'Allow',
    Action: ['rekognition:StartFaceLivenessSession'],
    Resource: '*',
  }],
});

let policyArn;
try {
  const res = await iamClient.send(new CreatePolicyCommand({
    PolicyName: 'GardenLivenessPolicy',
    PolicyDocument: policyDocument,
    Description: 'Allows unauthenticated mobile clients to run AWS Face Liveness sessions',
  }));
  policyArn = res.Policy.Arn;
  console.log(`     ✅ Policy ARN: ${policyArn}`);
} catch (e) {
  if (e.name === 'EntityAlreadyExistsException') {
    // Derive the ARN from account ID
    const accountId = roleArn.split(':')[4];
    policyArn = `arn:aws:iam::${accountId}:policy/GardenLivenessPolicy`;
    console.log(`     ℹ️  Policy ya existe: ${policyArn}`);
  } else {
    console.error('     ❌ Error:', e.message);
    process.exit(1);
  }
}

await iamClient.send(new AttachRolePolicyCommand({
  RoleName: 'GardenLivenessUnauthRole',
  PolicyArn: policyArn,
}));
console.log('     ✅ Policy adjuntada al role');

// ── 4. Set roles on Identity Pool ───────────────────────────────────────────
console.log('4/4  Asignando roles al Identity Pool...');
await cognitoClient.send(new SetIdentityPoolRolesCommand({
  IdentityPoolId: identityPoolId,
  Roles: {
    unauthenticated: roleArn,
  },
}));
console.log('     ✅ Roles configurados');

// ── Result ───────────────────────────────────────────────────────────────────
console.log('\n✅ Configuración completa\n');
console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
console.log(`COGNITO_IDENTITY_POOL_ID=${identityPoolId}`);
console.log(`AWS_REGION=${region}`);
console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
console.log('\nCopia estos valores — los necesitas en el paso siguiente.\n');
