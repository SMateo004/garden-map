import { Router, Request, Response } from 'express';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import { asyncHandler } from '../../shared/async-handler.js';
import Anthropic from '@anthropic-ai/sdk';
import { blockchainService } from '../../services/blockchain.service.js';
import logger from '../../shared/logger.js';
import { track } from '../../shared/analytics.js';

// Use the shared Prisma singleton — avoids a separate connection pool per module
import prisma from '../../config/database.js';

const router = Router();
const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

// POST /api/disputes/:bookingId/client-report — cliente reporta razones
router.post('/:bookingId/client-report', authMiddleware, requireRole('CLIENT'),
  asyncHandler(async (req: Request, res: Response) => {
    // Verificar si las disputas están habilitadas
    const { getBoolSetting } = await import('../../utils/settings-cache.js');
    if (!await getBoolSetting('disputasEnabled', true)) {
      return res.status(503).json({
        success: false,
        error: { code: 'DISPUTAS_DISABLED', message: 'El sistema de disputas está temporalmente deshabilitado. Contacta al soporte.' },
      });
    }

    const { bookingId } = req.params;
    const userId = (req as any).user.userId;
    const { reasons } = req.body; // string[]

    if (!reasons || !Array.isArray(reasons) || reasons.length === 0) {
      return res.status(400).json({ success: false, error: { message: 'Selecciona al menos una razón' } });
    }

    const booking = await prisma.booking.findFirst({
      where: { id: bookingId, clientId: userId },
      include: { caregiver: { include: { user: true } } },
    });
    if (!booking) return res.status(404).json({ success: false, error: { message: 'Reserva no encontrada' } });

    // Only allow disputes on COMPLETED bookings whose payment is ON_HOLD (i.e. client rated <3)
    if (booking.status !== 'COMPLETED' || booking.payoutStatus !== 'ON_HOLD') {
      return res.status(400).json({
        success: false,
        error: { message: 'Solo puedes disputar servicios completados con pago retenido. Califica el servicio primero.' },
      });
    }

    // Prevent re-opening a dispute that's already resolved OR actively being
    // resolved by the AI right now (overwriting clientReasons mid-resolution
    // would leave the final `resolution` text out of sync with what actually
    // got decided/paid).
    const existingDispute = await (prisma as any).dispute.findUnique({ where: { bookingId } });
    if (existingDispute?.status === 'RESOLVED' || existingDispute?.status === 'PENDING_AI') {
      return res.status(409).json({
        success: false,
        error: { message: 'Esta disputa ya fue resuelta o está siendo evaluada y no puede modificarse.' },
      });
    }

    const dispute = await (prisma as any).dispute.upsert({
      where: { bookingId },
      create: { bookingId, clientReasons: reasons, status: 'PENDING_CAREGIVER' },
      update: { clientReasons: reasons, status: 'PENDING_CAREGIVER' },
    });

    await prisma.notification.create({
      data: {
        userId: booking.caregiver.userId,
        title: '⚠️ Disputa abierta',
        message: `El dueño reportó un problema con el servicio. Por favor responde a la encuesta para resolver la disputa.`,
        type: 'SYSTEM',
      },
    });

    track(userId, 'dispute_opened', { bookingId, disputeId: dispute.id, reasons });
    res.json({ success: true, data: { disputeId: dispute.id, status: dispute.status } });
  })
);

