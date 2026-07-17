import { Router, Request, Response } from 'express';
import multer from 'multer';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import { asyncHandler } from '../../shared/async-handler.js';
import prisma from '../../config/database.js';
import { track } from '../../shared/analytics.js';
import { uploadImage } from '../../services/storage.service.js';
import { assertImageBuffer } from '../../shared/mime-validation.js';
import { validateBankInfo, persistBankInfo, isPhoneBasedBankType } from './bank-info.util.js';

const router = Router();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 20 * 1024 * 1024 } });

// ──────────────────────────────────────────────────────────────────────────────
// GET /api/wallet — saldo e historial del usuario autenticado (CLIENT o CAREGIVER)
// ──────────────────────────────────────────────────────────────────────────────
router.get('/', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const userId = (req as any).user.userId;

  // Unified balance lives on User
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: {
      balance: true,
      bankName: true,
      bankAccount: true,
      bankHolder: true,
      bankType: true,
      withdrawalMethod: true,
    },
  });

  const currentQr = await prisma.withdrawalQr.findFirst({
    where: { userId, isCurrent: true },
    orderBy: { createdAt: 'desc' },
  });

  const balance = Number(user?.balance ?? 0);

  // Last 50 transactions for the history list
  const transactions = await prisma.walletTransaction.findMany({
    where: { userId },
    orderBy: { createdAt: 'desc' },
    take: 50,
  });

  // Aggregate lifetime stats
  const [earnedAgg, paidAgg, withdrawnAgg, pendingAgg, refundAgg] = await Promise.all([
    prisma.walletTransaction.aggregate({
      where: { userId, type: 'EARNING', status: 'COMPLETED' },
      _sum: { amount: true },
    }),
    prisma.walletTransaction.aggregate({
      where: { userId, type: { in: ['PAYMENT', 'WALLET_PAYMENT'] }, status: 'COMPLETED' },
      _sum: { amount: true },
    }),
    prisma.walletTransaction.aggregate({
      where: { userId, type: 'WITHDRAWAL', status: 'COMPLETED' },
      _sum: { amount: true },
    }),
    prisma.walletTransaction.aggregate({
      where: { userId, type: 'WITHDRAWAL', status: { in: ['PENDING', 'PROCESSING'] } },
      _sum: { amount: true },
    }),
    prisma.walletTransaction.aggregate({
      where: { userId, type: 'REFUND', status: 'COMPLETED' },
      _sum: { amount: true },
    }),
  ]);

  const totalEarned   = Number(earnedAgg._sum.amount    ?? 0);
  const totalPaid     = Number(paidAgg._sum.amount      ?? 0);
  const totalWithdrawn = Number(withdrawnAgg._sum.amount ?? 0);
  const pendingWithdrawals = Number(pendingAgg._sum.amount ?? 0);
  const totalRefunds  = Number(refundAgg._sum.amount    ?? 0);

  const availableBalance = Math.max(0, balance - pendingWithdrawals);

  res.json({
    success: true,
    data: {
      balance,
      availableBalance,
      totalEarned,
      totalPaid,
      totalWithdrawn,
      pendingWithdrawals,
      totalRefunds,
      transactions: transactions.map(t => ({
        id: t.id,
        type: t.type,
        amount: Number(t.amount),
        balance: Number(t.balance),
        description: t.description,
        bookingId: t.bookingId,
        status: t.status,
        createdAt: t.createdAt.toISOString(),
      })),
      bankInfo: user?.bankName ? {
        bankName:    user.bankName,
        bankAccount: user.bankAccount,
        bankHolder:  user.bankHolder,
        bankType:    user.bankType,
        isPhoneBased: isPhoneBasedBankType(user.bankType),
      } : null,
      withdrawalMethod: user?.withdrawalMethod ?? 'BANK_TRANSFER',
      qrInfo: currentQr ? {
        imageUrl:  currentQr.imageUrl,
        updatedAt: currentQr.createdAt.toISOString(),
      } : null,
    },
  });
}));

