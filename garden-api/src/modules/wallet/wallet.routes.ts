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
      caregiverBankInfo: role === 'CAREGIVER' ? {
        bankName,
        bankAccount,
        bankHolder,
        bankType,
      } : null
    },
  });
}));

// POST /api/wallet/withdraw — solicitar retiro (flujo corregido)
router.post('/withdraw', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const userId = (req as any).user.userId;
  const { amount } = req.body;

  if (!amount || amount <= 0) {
    return res.status(400).json({ success: false, error: { message: 'Monto inválido' } });
  }

  // Verificar saldo disponible
  const profile = await prisma.caregiverProfile.findUnique({
    where: { userId },
    select: { balance: true, bankName: true, bankAccount: true, bankHolder: true, bankType: true },
  });

  if (!profile?.bankName || !profile?.bankAccount || !profile?.bankHolder) {
    return res.status(400).json({ 
      success: false, 
      error: { message: 'Configura tus datos bancarios antes de solicitar un retiro' } 
    });
  }

  const currentBalance = Number(profile.balance ?? 0);
  if (amount > currentBalance) {
    return res.status(400).json({ success: false, error: { message: 'Saldo insuficiente' } });
  }

  // Verificar que no haya retiro pendiente
  const pendingWithdrawal = await prisma.walletTransaction.findFirst({
    where: { userId, type: 'WITHDRAWAL', status: 'PENDING' },
  });

  if (pendingWithdrawal) {
    return res.status(400).json({ 
      success: false, 
      error: { message: 'Ya tienes una solicitud de retiro pendiente' } 
    });
  }

  // Crear solicitud SIN descontar saldo todavía
  const transaction = await prisma.walletTransaction.create({
    data: {
      userId,
      type: 'WITHDRAWAL',
      amount,
      balance: currentBalance, // saldo actual sin cambios
      description: `Retiro a ${profile.bankName} - ${profile.bankHolder} (${profile.bankAccount})`,
      status: 'PENDING',
    },
  });

  // Notificar al admin
  const admins = await prisma.user.findMany({ where: { role: 'ADMIN' } });
  for (const admin of admins) {
    await prisma.notification.create({
      data: {
        userId: admin.id,
        title: '💰 Solicitud de retiro',
        message: `${profile.bankHolder} solicita retirar Bs ${amount} a ${profile.bankName} (${profile.bankAccount})`,
        type: 'SYSTEM',
      },
    });
  }

  res.json({ 
    success: true, 
    data: { 
      id: transaction.id,
      message: 'Solicitud enviada. El admin procesará tu retiro.' 
    } 
  });
}));

async function getWalletStatsAndTransactions(userId: string) {
  const transactions = await prisma.walletTransaction.findMany({
    where: { userId },
    orderBy: { createdAt: 'desc' },
    take: 50,
  });

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
    .filter(t => t.type === 'WITHDRAWAL' && (t.status === 'PENDING' || t.status === 'PROCESSING'))
    .reduce((sum, t) => sum + Number(t.amount), 0);

  return {
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
  };
}

export default router;
