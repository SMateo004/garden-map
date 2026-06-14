import { Request } from 'express';
import crypto from 'crypto';
import geoip from 'geoip-lite';
import prisma from '../../config/database.js';
import logger from '../../shared/logger.js';
import { env } from '../../config/env.js';

export interface DeviceInfo {
    userAgent: string;
    ip: string;
    os?: string;
    browser?: string;
    deviceType?: string;
    resolution?: string;
}

export interface BehavioralFingerprint {
    hash: string;
    details: DeviceInfo;
}

/**
 * Extracts device info from request headers and body.
 */
export function getDeviceInfo(req: Request): DeviceInfo {
    const userAgent = req.headers['user-agent'] || 'unknown';
    const rawIp = (req.headers['x-forwarded-for'] as string) || req.socket.remoteAddress || '0.0.0.0';
    const ip = rawIp.split(',')[0]!.trim().substring(0, 45);

    // These usually come from frontend client-side fingerprinting and are sent in the body or specific headers
    const resolution = req.body?.resolution || req.headers['x-device-resolution'] || 'unknown';

    // Simple UA parsing (production apps would use a library like ua-parser-js)
    let os = 'Unknown OS';
    if (userAgent.includes('Windows')) os = 'Windows';
    else if (userAgent.includes('Macintosh')) os = 'MacOS';
    else if (userAgent.includes('iPhone')) os = 'iOS';
    else if (userAgent.includes('Android')) os = 'Android';
    else if (userAgent.includes('Linux')) os = 'Linux';

    let browser = 'Unknown Browser';
    if (userAgent.includes('Chrome')) browser = 'Chrome';
    else if (userAgent.includes('Safari') && !userAgent.includes('Chrome')) browser = 'Safari';
    else if (userAgent.includes('Firefox')) browser = 'Firefox';
    else if (userAgent.includes('Edge')) browser = 'Edge';

    let deviceType = 'Desktop';
    if (userAgent.includes('Mobi')) deviceType = 'Mobile';
    else if (userAgent.includes('Tablet')) deviceType = 'Tablet';

    return {
        userAgent,
        ip,
        os,
        browser,
        deviceType,
        resolution,
    };
}

/**
 * Generates a stable fingerprint hash for a device.
 */
export function generateFingerprint(info: DeviceInfo): string {
    const components = [
        info.userAgent,
        info.ip.split('.').slice(0, 3).join('.'), // Use /24 for some IP stability if dynamic
        info.os,
        info.browser,
        info.resolution
    ].join('|');

    return crypto.createHash('sha256').update(components).digest('hex');
}

/**
 * Real geolocation from IP using geoip-lite's bundled MaxMind database.
 * No external calls — lookup is synchronous and in-memory.
 */
export async function getGeolocation(ip: string) {
    if (ip === '127.0.0.1' || ip === '::1' || ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('172.')) {
        return { country: 'Local', city: 'DevEnvironment', proxy: false };
    }

    const geo = geoip.lookup(ip);
    if (!geo) {
        logger.warn('[Fraud] geoip lookup returned null', { ip });
        return { country: 'Unknown', city: 'Unknown', proxy: false };
    }

    return {
        country: geo.country ?? 'Unknown',
        city: geo.city ?? 'Unknown',
        region: geo.region ?? undefined,
        timezone: geo.timezone ?? undefined,
        proxy: false, // geoip-lite doesn't detect proxies; upgrade to MaxMind GeoIP2 for proxy detection
    };
}

// Track consecutive audit failures to detect DB issues early.
let _auditFailStreak = 0;
const AUDIT_FAIL_ALERT_THRESHOLD = 3;

/**
 * Logs a verification audit entry.
 * On consecutive failures, creates an admin alert so the issue is visible.
 */