// POST /api/disputes/:bookingId/caregiver-response — cuidador responde y disputa se resuelve automáticamente
router.post('/:bookingId/caregiver-response', authMiddleware, requireRole('CAREGIVER'),
  asyncHandler(async (req: Request, res: Response) => {
    const { bookingId } = req.params;
    const userId = (req as any).user.userId;
    const { responses } = req.body; // string[]

    const booking = await prisma.booking.findFirst({
      where: { id: bookingId },
      include: {
        caregiver: { include: { user: true } },
        dispute: true,
      } as any,
    });
    if (!booking || (booking as any).caregiver.userId !== userId) {
      return res.status(403).json({ success: false, error: { message: 'Sin acceso' } });
    }
    if (!(booking as any).dispute) {
      return res.status(404).json({ success: false, error: { message: 'No hay disputa activa' } });
    }

    // Atomic claim — evita que un doble-click o un reintento de red dispare
    // el juicio de IA (y por lo tanto applyResolution) dos veces para la
    // misma disputa. Solo una request gana la carrera; la otra ve count=0.
    const claimedResponse = await prisma.dispute.updateMany({
      where: { bookingId, status: 'PENDING_CAREGIVER' },
      data: { caregiverResponse: responses, status: 'PENDING_AI' },
    });
    if (claimedResponse.count === 0) {
      return res.status(409).json({
        success: false,
        error: { message: 'Esta disputa ya fue respondida o está siendo evaluada.' },
      });
    }

    // ── Recopilar toda la evidencia disponible para el agente ────────────────
    const [chatMessages, review, fullBooking] = await Promise.all([
      prisma.chatMessage.findMany({
        where: { bookingId },
        orderBy: { createdAt: 'asc' },
        select: { senderRole: true, message: true, createdAt: true },
      }),
      prisma.review.findFirst({
        where: { bookingId },
        select: { rating: true, comment: true, createdAt: true },
      }),
      prisma.booking.findFirst({
        where: { id: bookingId },
        include: {
          caregiver: {
            select: {
              rating: true,
              reviewCount: true,
              experienceYears: true,
              bio: true,
            },
          },
        },
      }),
    ]);

    const evidence = {
      booking: {
        serviceType: (fullBooking as any)?.serviceType,
        status: (fullBooking as any)?.status,
        totalAmount: Number((fullBooking as any)?.totalAmount),
        startDate: (fullBooking as any)?.startDate,
        endDate: (fullBooking as any)?.endDate,
        walkDate: (fullBooking as any)?.walkDate,
        petName: (fullBooking as any)?.petName,
        petBreed: (fullBooking as any)?.petBreed,
        petSize: (fullBooking as any)?.petSize,
        specialNeeds: (fullBooking as any)?.specialNeeds,
        serviceStartPhoto: (fullBooking as any)?.serviceStartPhoto,
        serviceEndPhoto: (fullBooking as any)?.serviceEndPhoto,
        serviceStartedAt: (fullBooking as any)?.serviceStartedAt,
        serviceEndedAt: (fullBooking as any)?.serviceEndedAt,
        trackingPoints: Array.isArray((fullBooking as any)?.serviceTrackingData)
          ? ((fullBooking as any).serviceTrackingData as any[]).length
          : null,
        serviceEvents: Array.isArray((fullBooking as any)?.serviceEvents)
          ? (fullBooking as any).serviceEvents
          : [],
      },
      caregiver: {
        rating: (fullBooking as any)?.caregiver?.rating,
        reviewCount: (fullBooking as any)?.caregiver?.reviewCount,
        experienceYears: (fullBooking as any)?.caregiver?.experienceYears,
      },
      chat: chatMessages.map(m => ({
        role: m.senderRole,
        text: m.message,
        at: m.createdAt,
      })),
      review: review && review.rating != null
        ? { rating: review.rating as number, comment: review.comment, at: review.createdAt }
        : null,
    };

    // El agente de IA investiga toda la evidencia y toma la decisión definitiva
    const resolution = await resolveDisputeWithAI(
      (booking as any).dispute!.clientReasons,
      responses,
      bookingId!,
      Number((booking as any).totalAmount),
      evidence,
    );

    try {
      await applyResolution(bookingId!, resolution, booking);
    } catch (err: any) {
      if (err.code === 'DISPUTE_ALREADY_RESOLVED') {
        return res.status(409).json({ success: false, error: { message: err.message } });
      }
      throw err;
    }

    res.json({ success: true, data: resolution });
  })
);

