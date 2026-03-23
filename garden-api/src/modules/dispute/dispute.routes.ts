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

    // Verificar que el cliente es el titular de la reserva
    const booking = await prisma.booking.findFirst({
      where: { id: bookingId, clientId: userId },
      include: { caregiver: { include: { user: true } } },
    });
    if (!booking) return res.status(404).json({ success: false, error: { message: 'Reserva no encontrada' } });

    // Crear o actualizar disputa
    const dispute = await (prisma as any).dispute.upsert({
      where: { bookingId },
      create: { bookingId, clientReasons: reasons, status: 'PENDING_CAREGIVER' },
      update: { clientReasons: reasons, status: 'PENDING_CAREGIVER' },
    });

    // Notificar al cuidador
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

// POST /api/disputes/:bookingId/caregiver-response — cuidador responde
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

    // Actualizar con respuesta del cuidador
    await prisma.dispute.update({
      where: { bookingId },
      data: { caregiverResponse: responses, status: 'PENDING_AI' },
    });

    // Llamar al agente de IA para resolver
    const resolution = await resolveDisputeWithAI(
      (booking as any).dispute!.clientReasons,
      responses,
      bookingId!,
      Number((booking as any).totalAmount),
    );

    // Aplicar resolución
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

async function resolveDisputeWithAI(
  clientReasons: string[],
  caregiverResponses: string[],
  bookingId: string,
  amount: number,
) {
  const prompt = `Eres el agente de resolución de disputas de GARDEN, una plataforma de cuidado de mascotas en Santa Cruz de la Sierra, Bolivia.

Una reserva terminó con calificación menor a 3 estrellas y hay una disputa.

RAZONES DEL DUEÑO DE LA MASCOTA:
${clientReasons.map(r => `- ${r}`).join('\n')}

RESPUESTAS DEL CUIDADOR:
${caregiverResponses.map(r => `- ${r}`).join('\n')}

MONTO EN DISPUTA: Bs ${amount}

Analiza objetivamente ambas versiones y determina:
1. VEREDICTO: ¿Quién tiene razón? Responde SOLO con "CLIENT_WINS", "CAREGIVER_WINS" o "PARTIAL"
2. ANÁLISIS: Explica en 2-3 oraciones tu razonamiento
3. RECOMENDACIONES: Si el cuidador pierde total o parcialmente, da 3 recomendaciones específicas para mejorar su servicio, reputación y precios en Santa Cruz

Responde SOLO en este formato JSON exacto:
{
  "verdict": "CLIENT_WINS" | "CAREGIVER_WINS" | "PARTIAL",
  "analysis": "texto del análisis",
  "recommendations": ["recomendación 1", "recomendación 2", "recomendación 3"]
}`;

  const message = await anthropic.messages.create({
    model: 'claude-sonnet-4-6',
    max_tokens: 1000,
    messages: [{ role: 'user', content: prompt }],
  });

  const content = (message.content[0] as any).text || '{}';
  const clean = content.replace(/```json|```/g, '').trim();
  
  try {
    return JSON.parse(clean);
  } catch {
    return {
      verdict: 'PARTIAL',
      analysis: 'No se pudo determinar con certeza. Se aplicará resolución parcial.',
      recommendations: ['Mejorar comunicación con el dueño', 'Revisar precios', 'Actualizar perfil'],
    };
  }
}

