import { Router, Request, Response } from 'express';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import { asyncHandler } from '../../shared/async-handler.js';
import prisma from '../../config/database.js';

const router = Router();

// GET /api/wallet — obtener saldo e historial del usuario autenticado
router.get('/', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const userId = (req as any).user.userId;
  const role = (req as any).user.role;

  let balance = 0;
  let bankName: string | null | undefined;
  let bankAccount: string | null | undefined;
  let bankHolder: string | null | undefined;
  let bankType: string | null | undefined;

  if (role === 'CAREGIVER') {
    const profile = await prisma.caregiverProfile.findUnique({
      where: { userId },
      select: {
        balance: true,
        bankName: true,
        bankAccount: true,
        bankHolder: true,
        bankType: true,
      },
    });
    balance = Number(profile?.balance ?? 0);
    bankName = profile?.bankName;
    bankAccount = profile?.bankAccount;
    bankHolder = profile?.bankHolder;
    bankType = profile?.bankType;
  } else if (role === 'CLIENT') {
    const profile = await prisma.clientProfile.findUnique({
      where: { userId },
      select: { balance: true },
    });
    balance = Number(profile?.balance ?? 0);
  }

  // Last 50 transactions for the history list
  const transactions = await prisma.walletTransaction.findMany({
    where: { userId },
    orderBy: { createdAt: 'desc' },
    take: 50,
  });

  // Aggregate lifetime stats from the DB — never from the truncated take:50 slice.
  const [earnedAgg, paidAgg, withdrawnAgg, pendingAgg] = await Promise.all([
    prisma.walletTransaction.aggregate({
      where: { userId, type: 'EARNING', status: 'COMPLETED' },
      _sum: { amount: true },
    }),
    prisma.walletTransaction.aggregate({
      where: { userId, type: 'PAYMENT', status: 'COMPLETED' },
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
  ]);

  const totalEarned = Number(earnedAgg._sum.amount ?? 0);
  const totalPaid = Number(paidAgg._sum.amount ?? 0);
  const totalWithdrawn = Number(withdrawnAgg._sum.amount ?? 0);
  const pendingWithdrawals = Number(pendingAgg._sum.amount ?? 0);

  res.json({
    success: true,
    data: {
      balance,
      totalEarned,
      totalPaid,
      totalWithdrawn,
      pendingWithdrawals,
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
      caregiverBankInfo: role === 'CAREGIVER' ? {
        bankName,
        bankAccount,
        bankHolder,
        bankType,
      } : null,
    },
  });
}));

