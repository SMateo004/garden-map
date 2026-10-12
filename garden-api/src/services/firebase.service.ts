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
  data?: Record<string, string>,
  webLink?: string
): Promise<void> {
  if (!fcmToken) return;
  const messaging = await getMessaging();
  if (!messaging) return;

  try {
    await messaging.send({
      token: fcmToken,
      notification: { title, body },
      ...(data ? { data } : {}),
      // Tokens del navegador (panel admin): a dónde lleva tocar el aviso.
      ...(webLink ? { webpush: { fcmOptions: { link: webLink } } } : {}),
      // Sonido de GARDEN (roce de arbustos) y su canal de Android, definidos en
      // la app (LocalNotificationService). Una versión vieja de la app que no
      // los tenga usa el sonido normal del teléfono.
      android: {
        priority: 'high',
        notification: { sound: 'garden_arbusto', channelId: 'garden_avisos' },
      },
      apns: {
        payload: { aps: { sound: 'garden_arbusto.wav', badge: 1 } },
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
 * Tipo con que el aviso queda en la bandeja del admin (Notification.type,
 * VarChar 20). La app lo usa para el icono y para abrir la pestaña del panel
 * que corresponde (ver adminTabFor en notification_bell.dart). El `type` del
 * push NO cambia: la app del celular ya lo usa (ej. la alarma de emergencia).
 */
export function adminInboxType(pushType?: string): string {
  const t = pushType ?? '';
  if (t.startsWith('ADMIN_') && t.length <= 20) return t;
  if (t === 'CLIENT_SOS_URGENT' || t === 'SERVICE_INCIDENT_URGENT') return 'ADMIN_URGENT';
  if (t === 'WALKIN_INCIDENT') return 'ADMIN_INCIDENT';
  if (t === 'EMAIL_OTP_MANUAL_HELP') return 'ADMIN_VERIFY_EMAIL';
  if (t === 'PHONE_OTP_MANUAL_HELP') return 'ADMIN_VERIFY_PHONE';
  if (t === 'CHAT_REPORT') return 'ADMIN_CHAT_REPORT';
  if (t.startsWith('DISPUTE')) return 'ADMIN_DISPUTE';
  if (t.startsWith('BLOCKCHAIN')) return 'ADMIN_BLOCKCHAIN';
  if (t.startsWith('EXTENSION')) return 'ADMIN_EXTENSION';
  if (t.startsWith('WITHDRAWAL')) return 'ADMIN_WITHDRAWAL';
  if (t.startsWith('PAYMENT') || t.startsWith('SIP')) return 'ADMIN_PAYMENT';
  if (t === 'CAREGIVER_SUBMIT') return 'ADMIN_CAREGIVER';
  if (t.startsWith('NIT')) return 'ADMIN_NIT';
  if (t === 'LOW_RATING') return 'ADMIN_RATING';
  return 'ADMIN_ALERT';
}

/**
 * Avisa a TODOS los admins por la app: deja el aviso en su bandeja (la
 * campana del panel admin, que lo muestra aunque nadie tenga push activo) y
 * manda push a los que tengan token — celular o navegador del panel.
 *
 * Antes solo mandaba push, y ningún admin tenía token (el panel se usa desde
 * el navegador, que nunca registraba uno): todas las alertas se perdían.
 * Nunca lanza ni bloquea el flujo que la dispara.
 */
export async function sendPushToAdmins(
  title: string,
  body: string,
  data?: Record<string, string>
): Promise<void> {
  try {
    const admins = await prisma.user.findMany({
      where: { role: 'ADMIN' },
      select: { id: true, fcmToken: true },
    });
    if (admins.length === 0) {
      logger.error('[ADMIN-ALERT] No hay admins para avisar', { title });
      return;
    }
    const inboxType = adminInboxType(data?.type);
    await prisma.notification.createMany({
      data: admins.map((a) => ({
        userId: a.id,
        title: title.slice(0, 200),
        message: body,
        type: inboxType,
        bookingId: data?.bookingId ?? null,
      })),
    });
    const pushData = { ...(data ?? {}), adminType: inboxType };
    await Promise.all(
      admins
        .map((a) => a.fcmToken)
        .filter((t): t is string => !!t)
        .map((token) => sendPush(token, title, body, pushData, adminPanelLink()))
    );
  } catch (err: any) {
    logger.warn('[FCM] sendPushToAdmins error', { error: err.message });
  }
}

/** Alias con el nombre que describe lo que hace hoy (bandeja + push). */
export const notifyAdmins = sendPushToAdmins;

/** Al tocar el push en el navegador, abre el panel admin. */
function adminPanelLink(): string | undefined {
  const base = process.env.FRONTEND_URL ?? '';
  return base.startsWith('https://') ? `${base.replace(/\/$/, '')}/app.html#/admin` : undefined;
}
