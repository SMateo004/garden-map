import { Router } from 'express';

/**
 * Página pública de Política de Privacidad — requerida por App Store Connect
 * y Google Play Console como URL pública (no basta con el texto dentro de la
 * app). Mismo contenido que PrivacyPolicyScreen en garden-app/lib/screens/legal/legal_screen.dart —
 * si se actualiza uno, actualizar el otro.
 */

const LAST_UPDATED = 'Julio 2026';

const SECTIONS: Array<{ title: string; body: string }> = [
  {
    title: '1. ¿Quiénes somos?',
    body: 'Garden Bolivia es una plataforma de servicios de cuidado de mascotas que conecta a dueños de mascotas con cuidadores verificados en Santa Cruz de la Sierra, Bolivia. Operamos bajo la normativa boliviana de protección de datos personales.',
  },
  {
    title: '2. Datos que recopilamos',
    body: 'Recopilamos los siguientes datos para operar el servicio:\n\n'
      + '• Datos de cuenta: nombre, apellido, correo electrónico, teléfono y contraseña (cifrada).\n'
      + '• Datos de perfil: foto de perfil, dirección, información sobre tu mascota (nombre, raza, edad, necesidades especiales).\n'
      + '• Datos de verificación: para cuidadores, fotografía del carnet de identidad (CI) para validar la identidad.\n'
      + '• Datos de uso: reservas, pagos, mensajes de chat, calificaciones y reseñas.\n'
      + '• Datos técnicos: dirección IP, tipo de dispositivo, sistema operativo, identificadores únicos del dispositivo.\n'
      + '• Datos de ubicación: ubicación aproximada para mostrar cuidadores cercanos, y ubicación GPS en tiempo real durante paseos activos.',
  },
  {
    title: '3. ¿Para qué usamos tus datos?',
    body: '• Crear y gestionar tu cuenta en Garden.\n'
      + '• Procesar reservas y pagos entre clientes y cuidadores.\n'
      + '• Verificar la identidad de los cuidadores para garantizar la seguridad.\n'
      + '• Revisar automáticamente, mediante inteligencia artificial, que las fotos que subes (perfil, mascota, espacio del hogar, evidencia de servicio) correspondan a lo solicitado.\n'
      + '• Analizar evidencia de disputas (mensajes de chat, fotos, ubicación GPS) mediante inteligencia artificial para determinar una resolución inicial, con posibilidad de apelación revisada por el equipo de Garden.\n'
      + '• Enviarte notificaciones relacionadas con tus reservas y actividad.\n'
      + '• Mejorar nuestros servicios mediante análisis de uso agregado y anónimo.\n'
      + '• Detectar y prevenir fraudes o actividades no autorizadas.\n'
      + '• Cumplir con obligaciones legales aplicables en Bolivia.',
  },
  {
    title: '4. Compartición de datos',
    body: 'Garden no vende ni alquila tus datos personales a terceros. Solo compartimos información cuando es necesario para prestar el servicio:\n\n'
      + '• Entre clientes y cuidadores: nombre, foto y datos de la reserva visibles para ambas partes.\n'
      + '• Proveedores de servicio: Cloudinary (almacenamiento de imágenes), Firebase (notificaciones push), Resend (correos electrónicos), AWS Rekognition (verificación de identidad y detección de vida), Anthropic/Claude (análisis automatizado de fotos y evidencia en disputas). Todos operan bajo acuerdos de confidencialidad.\n'
      + '• Pagos: se procesan mediante QR bancario (Sistema de Pagos Instantáneos - SIP) cuando esté disponible, o mediante transferencia bancaria con verificación manual de Garden mientras esa integración esté en curso.\n'
      + '• Autoridades: solo cuando la ley boliviana lo exija con orden judicial válida.',
  },
  {
    title: '5. Almacenamiento y seguridad',
    body: 'Tus datos se almacenan en servidores seguros con cifrado en tránsito (HTTPS/TLS) y en reposo. Las contraseñas se almacenan como hashes bcrypt y nunca en texto plano. Los tokens de sesión tienen expiración automática. Monitoreamos activamente incidentes de seguridad mediante Sentry.',
  },
  {
    title: '6. Tus derechos',
    body: 'Tienes derecho a:\n\n'
      + '• Acceder a los datos personales que tenemos sobre ti.\n'
      + '• Rectificar datos incorrectos o desactualizados.\n'
      + '• Solicitar la eliminación de tu cuenta y datos asociados.\n'
      + '• Oponerte al procesamiento de tus datos para fines de marketing.\n\n'
      + 'Para ejercer estos derechos, escríbenos a privacidad@garden.bo.',
  },
  {
    title: '7. Cookies y rastreo',
    body: 'La app móvil no utiliza cookies. La versión web puede utilizar cookies técnicas estrictamente necesarias para mantener tu sesión. No utilizamos cookies de rastreo de terceros.',
  },
  {
    title: '8. Menores de edad',
    body: 'Garden está destinada a mayores de 18 años. No recopilamos conscientemente datos de menores. Si detectas que un menor ha creado una cuenta, contáctanos a privacidad@garden.bo para eliminarla.',
  },
  {
    title: '9. Cambios a esta política',
    body: 'Podemos actualizar esta Política de Privacidad para reflejar cambios en nuestras prácticas o por requerimientos legales. Te notificaremos por correo electrónico o mediante una notificación en la app con al menos 15 días de anticipación.',
  },
  {
    title: '10. Contacto',
    body: 'Para consultas sobre privacidad:\n'
      + 'Email: contactogardenbo@gmail.com\n'
      + 'Teléfono: +591 75933133\n'
      + 'Dirección: C. 6 Barrio Equipetrol, Santa Cruz de la Sierra, Bolivia.',
  },
];

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function renderBody(body: string): string {
  return escapeHtml(body)
    .split('\n\n')
    .map((p) => `<p>${p.replace(/\n/g, '<br>')}</p>`)
    .join('\n');
}

function renderPage(title: string, sections: Array<{ title: string; body: string }>): string {
  const sectionsHtml = sections
    .map((s) => `<section><h2>${escapeHtml(s.title)}</h2>${renderBody(s.body)}</section>`)
    .join('\n');

  return `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${escapeHtml(title)} — Garden Bolivia</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 720px; margin: 0 auto; padding: 24px 20px 60px; color: #1f2937; line-height: 1.6; }
  h1 { font-size: 24px; margin-bottom: 4px; }
  .updated { color: #6b7280; font-size: 13px; margin-bottom: 32px; }
  h2 { font-size: 16px; margin-top: 28px; color: #15803d; }
  p { font-size: 14px; margin: 8px 0; }
</style>
</head>
<body>
  <h1>${escapeHtml(title)}</h1>
  <div class="updated">Última actualización: ${escapeHtml(LAST_UPDATED)}</div>
  ${sectionsHtml}
</body>
</html>`;
}

const router = Router();

/** GET /legal/privacy — página pública de Política de Privacidad (requerida por las tiendas de apps). */
router.get('/privacy', (_req, res) => {
  res.set('Content-Type', 'text/html; charset=utf-8');
  res.send(renderPage('Política de Privacidad', SECTIONS));
});

export default router;
