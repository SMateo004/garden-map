import { Router } from 'express';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import * as caregiverProfileController from './caregiver-profile.controller.js';
import { asyncHandler } from '../../shared/async-handler.js';
import { prisma } from '../../config/database.js';
import multer from 'multer';

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 5 * 1024 * 1024 } });

const router = Router();

// Todas las rutas requieren auth + role CAREGIVER
router.use(authMiddleware);
router.use(requireRole('CAREGIVER'));

router.get('/my-profile', caregiverProfileController.getMyProfile);
router.patch('/profile', caregiverProfileController.patchProfile);
router.patch('/user-info', caregiverProfileController.patchUserInfo);
router.post('/submit', caregiverProfileController.submit);
router.post('/send-verify-email', caregiverProfileController.sendVerifyEmail);
router.post('/verify-email', caregiverProfileController.verifyEmail);
router.get('/availability', caregiverProfileController.getMyAvailability);
router.patch('/availability', caregiverProfileController.patchAvailability);
router.get('/bookings', caregiverProfileController.getMyBookingsAsCaregiver);
router.get('/notifications', caregiverProfileController.getNotifications);
router.patch('/notifications/:id/read', caregiverProfileController.markNotificationRead);

router.patch('/bank-info', authMiddleware, requireRole('CAREGIVER'),
  asyncHandler(async (req, res) => {
    const userId = (req as any).user.userId;
    const { bankName, bankAccount, bankHolder, bankType } = req.body;
    
    await prisma.caregiverProfile.update({
      where: { userId },
      data: { bankName, bankAccount, bankHolder, bankType },
    });
    
    res.json({ success: true, data: { message: 'Datos bancarios actualizados' } });
  })
);

router.post('/profile/service-photo', authMiddleware, requireRole('CAREGIVER'),
  upload.single('servicePhoto'),
  asyncHandler(async (req, res) => {
    const userId = (req as any).user.userId;
    const file = req.file;
    if (!file) return res.status(400).json({ success: false, error: { message: 'No se proporcionó foto' } });
    
    // Guardar en uploads/service-photos
    const fs = await import('fs/promises');
    const path = await import('path');
    const filename = `service-${userId}-${Date.now()}.jpg`;
    const uploadDir = path.join(process.cwd(), 'uploads', 'service-photos');
    await fs.mkdir(uploadDir, { recursive: true });
    await fs.writeFile(path.join(uploadDir, filename), file.buffer);
    
    const photoUrl = `${process.env.API_BASE_URL || 'http://localhost:3000'}/uploads/service-photos/${filename}`;
    
    // Obtener fotos actuales para no sobrescribir, sino agregar
    const profile = await prisma.caregiverProfile.findFirst({ where: { userId } });
    const currentPhotos = profile?.photos ?? [];
    if (currentPhotos.length >= 6) {
      return res.status(400).json({ success: false, error: { message: 'Máximo 6 fotos permitidas' } });
    }

    await prisma.caregiverProfile.update({
      where: { userId },
      data: { photos: [...currentPhotos, photoUrl] },
    });
    
    res.json({ success: true, data: { photoUrl } });
  })
);

router.post('/profile/photo', authMiddleware, requireRole('CAREGIVER'), 
  upload.single('photo'), 
  asyncHandler(async (req, res) => {
    const userId = (req as any).user.userId;
    const file = req.file;
    if (!file) {
      return res.status(400).json({ success: false, error: { message: 'No se proporcionó foto' } });
    }
    
    // Guardar en uploads/profile
    const fs = await import('fs/promises');
    const path = await import('path');
    const filename = `profile-${userId}-${Date.now()}.jpg`;
    const uploadDir = path.join(process.cwd(), 'uploads', 'profiles');
    await fs.mkdir(uploadDir, { recursive: true });
    await fs.writeFile(path.join(uploadDir, filename), file.buffer);
    
    const photoUrl = `${process.env.API_BASE_URL || 'http://localhost:3000'}/uploads/profiles/${filename}`;
    
    // Actualizar en DB tanto el perfil como el usuario para consistencia
    await prisma.$transaction([
      prisma.caregiverProfile.update({
        where: { userId },
        data: { profilePhoto: photoUrl },
      }),
      prisma.user.update({
        where: { id: userId },
        data: { profilePicture: photoUrl },
      }),
    ]);
    
    res.json({ success: true, data: { photoUrl } });
  })
);

