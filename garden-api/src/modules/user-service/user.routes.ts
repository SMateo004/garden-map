import { Router } from 'express';
import { getById } from './user.service.js';
import { NotFoundError } from '../../shared/errors.js';
import { asyncHandler } from '../../shared/async-handler.js';
import { authMiddleware } from '../../middleware/auth.middleware.js';

const router = Router();

/**
 * GET /api/users/:id — antes no tenía NINGÚN middleware de auth: cualquiera
 * sin sesión podía pedir email/teléfono/fecha de nacimiento/dirección de
 * cualquier usuario solo con su UUID (obtenible de listados de cuidadores,
 * chats o reservas). Ahora requiere sesión, y solo se devuelven los datos
 * completos si el solicitante pide SU PROPIO id — para cualquier otro
 * usuario se recorta a los campos públicos de un perfil.
 */
router.get(
  '/:id',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const user = await getById(req.params.id!);
    if (!user) throw new NotFoundError('Usuario no encontrado');

    const isSelf = req.user!.userId === req.params.id;
    if (isSelf) {
      return res.json({ success: true, data: user });
    }

    const { id, firstName, lastName, profilePicture, city, role } = user;
    res.json({ success: true, data: { id, firstName, lastName, profilePicture, city, role } });
  })
);

export default router;