// GET /api/disputes/:bookingId — obtener estado de disputa (solo las partes o admin)
router.get('/:bookingId', authMiddleware,
  asyncHandler(async (req: Request, res: Response) => {
    const { bookingId } = req.params;
    const userId = (req as any).user.userId;
    const role = (req as any).user.role;

    // Authorization: only the booking's client, its caregiver, or an admin can read the dispute
    if (role !== 'ADMIN') {
      const booking = await prisma.booking.findUnique({
        where: { id: bookingId },
        include: { caregiver: { select: { userId: true } } },
      });
      if (!booking) return res.status(404).json({ success: false, error: { message: 'Reserva no encontrada' } });
      const isClient = booking.clientId === userId;
      const isCaregiver = booking.caregiver?.userId === userId;
      if (!isClient && !isCaregiver) {
        return res.status(403).json({ success: false, error: { message: 'Sin acceso a esta disputa' } });
      }
    }

    const dispute = await (prisma as any).dispute.findUnique({ where: { bookingId } });
    if (!dispute) return res.status(404).json({ success: false, error: { message: 'No hay disputa' } });
    res.json({ success: true, data: dispute });
  })
);

// ---------------------------------------------------------------------------
// Agente de IA investigador — analiza TODA la evidencia y siempre decide un ganador
// ---------------------------------------------------------------------------
async function resolveDisputeWithAI(
  clientReasons: string[],
  caregiverResponses: string[],
  bookingId: string,
  amount: number,
  evidence: {
    booking: Record<string, any>;
    caregiver: Record<string, any>;
    chat: Array<{ role: string; text: string; at: any }>;
    review: { rating: number; comment: string | null; at: any } | null;
  },
) {
  // Formatear chat para el prompt (máx 30 mensajes para no exceder tokens)
  const chatSample = evidence.chat.slice(-30);
  const chatText = chatSample.length > 0
    ? chatSample.map(m => `[${m.role}] ${m.text}`).join('\n')
    : 'Sin mensajes de chat registrados.';

  const reviewText = evidence.review
    ? `Calificación final del dueño: ${evidence.review.rating}/5 — "${evidence.review.comment ?? 'Sin comentario'}"`
    : 'El dueño no dejó reseña.';

  const b = evidence.booking;
  const bookingText = [
    `Tipo de servicio: ${b.serviceType ?? '—'}`,
    `Mascota: ${b.petName ?? '—'} (${b.petBreed ?? '—'}, talla ${b.petSize ?? '—'})`,
    b.specialNeeds ? `Necesidades especiales: ${b.specialNeeds}` : null,
    b.startDate || b.walkDate ? `Fecha: ${b.startDate ?? b.walkDate}` : null,
    b.serviceStartedAt ? `Servicio iniciado: ${b.serviceStartedAt}` : 'Servicio NO iniciado on-app.',
    b.serviceEndedAt ? `Servicio finalizado: ${b.serviceEndedAt}` : 'Servicio NO finalizado on-app.',
    b.serviceStartPhoto ? '✅ Foto de inicio del servicio disponible (cuidador la subió).' : '⚠️ Sin foto de inicio de servicio.',
    b.serviceEndPhoto ? '✅ Foto de fin del servicio disponible (cuidador la subió).' : '⚠️ Sin foto de fin de servicio.',
    b.trackingPoints !== null ? `GPS tracking: ${b.trackingPoints} puntos registrados.` : 'Sin datos GPS.',
    (b.serviceEvents as any[])?.length > 0
      ? `Eventos registrados: ${(b.serviceEvents as any[]).map((e: any) => e.type ?? e).join(', ')}`
      : 'Sin eventos de servicio registrados.',
  ].filter(Boolean).join('\n');

  const caregiverText = [
    `Rating cuidador: ${evidence.caregiver.rating ?? '—'}/5 (${evidence.caregiver.reviewCount ?? 0} reseñas)`,
    evidence.caregiver.experienceYears != null ? `Experiencia: ${evidence.caregiver.experienceYears} años` : null,
  ].filter(Boolean).join('\n');

  const prompt = `Eres el Agente Investigador de Disputas de GARDEN, la plataforma de cuidado de mascotas en Santa Cruz de la Sierra, Bolivia.

Tu rol es el de un JUEZ que tiene acceso completo al expediente de la reserva. Debes investigar toda la evidencia disponible y emitir un VEREDICTO DEFINITIVO. No puedes evadirte con respuestas ambiguas.

━━━━━━━━━━━━━━━━━━━━━━━
EXPEDIENTE DE LA RESERVA
━━━━━━━━━━━━━━━━━━━━━━━
${bookingText}

PERFIL DEL CUIDADOR:
${caregiverText}

━━━━━━━━━━━━━━━━━━━━━━━
VERSIÓN DEL DUEÑO (razones de la disputa):
${clientReasons.map(r => `• ${r}`).join('\n')}

VERSIÓN DEL CUIDADOR (su respuesta):
${caregiverResponses.map(r => `• ${r}`).join('\n')}

━━━━━━━━━━━━━━━━━━━━━━━
HISTORIAL DE CHAT ENTRE LAS PARTES:
${chatText}

RESEÑA FINAL:
${reviewText}

━━━━━━━━━━━━━━━━━━━━━━━
INSTRUCCIONES DEL JUEZ (OBLIGATORIAS — no negociables):

1. INVESTIGA toda la evidencia: fotos, GPS, chat, eventos, reseña, calificaciones.
2. DECIDE siempre un GANADOR CLARO:
   - CAREGIVER_WINS → si el cuidador cumplió con el servicio o las pruebas lo respaldan.
   - CLIENT_WINS → si el cuidador falló, no completó el servicio, o el dueño tiene evidencia.
3. PARTIAL solo como ÚLTIMO RECURSO absoluto: únicamente si las pruebas objetivas son completamente idénticas en peso para ambos lados y es imposible determinar un responsable. Esto debe ser muy raro.
4. La AUSENCIA DE EVIDENCIA (sin fotos, sin GPS, sin chat) cuenta EN CONTRA del cuidador, ya que es su responsabilidad documentar el servicio.
5. Un rating bajo (1-2 estrellas) + chat con quejas = señal fuerte en favor del cliente.
6. Un cuidador que sí subió fotos, tiene GPS, y buena comunicación en el chat = señal fuerte en su favor.
7. Siempre incluye qué evidencia específica fue DETERMINANTE en tu decisión.
8. La comisión de GARDEN (10%) se mantiene en cualquier veredicto.

Responde SOLO en este formato JSON exacto (sin texto adicional):
{
  "verdict": "CLIENT_WINS" | "CAREGIVER_WINS" | "PARTIAL",
  "analysis": "Explicación de 3-5 oraciones indicando qué evidencia fue determinante y por qué.",
  "recommendations": ["recomendación específica 1 para el cuidador", "recomendación 2", "recomendación 3"]
}`;

  // Retry up to 3 times before escalating to manual admin review.
  const MAX_ATTEMPTS = 3;
  let lastError: unknown;

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      const message = await anthropic.messages.create({
        model: 'claude-sonnet-4-6',
        max_tokens: 1200,
        messages: [{ role: 'user', content: prompt }],
      });

      const content = (message.content[0] as any).text || '{}';
      const clean = content.replace(/```json|```/g, '').trim();
      const parsed = JSON.parse(clean);

      if (!['CLIENT_WINS', 'CAREGIVER_WINS', 'PARTIAL'].includes(parsed.verdict)) {
        throw new Error(`Invalid verdict: ${parsed.verdict}`);
      }

      logger.info('AI dispute resolved', { bookingId, attempt, verdict: parsed.verdict });
      return parsed;
    } catch (err) {
      lastError = err;
      logger.warn(`AI dispute attempt ${attempt}/${MAX_ATTEMPTS} failed`, { bookingId, error: (err as Error).message });
      if (attempt < MAX_ATTEMPTS) {
        await new Promise(r => setTimeout(r, 1500 * attempt)); // back-off: 1.5s, 3s
      }
    }
  }

  // All 3 attempts failed — apply evidence-based deterministic fallback (no manual queue).
  logger.error('AI dispute resolution failed after 3 attempts — applying evidence-based fallback', { bookingId, lastError });

  const photoEvents = Array.isArray(b.serviceEvents)
    ? b.serviceEvents.filter((e: any) => e.type === 'PHOTO').length
    : 0;
  const hasGps = b.trackingPoints != null && b.trackingPoints > 0;
  const hasStartPhoto = !!b.serviceStartPhoto;
  const hasEndPhoto = !!b.serviceEndPhoto;

  // Caregiver wins if they documented the service: both start+end photos, OR 2+ event photos + GPS
  const caregiverDocumented = (hasStartPhoto && hasEndPhoto) || (photoEvents >= 2 && hasGps);
  const fallbackVerdict = caregiverDocumented ? 'CAREGIVER_WINS' : 'CLIENT_WINS';
  const fallbackAnalysis = caregiverDocumented
    ? `Decisión automática (fallo técnico IA, ${MAX_ATTEMPTS} intentos): el cuidador documentó el servicio con fotos y/o GPS — veredicto a su favor.`
    : `Decisión automática (fallo técnico IA, ${MAX_ATTEMPTS} intentos): el cuidador no subió documentación suficiente del servicio — reembolso al cliente.`;

  return {
    verdict: fallbackVerdict,
    analysis: fallbackAnalysis,
    recommendations: [],
  };
}

