import { Router } from 'express';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';
import * as trainingController from './training.controller.js';

const router = Router();

router.use(authMiddleware);
router.use(requireRole('CAREGIVER'));

router.get('/', trainingController.getMyTopics);
router.post('/:topicId/watched', trainingController.markVideoWatched);
router.post('/:topicId/quiz', trainingController.submitQuiz);

export default router;
