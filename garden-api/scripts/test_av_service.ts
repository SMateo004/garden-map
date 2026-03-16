import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();
import * as caregiverService from '../src/modules/caregiver-service/caregiver.service.js';

async function main() {
    const caregiverId = '361cecbd-bb7e-42d5-9e70-b108c51ced20';
    const from = new Date();
    const to = new Date();
    to.setDate(to.getDate() + 30);

    const res = await (caregiverService as any).getCaregiverAvailability(caregiverId, from, to);
    console.log('RES:', JSON.stringify(res, null, 2));
}

main().finally(() => prisma.$disconnect());
