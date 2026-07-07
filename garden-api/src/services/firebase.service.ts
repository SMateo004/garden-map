import logger from '../shared/logger.js';
import prisma from '../config/database.js';

let _initialized = false;
let _messagingInstance: any = null;

/** Lazily initializes Firebase Admin SDK using env vars. Returns null if not configured. */
async function getMessaging(): Promise<any> {
  if (_initialized) return _messagingInstance;
  _initialized = true;

  const projectId = process.env.FIREBASE_PROJECT_ID;
  const privateKey = process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n');
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;

  if (!projectId || !privateKey || !clientEmail) {
    logger.warn('[FCM] Firebase credentials not set — push notifications disabled');
    return null;
  }

  try {
    const { default: admin } = await import('firebase-admin');
    if (!admin.apps.length) {
      admin.initializeApp({
        credential: admin.credential.cert({ projectId, privateKey, clientEmail } as any),
      });
    }
    _messagingInstance = admin.messaging();
    logger.info('[FCM] Firebase Admin initialized successfully');
    return _messagingInstance;
  } catch (err: any) {
    logger.error('[FCM] Failed to initialize Firebase Admin', { error: err.message });
    return null;
  }
}

/**
 * Sends a push notification to a single FCM token.
 * Never throws — push is best-effort and must not block business logic.
 */
export async function sendPush(fcmToken: string, title: string, body: string): Promise<void> {
  if (!fcmToken) return;
  const messaging = await getMessaging();
  if (!messaging) return;

  try {
    await messaging.send({
      token: fcmToken,
      notification: { title, body },
      android: {
        priority: 'high',
        notification: { sound: 'default', channelId: 'garden_main' },
      },
      apns: {
        payload: { aps: { sound: 'default', badge: 1 } },
      },
    });
  } catch (err: any) {
    logger.warn('[FCM] Push delivery failed', { error: err.message });
  }
}

/**
 * Looks up the user's FCM token and sends a push notification.
 * Silently skips if user has no token registered.
 */
export async function sendPushToUser(userId: string, title: string, body: string): Promise<void> {
  try {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { fcmToken: true },
    });
    if (user?.fcmToken) {
      await sendPush(user.fcmToken, title, body);
    }
  } catch (err: any) {
    logger.warn('[FCM] sendPushToUser error', { userId, error: err.message });
  }
}

/**
 * Notifica a TODOS los usuarios con rol ADMIN (los que tengan token registrado).
 * Usado para alertas que requieren atención inmediata (ej. un pago quedó
 * pendiente de aprobación manual) — nunca bloquea el flujo que la dispara.
 */
export async function sendPushToAdmins(title: string, body: string): Promise<void> {
  try {
    const admins = await prisma.user.findMany({
      where: { role: 'ADMIN', fcmToken: { not: null } },
      select: { fcmToken: true },
    });
    await Promise.all(
      admins
        .map((a) => a.fcmToken)
        .filter((t): t is string => !!t)
        .map((token) => sendPush(token, title, body))
    );
  } catch (err: any) {
    logger.warn('[FCM] sendPushToAdmins error', { error: err.message });
  }
}
