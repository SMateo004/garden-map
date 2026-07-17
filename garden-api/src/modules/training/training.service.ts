/**
 * Capacitaciones de cuidadores.
 * - AMATEUR: obligatorias antes del primer servicio para cuidadores con
 *   experienceYears === 0, una por cada servicio que ofrezcan (máx 3).
 * - EXPERIENCE: visibles para todos, nunca obligatorias.
 *
 * `CaregiverProfile.trainingComplete` es un flag denormalizado (mismo patrón
 * que availabilityComplete/caregiverProfileComplete) recalculado acá y
 * consultado directamente por el marketplace — evita joins en cada búsqueda.
 */

import { prisma } from '../../config/database.js';
import { BadRequestError, NotFoundError } from '../../shared/errors.js';
import { ServiceType, TrainingAudience } from '@prisma/client';

const QUESTIONS_PER_TOPIC = 3;

/** Recalcula y persiste CaregiverProfile.trainingComplete. Llamar tras
 * cualquier cambio de progreso de capacitación, servicios ofrecidos, o
 * cambios de admin (activar/desactivar tema, eximir cuidador). */
export async function recomputeTrainingComplete(caregiverId: string): Promise<boolean> {
  const profile = await prisma.caregiverProfile.findUnique({
    where: { id: caregiverId },
    select: { isAmateur: true, servicesOffered: true },
  });
  if (!profile) return true;

  if (!profile.isAmateur || profile.servicesOffered.length === 0) {
    await prisma.caregiverProfile.update({ where: { id: caregiverId }, data: { trainingComplete: true } });
    return true;
  }

  const mandatoryTopics = await prisma.trainingTopic.findMany({
    where: { audience: TrainingAudience.AMATEUR, isActive: true, service: { in: profile.servicesOffered } },
    select: { id: true },
  });

  let complete = true;
  if (mandatoryTopics.length > 0) {
    const progress = await prisma.caregiverTrainingProgress.findMany({
      where: { caregiverId, topicId: { in: mandatoryTopics.map((t) => t.id) } },
      select: { topicId: true, completedAt: true, exemptedByAdmin: true },
    });
    const byTopic = new Map(progress.map((p) => [p.topicId, p]));
    complete = mandatoryTopics.every((t) => {
      const p = byTopic.get(t.id);
      return !!p && (p.exemptedByAdmin || p.completedAt !== null);
    });
  }

  await prisma.caregiverProfile.update({ where: { id: caregiverId }, data: { trainingComplete: complete } });
  return complete;
}

/** GET — temas aplicables al cuidador logueado, con su progreso. */
export async function getMyTopics(userId: string) {
  const profile = await prisma.caregiverProfile.findUnique({
    where: { userId },
    select: { id: true, isAmateur: true, servicesOffered: true },
  });
  if (!profile) throw new NotFoundError('No tienes perfil de cuidador', 'CAREGIVER_PROFILE_NOT_FOUND');
  if (profile.servicesOffered.length === 0) return { amateur: [], experience: [] };

  const topics = await prisma.trainingTopic.findMany({
    where: { isActive: true, service: { in: profile.servicesOffered } },
    orderBy: [{ audience: 'asc' }, { order: 'asc' }],
    include: {
      questions: { select: { id: true, text: true, choices: true, order: true }, orderBy: { order: 'asc' } },
      progress: { where: { caregiverId: profile.id } },
    },
  });

  const shape = (t: (typeof topics)[number]) => {
    const p = t.progress[0];
    return {
      id: t.id,
      service: t.service,
      audience: t.audience,
      title: t.title,
      introduction: t.introduction,
      videoUrl: t.videoUrl,
      questions: t.questions.map((q) => ({ id: q.id, text: q.text, choices: q.choices })),
      videoWatched: !!p?.videoWatchedAt,
      quizPassed: p?.quizPassed ?? false,
      quizAttempts: p?.quizAttempts ?? 0,
      exemptedByAdmin: p?.exemptedByAdmin ?? false,
      completedAt: p?.completedAt ?? null,
    };
  };

  return {
    // AMATEUR solo se muestra como obligatorio si el cuidador es amateur —
    // si ya no lo es, los mismos temas se ven pero como no-obligatorios
    // (agrupados igual que "experience" en el cliente vía el flag `mandatory`).
    amateur: topics.filter((t) => t.audience === TrainingAudience.AMATEUR).map((t) => ({ ...shape(t), mandatory: profile.isAmateur })),
    experience: topics.filter((t) => t.audience === TrainingAudience.EXPERIENCE).map((t) => ({ ...shape(t), mandatory: false })),
  };
}