// ---------------------------------------------------------------------------
// Aplicar resolución automáticamente según las reglas definidas
// ---------------------------------------------------------------------------
export async function applyResolution(bookingId: string, resolution: any, booking: any) {
  const totalAmount = Number(booking.totalAmount);
  const commission = Number(booking.commissionAmount ?? totalAmount * 0.10);
  const netAmount = totalAmount - commission; // 90% del total
  const caregiverUserId = booking.caregiver.userId;
  const clientId = booking.clientId;

  await (prisma as any).$transaction(async (tx: any) => {
    // Atomic claim — la disputa solo puede pagarse UNA vez. Sin esto, dos
    // llamadas a applyResolution() para la misma reserva (ej. race del
    // caregiver-response, o el job de onHoldSlaHoras liberando el pago justo
    // antes de que la IA resuelva) moverían dinero dos veces sobre el mismo
    // totalAmount. Cada rama de abajo sigue seteando el payoutStatus final
    // (PAID/REFUNDED) al terminar — este claim solo protege el punto de partida.
    const claimed = await tx.booking.updateMany({
      where: { id: bookingId, payoutStatus: 'ON_HOLD' },
      data: { payoutStatus: 'RESOLVING_DISPUTE' },
    });
    if (claimed.count === 0) {
      throw Object.assign(new Error('La disputa ya fue resuelta o el pago ya no está retenido'), { code: 'DISPUTE_ALREADY_RESOLVED' });
    }

    if (resolution.verdict === 'CAREGIVER_WINS') {
      // ── Pago completo al cuidador (90% del total) ──────────────────────────
      // Snapshot balance BEFORE increment so WalletTransaction.balance is correct
      const caregiverBefore = await tx.caregiverProfile.findUnique({
        where: { userId: caregiverUserId },
        select: { balance: true },
      });
      const caregiverBalanceBefore = Number(caregiverBefore?.balance ?? 0);

      await tx.caregiverProfile.update({
        where: { userId: caregiverUserId },
        data: { balance: { increment: netAmount } },
      });
      await tx.walletTransaction.create({
        data: {
          userId: caregiverUserId,
          type: 'EARNING',
          amount: netAmount,
          balance: caregiverBalanceBefore + netAmount,
          description: `Disputa resuelta a tu favor — Reserva #${bookingId.slice(0, 8).toUpperCase()}`,
          status: 'COMPLETED',
        },
      });
      await tx.dispute.update({
        where: { bookingId },
        data: {
          aiVerdict: 'CAREGIVER_WINS',
          aiAnalysis: resolution.analysis,
          aiRecommendations: JSON.stringify(resolution.recommendations),
          status: 'RESOLVED',
          resolution: `Pago completo al cuidador (Bs ${netAmount.toFixed(2)})`,
        },
      });
      await tx.booking.update({
        where: { id: bookingId },
        data: { status: 'COMPLETED', payoutStatus: 'PAID' },
      });
      await tx.notification.create({
        data: {
          userId: caregiverUserId,
          title: '✅ Disputa resuelta a tu favor',
          message: `GARDEN IA analizó el caso y determinó que tienes razón. Recibirás Bs ${netAmount.toFixed(2)} en tu billetera.`,
          type: 'SYSTEM',
        },
      });
      await tx.notification.create({
        data: {
          userId: clientId,
          title: '⚖️ Disputa resuelta',
          message: `GARDEN IA analizó el caso. Veredicto: a favor del cuidador. ${resolution.analysis}`,
          type: 'SYSTEM',
        },
      });

    } else if (resolution.verdict === 'CLIENT_WINS') {
      // ── Reembolso completo al cliente (incluyendo comisión) ────────────────
      const clientBefore = await tx.clientProfile.findUnique({
        where: { userId: clientId },
        select: { balance: true },
      });
      const clientBalanceBefore = Number(clientBefore?.balance ?? 0);

      await tx.clientProfile.update({
        where: { userId: clientId },
        data: { balance: { increment: totalAmount } },
      });
      await tx.walletTransaction.create({
        data: {
          userId: clientId,
          type: 'REFUND',
          amount: totalAmount,
          balance: clientBalanceBefore + totalAmount,
          description: `Reembolso por disputa — Reserva #${bookingId.slice(0, 8).toUpperCase()}`,
          status: 'COMPLETED',
        },
      });
      await tx.dispute.update({
        where: { bookingId },
        data: {
          aiVerdict: 'CLIENT_WINS',
          aiAnalysis: resolution.analysis,
          aiRecommendations: JSON.stringify(resolution.recommendations),
          status: 'RESOLVED',
          resolution: `Reembolso completo al cliente (Bs ${totalAmount.toFixed(2)})`,
        },
      });
      await tx.booking.update({
        where: { id: bookingId },
        data: { status: 'CANCELLED', payoutStatus: 'REFUNDED' },
      });
      await tx.notification.create({
        data: {
          userId: clientId,
          title: '✅ Reembolso aprobado',
          message: `GARDEN IA analizó el caso y aprobó tu reembolso de Bs ${totalAmount.toFixed(2)} (monto completo incluyendo comisión).`,
          type: 'SYSTEM',
        },
      });
      const recs = resolution.recommendations?.join(' | ') ?? '';
      await tx.notification.create({
        data: {
          userId: caregiverUserId,
          title: '⚠️ Disputa resuelta — Mejora tu servicio',
          message: `La disputa se resolvió a favor del cliente. ${resolution.analysis} Recomendaciones: ${recs}`,
          type: 'SYSTEM',
        },
      });

    } else {
      // ── PARTIAL: 80% al cuidador + 20% → código de descuento para el dueño ─
      // La comisión (10%) se mantiene. El split es sobre el netAmount (90%).
      const caregiverPayout = parseFloat((netAmount * 0.80).toFixed(2)); // 72% del total
      const clientDiscountAmount = parseFloat((netAmount * 0.20).toFixed(2)); // 18% del total

      // Generar código único de descuento de un solo uso
      const discountCode = `GDN-${bookingId.slice(0, 6).toUpperCase()}-${Date.now().toString(36).toUpperCase().slice(-4)}`;

      const giftCode = await tx.giftCode.create({
        data: {
          code: discountCode,
          amount: clientDiscountAmount,
          maxUses: 1,
          active: true,
        },
      });

      const caregiverBeforePartial = await tx.caregiverProfile.findUnique({
        where: { userId: caregiverUserId },
        select: { balance: true },
      });
      const caregiverBalanceBeforePartial = Number(caregiverBeforePartial?.balance ?? 0);

      await tx.caregiverProfile.update({
        where: { userId: caregiverUserId },
        data: { balance: { increment: caregiverPayout } },
      });
      await tx.walletTransaction.create({
        data: {
          userId: caregiverUserId,
          type: 'EARNING',
          amount: caregiverPayout,
          balance: caregiverBalanceBeforePartial + caregiverPayout,
          description: `Disputa resuelta (parcial 80%) — Reserva #${bookingId.slice(0, 8).toUpperCase()}`,
          status: 'COMPLETED',
        },
      });
      await tx.dispute.update({
        where: { bookingId },
        data: {
          aiVerdict: 'PARTIAL',
          aiAnalysis: resolution.analysis,
          aiRecommendations: JSON.stringify(resolution.recommendations),
          status: 'RESOLVED',
          resolution: `Parcial: cuidador Bs ${caregiverPayout.toFixed(2)} (80%) | descuento dueño Bs ${clientDiscountAmount.toFixed(2)} (20%) | código: ${discountCode}`,
          discountCodeId: giftCode.id,
        },
      });
      await tx.booking.update({
        where: { id: bookingId },
        data: { status: 'COMPLETED', payoutStatus: 'PAID' },
      });

      // Notificar al dueño con el código de descuento (va directo a notificaciones)
      await tx.notification.create({
        data: {
          userId: clientId,
          title: '🎟️ Código de compensación — Uso único',
          message: `GARDEN IA analizó tu caso. Como compensación parcial, te enviamos un código de descuento de Bs ${clientDiscountAmount.toFixed(2)} para tu próxima reserva.\n\nCódigo: ${discountCode}\n\nUso único. Válido hasta que lo uses. ${resolution.analysis}`,
          type: 'SYSTEM',
        },
      });
      await tx.notification.create({
        data: {
          userId: caregiverUserId,
          title: '⚖️ Disputa resuelta — Pago parcial',
          message: `GARDEN IA resolvió la disputa con pago parcial. Recibirás Bs ${caregiverPayout.toFixed(2)} (80% del monto neto). ${resolution.analysis}`,
          type: 'SYSTEM',
        },
      });
    }
  });

  // ── Registrar en blockchain con retry (3 intentos, back-off exponencial) ──
  // Fire-and-forget but with retry so ledger inconsistencies are minimized.
  // If all retries fail, an admin notification is created so it can be manually re-submitted.
  _dispatchBlockchainWithRetry(bookingId, resolution.verdict, netAmount, totalAmount);
}