export async function logVerificationAudit(data: {
    userId: string;
    sessionId?: string;
    action: 'SUBMIT' | 'APPROVE' | 'REJECT' | 'LOCK';
    status: string;
    ipAddress?: string;
    deviceFingerprint?: string;
    trustScore?: number;
    behaviorScore?: number;
    fraudFlags?: any;
    notes?: string;
}) {
    try {
        // @ts-ignore
        await prisma.verificationAudit.create({
            data: {
                userId: data.userId,
                sessionId: data.sessionId,
                action: data.action,
                status: data.status,
                ipAddress: data.ipAddress,
                deviceFingerprint: data.deviceFingerprint,
                trustScore: data.trustScore,
                behaviorScore: data.behaviorScore,
                fraudFlags: data.fraudFlags,
                notes: data.notes,
            }
        });
        _auditFailStreak = 0; // reset on success
    } catch (error: any) {
        _auditFailStreak++;
        logger.error('Failed to log verification audit', { error: error.message, userId: data.userId, streak: _auditFailStreak });

        // If failures are persistent, create an admin notification so it's not silent.
        if (_auditFailStreak >= AUDIT_FAIL_ALERT_THRESHOLD) {
            _auditFailStreak = 0; // reset so we don't spam
            prisma.adminNotification.create({
                data: {
                    type: 'AUDIT_LOG_FAILURE',
                    caregiverId: data.userId, // reusing caregiverId field for the affected userId
                },
            }).catch(() => {}); // don't let this double-fail
        }
    }
}

/**
 * Advanced Behavioral Risk Calculation
 */
export async function calculateBehavioralRisk(params: {
    userId: string;
    deviceFingerprint: string;
    ciNumber?: string | null;
    currentFaceSimilarity: number;
    userCity?: string | null;
}) {
    let behaviorScore = 100;
    const fraudFlags: string[] = [];
    const { userId, deviceFingerprint, ciNumber, currentFaceSimilarity, userCity } = params;

    // 1. Device Check (Multiple accounts on same device)
    if (deviceFingerprint !== 'unknown') {
        const sameDeviceOtherUser = await prisma.identityVerificationSession.count({
            // @ts-ignore
            where: { deviceFingerprint, userId: { not: userId } }
        });
        if (sameDeviceOtherUser > 0 && env.NODE_ENV !== 'development') {
            behaviorScore -= 30;
            fraudFlags.push('multiple_accounts_on_device');
        }
    }

    // 2. Duplicate Identity Check (Identity Graph)
    if (ciNumber) {
        const duplicateCI = await prisma.caregiverProfile.findFirst({
            where: { ciNumber, userId: { not: userId }, verified: true }
        });
        if (duplicateCI) {
            behaviorScore = 0; // Immediate risk: Identity theft or reuse
            fraudFlags.push('duplicate_identity');
        }
    }

    // 3. Attempt Pattern (Brute Force)
    const oneHourAgo = new Date(Date.now() - 3600000);
    const recentAttemptsCount = await prisma.identityVerificationSession.count({
        where: { userId, createdAt: { gt: oneHourAgo } }
    });
    const attemptThreshold = env.NODE_ENV === 'development' ? 20 : 3;
    if (recentAttemptsCount > attemptThreshold) {
        behaviorScore -= 30; // -0.3 penalty
        fraudFlags.push('suspicious_behavior');
    }

    // 4. Identity Inconsistency (Swapping faces)
    const previousSession = await prisma.identityVerificationSession.findFirst({
        where: { userId, status: 'REJECTED' },
        orderBy: { createdAt: 'desc' }
    });
    if (previousSession && previousSession.similarity != null) {
        if (Math.abs(currentFaceSimilarity - previousSession.similarity) > 40) {
            behaviorScore -= 50;
            fraudFlags.push('identity_inconsistency');
        }
    }

    // 5. Geolocation Check
    // (Simulated - in production we'd get real Geo from IP here)
    // For now we use the placeholder logic from getGeolocation elsewhere or pass it in

    return {
        behaviorScore: Math.max(0, behaviorScore),
        fraudFlags
    };
}