async function applyResolution(bookingId: string, resolution: any, booking: any) {
  const amount = Number(booking.totalAmount);
  const commission = Number(booking.commissionAmount ?? 0);
  const netAmount = amount - commission;
  const caregiverUserId = booking.caregiver.userId;
  const clientId = booking.clientId;

  await (prisma as any).$transaction(async (tx: any) => {
    // Actualizar disputa
    await tx.dispute.update({
      where: { bookingId },
      data: {
        aiVerdict: resolution.verdict,
        aiAnalysis: resolution.analysis,
        aiRecommendations: JSON.stringify(resolution.recommendations),
        status: 'RESOLVED',
        resolution: resolution.verdict === 'CLIENT_WINS'
          ? 'Reembolso completo al cliente'
          : resolution.verdict === 'CAREGIVER_WINS'
            ? 'Pago completo al cuidador'
            : 'Resolución parcial',
      },
    });

    if (resolution.verdict === 'CAREGIVER_WINS') {
      // Pagar al cuidador normalmente
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
          description: `Disputa resuelta a tu favor - Reserva #${bookingId.slice(0, 8)}`,
          status: 'COMPLETED',
        },
      });
      // Notificar al cuidador
      await tx.notification.create({
        data: {
          userId: caregiverUserId,
          title: '✅ Disputa resuelta a tu favor',
          message: `La IA de GARDEN analizó el caso y determinó que tienes razón. Recibirás Bs ${netAmount} en tu billetera.`,
          type: 'SYSTEM',
        },
      });
      // Notificar al cliente
      await tx.notification.create({
        data: {
          userId: clientId,
          title: 'Disputa resuelta',
          message: `La IA de GARDEN analizó el caso. El veredicto fue a favor del cuidador. ${resolution.analysis}`,
          type: 'SYSTEM',
        },
      });
    } else if (resolution.verdict === 'CLIENT_WINS') {
      // Reembolso completo al cliente (incluyendo comisión)
      await tx.clientProfile.update({
        where: { userId: clientId },
        data: { balance: { increment: amount } }, // reembolso completo
      });
      await tx.walletTransaction.create({
        data: {
          userId: clientId,
          type: 'REFUND',
          amount: amount,
          balance: 0,
          description: `Reembolso por disputa - Reserva #${bookingId.slice(0, 8)}`,
          status: 'COMPLETED',
        },
      });
      // Notificar al cliente
      await tx.notification.create({
        data: {
          userId: clientId,
          title: '✅ Reembolso aprobado',
          message: `La IA de GARDEN analizó el caso y aprobó tu reembolso de Bs ${amount} (incluyendo comisión).`,
          type: 'SYSTEM',
        },
      });
      // Notificar al cuidador con recomendaciones
      const recs = resolution.recommendations?.join(', ') ?? '';
      await tx.notification.create({
        data: {
          userId: caregiverUserId,
          title: '⚠️ Disputa resuelta - Recomendaciones',
          message: `La disputa se resolvió a favor del cliente. Recomendaciones: ${recs}`,
          type: 'SYSTEM',
        },
      });
    }

    // Marcar booking como completado y pagado en BD si no fue cliente quien gano completamente
    await tx.booking.update({
      where: { id: bookingId },
      data: { 
        status: resolution.verdict === 'CLIENT_WINS' ? 'CANCELLED' : 'COMPLETED',
        payoutStatus: resolution.verdict === 'CLIENT_WINS' ? 'REFUNDED' : 'PAID'
      },
    });
  });

  // Fuera de la transaccion ejecutamos el Smart Contract
  if (resolution.verdict === 'CAREGIVER_WINS') {
    blockchainService.finalizeBookingOnChain(bookingId, booking.ownerRating || 5).catch(err => {
      logger.error('Blockchain completion failed (caregiver wins)', { bookingId, err });
    });
  } else if (resolution.verdict === 'CLIENT_WINS') {
    blockchainService.cancelBookingOnChain(bookingId, 'Resolución de disputa a favor del cliente').catch(err => {
      logger.error('Blockchain cancel failed (client wins)', { bookingId, err });
    });
  } else {
    // Si fue empate o parcial, decidimos cerrar liberando pago al cuidador (por simplicar el escrow MVP)
    blockchainService.finalizeBookingOnChain(bookingId, booking.ownerRating || 5).catch(err => {
      logger.error('Blockchain completion failed (partial)', { bookingId, err });
    });
  }
}

export default router;
