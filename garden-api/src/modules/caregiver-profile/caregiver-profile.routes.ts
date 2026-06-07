import { Router } from 'express';
import { z } from 'zod';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import * as caregiverProfileController from './caregiver-profile.controller.js';
import { asyncHandler } from '../../shared/async-handler.js';
import { prisma } from '../../config/database.js';
import multer from 'multer';
import { uploadImage } from '../../services/storage.service.js';
import logger from '../../shared/logger.js';

const bankInfoSchema = z.object({
  bankName: z.string().min(2, 'Nombre del banco requerido').max(100),
  bankAccount: z.string().min(4, 'Número de cuenta requerido').max(50).regex(/^[a-zA-Z0-9\-]+$/, 'Cuenta inválida'),
  bankHolder: z.string().min(2, 'Nombre del titular requerido').max(100),
  bankType: z.string().min(1, 'Tipo de cuenta requerido').max(50),
});

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 20 * 1024 * 1024 } });

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
    const parsed = bankInfoSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({
        success: false,
        error: { code: 'VALIDATION_ERROR', message: parsed.error.errors[0]?.message ?? 'Datos inválidos' },
      });
    }
    const userId = (req as any).user.userId;
    const { bankName, bankAccount, bankHolder, bankType } = parsed.data;

    await prisma.caregiverProfile.update({
      where: { userId },
      data: { bankName, bankAccount, bankHolder, bankType },
    });

    res.json({ success: true, data: { message: 'Datos bancarios actualizados' } });
  })
);

// ── Caregiver action photos (fotos del cuidador en acción — todos los servicios) ──────────────

const PLACE_PHOTO_SECTIONS = ['sala', 'descanso', 'alimentacion', 'jardin', 'juego'] as const;
type PlacePhotoSection = typeof PLACE_PHOTO_SECTIONS[number];

/** POST /profile/caregiver-photo — sube una foto del cuidador en acción. Máx 6. */
router.post('/profile/caregiver-photo', upload.single('caregiverPhoto'),
  asyncHandler(async (req, res) => {
    const userId = (req as any).user.userId;
    const file = req.file;
    if (!file) return res.status(400).json({ success: false, error: { message: 'No se proporcionó foto' } });
    if (!file.mimetype.startsWith('image/')) return res.status(400).json({ success: false, error: { message: 'Solo se permiten imágenes (JPG/PNG)' } });

    const profile = await prisma.caregiverProfile.findFirst({ where: { userId }, select: { caregiverPhotos: true } });
    if (!profile) return res.status(404).json({ success: false, error: { message: 'Perfil no encontrado' } });
    if ((profile.caregiverPhotos?.length ?? 0) >= 6) {
      return res.status(400).json({ success: false, error: { message: 'Máximo 6 fotos de cuidador permitidas' } });
    }

    const photoUrl = await uploadImage(file.buffer, { folder: 'caregivers', name: `caregiver_${userId}_${Date.now()}` });
    const updated = await prisma.caregiverProfile.update({
      where: { userId },
      data: { caregiverPhotos: { push: photoUrl } },
      select: { caregiverPhotos: true },
    });
    res.json({ success: true, data: { photoUrl, total: updated.caregiverPhotos.length } });
  })
);

/** DELETE /profile/caregiver-photo — elimina una foto del cuidador. Body: { photoUrl } */
router.delete('/profile/caregiver-photo',
  asyncHandler(async (req, res) => {
    const userId = (req as any).user.userId;
    const { photoUrl } = req.body as { photoUrl: string };
    if (!photoUrl) return res.status(400).json({ success: false, error: { message: 'photoUrl requerido' } });
    const profile = await prisma.caregiverProfile.findFirst({ where: { userId }, select: { caregiverPhotos: true } });
    if (!profile) return res.status(404).json({ success: false, error: { message: 'Perfil no encontrado' } });
    await prisma.caregiverProfile.update({
      where: { userId },
      data: { caregiverPhotos: { set: profile.caregiverPhotos.filter(p => p !== photoUrl) } },
    });
    res.json({ success: true });
  })
);

// ── Place photos por sección (solo HOSPEDAJE/GUARDERÍA) ───────────────────────────────────────