router.get('/dashboard-stats', authMiddleware, requireRole('CAREGIVER'),
  asyncHandler(async (req, res) => {
    const userId = (req as any).user.userId;

    const profile = await prisma.caregiverProfile.findUnique({
      where: { userId },
      select: {
        id: true, balance: true, rating: true, reviewCount: true,
        onboardingStatus: true, profilePhoto: true, status: true,
      },
    });
    if (!profile) return res.status(404).json({ success: false });

    const now = new Date();
    const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
    const today = new Date(); today.setHours(0, 0, 0, 0);

    const [
      totalBookings, monthBookings, completedBookings, avgRatingAgg,
      pendingBookings, completedThisMonth, acceptedBookings, respondedBookings,
      nextBookingRaw, monthEarningsAgg, allTimeEarningsAgg,
    ] = await Promise.all([
      prisma.booking.count({ where: { caregiverId: profile.id } }),
      prisma.booking.count({ where: { caregiverId: profile.id, createdAt: { gte: startOfMonth } } }),
      prisma.booking.count({ where: { caregiverId: profile.id, status: 'COMPLETED' } }),
      prisma.booking.aggregate({
        where: { caregiverId: profile.id, ownerRating: { not: null } },
        _avg: { ownerRating: true },
      }),
      prisma.booking.count({
        where: { caregiverId: profile.id, status: { in: ['CONFIRMED', 'WAITING_CAREGIVER_APPROVAL'] } },
      }),
      prisma.booking.findMany({
        where: { caregiverId: profile.id, status: 'COMPLETED', createdAt: { gte: startOfMonth } },
        select: { serviceType: true, duration: true, totalDays: true },
      }),
      prisma.booking.count({
        where: { caregiverId: profile.id, status: { in: ['CONFIRMED', 'COMPLETED', 'IN_PROGRESS'] } },
      }),
      prisma.booking.count({
        where: {
          caregiverId: profile.id,
          status: { notIn: ['PENDING_PAYMENT', 'PAYMENT_PENDING_APPROVAL', 'CANCELLED'] },
        },
      }),
      prisma.booking.findFirst({
        where: {
          caregiverId: profile.id,
          status: 'CONFIRMED',
          OR: [{ walkDate: { gte: today } }, { startDate: { gte: today } }],
        },
        orderBy: [{ walkDate: 'asc' }, { startDate: 'asc' }],
        select: { walkDate: true, startDate: true, petName: true, serviceType: true, startTime: true },
      }),
      prisma.walletTransaction.aggregate({
        where: { userId, type: 'EARNING', createdAt: { gte: startOfMonth } },
        _sum: { amount: true },
      }),
      prisma.walletTransaction.aggregate({
        where: { userId, type: 'EARNING' },
        _sum: { amount: true },
      }),
    ]);

    // Horas trabajadas este mes (estimación)
    const hoursWorked = completedThisMonth.reduce((acc, b) => {
      if (b.serviceType === 'PASEO') return acc + (b.duration ?? 30) / 60;
      return acc + (b.totalDays ?? 1) * 8;
    }, 0);

    // Tasa de aceptación
    const acceptanceRate = respondedBookings > 0
      ? Math.round((acceptedBookings / respondedBookings) * 100)
      : 100;

    // Próxima reserva
    const nextBooking = nextBookingRaw ? {
      date: (nextBookingRaw.walkDate ?? nextBookingRaw.startDate)?.toISOString().substring(0, 10) ?? null,
      petName: nextBookingRaw.petName,
      serviceType: String(nextBookingRaw.serviceType),
      startTime: nextBookingRaw.startTime ?? null,
    } : null;

    // Completitud del perfil
    const profileCompleteness = (profile.onboardingStatus as any)?.percentage ?? 0;

    res.json({
      success: true,
      data: {
        // Campos existentes (retrocompat)
        balance: Number(profile.balance),
        totalBookings,
        monthBookings,
        completedBookings,
        avgRating: Number((avgRatingAgg._avg.ownerRating ?? profile.rating ?? 0).toFixed(1)),
        pendingBookings,
        monthEarnings: Number(monthEarningsAgg._sum.amount ?? 0),
        // Nuevos campos
        thisMonth: {
          bookings: monthBookings,
          earnings: Number(monthEarningsAgg._sum.amount ?? 0),
          hoursWorked: Math.round(hoursWorked * 10) / 10,
        },
        allTime: {
          bookings: totalBookings,
          earnings: Number(allTimeEarningsAgg._sum.amount ?? 0),
          rating: Number((avgRatingAgg._avg.ownerRating ?? profile.rating ?? 0).toFixed(1)),
          reviewCount: profile.reviewCount ?? 0,
        },
        acceptanceRate,
        nextBooking,
        profileCompleteness,
      },
    });
  })
);

export default router;