/** Admin — progreso de capacitaciones de un cuidador puntual (para poder eximirlo tema por tema). */
export async function adminGetCaregiverTopics(caregiverId: string) {
  const profile = await prisma.caregiverProfile.findUnique({
    where: { id: caregiverId },
    select: { isAmateur: true, servicesOffered: true },
  });
  if (!profile) throw new NotFoundError('Cuidador no encontrado', 'CAREGIVER_NOT_FOUND');
  if (profile.servicesOffered.length === 0) return [];

  const topics = await prisma.trainingTopic.findMany({
    where: { service: { in: profile.servicesOffered } },
    orderBy: [{ audience: 'asc' }, { order: 'asc' }],
    include: { progress: { where: { caregiverId } } },
  });

  return topics.map((t) => {
    const p = t.progress[0];
    return {
      id: t.id,
      service: t.service,
      audience: t.audience,
      title: t.title,
      isActive: t.isActive,
      mandatory: t.audience === TrainingAudience.AMATEUR && profile.isAmateur,
      videoWatched: !!p?.videoWatchedAt,
      quizPassed: p?.quizPassed ?? false,
      exemptedByAdmin: p?.exemptedByAdmin ?? false,
      completedAt: p?.completedAt ?? null,
    };
  });
}

/** POST — marca el video de un tema como visto (el cliente confirma que el reproductor llegó al final). */
export async function markVideoWatched(userId: string, topicId: string) {
  const profile = await prisma.caregiverProfile.findUnique({ where: { userId }, select: { id: true, servicesOffered: true } });
  if (!profile) throw new NotFoundError('No tienes perfil de cuidador', 'CAREGIVER_PROFILE_NOT_FOUND');

  const topic = await prisma.trainingTopic.findUnique({ where: { id: topicId } });
  if (!topic || !topic.isActive) throw new NotFoundError('Capacitación no encontrada', 'TRAINING_TOPIC_NOT_FOUND');
  if (!profile.servicesOffered.includes(topic.service)) {
    throw new BadRequestError('Esta capacitación no corresponde a un servicio que ofreces', 'TRAINING_SERVICE_MISMATCH');
  }

  await prisma.caregiverTrainingProgress.upsert({
    where: { caregiverId_topicId: { caregiverId: profile.id, topicId } },
    update: { videoWatchedAt: new Date() },
    create: { caregiverId: profile.id, topicId, videoWatchedAt: new Date() },
  });

  return { success: true as const };
}

/** POST — envía las respuestas del quiz. answers: array de índices elegidos, en el mismo orden que las preguntas devueltas por getMyTopics. */
export async function submitQuiz(userId: string, topicId: string, answers: number[]) {
  const profile = await prisma.caregiverProfile.findUnique({ where: { userId }, select: { id: true, servicesOffered: true } });
  if (!profile) throw new NotFoundError('No tienes perfil de cuidador', 'CAREGIVER_PROFILE_NOT_FOUND');

  const topic = await prisma.trainingTopic.findUnique({
    where: { id: topicId },
    include: { questions: { orderBy: { order: 'asc' } } },
  });
  if (!topic || !topic.isActive) throw new NotFoundError('Capacitación no encontrada', 'TRAINING_TOPIC_NOT_FOUND');
  if (!profile.servicesOffered.includes(topic.service)) {
    throw new BadRequestError('Esta capacitación no corresponde a un servicio que ofreces', 'TRAINING_SERVICE_MISMATCH');
  }
  if (topic.questions.length !== QUESTIONS_PER_TOPIC || answers.length !== topic.questions.length) {
    throw new BadRequestError('Cantidad de respuestas inválida', 'TRAINING_ANSWERS_MISMATCH');
  }

  const progress = await prisma.caregiverTrainingProgress.findUnique({
    where: { caregiverId_topicId: { caregiverId: profile.id, topicId } },
  });
  if (!progress?.videoWatchedAt) {
    throw new BadRequestError('Debes terminar de ver el video antes de responder el quiz', 'TRAINING_VIDEO_NOT_WATCHED');
  }

  const correctCount = topic.questions.reduce((acc, q, i) => acc + (q.correctIndex === answers[i] ? 1 : 0), 0);
  const passed = correctCount === topic.questions.length;

  const updated = await prisma.caregiverTrainingProgress.update({
    where: { caregiverId_topicId: { caregiverId: profile.id, topicId } },
    data: {
      quizPassed: passed,
      quizAttempts: { increment: 1 },
      lastQuizScore: correctCount,
      completedAt: passed ? new Date() : progress.completedAt,
    },
  });

  if (passed) await recomputeTrainingComplete(profile.id);

  return { passed, correctCount, total: topic.questions.length, attempts: updated.quizAttempts };
}

// ── Admin ────────────────────────────────────────────────────────────────

export async function adminListTopics() {
  return prisma.trainingTopic.findMany({
    orderBy: [{ audience: 'asc' }, { service: 'asc' }, { order: 'asc' }],
    include: { questions: { orderBy: { order: 'asc' } }, _count: { select: { progress: true } } },
  });
}

export interface AdminTopicQuestionInput {
  text: string;
  choices: string[];
  correctIndex: number;
}

export interface AdminTopicInput {
  service: ServiceType;
  audience: TrainingAudience;
  title: string;
  introduction?: string;
  videoUrl: string;
  isActive?: boolean;
  order?: number;
  questions: AdminTopicQuestionInput[];
}

