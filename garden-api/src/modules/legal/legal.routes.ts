import { Router } from 'express';
import { getPricingConfig } from '../pricing/pricing.service.js';
import { withoutTaxMentions } from './tax-clauses.js';

/**
 * Páginas públicas de Política de Privacidad y Términos y Condiciones —
 * requeridas por App Store Connect y Google Play Console como URL pública
 * (no basta con el texto dentro de la app). Mismo contenido que
 * PrivacyPolicyScreen / TermsOfServiceScreen en
 * garden-app/lib/screens/legal/legal_screen.dart — si se actualiza uno,
 * actualizar el otro. El Contrato de Cuidador (caregiver_contract_content.dart)
 * es un documento aparte, solo para onboarding — no tiene URL pública porque
 * no es lo que piden las tiendas.
 */

const LAST_UPDATED = 'Octubre 2026';

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
      + '• Registro público en blockchain: de cada Reserva pagada se publican en la red principal de Polygon su identificador interno, una referencia seudónima de cada parte (calculada con una clave secreta de Garden), el monto, las fechas y cómo terminó; de los perfiles, la referencia seudónima, el rol y si la identidad está verificada. Nunca nombres, teléfonos, correos, direcciones ni fotos. Por tratarse de una blockchain pública esos registros no se pueden borrar, ni siquiera si eliminas tu cuenta; sin la clave de Garden no permiten identificarte (ver Términos, sección 19).\n'
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

