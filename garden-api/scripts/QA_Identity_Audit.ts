import prisma from '../src/config/database.js';
import { submitVerification } from '../src/modules/verification/verification.service.js';
import { calculateBehavioralRisk } from '../src/modules/verification/fraud.service.js';
import { calculateDetailedTrustScore } from '../src/modules/verification/identity-validation.service.ts';

async function runAudit() {
    console.log("🛠️  IDENTITY VERIFICATION SYSTEM - COMPREHENSIVE QA AUDIT\n");

    // --- SETUP ---
    const testUserId = "qa-audit-user";
    const testUserId2 = "qa-audit-user-2";
    const dummyBuffer = Buffer.from('dummy-image-data');
    const emptyBuffer = Buffer.alloc(0);

    // Initial cleaning
    await prisma.identityVerificationSession.deleteMany({ where: { userId: { in: [testUserId, testUserId2] } } });
    await prisma.caregiverProfile.deleteMany({ where: { userId: { in: [testUserId, testUserId2] } } });
    await prisma.user.deleteMany({ where: { id: { in: [testUserId, testUserId2] } } });

    await prisma.user.create({ data: { id: testUserId, email: "qa1@test.com", phone: "qa1", firstName: "QA", lastName: "Tester", role: "CAREGIVER", passwordHash: "..." } });
    await prisma.user.create({ data: { id: testUserId2, email: "qa2@test.com", phone: "qa2", firstName: "Security", lastName: "Audit", role: "CAREGIVER", passwordHash: "..." } });
    await prisma.caregiverProfile.create({ data: { userId: testUserId, verified: false } });

    console.log("✅ Environment Setup Complete\n");

    // --- TEST 1: INPUT VALIDATION (MISSING IMAGES) ---
    console.log("🧪 TEST 1: INPUT VALIDATION (ZERO BUFFER)");
    try {
        await submitVerification(`userId:${testUserId}`, emptyBuffer, dummyBuffer, dummyBuffer, undefined, "audit-liveness-id");
        console.log("❌ FAIL: System accepted empty selfie buffer");
    } catch (e: any) {
        console.log(`✔️ PASS: Caught expected error: ${e.message}`);
    }

    // --- TEST 2: IDENTITY REUSE ---
    console.log("\n🧪 TEST 2: IDENTITY REUSE (SECURITY)");
    // Mark user 1 as verified with a CI
    await prisma.caregiverProfile.update({
        where: { userId: testUserId },
        data: { ciNumber: "QA-REF-123", verified: true }
    });

    const reuseRisk = await calculateBehavioralRisk({
        userId: testUserId2,
        deviceFingerprint: "any",
        ciNumber: "QA-REF-123",
        currentFaceSimilarity: 95
    });

    if (reuseRisk.fraudFlags.includes('duplicate_identity') && reuseRisk.behaviorScore === 0) {
        console.log("✔️ PASS: Identity reuse detected and behavioral score killed (0)");
    } else {
        console.log("❌ FAIL: Identity reuse NOT detected or score not 0");
    }

    // --- TEST 3: ATTEMPT LOCKOUT ---
    console.log("\n🧪 TEST 3: BRUTE FORCE / ATTEMPT ATTACK");
    // Create 4 sessions for user 2 within 1 hour
    for (let i = 0; i < 4; i++) {
        await prisma.identityVerificationSession.create({
            data: {
                userId: testUserId2,
                status: 'REJECTED',
                createdAt: new Date(),
                expiresAt: new Date(Date.now() + 100000)
            }
        });
    }
    const floodRisk = await calculateBehavioralRisk({
        userId: testUserId2,
        deviceFingerprint: "f-1",
        currentFaceSimilarity: 90
    });
    console.log(`Flood behavior results: Score=${floodRisk.behaviorScore}, Flags=[${floodRisk.fraudFlags.join(",")}]`);
    if (floodRisk.fraudFlags.includes('suspicious_behavior')) {
        console.log("✔️ PASS: Flood attack detected");
    }

    // --- TEST 4: SCORING LOGIC (WEIGHTED) ---
    console.log("\n🧪 TEST 4: SCORING MARGINS (UX & PERFORMANCE)");
    const verifScore = calculateDetailedTrustScore({
        faceSimilarity: 96,
        livenessScore: 100,
        nameSimilarity: 95,
        ocrConfidence: 95,
        docConfidence: 95,
        sharpness: 90,
        brightness: 50,
        behaviorScore: 100,
        isLivenessPassed: true,
        isLastNameMatch: true,
        isFaceInCI: true,
        fraudFlagsCount: 0
    });
    console.log(`Ideal Case Score: ${verifScore.trustScore}% Status: ${verifScore.status}`);

    const reviewScore = calculateDetailedTrustScore({
        faceSimilarity: 80, // Lowered match
        livenessScore: 100,
        nameSimilarity: 75, // Fuzzy name
        ocrConfidence: 70,
        docConfidence: 75,
        sharpness: 60,
        brightness: 50,
        behaviorScore: 90,
        isLivenessPassed: true,
        isLastNameMatch: true,
        isFaceInCI: true,
        fraudFlagsCount: 1
    });
    console.log(`Edge Case Score: ${reviewScore.trustScore}% Status: ${reviewScore.status}`);

    // --- TEST 5: HARD BLOCK OVERRIDES ---
    console.log("\n🧪 TEST 5: HARD BLOCKS (LIVENESS FAILURE)");
    const blocked = calculateDetailedTrustScore({
        faceSimilarity: 99,
        livenessScore: 0,
        nameSimilarity: 100,
        ocrConfidence: 100,
        docConfidence: 100,
        sharpness: 90,
        brightness: 50,
        behaviorScore: 100,
        isLivenessPassed: false, // HARD BLOCK
        isLastNameMatch: true,
        isFaceInCI: true,
        fraudFlagsCount: 0
    });
    console.log(`Final Status (Liveness Fail): ${blocked.status}`);
    if (blocked.status === 'REJECTED') console.log("✔️ PASS: Liveness hard block enforced");

    // --- TEST 6: DATABASE HYGIENE ---
    console.log("\n🧪 TEST 6: AUDIT TRAIL DATA");
    try {
        const audit = await prisma.identityVerificationSession.findFirst({
            where: { userId: testUserId2 },
            orderBy: { createdAt: 'desc' }
        });
        if (audit) {
            console.log(`✔️ PASS: Sessions recorded in DB for user ${testUserId2}`);
        }
    } catch (e) {
        console.log("❌ FAIL: Could not query session audits");
    }

    // Cleanup
    await prisma.identityVerificationSession.deleteMany({ where: { userId: { in: [testUserId, testUserId2] } } });
    await prisma.caregiverProfile.deleteMany({ where: { userId: { in: [testUserId, testUserId2] } } });
    await prisma.user.deleteMany({ where: { id: { in: [testUserId, testUserId2] } } });

    console.log("\n🏁 AUDIT COMPLETE");
}

runAudit().catch(console.error);