// POST /api/wallet/withdraw — solicitar retiro (solo CAREGIVER)
router.post(
  '/withdraw',
  authMiddleware,
  requireRole('CAREGIVER'),
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

    // All checks (balance, bank info, duplicate pending) run inside a transaction
    // so there is no TOCTOU race between the check and the INSERT.
    let transactionId: string;
    let profileSnapshot: { bankName: string; bankAccount: string; bankHolder: string };

    try {
      await prisma.$transaction(async (tx) => {
        const profile = await tx.caregiverProfile.findUnique({
          where: { userId },
          select: { balance: true, bankName: true, bankAccount: true, bankHolder: true, bankType: true },
        });

        if (!profile?.bankName || !profile?.bankAccount || !profile?.bankHolder) {
          throw Object.assign(new Error('NO_BANK_INFO'), { code: 'NO_BANK_INFO' });
        }

        const currentBalance = Number(profile.balance ?? 0);
        if (parsedAmount > currentBalance) {
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
            description: `Retiro a ${profile.bankName} - ${profile.bankHolder} (${profile.bankAccount})`,
            status: 'PENDING',
          },
        });

        transactionId = txRecord.id;
        profileSnapshot = {
          bankName: profile.bankName,
          bankAccount: profile.bankAccount,
          bankHolder: profile.bankHolder,
        };
      });
    } catch (err: any) {
      if (err.code === 'NO_BANK_INFO') {
        return res.status(400).json({
          success: false,
          error: { message: 'Configura tus datos bancarios antes de solicitar un retiro' },
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

    // Notifications are non-critical — run outside the transaction
    const admins = await prisma.user.findMany({ where: { role: 'ADMIN' } });
    await Promise.all(admins.map(admin =>
      prisma.notification.create({
        data: {
          userId: admin.id,
          title: '💰 Solicitud de retiro',
          message: `${profileSnapshot!.bankHolder} solicita retirar Bs ${parsedAmount} a ${profileSnapshot!.bankName} (${profileSnapshot!.bankAccount})`,
          type: 'SYSTEM',
        },
      })
    ));

    await prisma.notification.create({
      data: {
        userId,
        title: '✅ Solicitud de retiro recibida',
        message:
          `Hemos recibido tu solicitud de retiro de Bs ${parsedAmount} a ${profileSnapshot!.bankName} (${profileSnapshot!.bankAccount} — ${profileSnapshot!.bankHolder}).\n\n` +
          `El depósito se realizará en un plazo máximo de 5 días hábiles de forma completamente gratuita.\n\n` +
          `Cuando el depósito sea confirmado, te lo notificaremos aquí. ¡Gracias por confiar en Garden!`,
        type: 'SYSTEM',
      },
    });

    res.json({
      success: true,
      data: { id: transactionId!, message: 'Solicitud enviada. El admin procesará tu retiro.' },
    });
  })
);

// POST /api/wallet/redeem — canjear código de regalo
router.post('/redeem', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const userId = (req as any).user.userId;
  const role = (req as any).user.role;
  const { code } = req.body;

  if (!code || typeof code !== 'string') {
    return res.status(400).json({ success: false, error: { message: 'Código requerido' } });
  }

  const normalizedCode = code.trim().toUpperCase();

  // Pre-flight check (fast reject before entering the transaction)
  const giftCode = await prisma.giftCode.findUnique({ where: { code: normalizedCode } });
  if (!giftCode || !giftCode.active) {
    return res.status(400).json({ success: false, error: { message: 'Código inválido o expirado' } });
  }
  if (giftCode.expiresAt && giftCode.expiresAt < new Date()) {
    return res.status(400).json({ success: false, error: { message: 'Código expirado' } });
  }

  const amount = Number(giftCode.amount);

  // All uniqueness checks are re-validated inside the transaction to prevent race conditions:
  // two simultaneous requests could both pass the pre-flight and both redeem without this guard.
  let newBalance = 0;
  try {
    await prisma.$transaction(async (tx) => {
      const fresh = await tx.giftCode.findUnique({ where: { code: normalizedCode } });
      if (!fresh || !fresh.active) {
        throw Object.assign(new Error('INVALID'), { code: 'INVALID' });
      }
      if (fresh.expiresAt && fresh.expiresAt < new Date()) {
        throw Object.assign(new Error('EXPIRED'), { code: 'EXPIRED' });
      }
      if (fresh.usedBy.includes(userId)) {
        throw Object.assign(new Error('ALREADY_USED'), { code: 'ALREADY_USED' });
      }
      if (fresh.usedBy.length >= fresh.maxUses) {
        throw Object.assign(new Error('EXHAUSTED'), { code: 'EXHAUSTED' });
      }

      if (role === 'CAREGIVER') {
        const updated = await tx.caregiverProfile.update({
          where: { userId },
          data: { balance: { increment: amount } },
          select: { balance: true },
        });
        newBalance = Number(updated.balance);
      } else if (role === 'CLIENT') {
        const updated = await tx.clientProfile.update({
          where: { userId },
          data: { balance: { increment: amount } },
          select: { balance: true },
        });
        newBalance = Number(updated.balance);
      } else {
        throw Object.assign(new Error('INVALID_ROLE'), { code: 'INVALID_ROLE' });
      }

      await tx.giftCode.update({
        where: { id: fresh.id },
        data: { usedBy: { push: userId } },
      });

      await tx.walletTransaction.create({
        data: {
          userId,
          type: 'REFUND',
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
      INVALID_ROLE: 'Tu tipo de cuenta no puede canjear códigos',
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
