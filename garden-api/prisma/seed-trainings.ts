/**
 * Seed idempotente de capacitaciones AMATEUR (una por servicio: PASEO, HOSPEDAJE, GUARDERIA).
 * Los `videoUrl` quedan vacíos e `isActive: false` a propósito — no hay videos reales
 * todavía. El admin debe cargar el link de YouTube real de cada tema desde la nueva
 * sección de Capacitaciones y activarlo recién ahí (no queremos que un cuidador vea
 * un tema "obligatorio" sin video real).
 *
 * Ejecutar una sola vez: npx tsx prisma/seed-trainings.ts
 */

import { PrismaClient, ServiceType, TrainingAudience } from '@prisma/client';

const prisma = new PrismaClient();

const TOPICS: {
  service: ServiceType;
  title: string;
  introduction: string;
  questions: { text: string; choices: string[]; correctIndex: number }[];
}[] = [
  {
    service: ServiceType.PASEO,
    title: 'Fundamentos de paseo seguro',
    introduction:
      'Antes de tu primer paseo, aprende lo básico para mantener a la mascota y a vos seguros: manejo de correa, señales de estrés y qué hacer ante una emergencia.',
    questions: [
      {
        text: 'Si la mascota que estás paseando muestra señales de estrés (jadeo excesivo, cola entre las patas, intentos de huir), ¿qué debes hacer primero?',
        choices: [
          'Detener el paseo y alejarla de lo que la estresa, dándole espacio para calmarse',
          'Ignorarlo y seguir caminando normalmente',
          'Forzarla a acercarse a lo que le da miedo para que se acostumbre',
        ],
        correctIndex: 0,
      },
      {
        text: '¿Cuál es la forma correcta de sostener la correa durante el paseo?',
        choices: [
          'Enrollada varias veces en la mano para tener más control y evitar que se suelte',
          'Sostenida sin enrollar, dejando que se deslice libremente ante un tirón fuerte',
          'Atada a la muñeca sin sujetarla con la mano',
        ],
        correctIndex: 0,
      },
      {
        text: 'Si la mascota se suelta de la correa durante el paseo, ¿qué debes hacer?',
        choices: [
          'Perseguirla corriendo y gritando su nombre',
          'Mantener la calma, llamarla con voz tranquila y usar premios si tenés, evitando correr detrás de ella',
          'Dejarla ir y avisar al dueño recién al final del paseo',
        ],
        correctIndex: 1,
      },
    ],
  },
  {
    service: ServiceType.HOSPEDAJE,
    title: 'Cuidados básicos de hospedaje',
    introduction:
      'Hospedar una mascota en tu hogar implica responsabilidades extra: alimentación, rutina y contacto con el dueño. Este tema cubre lo esencial antes de tu primer hospedaje.',
    questions: [
      {
        text: 'Un cliente te deja instrucciones específicas de alimentación para su mascota. ¿Qué debes hacer?',
        choices: [
          'Seguir exactamente las instrucciones del dueño, sin cambiar marca, cantidad ni horario de la comida',
          'Darle la comida que vos consideres mejor, aunque sea distinta a la indicada',
          'Alimentarla solo cuando te acuerdes, sin horario fijo',
        ],
        correctIndex: 0,
      },
      {
        text: '¿Qué debes hacer si la mascota hospedada muestra signos de enfermedad (vómito, diarrea, letargo) durante su estadía?',
        choices: [
          'Esperar a que el dueño regrese para contarle',
          'Contactar de inmediato al dueño y, si es necesario, llevarla a una clínica veterinaria de confianza',
          'No hacer nada, es normal que las mascotas se sientan mal en un lugar nuevo',
        ],
        correctIndex: 1,
      },
      {
        text: 'Según los Términos de Garden, ¿qué pasa si retienes a una mascota más tiempo del acordado sin causa justificada?',
        choices: [
          'No pasa nada, es una decisión tuya como cuidador',
          'Puede constituir el delito de apropiación indebida y Garden suspenderá tu cuenta de inmediato',
          'Solo se te descuenta una calificación negativa',
        ],
        correctIndex: 1,
      },
    ],
  },
  {
    service: ServiceType.GUARDERIA,
    title: 'Seguridad en guardería',
    introduction:
      'En la guardería vas a cuidar mascotas por varias horas, a veces junto con otras. Este tema cubre cómo prevenir accidentes y manejar situaciones entre varias mascotas.',
    questions: [
      {
        text: 'Si tienes varias mascotas en guardería al mismo tiempo y dos empiezan a pelear, ¿qué debes hacer?',
        choices: [
          'Meter las manos entre ellas para separarlas físicamente de inmediato',
          'Separarlas usando un objeto (como una silla) o haciendo ruido fuerte, sin meter las manos entre los animales',
          'Dejar que se resuelvan solas',
        ],
        correctIndex: 1,
      },
      {
        text: '¿Qué información sobre la mascota es obligatorio que el dueño te dé antes de la guardería, según los Términos de Garden?',
        choices: [
          'Solo el nombre de la mascota',
          'Raza, edad, temperamento, alergias, enfermedades, medicamentos, vacunas e historial de mordeduras',
          'No es obligatorio pedir ninguna información extra',
        ],
        correctIndex: 1,
      },
      {
        text: '¿Qué recomienda Garden respecto a enviar fotos o actualizaciones al dueño durante el servicio?',
        choices: [
          'Nunca, solo al finalizar',
          'Enviarlas regularmente durante el servicio — mejora la confianza y las reseñas',
          'Solo si el dueño lo pide explícitamente',
        ],
        correctIndex: 1,
      },
    ],
  },
];

async function main() {
  for (const t of TOPICS) {
    const topic = await prisma.trainingTopic.upsert({
      where: { service_audience: { service: t.service, audience: TrainingAudience.AMATEUR } },
      update: { title: t.title, introduction: t.introduction },
      create: {
        service: t.service,
        audience: TrainingAudience.AMATEUR,
        title: t.title,
        introduction: t.introduction,
        videoUrl: '',
        isActive: false, // el admin lo activa cuando cargue el video real
      },
    });

    // Reemplaza las preguntas existentes del tema (idempotente sin duplicar).
    await prisma.trainingQuestion.deleteMany({ where: { topicId: topic.id } });
    for (let i = 0; i < t.questions.length; i++) {
      const q = t.questions[i];
      await prisma.trainingQuestion.create({
        data: {
          topicId: topic.id,
          text: q.text,
          choices: q.choices,
          correctIndex: q.correctIndex,
          order: i,
        },
      });
    }
    console.log(`Tema sembrado: ${t.service} / AMATEUR — "${t.title}" (${t.questions.length} preguntas)`);
  }
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
