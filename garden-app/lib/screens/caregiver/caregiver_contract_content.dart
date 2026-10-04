/// Contenido del Contrato de Cuidador — se muestra como último paso del
/// registro (ver onboarding_wizard_screen.dart, _buildStep10) y exige que el
/// usuario scrollee hasta el final antes de poder aceptar. Complementa, no
/// reemplaza, los Términos y Condiciones y la Política de Privacidad
/// (legal_screen.dart) que el Cuidador ya aceptó en el Paso 0 del registro.
///
/// Si cambia una regla de negocio referenciada acá (comisión, plazos,
/// política de reembolsos), actualizar también legal_screen.dart y
/// garden-api/src/agents/soporte-chat.agent.ts — las tres copias deben
/// coincidir.
library;

class ContractSection {
  final String title;
  final String body;
  const ContractSection(this.title, this.body);
}

const String contractLastUpdated = 'Agosto 2026';

const List<ContractSection> caregiverContractSections = [
  ContractSection(
    '1. Naturaleza de este contrato',
    'Este es el Contrato de Cuidador de GARDEN BOLIVIA ("Garden"). Al aceptarlo, confirmas que eres mayor de 18 años y que vas a prestar servicios de cuidado de mascotas como CUIDADOR INDEPENDIENTE a través de la Plataforma — no como empleado, dependiente ni socio de Garden. No existe relación laboral entre tú y Garden bajo ningún concepto: no hay salario, aguinaldo, horario fijo impuesto por Garden, ni subordinación. Tú decides qué reservas aceptar, tus precios y tu disponibilidad.\n\n'
    'Este contrato complementa — no reemplaza — los Términos y Condiciones y la Política de Privacidad de Garden, que ya aceptaste al comenzar tu registro. Ante cualquier duda entre ambos documentos, prevalece el más específico sobre el tema en cuestión.',
  ),
  ContractSection(
    '2. Qué es Garden y qué no es',
    'Garden es una plataforma tecnológica que te conecta con dueños de mascotas en Santa Cruz de la Sierra. Procesamos pagos de forma segura, verificamos tu identidad, te damos herramientas de comunicación y seguimiento GPS, y mediamos disputas cuando hace falta.\n\n'
    'Garden NO es una agencia de empleo ni una empresa de cuidado de mascotas. Tú eres quien presta el servicio directamente al Cliente; Garden facilita el encuentro y protege la transacción.',
  ),
  ContractSection(
    '3. Tus obligaciones como Cuidador',
    'Al aceptar una reserva, te comprometes a:\n\n'
    '• Cumplir con el horario y las condiciones acordadas con el Cliente.\n'
    '• Tratar a cada mascota con cuidado, paciencia y respeto en todo momento.\n'
    '• No delegar el cuidado a otra persona sin autorización expresa del Cliente y de Garden.\n'
    '• No coordinar ni aceptar pagos por fuera de la app para servicios originados en Garden — esto te deja sin la protección del Fondo de Garantía y puede suspender tu cuenta.\n'
    '• Transportar a las mascotas con condiciones mínimas de seguridad (correa, arnés o jaula homologada).\n'
    '• No administrar medicamentos sin instrucción escrita del Dueño.\n'
    '• Prestar el servicio siempre sobrio y sin sustancias controladas.\n'
    '• Responder al chat de la reserva y a las notificaciones de la app en un tiempo razonable.',
  ),
  ContractSection(
    '4. Cómo se paga tu trabajo',
    'Tú fijas libremente tu propio precio. Garden suma una tarifa de plataforma sobre tu precio (varía según el servicio) y el Cliente paga además los impuestos de ley; tú nunca pierdes parte de tu tarifa. Ejemplo: si cobras Bs. 100, tú recibes tus Bs. 100 completos.\n\n'
    'El pago se libera a tu billetera Garden de inmediato si el Cliente confirma que el servicio terminó bien, o automáticamente a las 24 horas de finalizado el servicio si el Cliente no confirma ni abre una disputa. Las propinas que te dejen los Clientes son 100% tuyas, sin comisión.\n\n'
    'Puedes retirar tu saldo a tu cuenta bancaria o billetera digital cuando quieras (monto mínimo aplica) — se procesa en 1-3 días hábiles, sin costo.',
  ),
  ContractSection(
    '5. Contactos de emergencia',
    'Los 3 contactos de emergencia que registraste en el paso anterior son parte de este contrato: autorizas a Garden a contactarlos si no podemos comunicarnos contigo durante más de 12 horas mientras tienes una mascota bajo tu cuidado, para verificar tu bienestar y el de la mascota. Es una medida de seguridad para ti también, no solo para el Cliente.',
  ),
  ContractSection(
    '6. Responsabilidad ante incidentes',
    'La seguridad de la mascota es tu responsabilidad principal mientras esté a tu cargo. Ante cualquier lesión, enfermedad o accidente, tu única obligación inmediata es llevarla al veterinario más cercano sin demora — eso es lo que determina si actuaste de buena fe.\n\n'
    'Si la investigación de Garden determina que el incidente fue accidental y no hubo negligencia de tu parte, el Fondo de Garantía Garden (hasta Bs. 2.000) puede cubrir los gastos veterinarios. Si se comprueba negligencia (descuido, abandono, falta de agua o alimento, sustancias tóxicas accesibles), los gastos corren enteramente por tu cuenta y Garden puede retenerlos de tus próximos pagos.\n\n'
    'El detalle completo de este proceso está en la Sección 12 de los Términos y Condiciones — te recomendamos leerla si todavía no lo hiciste.',
  ),
  ContractSection(
    '7. Verificación de identidad',
    'Ya pasaste (o vas a pasar) por nuestra verificación de identidad con reconocimiento facial. Esto confirma que eres quien dices ser — no es un aval de Garden sobre tu carácter o antecedentes. Si subiste tu documento de antecedentes penales de forma voluntaria, nuestro sistema solo lo revisa para detectar antecedentes explícitos de maltrato animal o violencia; cualquier caso dudoso lo revisa una persona del equipo de Garden, nunca una IA sola.',
  ),
  ContractSection(
    '8. Tu kit de bienvenida Garden',
    'Como parte de tu incorporación, Garden te va a enviar un kit de bienvenida con una polera y una gorra oficiales de Garden — la talla que elegiste en el paso anterior de tu registro.\n\n'
    'El kit llegará a tu domicilio en un plazo de 1 a 3 días hábiles. Coordinaremos contigo el día y horario de entrega a través de tus datos de contacto registrados — no hace falta que hagas nada más por ahora.\n\n'
    'Te pedimos usar la polera y/o gorra durante tus servicios activos: ayuda a que los dueños de mascotas te reconozcan fácilmente al momento de la recogida, y refuerza la confianza en la marca Garden frente a vecinos y terceros durante paseos. El kit es un obsequio de Garden para ti como Cuidador activo de la plataforma — no tiene costo ni se descuenta de tus pagos.',
  ),
  ContractSection(
    '9. Qué puede causar la suspensión de tu cuenta',
    'Garden puede suspender tu cuenta, de forma temporal o permanente, ante:\n\n'
    '• Maltrato, abandono o negligencia comprobada hacia una mascota bajo tu cuidado.\n'
    '• Retención indebida de una mascota al finalizar el servicio.\n'
    '• Cobrar o coordinar pagos fuera de la plataforma.\n'
    '• Prestar servicio bajo efectos de alcohol o sustancias controladas.\n'
    '• Acoso, insultos o discriminación hacia Clientes.\n'
    '• Reseñas falsas o manipulación de tu calificación.\n'
    '• Información falsa en tu registro o documentos.\n'
    '• Tres cancelaciones tardías (menos de 24h antes) en un período de 90 días.\n\n'
    'En casos graves, Garden puede además reportar la situación a las autoridades competentes (FELCC, Defensoría de la Madre Tierra, Gobierno Autónomo Municipal), conforme a lo descrito en los Términos y Condiciones.',
  ),
  ContractSection(
    '10. Si hay una disputa',
    'Si un Cliente cuestiona un servicio, un sistema de inteligencia artificial revisa la evidencia disponible (fotos, GPS, chat, calificaciones) y emite un veredicto inicial en minutos. Si no estás de acuerdo, tienes 5 días hábiles para apelar — la apelación la resuelve siempre una persona real del equipo de Garden, nunca la IA, y esa decisión es la definitiva dentro de Garden. El pago, el cierre de cada servicio y el veredicto de cada disputa quedan registrados en la red Polygon, sin datos personales.',
  ),
  ContractSection(
    '11. Terminación',
    'Puedes dejar de ofrecer servicios en Garden cuando quieras, sin penalización, siempre que no tengas reservas activas pendientes. Garden puede terminar este contrato en cualquier momento ante un incumplimiento grave de lo descrito arriba, notificándote el motivo a través de la app.',
  ),
  ContractSection(
    '12. Aceptación',
    'Al tocar "Acepto y finalizo el registro" declaras que leíste este contrato completo, que entiendes que actúas como prestador de servicios independiente (no empleado de Garden), y que aceptas cumplir con todo lo descrito aquí como condición para operar como Cuidador en la plataforma Garden.',
  ),
];
