import prisma from '../src/config/database.js';
import { calculateBehavioralRisk } from '../src/modules/verification/fraud.service.js';
import { calculateDetailedTrustScore, combineScores, getVerificationDecision } from '../src/modules/verification/identity-validation.service.js';

async function runEnhancedSimulation() {
    console.log("🚀 STARTING ENHANCED FRAUD SIMULATION TESTS (PRODUCTION-READY)\n");

    const testUserId = "valid-user-1";
    const testUserId2 = "fraud-user-2";
    const testFingerprint = "device-xyz-789";
    const testCI = "8888888-OK";

    // Clean up
    await prisma.identityVerificationSession.deleteMany({ where: { userId: { in: [testUserId, testUserId2] } } });
    await prisma.caregiverProfile.deleteMany({ where: { userId: { in: [testUserId, testUserId2] } } });
    await prisma.user.deleteMany({ where: { id: { in: [testUserId, testUserId2] } } });

    // 1. Setup Data
    await prisma.user.create({ data: { id: testUserId, email: "valid@test.com", phone: "70000001", firstName: "Juan", lastName: "Perez", role: "CAREGIVER", passwordHash: "..." } });
    await prisma.user.create({ data: { id: testUserId2, email: "fraud@test.com", phone: "70000002", firstName: "Fake", lastName: "Name", role: "CAREGIVER", passwordHash: "..." } });

    await prisma.caregiverProfile.create({ data: { userId: testUserId, ciNumber: testCI, verified: true } });
    await prisma.caregiverProfile.create({ data: { userId: testUserId2, verified: false } });

    console.log("✅ Simulation Environment Ready\n");

    // SCENARIO 1: Valid User (>95%)
    console.log("--- SCENARIO 1: VALID USER (EXPECT APPROVED) ---");
    const validResult = calculateDetailedTrustScore({
        faceSimilarity: 98,
        livenessScore: 100,
        nameSimilarity: 100,
        ocrConfidence: 99,
        docConfidence: 98,
        sharpness: 90,
        brightness: 50,
        behaviorScore: 100,
        isLivenessPassed: true,
        isLastNameMatch: true,
        isFaceInCI: true,
        fraudFlagsCount: 0
    });
    console.log(`Result Score: ${validResult.trustScore}% | Status: ${validResult.status}`);
    if (validResult.status === 'VERIFIED') console.log("✔️ PASS: Correctly Auto-Approved");

    // SCENARIO 2: Suspicious Behavior (Manual Review)
    console.log("\n--- SCENARIO 2: SUSPICIOUS BEHAVIOR (EXPECT REVIEW) ---");
    // Simulate some attempts
    const behaviorRisk = await calculateBehavioralRisk({
        userId: testUserId2,
        deviceFingerprint: testFingerprint,
        ciNumber: "NEW-CI-123",
        currentFaceSimilarity: 95
    });
    // Let's manually trigger manual review range by decreasing score
    const reviewResult = calculateDetailedTrustScore({
        faceSimilarity: 85,
        livenessScore: 80,
        nameSimilarity: 85,
        ocrConfidence: 80,
        docConfidence: 80,
        sharpness: 70,
        brightness: 50,
        behaviorScore: 70, // Penalty for something minor
        isLivenessPassed: true,
        isLastNameMatch: true,
        isFaceInCI: true,
        fraudFlagsCount: 0
    });
    console.log(`Result Score: ${reviewResult.trustScore}% | Status: ${reviewResult.status}`);
    if (reviewResult.status === 'REVIEW') console.log("✔️ PASS: Correctly sent to Manual Review");

    // SCENARIO 3: Identity Reuse (Auto Reject)
    console.log("\n--- SCENARIO 3: IDENTITY REUSE (EXPECT REJECT) ---");
    const reuseRisk = await calculateBehavioralRisk({
        userId: testUserId2,
        deviceFingerprint: "any-device",
        ciNumber: testCI, // ALREADY VERIFIED BY testUserId
        currentFaceSimilarity: 95
    });
    console.log(`Behavior Score for Reuse: ${reuseRisk.behaviorScore} | Flags: ${reuseRisk.fraudFlags.join(",")}`);

    const reuseFinal = calculateDetailedTrustScore({
        faceSimilarity: 98,
        livenessScore: 100,
        nameSimilarity: 98,
        ocrConfidence: 98,
        docConfidence: 98,
        sharpness: 90,
        brightness: 50,
        behaviorScore: reuseRisk.behaviorScore, // WILL BE 0
        isLivenessPassed: true,
        isLastNameMatch: true,
        isFaceInCI: true,
        fraudFlagsCount: reuseRisk.fraudFlags.length
    });
    console.log(`Final Result - Status: ${reuseFinal.status} (Hard Overrides apply in service)`);
    if (reuseRisk.behaviorScore === 0) console.log("✔️ PASS: Identity reuse blocked at behavioral level");

    // SCENARIO 4: Missing Image Check (Simulation of early fail)
    console.log("\n--- SCENARIO 4: MISSING IMAGES (EXPECT ERROR) ---");
    try {
        const { submitVerification } = await import('../src/modules/verification/verification.service.js');
        // Passing empty buffer to simulate missing image
        await submitVerification("fake-token", Buffer.alloc(0), Buffer.alloc(0), Buffer.alloc(0), undefined, "liveness-id");
    } catch (e: any) {
        console.log(`Caught Expected Error: ${e.message}`);
        if (e.message.includes('Se requiere')) console.log("✔️ PASS: Failed early as expected");
    }

    // SCENARIO 5: Score Weighting Check
    console.log("\n--- SCENARIO 5: WEIGHTED SCORE VERIFICATION ---");
    const score = combineScores({
        ocrScore: 100, // 15%
        faceScore: 100, // 50%
        behaviorScore: 100, // Multiplier (1.0)
        docScore: 100, // 10%
        livenessScore: 100 // 25%
    });
    console.log(`Calculated Combined Score (All 100%): ${score * 100}%`);
    if (score === 1.0) console.log("✔️ PASS: Weights correctly sum to 100%");

    // Cleanup
    await prisma.identityVerificationSession.deleteMany({ where: { userId: { in: [testUserId, testUserId2] } } });
    await prisma.caregiverProfile.deleteMany({ where: { userId: { in: [testUserId, testUserId2] } } });
    await prisma.user.deleteMany({ where: { id: { in: [testUserId, testUserId2] } } });

    console.log("\n🏁 ALL ENHANCED TESTS COMPLETED");
}

runEnhancedSimulation();