// ──────────────────────────────────────────────────────────────────────────────
// PUT /api/wallet/withdrawal-method — elegir modalidad de retiro (CLIENT o CAREGIVER)
// ──────────────────────────────────────────────────────────────────────────────
router.put('/withdrawal-method', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const userId = (req as any).user.userId;
  const { withdrawalMethod } = req.body;

  if (!['BANK_TRANSFER', 'QR_TRANSFER'].includes(withdrawalMethod)) {
    return res.status(400).json({
      success: false,
      error: { message: 'withdrawalMethod inválido. Debe ser BANK_TRANSFER o QR_TRANSFER' },
    });
  }

  await prisma.user.update({
    where: { id: userId },
    data: { withdrawalMethod },
  });

  res.json({ success: true, data: { withdrawalMethod } });
}));

// ──────────────────────────────────────────────────────────────────────────────
// POST /api/wallet/withdrawal-qr — subir/reemplazar el QR de cobro propio (CLIENT o CAREGIVER)
// ──────────────────────────────────────────────────────────────────────────────
router.post('/withdrawal-qr', authMiddleware, upload.single('qrImage'),
  asyncHandler(async (req: Request, res: Response) => {
    const userId = (req as any).user.userId;
    const file = req.file;
    if (!file) return res.status(400).json({ success: false, error: { message: 'No se proporcionó imagen de QR' } });
    if (!file.mimetype.startsWith('image/')) {
      return res.status(400).json({ success: false, error: { message: 'Solo se permiten imágenes (JPG/PNG)' } });
    }
    await assertImageBuffer(file.buffer);

    const imageUrl = await uploadImage(file.buffer, { folder: 'withdrawal-qr', name: `qr_${userId}_${Date.now()}` });

    // Se mantiene historial (isCurrent) en vez de sobreescribir un solo campo,
    // para poder auditar qué QR se usó ante una disputa sobre un retiro ya
    // procesado — ver comentario en el modelo WithdrawalQr.
    const qr = await prisma.$transaction(async (tx) => {
      await tx.withdrawalQr.updateMany({ where: { userId, isCurrent: true }, data: { isCurrent: false } });
      return tx.withdrawalQr.create({ data: { userId, imageUrl, isCurrent: true } });
    });

    res.json({
      success: true,
      data: { imageUrl: qr.imageUrl, updatedAt: qr.createdAt.toISOString(), message: 'QR de cobro actualizado' },
    });
  })
);

// ──────────────────────────────────────────────────────────────────────────────
// PUT /api/wallet/bank — actualizar datos bancarios (CLIENT o CAREGIVER)
// ──────────────────────────────────────────────────────────────────────────────
router.put('/bank', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const userId = (req as any).user.userId;
  const { bankName, bankAccount, bankHolder, bankType } = req.body;

  const validationError = validateBankInfo({ bankName, bankAccount, bankHolder, bankType });
  if (validationError) {
    return res.status(400).json({ success: false, error: validationError });
  }

  const role = (req as any).user.role;
  await persistBankInfo(userId, role, { bankName, bankAccount, bankHolder, bankType });

  res.json({ success: true, data: { message: 'Datos bancarios actualizados' } });
}));