/** POST /profile/place-photo — sube una foto de una sección del hogar. Body field: section. Máx 3 por sección. */
router.post('/profile/place-photo', upload.single('placePhoto'),
  asyncHandler(async (req, res) => {
    const userId = (req as any).user.userId;
    const file = req.file;
    const section = req.body?.section as string;

    if (!file) return res.status(400).json({ success: false, error: { message: 'No se proporcionó foto' } });
    if (!file.mimetype.startsWith('image/')) return res.status(400).json({ success: false, error: { message: 'Solo se permiten imágenes (JPG/PNG)' } });
    if (!PLACE_PHOTO_SECTIONS.includes(section as PlacePhotoSection)) {
      return res.status(400).json({ success: false, error: { message: `Sección inválida. Debe ser: ${PLACE_PHOTO_SECTIONS.join(', ')}` } });
    }

    const profile = await prisma.caregiverProfile.findFirst({ where: { userId }, select: { placePhotos: true } });
    if (!profile) return res.status(404).json({ success: false, error: { message: 'Perfil no encontrado' } });

    const current = (profile.placePhotos ?? {}) as Record<string, string[]>;
    const sectionPhotos = current[section] ?? [];
    if (sectionPhotos.length >= 3) {
      return res.status(400).json({ success: false, error: { message: 'Máximo 3 fotos por sección' } });
    }

    const photoUrl = await uploadImage(file.buffer, { folder: 'caregivers/place', name: `place_${section}_${userId}_${Date.now()}` });
    const updated = { ...current, [section]: [...sectionPhotos, photoUrl] };
    await prisma.caregiverProfile.update({ where: { userId }, data: { placePhotos: updated } });

    res.json({ success: true, data: { photoUrl, section, total: (updated[section] ?? []).length } });
  })
);

/** DELETE /profile/place-photo — elimina una foto de sección. Body: { section, photoUrl } */
router.delete('/profile/place-photo',
  asyncHandler(async (req, res) => {
    const userId = (req as any).user.userId;
    const { section, photoUrl } = req.body as { section: string; photoUrl: string };
    if (!section || !photoUrl) return res.status(400).json({ success: false, error: { message: 'section y photoUrl requeridos' } });

    const profile = await prisma.caregiverProfile.findFirst({ where: { userId }, select: { placePhotos: true } });
    if (!profile) return res.status(404).json({ success: false, error: { message: 'Perfil no encontrado' } });

    const current = (profile.placePhotos ?? {}) as Record<string, string[]>;
    const updated = { ...current, [section]: (current[section] ?? []).filter((p: string) => p !== photoUrl) };
    await prisma.caregiverProfile.update({ where: { userId }, data: { placePhotos: updated } });

    res.json({ success: true });
  })
);

// ── (legacy) service-photo ────────────────────────────────────────────────────────────────────
router.post('/profile/service-photo', upload.single('servicePhoto'),
  asyncHandler(async (req, res) => {
    const userId = (req as any).user.userId;
    const file = req.file;
    if (!file) return res.status(400).json({ success: false, error: { message: 'No se proporcionó foto' } });
    if (!file.mimetype.startsWith('image/')) {
      return res.status(400).json({ success: false, error: { message: 'Solo se permiten imágenes (JPG/PNG)' } });
    }

    // Pre-flight count check (fast reject before uploading)
    const profile = await prisma.caregiverProfile.findFirst({ where: { userId }, select: { photos: true } });
    if (!profile) return res.status(404).json({ success: false, error: { message: 'Perfil no encontrado' } });
    if ((profile.photos?.length ?? 0) >= 6) {
      return res.status(400).json({ success: false, error: { message: 'Máximo 6 fotos permitidas' } });
    }

    const photoUrl = await uploadImage(file.buffer, {
      folder: 'caregivers',
      name: `service_${userId}_${Date.now()}`,
    });

    const updatedProfile = await prisma.caregiverProfile.update({
      where: { userId },
      data: { photos: { push: photoUrl } },
      select: { photos: true },
    });

    res.json({ success: true, data: { photoUrl, totalPhotos: updatedProfile.photos.length } });
  })
);

