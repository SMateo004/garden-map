import { Router, Request, Response } from 'express';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import { asyncHandler } from '../../shared/async-handler.js';
import { PrismaClient } from '@prisma/client';
import Anthropic from '@anthropic-ai/sdk';
import { blockchainService } from '../../services/blockchain.service.js';
import logger from '../../shared/logger.js';

const router = Router();
const prisma = new PrismaClient();
const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

// POST /api/disputes/:bookingId/client-report — cliente reporta razones
router.post('/:bookingId/client-report', authMiddleware, requireRole('CLIENT'),
  asyncHandler(async (req: Request, res: Response) => {
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

    await prisma.dispute.update({
      where: { bookingId },
      data: { caregiverResponse: responses, status: 'PENDING_AI' },
    });

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
      review: review
        ? { rating: review.rating, comment: review.comment, at: review.createdAt }
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

    await applyResolution(bookingId!, resolution, booking);

    res.json({ success: true, data: resolution });
  })
);

// GET /api/disputes/:bookingId — obtener estado de disputa
router.get('/:bookingId', authMiddleware,
  asyncHandler(async (req: Request, res: Response) => {
    const { bookingId } = req.params;
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

  const message = await anthropic.messages.create({
    model: 'claude-sonnet-4-6',
    max_tokens: 1200,
    messages: [{ role: 'user', content: prompt }],
  });

  const content = (message.content[0] as any).text || '{}';
  const clean = content.replace(/```json|```/g, '').trim();

  try {
    const parsed = JSON.parse(clean);
    // Validar que el veredicto sea uno de los tres válidos
    if (!['CLIENT_WINS', 'CAREGIVER_WINS', 'PARTIAL'].includes(parsed.verdict)) {
      parsed.verdict = 'CLIENT_WINS'; // fallback conservador: si hay duda, favor al cliente
    }
    return parsed;
  } catch {
    logger.error('Failed to parse AI dispute resolution', { bookingId, content });
    // Fallback: sin evidencia clara → favor al cliente (el cuidador no documentó)
    return {
      verdict: 'CLIENT_WINS',
      analysis: 'El agente no pudo analizar el caso con certeza. Por política de GARDEN, ante la falta de evidencia documentada del servicio, se emite reembolso al cliente.',
      recommendations: [
        'Subir siempre fotos de inicio y fin del servicio',
        'Mantener comunicación activa en el chat de la app',
        'Activar el tracking GPS durante los paseos',
      ],
    };
  }
}

// ---------------------------------------------------------------------------
// Aplicar resolución automáticamente según las reglas definidas
// ---------------------------------------------------------------------------
async function applyResolution(bookingId: string, resolution: any, booking: any) {
  const totalAmount = Number(booking.totalAmount);
  const commission = Number(booking.commissionAmount ?? totalAmount * 0.10);
  const netAmount = totalAmount - commission; // 90% del total
  const caregiverUserId = booking.caregiver.userId;
  const clientId = booking.clientId;

  await (prisma as any).$transaction(async (tx: any) => {

    if (resolution.verdict === 'CAREGIVER_WINS') {
      // ── Pago completo al cuidador (90% del total) ──────────────────────────
      await tx.caregiverProfile.update({
        where: { userId: caregiverUserId },
        data: { balance: { increment: netAmount } },
      });
      await tx.walletTransaction.create({
        data: {
          userId: caregiverUserId,
          type: 'EARNING',
          amount: netAmount,
          balance: 0,
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
      await tx.clientProfile.update({
        where: { userId: clientId },
        data: { balance: { increment: totalAmount } },
      });
      await tx.walletTransaction.create({
        data: {
          userId: clientId,
          type: 'REFUND',
          amount: totalAmount,
          balance: 0,
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

      await tx.caregiverProfile.update({
        where: { userId: caregiverUserId },
        data: { balance: { increment: caregiverPayout } },
      });
      await tx.walletTransaction.create({
        data: {
          userId: caregiverUserId,
          type: 'EARNING',
          amount: caregiverPayout,
          balance: 0,
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

  // ── Registrar en blockchain según el veredicto ──────────────────────────
  try {
    if (resolution.verdict === 'CAREGIVER_WINS') {
      blockchainService.resolveDisputeCaregiverWinsOnChain(bookingId, netAmount).catch(err => {
        logger.error('Blockchain resolveDisputeCaregiverWins failed', { bookingId, err });
      });
    } else if (resolution.verdict === 'CLIENT_WINS') {
      blockchainService.resolveDisputeClientWinsOnChain(bookingId, totalAmount).catch(err => {
        logger.error('Blockchain resolveDisputeClientWins failed', { bookingId, err });
      });
    } else {
      const caregiverPayout = parseFloat((netAmount * 0.80).toFixed(2));
      const clientDiscountAmount = parseFloat((netAmount * 0.20).toFixed(2));
      blockchainService.resolvePartialOnChain(bookingId, caregiverPayout, clientDiscountAmount).catch(err => {
        logger.error('Blockchain resolvePartial failed', { bookingId, err });
      });
    }
  } catch (err) {
    logger.error('Blockchain dispatch error in applyResolution', { bookingId, err });
  }
}

export default router;
