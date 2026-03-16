import { Router } from 'express';
import { getById } from './user.service.js';
import { NotFoundError } from '../../shared/errors.js';
import { asyncHandler } from '../../shared/async-handler.js';

const router = Router();

router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const user = await getById(req.params.id!);
    if (!user) throw new NotFoundError('Usuario no encontrado');
    res.json({ success: true, data: user });
  })
);

export default router;
