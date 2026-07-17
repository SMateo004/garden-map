import { Request, Response } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import { BadRequestError } from '../../shared/errors.js';
import * as trainingService from './training.service.js';

/** GET /api/caregiver/trainings — temas aplicables al cuidador logueado. */
export const getMyTopics = asyncHandler(async (req: Request, res: Response) => {
  const data = await trainingService.getMyTopics(req.user!.userId);
  res.json({ success: true, data });
});

/** POST /api/caregiver/trainings/:topicId/watched */
export const markVideoWatched = asyncHandler(async (req: Request, res: Response) => {
  const data = await trainingService.markVideoWatched(req.user!.userId, req.params.topicId!);
  res.json({ success: true, data });
});

/** POST /api/caregiver/trainings/:topicId/quiz — Body: { answers: number[] } */
export const submitQuiz = asyncHandler(async (req: Request, res: Response) => {
  const answers = req.body?.answers;
  if (!Array.isArray(answers) || answers.some((a) => typeof a !== 'number')) {
    throw new BadRequestError('answers debe ser un array de números', 'VALIDATION_ERROR');
  }
  const data = await trainingService.submitQuiz(req.user!.userId, req.params.topicId!, answers);
  res.json({ success: true, data });
});

// ── Admin ────────────────────────────────────────────────────────────────

export const adminListTopics = asyncHandler(async (_req: Request, res: Response) => {
  const data = await trainingService.adminListTopics();
  res.json({ success: true, data });
});

export const adminCreateTopic = asyncHandler(async (req: Request, res: Response) => {
  const data = await trainingService.adminCreateTopic(req.user!.userId, req.body);
  res.json({ success: true, data });
});

export const adminUpdateTopic = asyncHandler(async (req: Request, res: Response) => {
  const data = await trainingService.adminUpdateTopic(req.params.topicId!, req.body);
  res.json({ success: true, data });
});

export const adminDeleteTopic = asyncHandler(async (req: Request, res: Response) => {
  const data = await trainingService.adminDeleteTopic(req.params.topicId!);
  res.json({ success: true, data });
});

/** GET /api/admin/caregivers/:caregiverId/trainings — progreso de un cuidador puntual. */
export const adminGetCaregiverTopics = asyncHandler(async (req: Request, res: Response) => {
  const data = await trainingService.adminGetCaregiverTopics(req.params.caregiverId!);
  res.json({ success: true, data });
});

/** PATCH /api/admin/caregivers/:caregiverId/trainings/:topicId/exempt — Body: { exempted: boolean } */
export const adminSetExemption = asyncHandler(async (req: Request, res: Response) => {
  const { exempted } = req.body ?? {};
  if (typeof exempted !== 'boolean') {
    throw new BadRequestError('exempted debe ser boolean', 'VALIDATION_ERROR');
  }
  const data = await trainingService.adminSetExemption(req.params.caregiverId!, req.params.topicId!, exempted);
  res.json({ success: true, data });
});