async function _dispatchBlockchainWithRetry(
  bookingId: string,
  verdict: string,
  netAmount: number,
  totalAmount: number,
  maxAttempts = 3,
) {
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      if (verdict === 'CAREGIVER_WINS') {
        await blockchainService.resolveDisputeCaregiverWinsOnChain(bookingId, netAmount);
      } else if (verdict === 'CLIENT_WINS') {
        await blockchainService.resolveDisputeClientWinsOnChain(bookingId, totalAmount);
      } else if (verdict === 'PARTIAL') {
        const caregiverPayout = parseFloat((netAmount * 0.80).toFixed(2));
        const clientDiscountAmount = parseFloat((netAmount * 0.20).toFixed(2));
        await blockchainService.resolvePartialOnChain(bookingId, caregiverPayout, clientDiscountAmount);
      }
      logger.info('Blockchain dispute record saved', { bookingId, verdict, attempt });
      return; // success
    } catch (err: any) {
      logger.warn(`Blockchain dispatch attempt ${attempt}/${maxAttempts} failed`, { bookingId, error: err.message });
      if (attempt < maxAttempts) {
        await new Promise(r => setTimeout(r, 1000 * Math.pow(2, attempt - 1))); // 1s, 2s
      }
    }
  }
  // All retries exhausted — flag for admin to manually re-submit
  logger.error('Blockchain dispatch failed after all retries — admin notification created', { bookingId, verdict });
  await prisma.adminNotification.create({
    data: {
      type: 'BLOCKCHAIN_FAILURE',
      bookingId,
      caregiverId: '', // unknown at this point — admin can look up by bookingId
    },
  }).catch(() => {});
}

export default router;