// ──────────────────────────────────────────────────────────────────────────────
// POST /api/wallet/withdraw — solicitar retiro (CLIENT o CAREGIVER)
// ──────────────────────────────────────────────────────────────────────────────
router.post(
  '/withdraw',
  authMiddleware,
  asyncHandler(async (req: Request, res: Response) => {
    const userId = (req as any).user.userId;
    const { amount } = req.body;

    const { getBoolSetting, getNumericSetting } = await import('../../utils/settings-cache.js');
    if (!await getBoolSetting('retirosEnabled', true)) {
      return res.status(503).json({
        success: false,
        error: { code: 'RETIROS_DISABLED', message: 'Los retiros están temporalmente deshabilitados. Inténtalo más tarde.' },
      });
    }

    const parsedAmount = Number(amount);
    if (!parsedAmount || parsedAmount <= 0 || !Number.isFinite(parsedAmount)) {
      return res.status(400).json({ success: false, error: { message: 'Monto inválido' } });
    }

    const montoMinimo = await getNumericSetting('montoMinimoRetiro', 50);
    if (parsedAmount < montoMinimo) {
      return res.status(400).json({
        success: false,
        error: { message: `El monto mínimo de retiro es Bs ${montoMinimo}` },
      });
    }

    let transactionId: string;
    // Snapshot de a dónde se envía el dinero — texto legible para notificaciones,
    // independientemente de la modalidad elegida (transferencia bancaria o QR).
    let destinationSummary: string;
    let destinationDetail: string;

    try {
      await prisma.$transaction(async (tx) => {
        // Lock this user's row for the rest of the transaction — without this,
        // two near-simultaneous withdrawal requests (double-tap, retry, two
        // devices) can both read "no pending withdrawal yet" under Postgres's
        // default Read Committed isolation and both proceed to create one,
        // exceeding the real balance. The lock serializes them: the second
        // request blocks here until the first commits, then re-reads fresh state.
        await tx.$queryRaw`SELECT id FROM "users" WHERE id = ${userId} FOR UPDATE`;

        const user = await tx.user.findUnique({
          where: { id: userId },
          select: {
            balance: true, bankName: true, bankAccount: true, bankHolder: true, bankType: true,
            withdrawalMethod: true,
          },
        });

        let description: string;

        if (user?.withdrawalMethod === 'QR_TRANSFER') {
          const currentQr = await tx.withdrawalQr.findFirst({
            where: { userId, isCurrent: true },
            orderBy: { createdAt: 'desc' },
          });
          if (!currentQr) {
            throw Object.assign(new Error('NO_QR_INFO'), { code: 'NO_QR_INFO' });
          }
          description = `Retiro vía QR de transferencia (QR subido el ${currentQr.createdAt.toLocaleDateString('es-BO')})`;
          destinationSummary = 'tu QR de transferencia';
          destinationDetail = currentQr.imageUrl;
        } else {
          if (!user?.bankName || !user?.bankAccount || !user?.bankHolder) {
            throw Object.assign(new Error('NO_BANK_INFO'), { code: 'NO_BANK_INFO' });
          }
          description = `Retiro a ${user.bankName} - ${user.bankHolder} (${user.bankAccount})`;
          destinationSummary = `${user.bankName} (${user.bankAccount})`;
          destinationDetail = `${user.bankName} (${user.bankAccount} — ${user.bankHolder})`;
        }

        const currentBalance = Number(user!.balance ?? 0);

        // Calculate pending withdrawals to avoid double-spending
        const pendingAgg = await tx.walletTransaction.aggregate({
          where: { userId, type: 'WITHDRAWAL', status: { in: ['PENDING', 'PROCESSING'] } },
          _sum: { amount: true },
        });
        const pendingAmount = Number(pendingAgg._sum.amount ?? 0);
        const availableBalance = Math.max(0, currentBalance - pendingAmount);

        if (parsedAmount > availableBalance) {
          throw Object.assign(new Error('INSUFFICIENT_BALANCE'), { code: 'INSUFFICIENT_BALANCE' });
        }

        const existing = await tx.walletTransaction.findFirst({
          where: { userId, type: 'WITHDRAWAL', status: { in: ['PENDING', 'PROCESSING'] } },
        });
        if (existing) {
          throw Object.assign(new Error('ALREADY_PENDING'), { code: 'ALREADY_PENDING' });
        }

        const txRecord = await tx.walletTransaction.create({
          data: {
            userId,
            type: 'WITHDRAWAL',
            amount: parsedAmount,
            balance: currentBalance,
            description,
            status: 'PENDING',
          },
        });

        transactionId = txRecord.id;
      });
    } catch (err: any) {
      if (err.code === 'NO_BANK_INFO') {
        return res.status(400).json({
          success: false,
          error: { message: 'Configura tus datos bancarios antes de solicitar un retiro' },
        });
      }
      if (err.code === 'NO_QR_INFO') {
        return res.status(400).json({
          success: false,
          error: { message: 'Sube tu QR de cobro antes de solicitar un retiro' },
        });
      }
      if (err.code === 'INSUFFICIENT_BALANCE') {
        return res.status(400).json({ success: false, error: { message: 'Saldo insuficiente' } });
      }
      if (err.code === 'ALREADY_PENDING') {
        return res.status(400).json({
          success: false,
          error: { message: 'Ya tienes una solicitud de retiro pendiente' },
        });
      }
      throw err;
    }

    // Notify admins and the user (non-critical — outside transaction)
    const requester = await prisma.user.findUnique({ where: { id: userId }, select: { firstName: true, lastName: true } });
    const requesterName = requester ? `${requester.firstName} ${requester.lastName}` : 'Un usuario';

    const admins = await prisma.user.findMany({ where: { role: 'ADMIN' } });
    await Promise.all(admins.map(admin =>
      prisma.notification.create({
        data: {
          userId: admin.id,
          title: '💰 Solicitud de retiro',
          message: `${requesterName} solicita retirar Bs ${parsedAmount} a ${destinationDetail!}`,
          type: 'SYSTEM',
        },
      })
    ));

    await prisma.notification.create({
      data: {
        userId,
        title: '✅ Solicitud de retiro recibida',
        message:
          `Hemos recibido tu solicitud de retiro de Bs ${parsedAmount} a ${destinationSummary!}.\n\n` +
          `El depósito se realizará en un plazo máximo de 5 días hábiles de forma completamente gratuita.\n\n` +
          `Cuando el depósito sea confirmado, te lo notificaremos aquí. ¡Gracias por confiar en Garden!`,
        type: 'SYSTEM',
      },
    });

    track(userId, 'withdrawal_requested', {
      transactionId: transactionId!,
      amount: parsedAmount,
      destination: destinationSummary!,
    });

    res.json({
      success: true,
      data: { id: transactionId!, message: 'Solicitud enviada. Procesaremos tu retiro pronto.' },
    });
  })
);