function validateQuestions(questions: AdminTopicQuestionInput[]) {
  if (questions.length !== QUESTIONS_PER_TOPIC) {
    throw new BadRequestError(`Cada tema debe tener exactamente ${QUESTIONS_PER_TOPIC} preguntas`, 'TRAINING_QUESTIONS_COUNT');
  }
  for (const q of questions) {
    if (q.choices.length < 2) throw new BadRequestError('Cada pregunta necesita al menos 2 opciones', 'TRAINING_CHOICES_COUNT');
    if (q.correctIndex < 0 || q.correctIndex >= q.choices.length) {
      throw new BadRequestError('correctIndex fuera de rango', 'TRAINING_CORRECT_INDEX_INVALID');
    }
  }
}

export async function adminCreateTopic(adminUserId: string, input: AdminTopicInput) {
  validateQuestions(input.questions);
  const topic = await prisma.trainingTopic.create({
    data: {
      service: input.service,
      audience: input.audience,
      title: input.title,
      introduction: input.introduction,
      videoUrl: input.videoUrl,
      isActive: input.isActive ?? true,
      order: input.order ?? 0,
      createdBy: adminUserId,
      questions: {
        create: input.questions.map((q, i) => ({ text: q.text, choices: q.choices, correctIndex: q.correctIndex, order: i })),
      },
    },
    include: { questions: true },
  });
  await recomputeAllTrainingCompleteForService(topic.service, topic.audience);
  return topic;
}

export async function adminUpdateTopic(topicId: string, input: Partial<AdminTopicInput>) {
  const existing = await prisma.trainingTopic.findUnique({ where: { id: topicId } });
  if (!existing) throw new NotFoundError('Capacitación no encontrada', 'TRAINING_TOPIC_NOT_FOUND');

  if (input.questions) validateQuestions(input.questions);

  const topic = await prisma.$transaction(async (tx) => {
    const updated = await tx.trainingTopic.update({
      where: { id: topicId },
      data: {
        service: input.service,
        audience: input.audience,
        title: input.title,
        introduction: input.introduction,
        videoUrl: input.videoUrl,
        isActive: input.isActive,
        order: input.order,
      },
    });
    if (input.questions) {
      await tx.trainingQuestion.deleteMany({ where: { topicId } });
      await tx.trainingQuestion.createMany({
        data: input.questions.map((q, i) => ({ topicId, text: q.text, choices: q.choices, correctIndex: q.correctIndex, order: i })),
      });
    }
    return updated;
  });

  await recomputeAllTrainingCompleteForService(topic.service, topic.audience);
  return prisma.trainingTopic.findUnique({ where: { id: topicId }, include: { questions: { orderBy: { order: 'asc' } } } });
}

export async function adminDeleteTopic(topicId: string) {
  const topic = await prisma.trainingTopic.findUnique({ where: { id: topicId } });
  if (!topic) throw new NotFoundError('Capacitación no encontrada', 'TRAINING_TOPIC_NOT_FOUND');
  await prisma.trainingTopic.delete({ where: { id: topicId } });
  await recomputeAllTrainingCompleteForService(topic.service, topic.audience);
  return { success: true as const };
}

/** El admin exime a un cuidador puntual de un tema (aunque sea obligatorio para su categoría). */
export async function adminSetExemption(caregiverId: string, topicId: string, exempted: boolean) {
  const [caregiver, topic] = await Promise.all([
    prisma.caregiverProfile.findUnique({ where: { id: caregiverId }, select: { id: true } }),
    prisma.trainingTopic.findUnique({ where: { id: topicId } }),
  ]);
  if (!caregiver) throw new NotFoundError('Cuidador no encontrado', 'CAREGIVER_NOT_FOUND');
  if (!topic) throw new NotFoundError('Capacitación no encontrada', 'TRAINING_TOPIC_NOT_FOUND');

  await prisma.caregiverTrainingProgress.upsert({
    where: { caregiverId_topicId: { caregiverId, topicId } },
    update: { exemptedByAdmin: exempted, completedAt: exempted ? new Date() : null },
    create: { caregiverId, topicId, exemptedByAdmin: exempted, completedAt: exempted ? new Date() : null },
  });

  await recomputeTrainingComplete(caregiverId);
  return { success: true as const };
}

/** Tras crear/editar/borrar un tema AMATEUR, recalcula el flag de todos los
 * cuidadores amateur que ofrecen ese servicio (puede afectar si ahora tienen
 * o dejan de tener una capacitación obligatoria pendiente). */
async function recomputeAllTrainingCompleteForService(service: ServiceType, audience: TrainingAudience) {
  if (audience !== TrainingAudience.AMATEUR) return;
  const caregivers = await prisma.caregiverProfile.findMany({
    where: { isAmateur: true, servicesOffered: { has: service } },
    select: { id: true },
  });
  // Perfiles afectados por un cambio de contenido del admin — típicamente
  // decenas, no miles; secuencial es suficiente y evita saturar el pool de conexiones.
  for (const c of caregivers) {
    await recomputeTrainingComplete(c.id);
  }
}
