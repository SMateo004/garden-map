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
export async function sendPush(
  fcmToken: string,
  title: string,
  body: string,
  data?: Record<string, string>
): Promise<void> {
  if (!fcmToken) return;
  const messaging = await getMessaging();
  if (!messaging) return;

  try {
    await messaging.send({
      token: fcmToken,
      notification: { title, body },
      ...(data ? { data } : {}),
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
 * Envía un push silencioso (data-only, SIN `notification`) — no muestra
 * ningún banner ni entra al tray de notificaciones, solo despierta el
 * background message handler de la app. Usado para el ping de ubicación
 * horario de Hospedaje/Guardería (ver hospedaje-location-ping.job.ts):
 * el cuidador nunca debe ver que se le pidió su ubicación, a diferencia
 * de sendPush() que siempre es visible.
 *
 * apns `content-available: 1` es lo que permite a iOS despertar la app en
 * segundo plano sin mostrar alerta — Apple entrega esto "best effort", no
 * garantiza el momento exacto (puede demorarse o descartarse con batería
 * baja). Android entrega mensajes data-only de forma más confiable.
 */
export async function sendSilentDataPush(
  fcmToken: string,
  data: Record<string, string>
): Promise<void> {
  if (!fcmToken) return;
  const messaging = await getMessaging();
  if (!messaging) return;

  try {
    await messaging.send({
      token: fcmToken,
      data,
      android: { priority: 'high' },
      apns: {
        payload: { aps: { 'content-available': 1 } },
        headers: { 'apns-priority': '5' },
      },
    });
  } catch (err: any) {
    logger.warn('[FCM] Silent push delivery failed', { error: err.message });
  }
}

/**
 * Looks up the user's FCM token and sends a push notification.
 * Silently skips if user has no token registered.
 *
 * `data` (opcional) — payload de deep-link que la app usa para navegar a la
 * pantalla correcta al tocar la notificación (ver FcmService._handleNotificationTap
 * en el cliente Flutter). Sin esto, la notificación se abre pero no lleva a
 * ningún lado — quedó así de origen en la mayoría de los call sites de este
 * proyecto, algo reportado explícitamente como bug por el dueño del negocio.
 */
export async function sendPushToUser(
  userId: string,
  title: string,
  body: string,
  data?: Record<string, string>
): Promise<void> {
  try {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { fcmToken: true },
    });
    if (user?.fcmToken) {
      await sendPush(user.fcmToken, title, body, data);
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
export async function sendPushToAdmins(
  title: string,
  body: string,
  data?: Record<string, string>
): Promise<void> {
  try {
    const admins = await prisma.user.findMany({
      where: { role: 'ADMIN', fcmToken: { not: null } },
      select: { fcmToken: true },
    });
    await Promise.all(
      admins
        .map((a) => a.fcmToken)
        .filter((t): t is string => !!t)
        .map((token) => sendPush(token, title, body, data))
    );
  } catch (err: any) {
    logger.warn('[FCM] sendPushToAdmins error', { error: err.message });
  }
}