// ──────────────────────────────────────────────────────────────────────────────
// POST /api/wallet/redeem — canjear código de regalo (CLIENT o CAREGIVER)
// ──────────────────────────────────────────────────────────────────────────────
router.post('/redeem', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const userId = (req as any).user.userId;
  const { code } = req.body;

  if (!code || typeof code !== 'string') {
    return res.status(400).json({ success: false, error: { message: 'Código requerido' } });
  }

  const normalizedCode = code.trim().toUpperCase();

  const giftCode = await prisma.giftCode.findUnique({ where: { code: normalizedCode } });
  if (!giftCode || !giftCode.active) {
    return res.status(400).json({ success: false, error: { message: 'Código inválido o expirado' } });
  }
  if (giftCode.expiresAt && giftCode.expiresAt < new Date()) {
    return res.status(400).json({ success: false, error: { message: 'Código expirado' } });
  }

  const amount = Number(giftCode.amount);
  let newBalance = 0;

  try {
    await prisma.$transaction(async (tx) => {
      const fresh = await tx.giftCode.findUnique({ where: { code: normalizedCode } });
      if (!fresh || !fresh.active) throw Object.assign(new Error('INVALID'), { code: 'INVALID' });
      if (fresh.expiresAt && fresh.expiresAt < new Date()) throw Object.assign(new Error('EXPIRED'), { code: 'EXPIRED' });
      if (fresh.usedBy.includes(userId)) throw Object.assign(new Error('ALREADY_USED'), { code: 'ALREADY_USED' });
      if (fresh.usedBy.length >= fresh.maxUses) throw Object.assign(new Error('EXHAUSTED'), { code: 'EXHAUSTED' });

      const updated = await tx.user.update({
        where: { id: userId },
        data: { balance: { increment: amount } },
        select: { balance: true },
      });
      newBalance = Number(updated.balance);

      await tx.giftCode.update({
        where: { id: fresh.id },
        data: { usedBy: { push: userId } },
      });

      await tx.walletTransaction.create({
        data: {
          userId,
          type: 'GIFT',
          amount,
          balance: newBalance,
          description: `Código de regalo: ${normalizedCode}`,
          status: 'COMPLETED',
        },
      });
    });
  } catch (err: any) {
    const codeMap: Record<string, string> = {
      INVALID: 'Código inválido o expirado',
      EXPIRED: 'Código expirado',
      ALREADY_USED: 'Ya usaste este código',
      EXHAUSTED: 'Código agotado',
    };
    const msg = codeMap[err.code];
    if (msg) return res.status(400).json({ success: false, error: { message: msg } });
    throw err;
  }

  res.json({
    success: true,
    data: { amount, balance: newBalance, message: `¡Recibiste Bs ${amount} de regalo!` },
  });
}));

export default router;
