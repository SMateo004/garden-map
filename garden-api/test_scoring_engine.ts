import { calculateDetailedTrustScore } from './src/modules/verification/identity-validation.service.js';

interface TestCase {
    name: string;
    input: Parameters<typeof calculateDetailedTrustScore>[0];
}

const cases: TestCase[] = [
    {
        name: "1. Perfect Legend Match",
        input: {
            faceSimilarity: 99,
            livenessScore: 100,
            nameSimilarity: 100,
            ocrConfidence: 100,
            docConfidence: 99,
            sharpness: 90,
            brightness: 50,
            behaviorScore: 100,
            isLivenessPassed: true,
            isLastNameMatch: true,
            isFaceInCI: true,
            fraudFlagsCount: 0,
        }
    },
    {
        name: "2. Absolute Fraud (Different Person)",
        input: {
            faceSimilarity: 12,
            livenessScore: 95,
            nameSimilarity: 98,
            ocrConfidence: 95,
            docConfidence: 95,
            sharpness: 80,
            brightness: 50,
            behaviorScore: 100,
            isLivenessPassed: true,
            isLastNameMatch: true,
            isFaceInCI: true,
            fraudFlagsCount: 0,
        }
    },
    {
        name: "3. Liveness Failed (Hard Block)",
        input: {
            faceSimilarity: 98,
            livenessScore: 0,
            nameSimilarity: 100,
            ocrConfidence: 100,
            docConfidence: 99,
            sharpness: 90,
            brightness: 50,
            behaviorScore: 100,
            isLivenessPassed: false,
            isLastNameMatch: true,
            isFaceInCI: true,
            fraudFlagsCount: 0,
        }
    },
    {
        name: "4. Suspicious Behavior (Low Behavior Score)",
        input: {
            faceSimilarity: 96,
            livenessScore: 95,
            nameSimilarity: 100,
            ocrConfidence: 100,
            docConfidence: 95,
            sharpness: 90,
            brightness: 50,
            behaviorScore: 20, // Multiple accounts or too many attempts
            isLivenessPassed: true,
            isLastNameMatch: true,
            isFaceInCI: true,
            fraudFlagsCount: 1,
        }
    },
    {
        name: "5. Coordinated Fraud (Zero Behavior)",
        input: {
            faceSimilarity: 98,
            livenessScore: 95,
            nameSimilarity: 95,
            ocrConfidence: 90,
            docConfidence: 90,
            sharpness: 80,
            brightness: 50,
            behaviorScore: 0, // Hard duplicate CI
            isLivenessPassed: true,
            isLastNameMatch: true,
            isFaceInCI: true,
            fraudFlagsCount: 2,
        }
    }
];

function runTests() {
    console.log("ADVANCED FRAUD ENGINE SIMULATED TESTS\n" + "=".repeat(40));

    cases.forEach(c => {
        const result = calculateDetailedTrustScore(c.input);
        const statusColor = result.status === 'VERIFIED' ? '\x1b[32m' : result.status === 'REVIEW' ? '\x1b[33m' : '\x1b[31m';
        const resetColor = '\x1b[0m';

        console.log(`${c.name}`);
        console.log(`- Scores: [F:${result.faceScore} L:${result.livenessScore} O:${result.ocrScore} D:${result.docScore} Q:${result.qualityScore} B:${result.behaviorScore}]`);
        console.log(`- Final Score: ${result.trustScore}%`);
        console.log(`- Status: ${statusColor}${result.status}${resetColor}`);
        console.log("-".repeat(40));
    });
}

runTests();