export const SECTIONS_TERMS: Array<{ title: string; body: string }> = [
  {
    title: '1. Quiénes somos y qué es Garden',
    body: 'Garden Bolivia ("Garden", "la Plataforma", "nosotros") es una plataforma tecnológica de intermediación que conecta a dueños de mascotas ("Clientes" o "Dueños") con personas que ofrecen servicios de cuidado de animales domésticos ("Cuidadores") en Santa Cruz de la Sierra, Bolivia.\n\n'
      + 'Garden NO es una empresa de cuidado de mascotas ni empleadora de cuidadores. Actuamos exclusivamente como intermediario tecnológico que facilita el encuentro entre oferta y demanda, procesa pagos de forma segura y ofrece herramientas de comunicación y seguimiento del servicio. Los Cuidadores participan de forma voluntaria e independiente, sin ninguna relación laboral con Garden (ver sección 30).\n\n'
      + 'Además, registramos cada Reserva pagada en la red principal de Polygon, una blockchain pública: el pago, las extensiones, cómo terminó el servicio y el veredicto de las disputas quedan en un registro que ninguna de las partes, ni Garden, puede modificar después (ver sección 19).',
  },
  {
    title: '2. Definiciones clave',
    body: '• CLIENTE / DUEÑO: persona natural mayor de 18 años que usa Garden para contratar servicios de cuidado para su mascota.\n\n'
      + '• CUIDADOR: persona natural mayor de 18 años, verificada por Garden, que ofrece servicios de cuidado de mascotas a través de la Plataforma. Los Cuidadores participan de forma VOLUNTARIA y como prestadores de servicios independientes: NO son empleados, dependientes ni trabajadores de Garden y entre ellos y Garden no existe relación laboral de ningún tipo (ver sección 30).\n\n'
      + '• RESERVA: acuerdo de servicio entre un Cliente y un Cuidador, confirmado y pagado a través de la Plataforma.\n\n'
      + '• SERVICIO: cualquier modalidad de cuidado de mascotas ofrecida en la Plataforma (hospedaje, guardería, paseo).\n\n'
      + '• SMART CONTRACT: programa público de Garden desplegado en la red principal de Polygon que registra los datos esenciales de cada Reserva pagada (monto, fechas, tipo de servicio y cómo terminó). No custodia dinero: los pagos se procesan fuera de la blockchain. Lo registrado no se puede modificar ni borrar.\n\n'
      + '• BILLETERA GARDEN: saldo virtual en Bolivianos acumulado en la cuenta del usuario, producto de reembolsos u otros créditos otorgados por Garden.\n\n'
      + '• COMISIÓN DE PLATAFORMA: tarifa que Garden cobra sobre el valor de cada Reserva por el uso de la infraestructura tecnológica, procesamiento de pagos y garantías del servicio.\n\n'
      + '• FONDO DE GARANTÍA GARDEN: reserva económica administrada por Garden destinada a cubrir situaciones excepcionales contempladas en estos Términos, sujeta a disponibilidad y verificación previa de cada caso.',
  },
  {
    title: '3. Requisitos para registrarse',
    body: 'TODOS LOS USUARIOS:\n'
      + '• Ser persona natural mayor de 18 años.\n'
      + '• Proporcionar nombre completo real, correo electrónico válido y número de teléfono activo en Bolivia.\n'
      + '• Aceptar estos Términos y la Política de Privacidad de forma expresa antes de completar el registro. Los Cuidadores deben además volver a aceptarlos cada 2 meses (ver sección 32).\n'
      + '• No haber sido suspendido o baneado previamente de la Plataforma.\n\n'
      + 'CUIDADORES (requisitos adicionales):\n'
      + '• Presentar Cédula de Identidad (CI) boliviana vigente para verificación de identidad mediante IA.\n'
      + '• Completar el proceso de verificación facial de identidad antes de ofrecer servicios.\n'
      + '• Proporcionar una dirección física verificable en Santa Cruz de la Sierra (para servicios en domicilio del cuidador).\n'
      + '• Registrar un contacto de emergencia (ver Sección 17) antes de ofrecer servicios de Hospedaje o Guardería.\n'
      + '• No tener antecedentes penales relacionados con maltrato animal o violencia (Garden puede verificar esto en coordinación con autoridades).\n'
      + '• Aceptar expresamente la Política de Bienestar Animal de Garden.\n\n'
      + 'ANTECEDENTES PENALES (documento opcional): El Cuidador puede además subir voluntariamente un documento de antecedentes penales (FELCC/REJAP) para obtener el distintivo "Antecedentes verificados" en su perfil público. No es un requisito para operar en la Plataforma. El documento es revisado por un sistema de inteligencia artificial que únicamente señala documentos dudosos o con antecedentes explícitos de maltrato animal o violencia para revisión de un administrador de Garden — la IA nunca suspende una cuenta por sí sola. Si el documento es rechazado por no ser válido (borroso, vencido, no corresponde a la persona), esto no suspende la cuenta, solo se le pide al Cuidador subir uno nuevo.\n\n'
      + 'La información falsa en el registro constituye causal de suspensión inmediata y permanente de la cuenta, sin derecho a reembolso de saldos pendientes, y puede derivar en acciones legales al amparo del Código Penal Boliviano (Decreto Ley N° 10426, Art. 335 - Estelionato y Art. 199 - Falsedad material).',
  },
  {
    title: '4. Especies y animales aptos para la Plataforma',
    body: 'Garden está diseñada para el cuidado de mascotas domésticas comunes: principalmente perros y gatos, y en menor medida aves y roedores pequeños de tenencia doméstica legal en Bolivia.\n\n'
      + 'QUEDA EXPRESAMENTE PROHIBIDO registrar o solicitar servicios para:\n'
      + '✗ Fauna silvestre o especies protegidas, conforme a la Ley N° 1333 de Medio Ambiente y los convenios CITES suscritos por Bolivia.\n'
      + '✗ Animales exóticos o peligrosos no aptos para el hogar (serpientes venenosas, primates, felinos grandes, y similares).\n'
      + '✗ Cualquier especie cuya tenencia como mascota sea ilegal en el territorio boliviano.\n\n'
      + 'Garden se reserva el derecho de rechazar, cancelar o eliminar sin reembolso cualquier Reserva que involucre una especie no permitida. Si se detecta tenencia ilegal de fauna silvestre, Garden podrá reportarlo a la Autoridad de Bosques y Tierra (ABT) o a la Defensoría de la Madre Tierra, además de suspender permanentemente la cuenta involucrada.',
  },
  {
    title: '5. Servicios disponibles en la Plataforma',
    body: 'HOSPEDAJE: La mascota pernocta en el domicilio del Cuidador. El Cuidador asume responsabilidad de custodia plena durante todo el período contratado, incluyendo alimentación, acceso a agua, ejercicio básico y atención en caso de emergencia.\n\n'
      + 'GUARDERÍA DIURNA: La mascota permanece en el domicilio del Cuidador durante el día (máx. 12 horas). Mismo nivel de responsabilidad que el hospedaje.\n\n'
      + 'PASEO: El Cuidador retira a la mascota en el domicilio del Cliente, la pasea por una ruta predefinida (visible en tiempo real mediante GPS en la app) y la devuelve. El paseo estándar es de 30 minutos; el paseo extendido es de 60 minutos.\n\n'
      + 'MEET & GREET: Reunión presencial gratuita de 20-30 minutos entre el Cliente, el Cuidador y la mascota antes de confirmar la Reserva. Obligatoria para servicios de hospedaje y guardería en primera reserva.',
  },
  {
    title: '6. Comisiones, precios y estructura de pagos',
    body: 'PRECIOS: Los Cuidadores establecen libremente sus tarifas en Bolivianos (Bs.). El precio que publica el Cuidador es el monto íntegro que recibirá por el servicio.\n\n'
      + 'TARIFA DE PLATAFORMA: Garden suma al precio establecido por el Cuidador una tarifa de plataforma que varía según el servicio y el Cuidador o empresa. Está incluida en el precio que el Cliente ve en la app, la paga el Cliente y cubre: el procesamiento seguro del pago, el Fondo de Garantía Garden, el soporte al usuario, la verificación de identidad de Cuidadores y el mantenimiento de la infraestructura tecnológica.\n\n'
      + 'EJEMPLO (los porcentajes pueden variar): si el Cuidador cobra Bs. 100 por un servicio, el Cliente ve un precio de Bs. 110 (precio del Cuidador + tarifa de plataforma) y al pagar se suman los impuestos de ley (16%: Bs. 18), para un total de Bs. 128. El Cuidador recibe íntegramente sus Bs. 100.\n\n'
      + 'DISTRIBUCIÓN DEL PAGO:\n'
      + '  → El Cuidador fija su precio (ej.: Bs. 100).\n'
      + '  → El Cliente ve el precio del Cuidador + tarifa de plataforma (ej.: Bs. 110) y al pagar se suman los impuestos de ley (ej.: Bs. 18), para un total de Bs. 128.\n'
      + '  → El Cuidador recibe el 100% de su precio establecido (ej.: Bs. 100).\n'
      + '  → Garden retiene la tarifa de plataforma (ej.: Bs. 10) y destina los impuestos cobrados al pago de sus obligaciones tributarias (ej.: Bs. 18).\n'
      + '  → El pago al Cuidador se libera de inmediato si el Cliente confirma la finalización del servicio, o automáticamente a las 24 horas de finalizado el servicio si el Cliente no confirma ni abre una disputa.\n\n'
      + 'REGISTRO EN BLOCKCHAIN: Cuando se confirma el pago de una Reserva, Garden la registra en un smart contract de la red principal de Polygon con el monto pagado, las fechas, el tipo de servicio y una referencia seudónima de cada parte (no sus datos personales). Ese registro es público y no puede ser alterado por ninguna de las partes ni por Garden. El dinero no pasa por la blockchain.\n\n'
      + 'VERIFICACIÓN DEL PAGO: Mientras Garden completa la integración directa con el sistema bancario (QR interbancario SIP), la confirmación de que un pago fue efectivamente transferido puede realizarse mediante revisión manual por parte del equipo de Garden, en lugar de una confirmación automática instantánea del banco. Esto no cambia el monto que pagas ni tus derechos de reembolso — solo el tiempo que puede tomar la confirmación mientras esta integración esté en curso.\n\n'
      + 'IVA E IMPUESTOS: Los impuestos de ley (IVA 13% e IT 3%, 16% en total) se muestran por separado en el detalle de pago y se suman al precio del servicio; no se descuentan al Cuidador. Garden emite las facturas electrónicas que correspondan al amparo de la Ley N° 812 (Factura Electrónica) y las disposiciones del Servicio de Impuestos Nacionales (SIN).\n\n'
      + 'PROPINAS: Los Clientes pueden dejar propinas voluntarias al finalizar el servicio. Las propinas van íntegramente al Cuidador (0% de comisión sobre propinas).',
  },
  {
    title: '7. Política de cancelación y reembolsos',
    body: 'HOSPEDAJE Y GUARDERÍA:\n'
      + '• Cancelación con más de 48 horas de anticipación: reembolso del 100% (menos un cargo administrativo fijo de Bs. 10).\n'
      + '• Cancelación entre 24 y 48 horas de anticipación: reembolso del 50% (también con el cargo de Bs. 10 descontado).\n'
      + '• Cancelación con menos de 24 horas o sin presentación (no-show): sin reembolso.\n\n'
      + 'PASEO:\n'
      + '• Cancelación con más de 12 horas de anticipación: reembolso del 100%.\n'
      + '• Cancelación entre 6 y 12 horas de anticipación: reembolso del 50%.\n'
      + '• Cancelación con menos de 6 horas o sin presentación: sin reembolso.\n\n'
      + 'CANCELACIÓN POR EL CUIDADOR: Si el Cuidador cancela con menos de 24 horas de anticipación, el Cliente recibe reembolso del 100% y el Cuidador recibe una penalización en su perfil. Tres cancelaciones tardías en 90 días resultan en suspensión temporal de 30 días.\n\n'
      + 'CASOS DE FUERZA MAYOR (bloqueos, paros, desastres naturales): Si un bloqueo de calles, paro cívico, estado de emergencia declarado o un desastre natural impide físicamente que el Cliente o el Cuidador cumplan con el horario acordado, ninguna de las partes sufre penalización — la reserva puede reprogramarse sin costo o cancelarse con reembolso del 100%, sin importar la ventana de tiempo indicada arriba. Quien solicita esta excepción debe notificar a Garden apenas sea razonablemente posible, idealmente con evidencia de la situación (noticias, fotos, comunicados oficiales).\n\n'
      + 'MOTIVO OBLIGATORIO Y MAL CLIMA: Toda cancelación (por el Cliente o por el Cuidador) antes de que inicie el servicio requiere indicar un motivo. Si el motivo es "Mal clima", se garantiza reembolso del 100% al Cliente sin importar cuánto faltaba para el servicio — pero únicamente para Paseo (el único servicio donde el mal clima impide físicamente salir a la calle) y hasta un máximo de 2 veces por Cliente cada 90 días. A partir de la tercera cancelación por "Mal clima" en ese período, o si el servicio es Hospedaje o Guardería, se aplica la tabla de reembolso escalonado por tiempo indicada arriba. Para cualquier otro motivo, también se aplica dicha tabla.\n\n'
      + 'REEMBOLSOS: Los reembolsos se acreditan en la Billetera Garden en un plazo de 1-3 días hábiles. El retiro del saldo a cuenta bancaria se procesa en 1-3 días hábiles adicionales.',
  },
  {
    title: '8. Derechos y obligaciones del Dueño de mascota',
    body: 'El Dueño de mascota PUEDE:\n\n'
      + '✓ Buscar y comparar perfiles de cuidadores verificados con reseñas reales.\n'
      + '✓ Solicitar un Meet & Greet gratuito antes de confirmar cualquier reserva de hospedaje.\n'
      + '✓ Ver en tiempo real la ubicación GPS de su mascota durante los paseos.\n'
      + '✓ Recibir fotos y actualizaciones durante el servicio a través del chat integrado.\n'
      + '✓ Calificar al Cuidador con estrellas y dejar una reseña escrita al finalizar el servicio.\n'
      + '✓ Abrir una disputa dentro de las 24 horas siguientes a la finalización del servicio si considera que este no fue prestado correctamente.\n'
      + '✓ Solicitar acceso a las imágenes y registros de GPS de su servicio por hasta 30 días después de su finalización.\n'
      + '✓ Cancelar su cuenta y solicitar la eliminación de sus datos personales en cualquier momento.\n\n'
      + 'OBLIGACIONES DEL DUEÑO (de cumplimiento obligatorio antes de cada servicio):\n\n'
      + '⚠ Declaración completa de la mascota: El Dueño ESTÁ OBLIGADO a informar, antes de cada Reserva, todos los aspectos relevantes de su mascota, incluyendo sin limitarse a: raza, edad, peso, temperamento, comportamiento con extraños y otros animales, alergias alimentarias y ambientales, enfermedades crónicas o preexistentes, medicamentos en curso (dosis y horarios), vacunas al día, historial de mordeduras o agresiones, y cualquier trauma o fobia conocida.\n\n'
      + 'Esta declaración tiene carácter contractual. El incumplimiento total o parcial de esta obligación exime al Cuidador y a Garden de cualquier responsabilidad por incidentes derivados de información omitida o falsa, trasladando toda responsabilidad civil y económica al Dueño conforme al Art. 519 del Código Civil Boliviano (autonomía de la voluntad y buena fe contractual).',
  },
  {
    title: '9. Prohibiciones para el Dueño de mascota',
    body: 'El Dueño de mascota NO PUEDE:\n\n'
      + '✗ Acordar pagos directos con el Cuidador para evadir la Plataforma ni la comisión de Garden. Esto constituye incumplimiento grave y puede resultar en suspensión permanente de ambas cuentas.\n\n'
      + '✗ Proporcionar información falsa o incompleta sobre el comportamiento, estado de salud o vacunación de su mascota. Los daños causados por ocultamiento de información son responsabilidad exclusiva del Dueño.\n\n'
      + '✗ Entregar una mascota diferente a la registrada en la Reserva sin notificación previa al Cuidador.\n\n'
      + '✗ Solicitar al Cuidador que realice actividades no acordadas en la Reserva (ej.: compras, mensajería, tareas domésticas).\n\n'
      + '✗ Acosar, amenazar, insultar o discriminar a los Cuidadores por ningún medio dentro o fuera de la Plataforma.\n\n'
      + '✗ Publicar reseñas falsas, difamatorias o malintencionadas.\n\n'
      + '✗ Registrar más de una cuenta personal.\n\n'
      + '✗ Ceder o compartir el acceso a su cuenta con terceros.\n\n'
      + '✗ Usar la Plataforma para fines comerciales (reventa de servicios, agencias de mascotas, etc.) sin acuerdo escrito previo con Garden.\n\n'
      + '✗ OBLIGACIÓN DE ALIMENTACIÓN (Hospedaje y Guardería): Para servicios de Hospedaje y Guardería, el Dueño ESTÁ OBLIGADO a entregar al Cuidador la alimentación completa y pre-porcionada para toda la duración del servicio, junto con las instrucciones específicas de frecuencia y cantidad. El Cuidador NO puede proporcionar alimentos propios ni de otra fuente a la mascota, ya que esto puede causar trastornos digestivos, reacciones alérgicas o intoxicaciones. El incumplimiento de esta obligación (no traer alimento suficiente) exime al Cuidador de toda responsabilidad por afecciones gastrointestinales de la mascota durante el servicio.',
  },
  {
    title: '10. Derechos y facultades del Cuidador',
    body: 'El Cuidador PUEDE:\n\n'
      + '✓ Establecer sus propios precios, horarios y disponibilidad libremente.\n'
      + '✓ Aceptar o rechazar cualquier solicitud de Reserva sin necesidad de justificación.\n'
      + '✓ Cancelar una Reserva activa si detecta que la mascota representa un riesgo para su seguridad o la de otros animales a su cuidado, notificando inmediatamente a Garden.\n'
      + '✓ Recibir el 100% del precio que él mismo ha establecido por cada Reserva. La tarifa de plataforma de Garden es añadida sobre el precio del Cuidador y pagada por el Cliente — el Cuidador NUNCA pierde parte de su tarifa.\n'
      + '✓ Trabajar con otras plataformas o por su cuenta: no hay exclusividad ni mínimo de reservas. Puede dejar de usar Garden cuando quiera, sin penalización, siempre que no tenga reservas confirmadas o en curso pendientes.\n'
      + '✓ Construir un perfil público con fotos, descripción y reseñas de sus servicios.\n'
      + '✓ Comunicarse con los Clientes a través del chat integrado para coordinación del servicio.\n'
      + '✓ Solicitar información adicional sobre la mascota antes de confirmar la Reserva.\n'
      + '✓ Establecer límites razonables (máx. número de mascotas simultáneas, razas que no acepta, peso máximo).\n'
      + '✓ Ver en el detalle de cada Reserva pagada, una vez cerrada, el comprobante de su registro en blockchain, con el enlace a la transacción en polygonscan.com.\n'
      + '✓ Negarse a alimentar a una mascota si el Dueño no proveyó alimento suficiente, reportando la situación a Garden a través de la app.',
  },
  {
    title: '11. Prohibiciones para el Cuidador',
    body: 'El Cuidador NO PUEDE:\n\n'
      + '✗ Solicitar o aceptar pagos fuera de la Plataforma para servicios originados en Garden.\n'
      + '✗ Delegar el cuidado de la mascota a otra persona no registrada en Garden sin autorización expresa del Cliente y de Garden.\n'
      + '✗ Transportar a la mascota en vehículo sin las condiciones mínimas de seguridad (jaula o arnés homologado).\n'
      + '✗ Administrar medicamentos a la mascota sin instrucciones escritas del Dueño y del veterinario.\n'
      + '✗ Mezclar mascotas con animales enfermos o sin vacunas al día en el espacio de hospedaje.\n'
      + '✗ Publicar fotos o videos de las mascotas a su cuidado en redes sociales sin autorización expresa del Cliente.\n'
      + '✗ Prestar el servicio bajo los efectos del alcohol o de sustancias controladas. Sanción: suspensión inmediata.\n'
      + '✗ Abandono de mascota: dejar de atender a una mascota bajo su custodia constituye maltrato animal y puede ser denunciado ante la Defensoría de la Madre Tierra y el Gobierno Autónomo Municipal de Santa Cruz.\n'
      + '✗ Acosar, insultar o discriminar a los Clientes.\n'
      + '✗ Inflar artificialmente sus calificaciones mediante reseñas falsas o acuerdos con terceros.\n'
      + '✗ Usar las fotos, datos o información de las mascotas de los Clientes con fines distintos a la prestación del servicio.',
  },
  {
    title: '12. ¿Qué pasa si la mascota se lastima, enferma o fallece?',
    body: 'La seguridad y bienestar de la mascota es responsabilidad EXCLUSIVA del Cuidador durante todo el período en que la mascota esté bajo su custodia, y los daños se le presumen imputables salvo que pruebe una causa de exoneración (ver sección 31).\n\n'
      + 'OBLIGACIÓN ÚNICA DEL CUIDADOR ANTE UNA EMERGENCIA:\n'
      + 'Ante cualquier incidente (lesión, enfermedad, accidente), la única y primera obligación del Cuidador es llevar a la mascota al veterinario más cercano de forma INMEDIATA, sin demora. Esta acción oportuna es lo que se le exige y lo que determina si actuó de buena fe.\n\n'
      + 'HERRAMIENTA "REPORTAR INCIDENTE" EN LA APP:\n'
      + 'Durante un servicio activo, el Cuidador puede tocar "Reportar incidente" para notificar de inmediato al equipo de Garden. Al hacerlo: (a) el cronómetro del servicio se pausa automáticamente — es la única excepción al cálculo normal de horas extra —, reanudándose cuando el Cuidador o un administrador de Garden marquen la emergencia como resuelta; (b) Garden recibe una alerta urgente y, si el servicio es un paseo, puede ver en tiempo real la ubicación GPS del Cuidador; (c) el Dueño recibe un aviso con lenguaje tranquilo indicando que hay una situación en atención. Al resolverse la emergencia, el Cuidador puede continuar el servicio normalmente o darlo por terminado ahí mismo.\n\n'
      + 'PROCEDIMIENTO DE EMERGENCIA (obligatorio):\n'
      + '1. El Cuidador lleva a la mascota al veterinario más cercano de inmediato y, de ser posible, reporta el incidente desde la app.\n'
      + '2. El Cuidador notifica a Garden y al Cliente a través de la app dentro de los 30 minutos siguientes.\n'
      + '3. Se documentan todos los gastos con facturas y reportes veterinarios.\n'
      + '4. Garden investiga la causa del incidente en un plazo de 5 días hábiles.\n\n'
      + 'FONDO DE GARANTÍA GARDEN (Bs. 2.000):\n'
      + 'Garden mantiene un Fondo de Garantía de hasta Bs. 2.000 por incidente, sujeto a disponibilidad y verificación, destinado a cubrir gastos veterinarios de emergencia en situaciones donde el incidente NO sea producto de negligencia del Cuidador (accidente fortuito, causa desconocida, condición preexistente no informada). Este fondo es una ayuda voluntaria y discrecional de Garden: no es un seguro, no es un derecho de ninguna de las partes, puede ser negado, reducido o suspendido en cualquier momento y no constituye reconocimiento de responsabilidad.\n\n'
      + 'SI SE DETERMINA NEGLIGENCIA DEL CUIDADOR:\n'
      + 'Si la investigación de Garden determina que el incidente fue causado por negligencia comprobable del Cuidador (descuido, abandono, falta de agua o alimentación, violencia, sustancias tóxicas accesibles en su domicilio), el Cuidador deberá cubrir el 100% de los gastos veterinarios documentados. En estos casos el Fondo de Garantía Garden no aplica — la responsabilidad económica recae íntegramente sobre el Cuidador. Garden retendrá los montos correspondientes de los próximos pagos del Cuidador hasta saldar la deuda. Para montos superiores a Bs. 5.000, Garden actuará como mediador ante instancias civiles.\n\n'
      + 'Esta estructura (tarifa de plataforma) existe precisamente para sostener el Fondo de Garantía y proteger a los Clientes en casos donde el incidente no sea negligencia del Cuidador.\n\n'
      + 'Fundamento legal: Art. 984 del Código Civil Boliviano (D.L. N° 12760) — responsabilidad por daño causado por culpa o negligencia.\n\n'
      + 'CAUSAS DE EXONERACIÓN (el Cuidador debe probarlas con evidencia documentada: fotos, GPS, chat, reportes veterinarios):\n'
      + '• Condición médica preexistente no declarada por el Dueño en la Reserva.\n'
      + '• Enfermedad por vacunas vencidas u omitidas (responsabilidad del Dueño).\n'
      + '• Muerte natural por edad avanzada o enfermedad terminal conocida.\n'
      + '• Accidente causado directamente por el comportamiento agresivo de la propia mascota.\n'
      + '• Afecciones gastrointestinales por no seguir la dieta indicada cuando el Dueño no proveyó alimento.\n'
      + '• Un incendio, inundación u otro siniestro en el domicilio del Cuidador no originado por su negligencia comprobable (ver también Sección 27 — fuerza mayor).',
  },
  {
    title: '13. ¿Qué pasa si la mascota se extravía durante el servicio?',
    body: 'Si la mascota se escapa o se pierde durante un paseo, hospedaje o guardería, el Cuidador debe actuar de inmediato:\n\n'
      + '1. Buscar activamente en la zona durante al menos 30 minutos antes de suspender la búsqueda inicial.\n'
      + '2. Notificar al Cliente y a Garden a través de la app dentro de los 30 minutos siguientes al hecho.\n'
      + '3. Reportar la mascota extraviada a la perrera municipal y, si tiene microchip o placa de identificación, difundir esos datos en canales de mascotas perdidas de la zona.\n'
      + '4. Documentar el lugar y hora exactos de la fuga.\n\n'
      + 'RESPONSABILIDAD: Se aplica el mismo marco de negligencia que en la Sección 12. Si la fuga ocurrió por descuido comprobable del Cuidador (correa sin asegurar, portón abierto, jaula mal cerrada), el Cuidador es responsable de los costos razonables de búsqueda (volantes, recompensa moderada) y de cualquier otra consecuencia civil aplicable. Si la fuga fue provocada por un factor externo repentino y ajeno a su control (ej. fuegos artificiales, un choque de tránsito cercano, un tercero que abrió una puerta), se considera un accidente fortuito y el Fondo de Garantía Garden puede cubrir gastos razonables de búsqueda, sujeto a verificación y disponibilidad.',
  },
  {
    title: '14. Daño causado por la mascota a terceros, a otras mascotas o a la propiedad',
    body: 'DAÑO A LA PROPIEDAD DEL CUIDADOR: Si la mascota del Cliente causa daños materiales al domicilio o pertenencias del Cuidador (muebles, pisos, objetos), el Cliente es responsable conforme al Art. 990 del Código Civil Boliviano (el dueño de un animal responde por los daños que este cause). El Cuidador debe documentar el daño con fotos y, de ser posible, comparar con fotos previas al servicio, además de facturas de reparación o reemplazo, y notificar a Garden dentro de las 24 horas siguientes para mediar la disputa — hasta un tope de Bs. 3.000 por incidente, sujeto a verificación.\n\n'
      + 'PELEAS ENTRE MASCOTAS EN GUARDERÍA U HOSPEDAJE: Si la mascota de un Cliente se pelea con la de otro Cliente, o con una mascota propia del Cuidador, dentro del mismo espacio: el Cuidador tiene el deber de evaluar la compatibilidad de los animales antes de mezclarlos y de separarlos ante la primera señal de tensión. Si no tomó esta precaución razonable, se aplica el marco de negligencia de la Sección 12. Si el altercado ocurre pese a medidas razonables de precaución, se trata como un accidente fortuito y puede acceder al Fondo de Garantía según corresponda.\n\n'
      + 'DAÑO A UN TERCERO QUE NO ES USUARIO DE GARDEN: Si la mascota lesiona a una persona ajena a la Plataforma (un peatón durante un paseo, un vecino, una visita en el domicilio del Cuidador), la responsabilidad civil recae en el Dueño de la mascota conforme al Art. 990 del Código Civil. Si el hecho ocurre mientras la mascota estaba bajo custodia del Cuidador, este asume frente al Dueño y frente a Garden las consecuencias económicas del reclamo (ver sección 31). Garden no es parte de ese reclamo, pero colaborará proporcionando a la autoridad competente los registros de la Reserva (GPS, fecha, identidad de las partes) que sean solicitados.\n\n'
      + 'REPORTE OBLIGATORIO POR MORDEDURA: Toda mordedura a una persona, sin importar la gravedad aparente, debe reportarse dentro de las 24 horas a las autoridades de salud municipal de Santa Cruz de la Sierra conforme al reglamento de control de rabia vigente, además de notificar a Garden a través de la app. El incumplimiento de este reporte es responsabilidad exclusiva de quien tenía la custodia de la mascota al momento del hecho.',
  },
  {
    title: '15. ¿Qué pasa si el Cuidador se lastima?',
    body: 'Los Cuidadores participan de forma voluntaria y son prestadores de servicios independientes, NO empleados de Garden (ver sección 30). Por lo tanto, Garden no está obligada a proveer seguro de accidentes laborales, seguro de salud ni aportes a la seguridad social.\n\n'
      + 'HERIDA O MORDIDA POR LA MASCOTA DEL CLIENTE:\n'
      + 'Conforme al Art. 990 del Código Civil Boliviano, el dueño de un animal es responsable por los daños que éste cause a terceros. Si la mascota del Cliente muerde o lesiona al Cuidador, el CLIENTE es civilmente responsable de los gastos médicos resultantes.\n\n'
      + 'El Cuidador debe:\n'
      + '1. Documentar el incidente con fotos, video y reporte médico.\n'
      + '2. Notificar a Garden dentro de las 2 horas siguientes.\n'
      + '3. Reportar la mordedura a las autoridades de salud municipal, conforme a la Sección 14.\n'
      + '4. Interponer disputa en la Plataforma para reclamación al Cliente.\n\n'
      + 'Garden podrá mediar la disputa y, a su criterio, retener fondos del Cliente para cubrir los gastos médicos documentados del Cuidador, hasta Bs. 3.000 por incidente; es una facilidad de mediación, no una obligación ni un seguro de Garden.\n\n'
      + 'ACCIDENTES INDEPENDIENTES DE LA MASCOTA:\n'
      + 'Caídas, accidentes de tránsito, u otros incidentes que no sean causados directamente por la mascota son responsabilidad del Cuidador. Garden recomienda encarecidamente que los Cuidadores contraten un seguro de accidentes personales.\n\n'
      + 'ACUERDO DE RIESGO: Al registrarse como Cuidador, el usuario reconoce expresamente que el cuidado de animales conlleva riesgos inherentes (mordeduras, arañazos, caídas, alérgenos, enfermedades zoonóticas transmisibles de un animal no vacunado) y acepta estos riesgos de forma voluntaria e informada, sin posibilidad de reclamar a Garden por ellos.',
  },
  {
    title: '16. Retención indebida y abandono de mascotas',
    body: 'RETENCIÓN INDEBIDA POR EL CUIDADOR: No devolver a la mascota al finalizar el servicio acordado, sin una causa justificada y documentada (por ejemplo, una emergencia veterinaria en curso reportada oportunamente), constituye retención no autorizada y puede configurar el delito de apropiación indebida conforme al Código Penal Boliviano. Ante esta situación, Garden suspenderá inmediatamente la cuenta del Cuidador, orientará al Cliente sobre cómo interponer una denuncia policial, y proporcionará a la autoridad competente todos los registros disponibles (chat, GPS, fotos, dirección registrada del Cuidador).\n\n'
      + 'BOTÓN SOS DEL DUEÑO: Además del "Reportar incidente" que puede usar el Cuidador (Sección 12), el Dueño cuenta con un botón de alerta ("SOS") visible durante cualquier servicio activo, pensado justamente para los casos en que el Cuidador sea la parte cuestionada. Al reportarlo, el equipo de Garden recibe una alerta urgente de forma inmediata y confidencial — por diseño, el Cuidador nunca es notificado de que se reportó un SOS, ni mientras está abierto ni al resolverse. Solo un administrador de Garden puede cerrar esta alerta; el Cuidador no tiene forma de autorresolverla.\n\n'
      + 'SUSPENSIÓN DURANTE UN SERVICIO EN CURSO: Si Garden suspende la cuenta de un Cuidador mientras tiene una Reserva confirmada o en curso, esa Reserva se cancela automáticamente con reembolso del 100% al Cliente, y el Cliente recibe de inmediato una notificación urgente con indicaciones concretas (contacto de soporte y referencia a este mismo proceso de retención indebida) para coordinar la recuperación de su mascota.\n\n'
      + 'ABANDONO POR EL DUEÑO: Si el Dueño no recoge a su mascota al finalizar un servicio de Hospedaje o Guardería y no responde a los intentos de contacto de Garden o del Cuidador dentro de 5 días calendario, Garden considerará la mascota en situación de abandono. En ese caso, el Cuidador puede: (a) acordar con el Dueño una extensión remunerada del servicio, cobrando la tarifa diaria correspondiente, la cual se acumula como deuda del Dueño; o (b) transcurridos los 5 días sin respuesta, entregar la mascota a la Defensoría de la Madre Tierra o a un refugio aliado de Garden, notificando previamente al Dueño por todos los medios de contacto disponibles. Garden no asume el costo del cuidado extendido, salvo que medie negligencia comprobada de Garden.',
  },
  {
    title: '17. Contacto de emergencia obligatorio',
    body: 'Todo Cuidador debe registrar exactamente 3 contactos de emergencia (nombre y teléfono de familiares o personas de confianza) como último paso de su registro, antes de que su perfil pueda activarse — sin importar qué servicios ofrezca.\n\n'
      + 'Si el Cuidador no puede ser contactado (no responde al chat, llamadas o notificaciones de la app) durante más de 12 horas mientras tiene una mascota bajo su custodia, Garden contactará a los contactos de emergencia registrados y, de ser necesario, a las autoridades locales, para verificar el bienestar del Cuidador y de la mascota.\n\n'
      + 'El Dueño también puede registrar un contacto de emergencia alternativo, por si Garden no logra comunicarse directamente con él durante una situación crítica relacionada con su mascota.',
  },
  {
    title: '18. Proceso de resolución de disputas',
    body: 'Garden ofrece un sistema de mediación interno antes de recurrir a instancias judiciales.\n\n'
      + 'PASO 1 — APERTURA DE DISPUTA:\n'
      + 'Cualquier parte puede abrir una disputa desde la app dentro de las 24 horas siguientes a la finalización del servicio. Pasado este plazo, el pago se libera definitivamente al Cuidador y no procede reclamación.\n\n'
      + 'PASO 2 — RESOLUCIÓN INICIAL (automatizada mediante IA):\n'
      + 'La evidencia ya existente en la reserva (fotos de inicio/fin de servicio, GPS, mensajes de chat, calificaciones) es analizada por un sistema de inteligencia artificial de Garden, que emite un veredicto inicial en minutos según reglas predefinidas y la evidencia disponible. Si el sistema de IA no está disponible, la disputa pasa a revisión manual de una persona del equipo de Garden en vez de resolverse automáticamente. En cualquiera de los dos casos, Garden puede:\n'
      + '• Liberar el pago total al Cuidador.\n'
      + '• Reembolsar parcial o totalmente al Cliente.\n'
      + '• Dividir el monto según grado de responsabilidad.\n'
      + '• Suspender o banear cuentas si hay evidencia de mala fe.\n\n'
      + 'PASO 3 — APELACIÓN (revisión humana):\n'
      + 'Cualquier parte puede apelar la resolución inicial en un plazo de 5 días hábiles desde el veredicto de la IA, presentando una explicación y, si tiene, nueva evidencia adicional. La apelación se registra en la app y queda en estado "en apelación" hasta ser resuelta. Toda apelación es revisada por una persona del equipo de Garden (no por el sistema automatizado), quien emite una decisión final por escrito — incluyendo, de corresponder, la corrección del pago o reembolso ya aplicado según el veredicto inicial de la IA. Esa decisión de apelación es definitiva dentro del proceso interno de Garden.\n\n'
      + 'PASO 4 — VÍA JUDICIAL:\n'
      + 'Si ninguna parte está satisfecha con la resolución de Garden, pueden recurrir a la Defensa del Consumidor (Ley N° 453) o a los tribunales civiles de Santa Cruz de la Sierra. Garden colaborará con las autoridades proporcionando todos los registros disponibles.',
  },
  {
    title: '19. Registro en blockchain (red principal de Polygon)',
    body: 'Desde el 4 de octubre de 2026, Garden registra cada Reserva pagada en la red principal de Polygon (Polygon PoS), una blockchain pública. Lo hacen dos smart contracts de Garden con el código publicado y verificado en polygonscan.com. No custodian dinero: los pagos se procesan fuera de la blockchain.\n\n'
      + 'QUÉ SE REGISTRA:\n'
      + '• El identificador interno de la Reserva.\n'
      + '• Una referencia seudónima de cada parte: un código derivado de su identificador interno con una clave secreta de Garden. Desde la blockchain no se puede llegar a su nombre, teléfono, correo ni a ningún otro dato personal.\n'
      + '• Tipo de servicio, monto pagado (en bolivianos) y fechas del servicio.\n'
      + '• Cada extensión del servicio, con el nuevo monto.\n'
      + '• Cómo terminó: servicio completado (con la calificación de 1 a 5 si el Dueño calificó, o sin calificación), cancelación (con un código de motivo y el monto reembolsado) o veredicto de una disputa (resultado y montos; también el de la apelación, si la hay).\n'
      + '• De los perfiles: la referencia seudónima, el rol (Dueño o Cuidador) y si la identidad fue verificada.\n\n'
      + 'QUÉ NO SE REGISTRA: nombres de personas ni de mascotas, teléfonos, correos, direcciones, fotos, mensajes del chat, comentarios de reseñas ni el texto de los análisis de disputas.\n\n'
      + 'DÓNDE VES TU COMPROBANTE: en el detalle de cada Reserva terminada, cancelada o rechazada (sección "Pago e historial"), el Dueño y el Cuidador ven "Registrada en blockchain" con el enlace a cada transacción en polygonscan.com. Mientras una transacción no se confirma, la Reserva muestra "Registro pendiente" y el sistema reintenta solo hasta completarlo. En Datos de la cuenta figuran la red y la dirección del contrato.\n\n'
      + 'DESDE CUÁNDO APLICA: a las Reservas pagadas desde el 4 de octubre de 2026. Las Reservas anteriores no tienen registro en blockchain, y así lo indica su detalle. Las reservas de prueba que crea el equipo de Garden no se registran.\n\n'
      + 'QUÉ IMPLICA PARA EL USUARIO:\n'
      + '• Lo registrado no puede ser alterado ni borrado por ninguna de las partes ni por Garden. Los hechos posteriores (una extensión, una cancelación, el resultado de una apelación) se agregan como registros nuevos.\n'
      + '• Cualquiera puede verificar el registro en polygonscan.com con el enlace del comprobante.\n'
      + '• En caso de litigio, el registro puede presentarse como evidencia documental; su valor probatorio lo determina la autoridad competente.\n\n'
      + 'LIMITACIÓN: El registro en blockchain es una herramienta de transparencia y no reemplaza las obligaciones legales establecidas en el Código Civil Boliviano ni en ninguna otra norma aplicable. Una falla de la red Polygon o de sus proveedores puede demorar un registro, pero no afecta tu Reserva ni tu pago.',
  },
  {
    title: '20. Verificación de identidad de Cuidadores',
    body: 'Todos los Cuidadores pasan por un proceso de verificación de identidad mediante inteligencia artificial antes de poder ofrecer servicios en la Plataforma:\n\n'
      + '1. Fotografía del Carnet de Identidad (CI) boliviano (anverso y reverso).\n'
      + '2. Selfie en tiempo real para comparación facial.\n'
      + '3. Validación automática de coincidencia de rostro con foto del CI.\n\n'
      + 'IMPORTANTE: La verificación confirma que la persona que se registra coincide con el documento presentado. NO implica que Garden avala el carácter, antecedentes penales o capacidad profesional del Cuidador.\n\n'
      + 'Los datos biométricos recopilados se usan exclusivamente para el proceso de verificación y no se comparten con terceros. Se almacenan cifrados por un máximo de 12 meses desde la última actividad del Cuidador en la Plataforma.',
  },
  {
    title: '21. Alcance del servicio',
    body: 'Garden opera actualmente en Santa Cruz de la Sierra, Bolivia. Los servicios están disponibles únicamente dentro del área metropolitana de Santa Cruz (Plan 3000, Equipetrol, Urubó, Los Lotes, Palmasola y zonas aledañas).\n\n'
      + 'Servicios que implican traslado de mascota (paseo, hospedaje): el Cuidador no puede transportar la mascota fuera del perímetro de Santa Cruz de la Sierra sin autorización escrita del Cliente.\n\n'
      + 'Garden no garantiza disponibilidad de Cuidadores en zonas rurales o localidades fuera del área metropolitana.',
  },
  {
    title: '22. Política de bienestar animal',
    body: 'Garden está comprometida con el bienestar de los animales. Todo usuario de la Plataforma acepta lo siguiente:\n\n'
      + '• Queda expresamente prohibido el maltrato físico, psicológico o por negligencia de cualquier animal, bajo pena de suspensión inmediata y denuncia ante las autoridades competentes.\n\n'
      + '• El maltrato animal en Bolivia puede ser sancionado bajo el Código Penal (Art. 347 Bis sobre daño a bienes con especial consideración para animales domésticos) y ordenanzas municipales del Gobierno Autónomo Municipal de Santa Cruz de la Sierra.\n\n'
      + '• Los Cuidadores se comprometen a:\n'
      + '  → Alimentar a la mascota con la frecuencia y tipo de alimento indicado por el Dueño.\n'
      + '  → Proveer agua fresca permanentemente.\n'
      + '  → Garantizar un espacio limpio, seguro y libre de amenazas.\n'
      + '  → No usar collares de pinchos, descargas eléctricas u otros dispositivos de corrección agresiva.\n'
      + '  → Reportar de inmediato cualquier cambio en el estado de salud o comportamiento de la mascota.',
  },
  {
    title: '23. Seguros recomendados',
    body: 'Bolivia no cuenta actualmente con un seguro obligatorio específico para servicios de cuidado de mascotas. Sin embargo, Garden recomienda encarecidamente:\n\n'
      + 'PARA DUEÑOS DE MASCOTAS:\n'
      + '• Contratar un seguro veterinario para su mascota que cubra urgencias y hospitalizaciones.\n'
      + '• Verificar que su póliza de seguro de hogar o de responsabilidad civil incluya daños causados por su mascota a terceros.\n\n'
      + 'PARA CUIDADORES:\n'
      + '• Contratar un seguro de accidentes personales que cubra actividades de cuidado de animales.\n'
      + '• Verificar que su seguro de hogar cubra daños a terceros y a animales bajo su custodia.\n\n'
      + 'La ausencia de seguro no exime a ninguna parte de sus responsabilidades civiles establecidas en el Código Civil Boliviano.',
  },
  {
    title: '24. Conducta prohibida y sanciones',
    body: 'Está terminantemente prohibido para TODOS los usuarios:\n\n'
      + '✗ Acordar o realizar transacciones económicas fuera de la Plataforma por servicios originados en Garden (circunvención de plataforma). Primera infracción: suspensión de 90 días. Segunda infracción: suspensión permanente.\n\n'
      + '✗ Crear perfiles falsos, usar identidades de terceros o proporcionar documentos falsificados. Sanción: suspensión permanente y denuncia penal.\n\n'
      + '✗ Publicar reseñas, calificaciones o comentarios falsos o manipulados. Sanción: eliminación del contenido y suspensión.\n\n'
      + '✗ Acosar, amenazar, extorsionar o discriminar a otros usuarios por cualquier medio. Sanción: suspensión inmediata y denuncia ante el Ministerio Público si corresponde.\n\n'
      + '✗ Usar Garden para actividades ilegales, incluyendo tráfico de animales, lavado de activos o cualquier actividad penada por las leyes bolivianas. Sanción: suspensión permanente y denuncia a las autoridades.\n\n'
      + '✗ Usar fotografías del domicilio de otro usuario, obtenidas a través de la Plataforma, con fines de vigilancia, acecho o para facilitar delitos contra la propiedad (por ejemplo, "casar" una vivienda para un robo). Sanción: suspensión permanente inmediata y denuncia penal.\n\n'
      + '✗ Registrar cuentas múltiples para evadir sanciones previas.\n\n'
      + '✗ Intentar acceder, hackear o dañar los sistemas informáticos de Garden, lo cual constituye delito informático conforme a la Ley N° 164 de Telecomunicaciones de Bolivia.\n\n'
      + 'SUSPENSIÓN AUTOMÁTICA POR CALIFICACIÓN BAJA (Cuidadores): Si un Cuidador acumula 5 o más calificaciones de 1 o 2 estrellas en el historial de sus Reservas, su cuenta se suspende automáticamente como medida preventiva, sin necesidad de una revisión manual previa. Un administrador de Garden puede revisar el caso y reactivar la cuenta; desde el momento de esa reactivación, solo se cuentan las calificaciones bajas nuevas para una eventual suspensión automática posterior — las anteriores a la reactivación no se vuelven a contar.\n\n'
      + 'REPORTE DE AUSENCIA (NO-SHOW) BIDIRECCIONAL: Tanto el Cliente como el Cuidador pueden reportar que la otra parte no se presentó al servicio acordado, dentro de las 24 horas siguientes a la cancelación por no presentación. Si una de las partes ya abrió un reclamo por este motivo, la otra debe responder dentro de ese mismo proceso en la app en vez de abrir uno nuevo.',
  },
  {
    title: '25. Privacidad y protección de datos',
    body: 'El tratamiento de tus datos personales se rige por la Política de Privacidad de Garden, disponible en la app y en garden.bo/privacidad.\n\n'
      + 'Garden cumple con los principios de protección de datos establecidos en la Constitución Política del Estado Plurinacional de Bolivia (Art. 130 — Habeas Data) y la Ley N° 164 de Telecomunicaciones.\n\n'
      + 'Tienes derecho a acceder, corregir y solicitar la eliminación de tus datos personales en cualquier momento contactando a privacidad@garden.bo.\n\n'
      + 'UBICACIÓN DURANTE SERVICIOS ACTIVOS: Durante un Paseo, Garden registra la ubicación en tiempo real del Cuidador para mostrar el recorrido al Dueño. Durante un servicio de Hospedaje o Guardería, Garden recolecta periódicamente puntos de ubicación del dispositivo del Cuidador mientras el servicio esté en curso, además de un punto al finalizarlo — esto es una medida de seguridad frente a robo o retención indebida de la mascota (ver Sección 16), y el registro solo es accesible para el equipo de Garden y, en caso de una denuncia, para la autoridad competente. Al solicitar la eliminación de su cuenta, un Cuidador también puede quedar registrado con un último punto de ubicación conocido, por el mismo motivo de seguridad.\n\n'
      + 'PIN DE SEGURIDAD: La Billetera (de Clientes y Cuidadores) y la sección de "gestionar reserva" del Cuidador (que incluye la ubicación exacta del Cliente y el inicio del servicio) están protegidas por un PIN propio de 4 dígitos, único por persona, con la opción de usar la biometría del dispositivo (huella o reconocimiento facial) como atajo. El PIN se almacena como un hash — nunca en texto plano — y ni el equipo de Garden ni ningún administrador puede verlo; solo puede reiniciarlo a solicitud del usuario cuando lo olvida, obligando a crear uno nuevo. Tras varios intentos fallidos, el PIN se bloquea temporalmente.',
  },
  {
    title: '26. Propiedad intelectual e imagen de los usuarios',
    body: 'Todo el contenido de Garden (nombre comercial, logotipo, diseño de interfaz, código fuente, algoritmos, base de datos de cuidadores) es propiedad exclusiva de Garden Bolivia y está protegido por la Ley N° 1322 de Derechos de Autor de Bolivia y los tratados internacionales suscritos por Bolivia (Convenio de Berna, ADPIC/TRIPS).\n\n'
      + 'Queda prohibido reproducir, distribuir, modificar, hacer ingeniería inversa o crear obras derivadas de cualquier elemento de Garden sin autorización escrita previa.\n\n'
      + 'IMAGEN DE LOS CUIDADORES: Los Cuidadores otorgan a Garden una licencia no exclusiva para usar sus fotografías de perfil y reseñas con fines de promoción de la Plataforma (por ejemplo, en la app, redes sociales o material publicitario), pudiendo revocarla por escrito en cualquier momento escribiendo a contactogardenbo@gmail.com. La revocación no afecta el uso ya realizado antes de la solicitud.\n\n'
      + 'CONTENIDO DE LOS CLIENTES: Los Clientes otorgan a Garden una licencia limitada y no exclusiva para usar las fotografías de su mascota y de su domicilio ÚNICAMENTE para: (a) prestar el servicio contratado, (b) el proceso de verificación automatizada por inteligencia artificial, y (c) como evidencia en caso de disputa. Estas fotografías NO se usarán con fines de marketing o publicidad de Garden sin el consentimiento expreso y por separado del Cliente.\n\n'
      + 'MENORES DE EDAD EN FOTOGRAFÍAS: Ningún usuario debe subir fotografías donde aparezcan menores de edad identificables (propios o de terceros) salvo que sea estrictamente necesario para el servicio y cuente con el consentimiento del padre, madre o tutor legal del menor. Si detectamos o se nos reporta una fotografía con un menor identificable sin el consentimiento correspondiente, la eliminaremos de inmediato al recibir la solicitud, sin necesidad de justificación adicional — escribe a privacidad@garden.bo.',
  },
  {
    title: '27. Limitación de responsabilidad y exención de demandas',
    body: 'Garden actúa exclusivamente como intermediario tecnológico y NO es parte del contrato de servicio entre Cliente y Cuidador. Los Cuidadores son prestadores de servicios independientes, no empleados, agentes ni representantes de Garden.\n\n'
      + 'EXENCIÓN EXPRESA DE RESPONSABILIDAD POR CONDUCTA DE CUIDADORES:\n'
      + 'Al aceptar estos Términos, el Usuario reconoce y acepta expresamente que:\n\n'
      + '1. En la máxima medida que la ley permita, Garden NO es responsable civil, penal ni administrativamente por actos, omisiones, negligencia, maltrato, abuso o cualquier otra conducta de los Cuidadores durante la prestación del servicio.\n\n'
      + '2. Si un Cuidador causa daño a una mascota, a un Cliente o a un tercero, la responsabilidad legal recae ÚNICAMENTE sobre el Cuidador de forma individual. El Usuario renuncia expresamente a cualquier acción judicial, administrativa o extrajudicial contra Garden por hechos imputables a Cuidadores.\n\n'
      + '3. Esta renuncia es válida y ejecutable conforme al Art. 519 del Código Civil Boliviano (principio de autonomía de la voluntad y libertad contractual) y el Art. 520 (fuerza vinculante de los contratos). Al aceptar estos Términos, el Usuario manifiesta su consentimiento libre, voluntario e informado.\n\n'
      + '4. Garden actúa como intermediario de buena fe, verificando la identidad de los Cuidadores, pero no garantiza ni puede garantizar el comportamiento futuro de ninguna persona natural. La verificación de identidad no implica aval de carácter, antecedentes penales o conducta.\n\n'
      + 'LIMITACIÓN GENERAL DE RESPONSABILIDAD:\n'
      + '• Garden NO garantiza la calidad, seguridad ni resultado de los servicios prestados por los Cuidadores.\n\n'
      + '• Garden NO asume responsabilidad por daños, lesiones, pérdidas o fallecimiento de mascotas, salvo los casos expresamente cubiertos por el Fondo de Garantía Garden (Sección 12), sujeto siempre a disponibilidad y verificación.\n\n'
      + '• La responsabilidad máxima de Garden ante cualquier reclamación que le sea atribuible directamente está limitada al monto de la tarifa de plataforma cobrado en la Reserva en disputa.\n\n'
      + '• Garden no es responsable por interrupciones del servicio causadas por fuerza mayor, fallas de terceros proveedores (internet, energía eléctrica, blockchain), errores de facturación no maliciosos que sean corregidos al detectarse, o ataques cibernéticos externos.\n\n'
      + '• Garden no es responsable por el uso que los Cuidadores o Clientes hagan de la información intercambiada fuera de la Plataforma.\n\n'
      + 'DERECHOS IRRENUNCIABLES: lo anterior se aplica en la máxima medida permitida por la ley y sin perjuicio de los derechos irrenunciables de los consumidores y usuarios (Ley N° 453) ni de las acciones que correspondan a las autoridades competentes.\n\n'
      + 'MEDIACIÓN VOLUNTARIA: El hecho de que Garden ofrezca un proceso de mediación y un Fondo de Garantía (Sección 12) es un acto voluntario de buena fe y no constituye, en ningún caso, reconocimiento de responsabilidad legal.',
  },
  {
    title: '28. Modificaciones a estos Términos',
    body: 'Garden puede actualizar estos Términos y Condiciones en cualquier momento. Los cambios significativos serán notificados:\n\n'
      + '• Por correo electrónico al email registrado en la cuenta, con al menos 15 días de anticipación.\n'
      + '• Mediante notificación push en la app.\n'
      + '• Con un aviso visible al iniciar sesión.\n\n'
      + 'CUIDADORES: para los Cuidadores, cada versión nueva debe aceptarse de forma expresa en la app (ver sección 32) y no basta el uso continuo; mientras no la acepten rigen las restricciones descritas en esa sección.\n\n'
      + 'El uso continuo de la Plataforma después del plazo de notificación implica la aceptación tácita de los nuevos términos. Si no estás de acuerdo con las modificaciones, puedes cerrar tu cuenta sin costo adicional dentro del plazo de notificación.',
  },
  {
    title: '29. Ley aplicable y jurisdicción',
    body: 'Estos Términos y Condiciones se rigen por las leyes de la República Plurinacional de Bolivia, incluyendo pero no limitado a:\n\n'
      + '• Código Civil Boliviano (D.L. N° 12760): contratos, responsabilidad civil, obligaciones.\n'
      + '• Ley N° 453 del Consumidor y del Usuario: derechos del consumidor de servicios.\n'
      + '• Ley N° 164 de Telecomunicaciones y TIC: servicios digitales y protección de datos.\n'
      + '• Ley N° 1322 de Derechos de Autor: propiedad intelectual.\n'
      + '• Ley N° 1333 de Medio Ambiente: protección de fauna silvestre.\n'
      + '• Código Penal Boliviano (D.L. N° 10426): delitos informáticos, fraude, falsedad, apropiación indebida.\n'
      + '• Constitución Política del Estado Plurinacional de Bolivia (2009): derechos fundamentales.\n\n'
      + 'Para cualquier controversia no resuelta mediante el proceso interno de Garden (Sección 18), las partes se someten expresamente a la jurisdicción de los Juzgados y Tribunales competentes de la ciudad de Santa Cruz de la Sierra, Bolivia, renunciando a cualquier otro fuero que pudiera corresponderles.',
  },
  {
    title: '30. Naturaleza voluntaria e independiente del Cuidador — sin relación laboral',
    body: 'El Cuidador participa en Garden de forma estrictamente VOLUNTARIA, por iniciativa propia y como PRESTADOR DE SERVICIOS INDEPENDIENTE. Garden no lo contrata ni le ofrece un cargo, puesto, empleo ni función dentro de la empresa. La inscripción, aprobación o permanencia en la Plataforma no crea relación laboral, de dependencia, de subordinación, de mandato, de agencia, de sociedad, de franquicia ni de representación entre el Cuidador y Garden.\n\n'
      + 'En consecuencia, y entre otras cosas:\n\n'
      + '• No existe salario, sueldo, aguinaldo, bonos, vacaciones, indemnización, desahucio, beneficios sociales ni aportes a la seguridad social a cargo de Garden.\n\n'
      + '• No hay horario, jornada, turnos, metas, exclusividad ni mínimo de servicios. El Cuidador decide libremente si, cuándo, cuánto y a quién atiende; puede rechazar cualquier solicitud sin justificación, trabajar con otras plataformas o por su cuenta, y dejar de usar Garden cuando quiera.\n\n'
      + '• Garden no dirige ni supervisa cómo el Cuidador presta el servicio. Las reglas de seguridad, de bienestar animal y de uso de la Plataforma existen para proteger a las mascotas, a los Dueños y la integridad del servicio; no son un poder de dirección propio de un empleador.\n\n'
      + '• El Cuidador aporta sus propios medios (domicilio, vehículo, herramientas, insumos y teléfono) y asume los costos y riesgos de su actividad.\n\n'
      + '• El Cuidador es el único responsable de sus obligaciones tributarias (inscripción en el NIT, IVA, IT, IUE u otras que le correspondan), de su seguridad social, de su salud y de sus seguros.\n\n'
      + '• El kit de bienvenida (polera y gorra) es un obsequio voluntario: no es uniforme, su uso es opcional y no genera subordinación.\n\n'
      + '• Las verificaciones de identidad, las calificaciones, la suspensión por incumplimiento y la aceptación periódica de estos Términos (sección 32) son mecanismos de seguridad y de calidad propios de una plataforma de intermediación, no el ejercicio de una potestad disciplinaria de empleador.\n\n'
      + 'El Cuidador declara y reconoce que no es ni será trabajador de Garden, que su relación con la Plataforma es la descrita en esta sección y que las personas que lo asistan (solo permitido con autorización, ver sección 11) tampoco son empleadas de Garden. Que Garden dé por terminada la participación de un Cuidador conforme a estos Términos no constituye un despido.',
  },
  {
    title: '31. Responsabilidad integral del Cuidador sobre la mascota e indemnidad',
    body: 'Desde que el Cuidador recibe a la mascota (o la retira del domicilio del Dueño) hasta que la devuelve al Dueño o a quien este designe, la mascota queda bajo su CUSTODIA EXCLUSIVA. Durante ese tiempo el Cuidador asume, frente al Dueño y frente a Garden, la máxima responsabilidad que la ley permita por la vida, salud, integridad, seguridad y paradero de la mascota, y por los daños que esta cause a terceros, a otras mascotas y a bienes.\n\n'
      + '1. RESPONSABILIDAD PRESUMIDA. Toda lesión, enfermedad, pérdida, fuga o muerte de la mascota ocurrida durante la custodia se presume imputable al Cuidador. Para liberarse debe probar, con evidencia documentada (fotos, GPS, chat, reportes veterinarios), alguna de estas causas: (a) una condición preexistente, una vacuna omitida o un dato relevante no declarado o falseado por el Dueño; (b) un hecho del Dueño o de un tercero ajeno a su control que no pudo evitar actuando con la debida diligencia; (c) fuerza mayor imprevisible e irresistible, habiendo cumplido de inmediato el procedimiento de emergencia de la sección 12; (d) muerte natural por edad avanzada o enfermedad terminal conocida.\n\n'
      + '2. ALCANCE. La responsabilidad comprende los gastos veterinarios (emergencia, tratamiento, hospitalización, necropsia), los gastos de búsqueda y la recompensa razonables, el valor de la mascota cuando corresponda y los demás daños acreditados, conforme a la ley.\n\n'
      + '3. DAÑOS A TERCEROS. El Cuidador responde frente al Dueño y frente a Garden por los reclamos de terceros (personas, otras mascotas, bienes) causados por la mascota mientras la tuvo bajo su custodia, sin perjuicio de la responsabilidad que la ley atribuya al Dueño frente al tercero.\n\n'
      + '4. INDEMNIDAD DE GARDEN. El Cuidador se obliga a mantener INDEMNE a Garden, a sus socios, directivos y dependientes, y a reembolsarles de inmediato toda suma que deban pagar (indemnizaciones, costas, honorarios razonables de abogado, multas y gastos de defensa) a causa de reclamos, demandas o denuncias vinculados con su conducta, su incumplimiento o hechos ocurridos durante su servicio o custodia. Garden podrá compensar esos montos con cualquier saldo o pago pendiente del Cuidador en la Billetera Garden y reclamar el remanente por la vía legal.\n\n'
      + '5. EL FONDO DE GARANTÍA NO ES UN SEGURO. Es una ayuda voluntaria y discrecional de Garden (sección 12): no es un derecho del Cuidador ni del Dueño, puede negarse, reducirse o suspenderse en cualquier momento y no implica reconocimiento de responsabilidad. Si Garden adelanta un pago y luego se determina negligencia del Cuidador, este lo reembolsa íntegramente.\n\n'
      + '6. RESPONSABILIDAD PERSONAL. La responsabilidad del Cuidador es personal y no se limita al monto de la Reserva ni a su saldo en la Plataforma: responde con su patrimonio. Es independiente de la responsabilidad penal que pudiera corresponderle por maltrato, abandono, retención indebida u otros hechos, respecto de la cual Garden colaborará con las autoridades (sección 16).\n\n'
      + '7. PRUEBA. El Cuidador acepta que los registros de la Plataforma (reserva, pagos, GPS, fotos, chat, calificaciones y registro en blockchain) se usen como prueba en cualquier reclamo.',
  },
  {
    title: '32. Aceptación periódica de estos Términos por el Cuidador (cada 2 meses)',
    body: 'Estos Términos, la Política de Privacidad y el Contrato de Cuidador deben ser aceptados de nuevo por el Cuidador CADA 2 MESES (60 días), contados desde su última aceptación, HAYA O NO prestado servicios en ese período y tenga o no reservas. Además, cada vez que Garden publique una versión nueva, el Cuidador debe aceptarla en la app dentro del plazo de 7 días que se le indique.\n\n'
      + 'CÓMO SE ACEPTA: desde la app, leyendo el texto vigente completo. Garden envía avisos en la app y notificaciones antes del vencimiento y mientras la aceptación esté pendiente.\n\n'
      + 'REGISTRO: cada aceptación queda guardada en el perfil del Cuidador, visible solo para el equipo de Garden, con fecha, hora, versión de los documentos, dirección IP y dispositivo. Garden podrá exhibir ese registro como evidencia.\n\n'
      + 'SI LA ACEPTACIÓN VENCE: el perfil deja de mostrarse en el marketplace y el Cuidador no puede recibir reservas nuevas hasta que acepte; vuelve a aparecer en cuanto lo haga. Las reservas ya confirmadas o en curso se atienden hasta su finalización bajo los términos que aceptó, y los pagos ya generados no se pierden. No aceptar no genera una sanción, pero el Cuidador puede dejar de usar Garden y solicitar la baja de su cuenta en cualquier momento.',
  },
  {
    title: '33. Declaraciones y responsabilidades adicionales del Dueño de mascota',
    body: 'Además de lo dispuesto en las secciones 8 y 9, el Dueño reconoce y acepta que:\n\n'
      + '1. ELECCIÓN LIBRE E INFORMADA. Elige por su cuenta al Cuidador (perfil, reseñas, Meet & Greet). Garden no recomienda ni garantiza a ningún Cuidador; las calificaciones y la verificación de identidad no garantizan su conducta futura.\n\n'
      + '2. RIESGOS INHERENTES. El cuidado de animales conlleva riesgos (estrés, enfermedad, lesiones, peleas, escape) que pueden presentarse aun con la debida diligencia, y los asume en la medida en que no sean imputables al Cuidador conforme a la sección 31.\n\n'
      + '3. RESPONSABILIDAD POR SU MASCOTA. Es responsable de su mascota fuera de la custodia del Cuidador y de lo que esta cause, dentro o fuera del servicio, cuando haya omitido o falseado información sobre su salud, temperamento o historial (sección 8).\n\n'
      + '4. AUTORIZACIÓN VETERINARIA Y LOCALIZACIÓN. Autoriza al Cuidador y a Garden a llevar a la mascota a un veterinario ante una emergencia, se obliga a pagar los gastos de atención que no se deban a negligencia comprobada del Cuidador y debe estar localizable durante todo el servicio.\n\n'
      + '5. RECLAMOS. Garden es un intermediario y no es parte del contrato de servicio: los reclamos por la prestación del servicio se dirigen al Cuidador, y a Garden solo por la mediación y los reembolsos previstos en estos Términos (sección 18), con la limitación de la sección 27.\n\n'
      + '6. INDEMNIDAD. Mantendrá indemne a Garden frente a reclamos de Cuidadores o de terceros originados en su mascota o en información falsa u omitida por el Dueño, y reembolsará los gastos razonables de defensa.\n\n'
      + '7. PRUEBA. Acepta que los registros de la Plataforma (GPS, chat, fotos, pagos y registro en blockchain) se usen como evidencia en cualquier reclamo.\n\n'
      + '8. TITULARIDAD. Declara ser propietario de la mascota o tener facultad para contratar su cuidado.',
  },
  {
    title: '34. Contacto y soporte',
    body: 'Para consultas, reportes o ejercicio de derechos:\n\n'
      + '📧 Email: contactogardenbo@gmail.com\n'
      + '📞 WhatsApp / Teléfono: +591 75933133\n'
      + '📍 Dirección: C. 6 Barrio Equipetrol, Santa Cruz de la Sierra, Bolivia\n\n'
      + 'Horario de atención: Lunes a Viernes, 8:00 a 18:00 (GMT-4, hora Bolivia).\n\n'
      + '© 2026 Garden Bolivia. Todos los derechos reservados.',
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

/** Términos vigentes: sin menciones de impuestos mientras estén en pausa (tax-clauses.ts). */
export function termsSections(taxesActive: boolean): Array<{ title: string; body: string }> {
  return taxesActive ? SECTIONS_TERMS : SECTIONS_TERMS.map((s) => ({ ...s, body: withoutTaxMentions(s.body) }));
}

/** GET /legal/terms — página pública de Términos y Condiciones (requerida por las tiendas de apps). */
router.get('/terms', async (_req, res) => {
  let taxesActive = false;
  try {
    taxesActive = (await getPricingConfig()).taxesActive;
  } catch {
    taxesActive = false;
  }
  res.set('Content-Type', 'text/html; charset=utf-8');
  res.send(renderPage('Términos y Condiciones', termsSections(taxesActive)));
});

export default router;
