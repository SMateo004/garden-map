import 'package:flutter/material.dart';

/// Contenido del Centro de Ayuda — Garden Bolivia.
///
/// Cada categoría agrupa artículos largos y explicados paso a paso (estilo
/// Airbnb Help Center). El contenido refleja el comportamiento REAL de la
/// app (montos, porcentajes, nombres de botones) — si cambia una regla de
/// negocio (comisión, ventanas de cancelación, mínimos de retiro), actualizar
/// aquí también.
class HelpSection {
  final String? heading;
  final String body;
  const HelpSection({this.heading, required this.body});
}

class HelpArticle {
  final String id;
  final String title;
  final String excerpt;
  final List<String> keywords;
  final List<HelpSection> sections;
  const HelpArticle({
    required this.id,
    required this.title,
    required this.excerpt,
    required this.keywords,
    required this.sections,
  });
}

class HelpCategory {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final List<HelpArticle> articles;
  const HelpCategory({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.articles,
  });
}

const List<HelpCategory> helpCenterCategories = [
  // ── 1. RESERVAS Y CANCELACIONES ──────────────────────────────────────────
  HelpCategory(
    id: 'reservas',
    title: 'Reservas y cancelaciones',
    description: 'Cómo reservar, el Meet & Greet, y cómo cancelar',
    icon: Icons.calendar_month_rounded,
    articles: [
      HelpArticle(
        id: 'como-reservar',
        title: 'Cómo hacer una reserva paso a paso',
        excerpt: 'Desde elegir cuidador hasta confirmar el pago.',
        keywords: ['reservar', 'nueva reserva', 'buscar cuidador', 'servicio'],
        sections: [
          HelpSection(
            body: 'Reservar un servicio en Garden toma solo unos minutos. '
                'Te explicamos cada paso para que sepas exactamente qué esperar.',
          ),
          HelpSection(
            heading: '1. Elige el tipo de servicio',
            body: 'Desde el marketplace, elige entre Paseo, Hospedaje, Guardería '
                'o Baño y estética. Cada servicio tiene una duración y una '
                'dinámica distinta — por ejemplo, el paseo estándar dura 30 '
                'minutos y el extendido 60 minutos; el hospedaje es de noche '
                'completa en casa del cuidador.',
          ),
          HelpSection(
            heading: '2. Filtra y compara cuidadores',
            body: 'Puedes filtrar por zona, tamaño de mascota y disponibilidad. '
                'Revisa el perfil de cada cuidador: calificación, número de '
                'reseñas, fotos de su espacio (si ofrece hospedaje/guardería) '
                'y su experiencia. Todos los cuidadores visibles ya pasaron '
                'verificación de identidad.',
          ),
          HelpSection(
            heading: '3. Elige fecha y confirma los datos de tu mascota',
            body: 'Selecciona la fecha y hora del servicio. Es muy importante '
                'que completes correctamente la información de tu mascota '
                '(raza, peso, temperamento, alergias, medicamentos, vacunas) — '
                'esta declaración es la que usa el cuidador para prepararse, y '
                'si se omite información relevante, la responsabilidad de '
                'cualquier incidente derivado recae en el dueño.',
          ),
          HelpSection(
            heading: '4. Meet & Greet (si aplica)',
            body: 'Para la primera reserva de Hospedaje o Guardería con un '
                'cuidador nuevo, es obligatorio coordinar un Meet & Greet: una '
                'reunión gratuita de 20-30 minutos (presencial o por '
                'videollamada) antes de confirmar el servicio. Se coordina '
                'directamente por el chat de la reserva.',
          ),
          HelpSection(
            heading: '5. Paga tu reserva',
            body: 'Puedes pagar con tu Billetera Garden (si tienes saldo), con '
                'QR bancario, o combinando ambos. El precio final incluye el '
                'monto que fija el cuidador más la comisión de plataforma del '
                '20%. Por ejemplo: si el cuidador cobra Bs 100, tú pagas Bs 120 '
                '— el cuidador recibe sus Bs 100 completos.',
          ),
          HelpSection(
            heading: '6. Espera la confirmación del cuidador',
            body: 'Una vez pagado, la reserva queda en estado "esperando '
                'confirmación del cuidador". Recibirás una notificación en '
                'cuanto la acepte. Puedes seguir el estado en "Mis reservas".',
          ),
        ],
      ),
      HelpArticle(
        id: 'cancelar-reserva',
        title: 'Cómo cancelar una reserva y cuánto me devuelven',
        excerpt: 'Ventanas de tiempo y porcentajes de reembolso por servicio.',
        keywords: ['cancelar', 'reembolso', 'devolución', 'anular reserva'],
        sections: [
          HelpSection(
            body: 'Puedes cancelar una reserva confirmada o pendiente de '
                'confirmación desde "Mis reservas" → selecciona la reserva → '
                'botón "Cancelar". El sistema te pedirá confirmar una vez más '
                'porque la acción no se puede deshacer.',
          ),
          HelpSection(
            heading: 'Hospedaje y Guardería',
            body: '• Más de 72 horas antes del servicio: reembolso del 100%.\n'
                '• Entre 24 y 72 horas antes: reembolso del 50%.\n'
                '• Menos de 24 horas o no te presentas: sin reembolso.',
          ),
          HelpSection(
            heading: 'Paseo y Visita domiciliaria',
            body: '• Más de 12 horas antes: reembolso del 100%.\n'
                '• Entre 2 y 12 horas antes: reembolso del 50%.\n'
                '• Menos de 2 horas o no te presentas: sin reembolso.',
          ),
          HelpSection(
            heading: 'Baño y estética',
            body: '• Más de 24 horas antes: reembolso del 100%.\n'
                '• Menos de 24 horas: reembolso del 50%.',
          ),
          HelpSection(
            heading: '¿Cómo y cuándo recibo mi reembolso?',
            body: 'Si pagaste con tu Billetera Garden, el reembolso se acredita '
                'de inmediato a tu billetera — verás la notificación al '
                'instante. Si pagaste por QR bancario, la parte transferida '
                'por banco requiere que el equipo de Garden procese la '
                'devolución manualmente a tu cuenta de origen, lo que puede '
                'tardar entre 1 y 3 días hábiles.',
          ),
          HelpSection(
            heading: 'Si el cuidador es quien cancela',
            body: 'Si el cuidador cancela con menos de 24 horas de anticipación, '
                'recibes el 100% de reembolso sin importar el servicio, y el '
                'cuidador recibe una penalización en su perfil. Tres '
                'cancelaciones tardías de un cuidador en 90 días resultan en '
                'una suspensión de 30 días para esa cuenta.',
          ),
        ],
      ),
      HelpArticle(
        id: 'meet-and-greet',
        title: 'Qué es el Meet & Greet y cómo agendarlo',
        excerpt: 'La reunión previa gratuita antes de hospedaje o guardería.',
        keywords: ['meet and greet', 'reunion previa', 'conocer cuidador'],
        sections: [
          HelpSection(
            body: 'El Meet & Greet es una reunión gratuita de 20 a 30 minutos '
                'entre tú, el cuidador y tu mascota, antes de confirmar una '
                'reserva de Hospedaje o Guardería por primera vez con ese '
                'cuidador. Sirve para que ambas partes se conozcan y resuelvan '
                'dudas antes de dejar a la mascota bajo su cuidado.',
          ),
          HelpSection(
            heading: 'Cómo se coordina',
            body: 'Dentro del chat de tu reserva, el cuidador (o tú) puede '
                'tocar "Proponer Meet & Greet". Ahí eligen: modalidad '
                '(presencial o videollamada), fecha, hora, y el punto de '
                'encuentro (con buscador de direcciones). La otra persona '
                'puede "Confirmar" la propuesta o pedir "Otra fecha".',
          ),
          HelpSection(
            heading: 'Después del Meet & Greet',
            body: 'Una vez que se realiza, confirmas si continúas con la '
                'reserva. Importante: si decides cancelar después de que la '
                'fecha del Meet & Greet ya pasó porque "no salió bien", esa '
                'cancelación no genera reembolso — por eso te recomendamos '
                'decidir y comunicarlo lo antes posible.',
          ),
        ],
      ),
    ],
  ),

  // ── 2. PAGOS ──────────────────────────────────────────────────────────
  HelpCategory(
    id: 'pagos',
    title: 'Pagos',
    description: 'Comisión, QR bancario, Billetera Garden y donaciones',
    icon: Icons.qr_code_scanner_rounded,
    articles: [
      HelpArticle(
        id: 'como-funciona-pago',
        title: 'Cómo funciona el pago y la comisión de Garden',
        excerpt: 'Por qué pagas un poco más del precio del cuidador.',
        keywords: ['comision', 'precio', 'cuanto cuesta', '20%'],
        sections: [
          HelpSection(
            body: 'Cada cuidador fija libremente el precio de su servicio. '
                'Garden añade una comisión de plataforma del 20% sobre ese '
                'precio, que paga el cliente. Esta comisión cubre el '
                'procesamiento seguro del pago, el fondo de garantía, el '
                'soporte, la verificación de identidad de los cuidadores y el '
                'mantenimiento de la app.',
          ),
          HelpSection(
            heading: 'Ejemplo',
            body: 'Si el cuidador cobra Bs 100 por su servicio, tú pagas Bs '
                '120 en total (Bs 100 + 20% de comisión). El cuidador recibe '
                'sus Bs 100 completos — Garden se queda únicamente con los Bs '
                '20 de comisión.',
          ),
          HelpSection(
            heading: '¿Cuándo recibe el cuidador su pago?',
            body: 'El pago se libera al cuidador dentro de las 24 horas '
                'siguientes a que ambas partes confirmen que el servicio '
                'terminó correctamente, o automáticamente a las 72 horas si el '
                'cliente no confirma ni abre una disputa.',
          ),
        ],
      ),
      HelpArticle(
        id: 'pagar-con-qr',
        title: 'Pagar con QR bancario paso a paso',
        excerpt: 'Cómo escanear, cuánto tiempo tienes y qué pasa si expira.',
        keywords: ['qr', 'pago qr', 'transferencia', 'banco'],
        sections: [
          HelpSection(
            body: 'Al confirmar una reserva, si eliges pagar por QR (o si tu '
                'saldo de billetera no cubre el total), la app genera un '
                'código QR bancario con el monto exacto a transferir.',
          ),
          HelpSection(
            heading: 'Pasos',
            body: '1. Escanea el QR desde la app de tu banco o billetera '
                'digital, o descárgalo con el botón "Guardar QR".\n'
                '2. Transfiere el monto exacto que aparece en pantalla — un '
                'monto distinto puede retrasar la aprobación del pago.\n'
                '3. Toca "Ya realicé el pago" — la app verifica automáticamente '
                'cada 5 segundos si el pago fue confirmado.\n'
                '4. En cuanto se confirma, tu reserva pasa a "esperando '
                'confirmación del cuidador".',
          ),
          HelpSection(
            heading: 'El QR tiene 15 minutos de validez',
            body: 'Verás una cuenta regresiva en pantalla (verde si te queda '
                'más de 5 minutos, naranja entre 2 y 5, rojo si queda menos de '
                '2). Si el tiempo llega a cero sin que se detecte el pago, la '
                'reserva se cancela automáticamente y puedes generar un QR '
                'nuevo desde el inicio.',
          ),
          HelpSection(
            heading: 'Si el sistema de QR no está disponible',
            body: 'En ese caso raro, la app te ofrece "Solicitar verificación '
                'manual": subes tu comprobante y el equipo de Garden revisa y '
                'aprueba el pago manualmente. No cambia el monto ni tus '
                'derechos de reembolso — solo puede tardar un poco más que la '
                'confirmación automática.',
          ),
        ],
      ),
      HelpArticle(
        id: 'billetera-garden',
        title: 'Qué es la Billetera Garden y cómo pagar con ella',
        excerpt: 'Tu saldo virtual por reembolsos y otros créditos.',
        keywords: ['billetera', 'saldo', 'wallet', 'pagar con saldo'],
        sections: [
          HelpSection(
            body: 'La Billetera Garden es un saldo en Bolivianos dentro de tu '
                'cuenta, que se acumula principalmente por reembolsos de '
                'cancelaciones. Puedes usarlo para pagar tu próxima reserva, '
                'total o parcialmente.',
          ),
          HelpSection(
            heading: 'Pago combinado (billetera + QR)',
            body: 'Si tu saldo no cubre el total de la reserva, la app te '
                'muestra el desglose: cuánto se descuenta de tu billetera y '
                'cuánto falta por pagar con QR. El saldo de billetera se '
                'descuenta de inmediato; el resto sigue el flujo normal de QR.',
          ),
        ],
      ),
      HelpArticle(
        id: 'donaciones',
        title: 'Donaciones a hogares de mascotas',
        excerpt: 'Propina voluntaria que va 100% a refugios, sin comisión.',
        keywords: ['donar', 'propina', 'refugio', 'hogar de perros'],
        sections: [
          HelpSection(
            body: 'Al pagar una reserva, puedes agregar una donación '
                'voluntaria (Bs 5, 10, 20 o un monto personalizado hasta Bs '
                '500) que se destina íntegramente a hogares de mascotas '
                'aliados. Garden no cobra comisión sobre las donaciones — el '
                '100% se destina a la causa.',
          ),
        ],
      ),
    ],
  ),

  // ── 3. RETIROS Y BILLETERA ────────────────────────────────────────────
  HelpCategory(
    id: 'retiros',
    title: 'Retiros y billetera',
    description: 'Configurar tus datos de cobro y solicitar un retiro',
    icon: Icons.account_balance_wallet_rounded,
    articles: [
      HelpArticle(
        id: 'configurar-datos-cobro',
        title: 'Cómo configurar tus datos de cobro',
        excerpt: 'Banco o billetera digital, antes de tu primer retiro.',
        keywords: ['datos de cobro', 'cuenta bancaria', 'configurar retiro'],
        sections: [
          HelpSection(
            body: 'Antes de solicitar tu primer retiro, necesitas registrar '
                'dónde quieres recibir el dinero. Ve a tu Billetera → sección '
                '"Datos de cobro" → botón "Configurar" (o "Editar" si ya los '
                'tenías).',
          ),
          HelpSection(
            heading: 'Qué necesitas ingresar',
            body: '• Elige si es un banco tradicional o una billetera digital '
                '(Tigo Money, Pago Fácil, etc.).\n'
                '• Si es banco: tipo de cuenta (ahorro o corriente) y número '
                'de cuenta.\n'
                '• Si es billetera digital: tu número de celular asociado.\n'
                '• Nombre completo del titular de la cuenta — debe coincidir '
                'con tu nombre registrado en Garden.\n\n'
                'Guarda con "Guardar datos de cobro". Puedes editarlos en '
                'cualquier momento antes de tu siguiente retiro.',
          ),
        ],
      ),
      HelpArticle(
        id: 'como-retirar',
        title: 'Cómo solicitar un retiro',
        excerpt: 'Monto mínimo, pasos y cuánto tarda en llegar el dinero.',
        keywords: ['retirar', 'retiro', 'sacar dinero', 'cobrar'],
        sections: [
          HelpSection(
            body: 'Con tus datos de cobro ya configurados, ve a tu Billetera y '
                'toca "Solicitar retiro".',
          ),
          HelpSection(
            heading: 'Pasos',
            body: '1. Ingresa el monto en Bolivianos que quieres retirar — '
                'el mínimo es Bs 50, y no puede superar tu saldo disponible '
                '(tu saldo total menos cualquier retiro que ya tengas '
                'pendiente).\n'
                '2. Revisa el resumen: monto, y los datos de la cuenta a la '
                'que se transferirá.\n'
                '3. Toca "Confirmar solicitud".\n'
                '4. Verás una notificación: "¡Solicitud enviada! Revisa tus '
                'notificaciones para más detalles."',
          ),
          HelpSection(
            heading: '¿Cuánto tarda?',
            body: 'El proceso de transferencia toma entre 1 y 3 días hábiles. '
                'Garden no cobra ninguna comisión adicional por retirar tu '
                'dinero.',
          ),
          HelpSection(
            heading: 'Cómo veo el estado de mi retiro',
            body: 'En el historial de tu Billetera, un retiro pendiente '
                'aparece con una etiqueta amarilla "Pendiente". Cuando se '
                'completa la transferencia, cambia a "Retirado".',
          ),
        ],
      ),
    ],
  ),

  // ── 4. SER CUIDADOR EN GARDEN ─────────────────────────────────────────
  HelpCategory(
    id: 'cuidador',
    title: 'Ser cuidador en Garden',
    description: 'Registro, verificación, precios y disponibilidad',
    icon: Icons.volunteer_activism_rounded,
    articles: [
      HelpArticle(
        id: 'como-registrarme',
        title: 'Cómo registrarme como cuidador',
        excerpt: 'El recorrido completo, paso a paso, hasta quedar activo.',
        keywords: ['ser cuidador', 'registro cuidador', 'convertirme en cuidador'],
        sections: [
          HelpSection(
            body: 'Convertirte en cuidador en Garden es gratis y se hace en '
                'un asistente de varios pasos. Si cierras la app a la mitad, '
                'al volver a entrar continúa exactamente donde quedaste — no '
                'pierdes lo que ya llenaste.',
          ),
          HelpSection(
            heading: '1. Tus datos y dirección',
            body: 'Nombre, correo, contraseña, teléfono boliviano y tu '
                'dirección completa (calle, número, zona/barrio). Debes ser '
                'mayor de 18 años.',
          ),
          HelpSection(
            heading: '2. Foto de perfil',
            body: 'Una foto clara de tu rostro — es la que verán los dueños '
                'de mascotas al elegirte.',
          ),
          HelpSection(
            heading: '3. Servicios y zona',
            body: 'Elige qué servicios vas a ofrecer (Paseo, Hospedaje, '
                'Guardería — puedes elegir varios). Si ofreces Hospedaje o '
                'Guardería, indica si vives en casa o departamento y si '
                'tienes patio.',
          ),
          HelpSection(
            heading: '4. Precios',
            body: 'Fijas tu propio precio para cada servicio que ofreces, '
                'dentro de un rango mínimo y máximo que define Garden por '
                'zona (normalmente entre Bs 10 y Bs 400). Este es el monto que '
                'recibes íntegro — la comisión del 20% la paga el cliente '
                'aparte.',
          ),
          HelpSection(
            heading: '5. Disponibilidad',
            body: 'Marca qué días (entre semana, fines de semana, feriados) y '
                'qué horarios (mañana, tarde, noche) puedes trabajar.',
          ),
          HelpSection(
            heading: '6. Fotos',
            body: 'Sube fotos tuyas en acción con mascotas (mínimo 2, hasta '
                '6). Si ofreces Hospedaje o Guardería, además debes subir al '
                'menos una foto de tu sala/área principal, tu zona de '
                'descanso para mascotas, y tu área de alimentación.',
          ),
          HelpSection(
            heading: '7. Tu perfil profesional',
            body: 'Escribe una bio breve (mínimo 10 caracteres) contando por '
                'qué eres un buen cuidador, indica si tienes experiencia '
                'profesional, qué tamaños de mascota aceptas y qué tipos de '
                'animales cuidas. Aquí también aceptas los Términos, la '
                'Política de Privacidad y el proceso de verificación.',
          ),
          HelpSection(
            heading: '8. Verificación de identidad',
            body: 'Escaneas tu Cédula de Identidad y haces una prueba de '
                '"vida" (parpadear, sonreír, girar la cabeza) frente a la '
                'cámara. Ver el artículo "Verificación de identidad" para más '
                'detalle.',
          ),
          HelpSection(
            heading: '9-10. Verificación de teléfono y correo',
            body: 'Recibes un código por SMS y confirmas tu correo. Al '
                'completar todo, tu perfil queda activo y ya puedes recibir '
                'reservas.',
          ),
        ],
      ),
      HelpArticle(
        id: 'verificacion-identidad',
        title: 'Verificación de identidad: cómo funciona',
        excerpt: 'Por qué la pedimos y qué hacer si no pasa a la primera.',
        keywords: ['verificacion', 'identidad', 'ci', 'liveness', 'reconocimiento facial'],
        sections: [
          HelpSection(
            body: 'Para proteger a los dueños de mascotas, todo cuidador debe '
                'verificar su identidad antes de aparecer en el marketplace. '
                'Usamos tecnología de reconocimiento facial (AWS Rekognition) '
                'para comparar tu Cédula de Identidad con tu rostro en vivo.',
          ),
          HelpSection(
            heading: 'Cómo se hace',
            body: 'Sostienes tu CI frente a la cámara para que el sistema '
                'extraiga tu foto y datos, y luego realizas una prueba de '
                'vida (parpadear, sonreír o girar la cabeza según te indique '
                'la pantalla). El sistema compara ambas fotos automáticamente.',
          ),
          HelpSection(
            heading: '¿Cuánto tarda la aprobación?',
            body: 'En la mayoría de los casos es instantánea. Si el sistema '
                'no logra confirmar la coincidencia con seguridad, tu caso '
                'pasa a revisión manual por el equipo de Garden, que suele '
                'tardar entre 24 y 48 horas.',
          ),
          HelpSection(
            heading: 'Si falla la verificación',
            body: 'Puedes volver a intentarlo — revisa que haya buena '
                'iluminación, que la CI se vea nítida y completa, y que tu '
                'rostro esté centrado y sin lentes oscuros o gorra.',
          ),
        ],
      ),
      HelpArticle(
        id: 'precios-y-disponibilidad',
        title: 'Cómo poner mis precios y mi disponibilidad',
        excerpt: 'Rangos permitidos y cómo editarlos después.',
        keywords: ['precios', 'tarifas', 'disponibilidad', 'horarios'],
        sections: [
          HelpSection(
            body: 'Puedes editar tus precios y disponibilidad en cualquier '
                'momento desde tu perfil → "Editar perfil". Los precios deben '
                'mantenerse dentro del rango mínimo y máximo que Garden '
                'define para tu zona y servicio (por defecto entre Bs 10 y Bs '
                '400).',
          ),
          HelpSection(
            heading: 'Recuerda',
            body: 'El precio que fijas es el monto íntegro que recibes — el '
                'cliente paga ese precio más el 20% de comisión de Garden. Si '
                'subes o bajas tu precio, se aplica a las reservas nuevas '
                'desde ese momento, no afecta reservas ya confirmadas.',
          ),
        ],
      ),
    ],
  ),

  // ── 5. DISPUTAS Y PROBLEMAS ────────────────────────────────────────────
  HelpCategory(
    id: 'disputas',
    title: 'Disputas y problemas con el servicio',
    description: 'Cómo reportar un problema y cómo se resuelve',
    icon: Icons.gavel_rounded,
    articles: [
      HelpArticle(
        id: 'reportar-problema',
        title: 'Cómo reportar un problema con un servicio',
        excerpt: 'Se activa al calificar con menos de 3 estrellas.',
        keywords: ['disputa', 'reportar', 'reclamo', 'queja'],
        sections: [
          HelpSection(
            body: 'Si algo salió mal durante un servicio, la vía para '
                'reportarlo es calificar el servicio con menos de 3 estrellas '
                'al finalizar. Esto retiene automáticamente el pago al '
                'cuidador y habilita el botón para abrir una disputa.',
          ),
          HelpSection(
            heading: 'Cómo abrir la disputa',
            body: 'Marca todas las razones que apliquen: el cuidador no llegó '
                'a tiempo, mi mascota se lastimó o enfermó, el servicio fue '
                'diferente a lo prometido, el cuidador fue irresponsable, el '
                'espacio no era adecuado, o no hubo comunicación durante el '
                'servicio. Toca "Enviar reporte".',
          ),
          HelpSection(
            heading: 'Qué pasa después',
            body: 'El cuidador recibe una notificación y puede dar su '
                'versión de los hechos con sus propias opciones (reconoce el '
                'problema, hubo circunstancias fuera de su control, no está '
                'de acuerdo, hubo un malentendido, tuvo una emergencia, o '
                'tiene evidencia/fotos). Una vez que el cuidador responde, el '
                'caso pasa automáticamente a resolución.',
          ),
        ],
      ),
      HelpArticle(
        id: 'resolucion-disputas',
        title: 'Cómo se resuelve una disputa (IA + blockchain)',
        excerpt: 'Un análisis automatizado con evidencia real del servicio.',
        keywords: ['resolucion', 'ia', 'inteligencia artificial', 'veredicto', 'blockchain'],
        sections: [
          HelpSection(
            body: 'Una vez que ambas partes dieron su versión, un sistema de '
                'inteligencia artificial (Anthropic Claude) analiza toda la '
                'evidencia disponible del servicio: el historial completo del '
                'chat, la calificación y comentario, el perfil y trayectoria '
                'del cuidador, y los detalles de la reserva.',
          ),
          HelpSection(
            heading: 'Los tres resultados posibles',
            body: '✅ A favor del cuidador: el pago retenido se libera a su '
                'billetera.\n'
                '❌ A favor del cliente: se procesa un reembolso completo.\n'
                '⚖️ Resolución parcial: se aplica una solución intermedia '
                'entre ambas partes.',
          ),
          HelpSection(
            heading: 'El veredicto queda registrado en blockchain',
            body: 'Cada resolución se graba de forma inmutable en la red '
                'Polygon, junto con un análisis en texto explicando el '
                'porqué de la decisión y, si aplica, recomendaciones para que '
                'el cuidador mejore.',
          ),
          HelpSection(
            heading: '¿Puedo apelar el veredicto de la IA?',
            body: 'Sí. Tienes 5 días hábiles desde el veredicto para tocar '
                '"Apelar esta decisión", explicar por qué no estás de acuerdo '
                'y agregar nueva evidencia si la tienes. A diferencia del '
                'primer veredicto, la apelación la revisa una persona real '
                'del equipo de Garden — no el sistema automatizado — y su '
                'decisión es la definitiva dentro del proceso interno de '
                'Garden.',
          ),
        ],
      ),
      HelpArticle(
        id: 'protocolo-emergencia',
        title: 'Protocolo de emergencia durante un servicio activo',
        excerpt: 'Qué pasa si el cuidador reporta un incidente o accidente.',
        keywords: ['emergencia', 'accidente', 'incidente', 'protocolo'],
        sections: [
          HelpSection(
            body: 'Si durante un servicio en curso (por ejemplo un paseo u '
                'hospedaje) ocurre un incidente o accidente, el cuidador puede '
                'reportarlo de inmediato desde la pantalla del servicio activo.',
          ),
          HelpSection(
            heading: 'Qué pasa cuando se reporta',
            body: '• El tiempo del servicio se pausa automáticamente — es la '
                'única excepción al cálculo normal de horas extra — y se '
                'reanuda cuando el cuidador o un administrador de Garden '
                'marcan la emergencia como resuelta.\n'
                '• El equipo de Garden recibe una alerta urgente (notificación '
                'push + alerta sonora si tiene la app abierta) y puede ver en '
                'tiempo real la ubicación del cuidador si el servicio es un '
                'paseo.\n'
                '• Tú, como dueño de la mascota, recibes un aviso con '
                'lenguaje tranquilo explicando que hay una situación que se '
                'está atendiendo.',
          ),
          HelpSection(
            heading: 'Cómo se resuelve',
            body: 'Un administrador de Garden revisa la situación y la marca '
                'como resuelta, o el propio cuidador la resuelve desde su '
                'pantalla. Al resolverse, el cuidador puede elegir entre '
                'continuar el servicio normalmente o darlo por terminado ahí '
                'mismo. Si el servicio se corta por una emergencia, contáctanos '
                'para revisar el caso y, si corresponde, procesar un ajuste o '
                'reembolso.',
          ),
        ],
      ),
    ],
  ),

  // ── 6. CALIFICACIONES Y RESEÑAS ────────────────────────────────────────
  HelpCategory(
    id: 'calificaciones',
    title: 'Calificaciones y reseñas',
    description: 'Cómo calificar un servicio y qué significan las estrellas',
    icon: Icons.star_rounded,
    articles: [
      HelpArticle(
        id: 'como-calificar',
        title: 'Cómo calificar un servicio',
        excerpt: 'Aparece automáticamente al completarse la reserva.',
        keywords: ['calificar', 'reseña', 'estrellas', 'review'],
        sections: [
          HelpSection(
            body: 'Cuando un servicio se marca como completado, en "Mis '
                'reservas" aparece el botón "Calificar experiencia". Elige de '
                '1 a 5 estrellas y, opcionalmente, deja un comentario para el '
                'cuidador.',
          ),
          HelpSection(
            heading: 'Por qué es importante calificar',
            body: 'Tu calificación queda en el perfil público del cuidador y '
                'ayuda a otros dueños a elegir con confianza. Además, la '
                'reserva no se cierra del todo hasta que calificas — es el '
                'último paso del ciclo del servicio.',
          ),
        ],
      ),
      HelpArticle(
        id: 'calificacion-baja',
        title: 'Qué pasa si doy o recibo una calificación baja',
        excerpt: 'Menos de 3 estrellas retiene el pago y habilita una disputa.',
        keywords: ['calificacion baja', '1 estrella', '2 estrellas', 'mala reseña'],
        sections: [
          HelpSection(
            body: 'Si calificas un servicio con menos de 3 estrellas, el pago '
                'al cuidador se retiene automáticamente (no se libera de '
                'inmediato) y se habilita la opción de abrir una disputa para '
                'contar qué pasó — ver el artículo "Cómo reportar un problema '
                'con un servicio".',
          ),
          HelpSection(
            heading: 'Si eres cuidador y recibiste una calificación baja',
            body: 'Recibirás una notificación y podrás dar tu versión de los '
                'hechos. Tu calificación promedio y número de reseñas son '
                'visibles en tu perfil público, y afectan tu posición en los '
                'resultados de búsqueda del marketplace.',
          ),
        ],
      ),
    ],
  ),

  // ── 7. CHAT Y MEET & GREET ──────────────────────────────────────────────
  HelpCategory(
    id: 'chat',
    title: 'Chat y coordinación',
    description: 'Cómo hablar con tu cuidador o cliente de forma segura',
    icon: Icons.chat_bubble_rounded,
    articles: [
      HelpArticle(
        id: 'usar-el-chat',
        title: 'Cómo usar el chat de tu reserva',
        excerpt: 'Mensajería en tiempo real entre cliente y cuidador.',
        keywords: ['chat', 'mensaje', 'hablar con cuidador', 'comunicacion'],
        sections: [
          HelpSection(
            body: 'Cada reserva tiene su propio chat en tiempo real entre tú '
                'y la otra parte, disponible desde que se coordina el Meet & '
                'Greet hasta después de completado el servicio (mientras no '
                'hayas calificado todavía).',
          ),
          HelpSection(
            heading: 'Qué puedes hacer en el chat',
            body: 'Enviar y recibir mensajes de texto, coordinar o responder '
                'una propuesta de Meet & Greet, y ver el estado de conexión '
                '("En línea") de la otra persona.',
          ),
        ],
      ),
      HelpArticle(
        id: 'seguridad-chat',
        title: 'Seguridad en el chat: qué evitar',
        excerpt: 'Por qué no debes coordinar pagos fuera de la app.',
        keywords: ['seguridad', 'estafa', 'pago directo', 'fuera de la plataforma'],
        sections: [
          HelpSection(
            body: 'Usa el chat de Garden para toda la coordinación del '
                'servicio. Te recomendamos no compartir datos personales '
                'sensibles fuera de la plataforma ni acordar pagos directos '
                'con la otra parte para "evitar la comisión" — esto va contra '
                'los Términos de uso, deja a ambas partes sin la protección '
                'del Fondo de Garantía Garden y de la resolución de disputas, '
                'y puede resultar en la suspensión permanente de ambas '
                'cuentas.',
          ),
        ],
      ),
    ],
  ),

  // ── 8. CUENTA Y SEGURIDAD ────────────────────────────────────────────────
  HelpCategory(
    id: 'cuenta',
    title: 'Cuenta y seguridad',
    description: 'Contraseña, verificación, y eliminar tu cuenta',
    icon: Icons.shield_rounded,
    articles: [
      HelpArticle(
        id: 'eliminar-cuenta',
        title: 'Cómo eliminar mi cuenta',
        excerpt: 'Requisitos previos y qué pasa con tu información.',
        keywords: ['eliminar cuenta', 'borrar cuenta', 'darme de baja'],
        sections: [
          HelpSection(
            body: 'Puedes eliminar tu cuenta desde Perfil → Eliminar cuenta, '
                'confirmando con tu contraseña.',
          ),
          HelpSection(
            heading: 'Antes de eliminar tu cuenta necesitas',
            body: '• No tener reservas activas o pendientes (pagos, '
                'confirmaciones o servicios en curso). Debes esperar a que '
                'finalicen o cancelarlas primero.\n'
                '• No tener disputas abiertas o en revisión.',
          ),
          HelpSection(
            heading: 'Qué pasa con tu saldo y tus datos',
            body: 'Si tienes saldo en tu Billetera Garden al eliminar la '
                'cuenta, ese saldo se transfiere a Garden (por eso te '
                'recomendamos retirarlo antes de eliminar tu cuenta). Tu '
                'información personal se anonimiza — tu nombre, correo y '
                'teléfono dejan de estar asociados a tu cuenta — pero el '
                'historial de transacciones y disputas se conserva por '
                'razones legales y de auditoría. Puedes volver a registrarte '
                'con el mismo correo más adelante si quieres, como una cuenta '
                'completamente nueva.',
          ),
        ],
      ),
      HelpArticle(
        id: 'cambiar-contrasena',
        title: 'Cómo cambiar mi contraseña',
        excerpt: 'Desde el perfil, en unos segundos.',
        keywords: ['contraseña', 'clave', 'cambiar password', 'recuperar cuenta'],
        sections: [
          HelpSection(
            body: 'Ve a Perfil → Configuración de cuenta → Cambiar '
                'contraseña. Te pedirá tu contraseña actual y la nueva dos '
                'veces para confirmarla. Si olvidaste tu contraseña, usa la '
                'opción "¿Olvidaste tu contraseña?" en la pantalla de inicio '
                'de sesión para recibir un enlace de restablecimiento por '
                'correo.',
          ),
        ],
      ),
      HelpArticle(
        id: 'por-que-verificamos-identidad',
        title: 'Por qué Garden pide verificación de identidad',
        excerpt: 'Cómo protegemos a la comunidad de cuidadores y dueños.',
        keywords: ['seguridad', 'confianza', 'verificacion', 'por que'],
        sections: [
          HelpSection(
            body: 'Todos los cuidadores en Garden pasan por un proceso de '
                'verificación de identidad con reconocimiento facial contra '
                'su Cédula de Identidad antes de poder ofrecer servicios — '
                'así te aseguras de que la persona que va a cuidar a tu '
                'mascota es quien dice ser. Los clientes también verifican su '
                'identidad al momento de reservar, protegiendo también a los '
                'cuidadores.',
          ),
        ],
      ),
    ],
  ),
];

/// Lista plana de todos los artículos (para el buscador del Centro de Ayuda).
List<({HelpCategory category, HelpArticle article})> get allHelpArticles => [
      for (final c in helpCenterCategories)
        for (final a in c.articles) (category: c, article: a),
    ];