router.post('/profile/walker-photo', authMiddleware, requireRole('CAREGIVER'),
  upload.single('walkerPhoto'),
  asyncHandler(async (req, res) => {
    const userId = (req as any).user.userId;
    const file = req.file;
    if (!file) return res.status(400).json({ success: false, error: { message: 'No se proporcionó foto' } });
    if (!file.mimetype.startsWith('image/')) {
      return res.status(400).json({ success: false, error: { message: 'Solo se permiten imágenes (JPG/PNG)' } });
    }

    const profile = await prisma.caregiverProfile.findFirst({ where: { userId }, select: { walkerPhotos: true } });
    if (!profile) return res.status(404).json({ success: false, error: { message: 'Perfil no encontrado' } });
    if (((profile as any).walkerPhotos?.length ?? 0) >= 4) {
      return res.status(400).json({ success: false, error: { message: 'Máximo 4 fotos permitidas' } });
    }

    const photoUrl = await uploadImage(file.buffer, {
      folder: 'caregivers',
      name: `walker_${userId}_${Date.now()}`,
    });

    const updatedProfile = await prisma.caregiverProfile.update({
      where: { userId },
      data: { walkerPhotos: { push: photoUrl } } as any,
      select: { walkerPhotos: true } as any,
    });

    res.json({ success: true, data: { photoUrl, totalPhotos: (updatedProfile as any).walkerPhotos.length } });
  })
);

router.delete('/profile/walker-photo', authMiddleware, requireRole('CAREGIVER'),
  asyncHandler(async (req, res) => {
    const userId = (req as any).user.userId;
    const { photoUrl } = req.body as { photoUrl: string };
    if (!photoUrl) return res.status(400).json({ success: false, error: { message: 'photoUrl requerido' } });

    const profile = await prisma.caregiverProfile.findFirst({ where: { userId }, select: { walkerPhotos: true } });
    if (!profile) return res.status(404).json({ success: false, error: { message: 'Perfil no encontrado' } });

    const updatedPhotos = ((profile as any).walkerPhotos as string[]).filter((p: string) => p !== photoUrl);
    await prisma.caregiverProfile.update({
      where: { userId },
      data: { walkerPhotos: { set: updatedPhotos } } as any,
    });

    res.json({ success: true, data: { message: 'Foto eliminada' } });
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

    const photoUrl = await uploadImage(file.buffer, {
      folder: 'caregivers',
      name: `profile-${userId}-${Date.now()}`,
    });

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
        select: { id: true, walkDate: true, startDate: true, petName: true, serviceType: true, startTime: true },
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
      id: nextBookingRaw.id,
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

/**
 * GET /api/caregiver/bookings/:bookingId/pet
 * Devuelve el perfil completo de la mascota asociada a una reserva del cuidador.
 * Solo accesible para reservas en estado WAITING_CAREGIVER_APPROVAL, CONFIRMED o IN_PROGRESS.
 */
router.get('/bookings/:bookingId/pet', asyncHandler(async (req, res) => {
  const userId = (req as any).user.userId;
  const { bookingId } = req.params;

  // Obtener el perfil del cuidador
  const caregiverProfile = await prisma.caregiverProfile.findFirst({
    where: { userId },
    select: { id: true },
  });
  if (!caregiverProfile) {
    return res.status(404).json({ success: false, error: { message: 'Perfil de cuidador no encontrado' } });
  }

  // Verificar que la reserva pertenece a este cuidador y está en un estado permitido
  const booking = await prisma.booking.findFirst({
    where: {
      id: bookingId,
      caregiverId: caregiverProfile.id,
      status: { in: ['WAITING_CAREGIVER_APPROVAL', 'CONFIRMED', 'IN_PROGRESS'] },
    },
    select: { petId: true },
  });
  if (!booking) {
    return res.status(404).json({ success: false, error: { message: 'Reserva no encontrada o acceso no permitido' } });
  }
  if (!booking.petId) {
    return res.status(404).json({ success: false, error: { message: 'Esta reserva no tiene mascota asociada' } });
  }

  // Obtener perfil completo de la mascota
  const pet = await prisma.pet.findUnique({
    where: { id: booking.petId },
    select: {
      id: true,
      name: true,
      breed: true,
      age: true,
      size: true,
      photoUrl: true,
      specialNeeds: true,
      notes: true,
      gender: true,
      weight: true,
      color: true,
      sterilized: true,
      microchipNumber: true,
      extraPhotos: true,
      vaccinePhotos: true,
      documents: true,
    },
  });
  if (!pet) {
    return res.status(404).json({ success: false, error: { message: 'Mascota no encontrada' } });
  }

  res.json({ success: true, data: pet });
}));

export default router;
