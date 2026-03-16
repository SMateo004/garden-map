import { generateLink } from './src/modules/verification/verification.service.js';
import prisma from './src/config/database.js';

async function main() {
    const userId = '79587d31-a7e2-40db-a78c-79ae46b367fa';
    const link = await generateLink(userId);
    console.log('Verification URL:', link.url);
    process.exit(0);
}

main().catch(console.error);
