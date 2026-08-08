import { Router } from 'express';
import { authMiddleware } from '../../middleware/auth.middleware.js';
import * as referralController from './referral.controller.js';

const router = Router();

router.use(authMiddleware);
router.get('/', referralController.getMy);
router.post('/apply', referralController.apply);

export default router;
