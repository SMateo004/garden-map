import { Router, Request, Response } from 'express';
import { authMiddleware } from '../../middleware/auth.middleware.js';
import { asyncHandler } from '../../shared/async-handler.js';
import prisma from '../../config/database.js';

const router = Router();

// GET /api/wallet — obtener saldo e historial del usuario autenticado
router.get('/', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const userId = (req as any).user.userId;
  const role = (req as any).user.role;

  let balance = 0;

  if (role === 'CAREGIVER') {
    const profile = await prisma.caregiverProfile.findUnique({
      where: { userId },
      select: { balance: true },
    });
    balance = Number(profile?.balance ?? 0);
  } else if (role === 'CLIENT') {
    const profile = await prisma.clientProfile.findUnique({
      where: { userId },
      select: { balance: true },
    });
    balance = Number(profile?.balance ?? 0);
  }

  const transactions = await prisma.walletTransaction.findMany({
    where: { userId },
    orderBy: { createdAt: 'desc' },
    take: 50,
  });

  // Estadísticas
  const totalEarned = transactions
    .filter(t => t.type === 'EARNING' && t.status === 'COMPLETED')
    .reduce((sum, t) => sum + Number(t.amount), 0);
  
  const totalPaid = transactions
    .filter(t => t.type === 'PAYMENT' && t.status === 'COMPLETED')
    .reduce((sum, t) => sum + Number(t.amount), 0);

  const totalWithdrawn = transactions
    .filter(t => t.type === 'WITHDRAWAL' && t.status === 'COMPLETED')
    .reduce((sum, t) => sum + Number(t.amount), 0);

  const pendingWithdrawals = transactions
    .filter(t => t.type === 'WITHDRAWAL' && t.status === 'PENDING')
    .reduce((sum, t) => sum + Number(t.amount), 0);

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
    },
  });
}));

// POST /api/wallet/withdraw — solicitar retiro
router.post('/withdraw', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const userId = (req as any).user.userId;
  const role = (req as any).user.role;
  const { amount, bankName, accountNumber, accountHolder } = req.body;

  if (!amount || amount <= 0) {
    return res.status(400).json({ success: false, error: { message: 'Monto inválido' } });
  }

  // Verificar saldo
  let currentBalance = 0;
  if (role === 'CAREGIVER') {
    const profile = await prisma.caregiverProfile.findUnique({
      where: { userId }, select: { balance: true },
    });
    currentBalance = Number(profile?.balance ?? 0);
  }

  if (amount > currentBalance) {
    return res.status(400).json({ success: false, error: { message: 'Saldo insuficiente' } });
  }

  // Crear transacción pendiente y descontar saldo
  await prisma.$transaction(async (tx) => {
    await tx.caregiverProfile.update({
      where: { userId },
      data: { balance: { decrement: amount } },
    });

    await tx.walletTransaction.create({
      data: {
        userId,
        type: 'WITHDRAWAL',
        amount: amount,
        balance: currentBalance - amount,
        description: `Retiro a ${bankName} - ${accountHolder} (${accountNumber})`,
        status: 'PENDING',
      },
    });

    // Notificar al admin
    const admins = await tx.user.findMany({ where: { role: 'ADMIN' } });
    for (const admin of admins) {
      await tx.notification.create({
        data: {
          userId: admin.id,
          title: 'Solicitud de retiro',
          message: `Un cuidador solicitó retiro de Bs ${amount} a ${bankName}`,
          type: 'SYSTEM',
        },
      });
    }
  });

  res.json({ success: true, data: { message: 'Solicitud de retiro enviada. El admin procesará tu pago.' } });
}));

export default router;
