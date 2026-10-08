/// Contenido del Contrato de Cuidador — se muestra como último paso del
/// registro (ver onboarding_wizard_screen.dart, _buildStep10) y exige que el
/// usuario scrollee hasta el final antes de poder aceptar. Se vuelve a mostrar
/// cada 2 meses (y ante una versión nueva) en la pantalla de renovación
/// (caregiver_terms_renewal_screen.dart). Complementa, no reemplaza, los
/// Términos y Condiciones y la Política de Privacidad (legal_screen.dart).
///
/// Si cambia una regla de negocio referenciada acá (comisión, plazos,
/// política de reembolsos, responsabilidad), actualizar también
/// legal_screen.dart, garden-api/src/modules/legal/legal.routes.ts y
/// garden-api/src/agents/soporte-chat.agent.ts — las copias deben coincidir.
///
/// Al cambiar los textos legales: subir [caregiverTermsVersion] y, en el
/// backend, CAREGIVER_TERMS_VERSION / CAREGIVER_TERMS_EFFECTIVE_AT
/// (garden-api/src/modules/legal/caregiver-terms.service.ts) — la app envía
/// esta versión al aceptar y el servidor la rechaza si no coincide.
library;

class ContractSection {
  final String title;
  final String body;
  const ContractSection(this.title, this.body);
}

const String contractLastUpdated = 'Octubre 2026';

/// Versión vigente de los textos que el Cuidador acepta (Términos + Privacidad + este contrato).
const String caregiverTermsVersion = '2026-10-05';

const List<ContractSection> caregiverContractSections = [
  ContractSection(
    '1. Naturaleza de este contrato: participación voluntaria e independiente',
    'Este es el Contrato de Cuidador de GARDEN BOLIVIA ("Garden"). Al aceptarlo, confirmas que eres mayor de 18 años y que participas en la Plataforma de forma estrictamente VOLUNTARIA, por iniciativa propia y como CUIDADOR INDEPENDIENTE. Garden NO te contrata ni te ofrece un cargo, puesto o empleo.\n\n'
    'No existe relación laboral, de dependencia, de subordinación, de mandato, de sociedad ni de representación entre tú y Garden, bajo ningún concepto. En concreto:\n\n'
    '• No hay salario, aguinaldo, bonos, vacaciones, indemnización ni aportes a la seguridad social a cargo de Garden.\n'
    '• No hay horario, turnos, metas, exclusividad ni mínimo de servicios. Tú decides si, cuándo y a quién atiendes, tus precios y tu disponibilidad; puedes rechazar cualquier solicitud, trabajar con otras plataformas o por tu cuenta, y dejar de usar Garden cuando quieras.\n'
    '• Garden no dirige cómo prestas el servicio. Sus reglas de seguridad y bienestar animal existen para proteger a las mascotas y a los Dueños, no para darte órdenes como un empleador.\n'
    '• Pones tus propios medios (domicilio, vehículo, insumos, teléfono) y asumes los costos y riesgos de tu actividad.\n'
    '• Eres el único responsable de tus impuestos (NIT, IVA, IT, IUE u otros que te correspondan), de tu seguridad social, de tu salud y de tus seguros.\n\n'
    'Este contrato complementa — no reemplaza — los Términos y Condiciones y la Política de Privacidad de Garden. Ante cualquier duda entre ambos documentos, prevalece el más específico sobre el tema en cuestión.',
  ),
  ContractSection(
    '2. Qué es Garden y qué no es',
    'Garden es una plataforma tecnológica que te conecta con dueños de mascotas en Santa Cruz de la Sierra. Procesamos pagos de forma segura, verificamos tu identidad, te damos herramientas de comunicación y seguimiento GPS, y mediamos disputas cuando hace falta.\n\n'
    'Garden NO es una agencia de empleo, ni una empresa de cuidado de mascotas, ni tu empleador, ni tu aseguradora. Tú eres quien presta el servicio directamente al Cliente; Garden facilita el encuentro y protege la transacción.',
  ),
  ContractSection(
    '3. Tus obligaciones como Cuidador',
    'Al aceptar una reserva, te comprometes a:\n\n'
    '• Cumplir con el horario y las condiciones acordadas con el Cliente.\n'
    '• Tratar a cada mascota con cuidado, paciencia y respeto en todo momento.\n'
    '• No delegar el cuidado a otra persona sin autorización expresa del Cliente y de Garden.\n'
    '• No coordinar ni aceptar pagos por fuera de la app para servicios originados en Garden — esto te deja sin la mediación de Garden y puede suspender tu cuenta.\n'
    '• Transportar a las mascotas con condiciones mínimas de seguridad (correa, arnés o jaula homologada).\n'
    '• No administrar medicamentos sin instrucción escrita del Dueño.\n'
    '• Prestar el servicio siempre sobrio y sin sustancias controladas.\n'
    '• Responder al chat de la reserva y a las notificaciones de la app en un tiempo razonable.',
  ),
  ContractSection(
    '4. Cómo se paga tu servicio',
    'Tú fijas libremente tu propio precio. Garden suma una tarifa de plataforma sobre tu precio (varía según el servicio); tú nunca pierdes parte de tu tarifa. Ejemplo: si cobras Bs. 100, tú recibes tus Bs. 100 completos.\n\n'
    'El pago se libera a tu billetera Garden de inmediato si el Cliente confirma que el servicio terminó bien, o automáticamente a las 24 horas de finalizado el servicio si el Cliente no confirma ni abre una disputa. Las propinas que te dejen los Clientes son 100% tuyas, sin comisión.\n\n'
    'Puedes retirar tu saldo a tu cuenta bancaria o billetera digital cuando quieras (monto mínimo aplica) — se procesa en 1-3 días hábiles, sin costo.\n\n'
    'Lo que recibes es un ingreso por tu servicio independiente: declararlo y pagar los impuestos que correspondan es tu responsabilidad.',
  ),
  ContractSection(
    '5. Contactos de emergencia',
    'Los 3 contactos de emergencia que registraste en el paso anterior son parte de este contrato: autorizas a Garden a contactarlos si no podemos comunicarnos contigo durante más de 12 horas mientras tienes una mascota bajo tu cuidado, para verificar tu bienestar y el de la mascota. Es una medida de seguridad para ti también, no solo para el Cliente.',
  ),
  ContractSection(
    '6. Tu responsabilidad total sobre la mascota',
    'Desde que recibes a la mascota (o la retiras del domicilio del Dueño) hasta que la devuelves, está bajo tu CUSTODIA EXCLUSIVA. Durante ese tiempo asumes, frente al Dueño y frente a Garden, la máxima responsabilidad que la ley permita por su vida, salud, integridad, seguridad y paradero, y por los daños que cause a terceros, a otras mascotas y a bienes.\n\n'
    '• RESPONSABILIDAD PRESUMIDA: toda lesión, enfermedad, pérdida, fuga o muerte ocurrida durante tu custodia se presume imputable a ti. Para liberarte tendrás que probar, con evidencia (fotos, GPS, chat, reportes veterinarios), que se debió a una condición o dato que el Dueño no declaró o falseó, a un hecho ajeno que no pudiste evitar actuando con la debida diligencia, a una fuerza mayor imprevisible e irresistible (habiendo cumplido de inmediato el procedimiento de emergencia), o a una muerte natural por edad o enfermedad terminal conocida.\n'
    '• ALCANCE: gastos veterinarios (emergencia, tratamiento, hospitalización, necropsia), gastos de búsqueda y recompensa razonables, el valor de la mascota cuando corresponda y los demás daños acreditados.\n'
    '• ANTE UN INCIDENTE, tu primera obligación es llevar a la mascota al veterinario más cercano sin demora, avisar a Garden y al Cliente por la app dentro de los 30 minutos y documentar todo. Eso determina si actuaste de buena fe, pero no te libera de la responsabilidad descrita arriba.\n'
    '• PERSONAL: tu responsabilidad no se limita al monto de la reserva ni a tu saldo en Garden: respondes con tu patrimonio, y es independiente de la responsabilidad penal que pudiera corresponderte por maltrato, abandono o retención indebida.\n\n'
    'El detalle completo está en las secciones 12 y 31 de los Términos y Condiciones.',
  ),
  ContractSection(
    '7. Indemnidad de Garden y Fondo de Garantía',
    'Te obligas a mantener INDEMNE a Garden, a sus socios, directivos y dependientes, y a reembolsarles de inmediato toda suma que deban pagar (indemnizaciones, costas, honorarios razonables de abogado, multas y gastos de defensa) por reclamos, demandas o denuncias vinculados con tu conducta, tu incumplimiento o hechos ocurridos durante tu servicio o custodia. Garden podrá compensar esos montos con tu saldo o con pagos pendientes en la Billetera Garden y reclamarte el resto por la vía legal.\n\n'
    'El Fondo de Garantía Garden (hasta Bs. 2.000 por caso) es una ayuda voluntaria y discrecional de Garden: NO es un seguro, NO es un derecho tuyo ni del Dueño, puede negarse, reducirse o suspenderse en cualquier momento y no significa que Garden reconozca responsabilidad alguna. Si Garden adelanta un pago y luego se comprueba negligencia de tu parte, debes reembolsarlo íntegramente. Te recomendamos contratar tu propio seguro de accidentes y de responsabilidad civil.',
  ),
  ContractSection(
    '8. Verificación de identidad',
    'Ya pasaste (o vas a pasar) por nuestra verificación de identidad con reconocimiento facial. Esto confirma que eres quien dices ser — no es un aval de Garden sobre tu carácter o antecedentes. Si subiste tu documento de antecedentes penales de forma voluntaria, una persona del equipo de Garden lo revisa antes de darte el distintivo, con ayuda de un sistema que señala antecedentes explícitos de maltrato animal o violencia; nunca lo decide una IA sola.',
  ),
  ContractSection(
    '9. Tu kit de bienvenida (voluntario)',
    'Como obsequio, Garden te enviará un kit de bienvenida con una polera y una gorra de Garden, en la talla que elegiste en tu registro. Llegará a tu domicilio en 1 a 3 días hábiles y coordinaremos la entrega con tus datos de contacto.\n\n'
    'Es un regalo: no tiene costo, no se descuenta de tus pagos, usarlo es OPCIONAL y no es un uniforme ni te obliga a nada. Si decides usarlo, ayuda a que los dueños te reconozcan al momento de la recogida.',
  ),
  ContractSection(
    '10. Qué puede causar la suspensión de tu cuenta',
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
    '11. Si hay una disputa',
    'Si un Cliente cuestiona un servicio, un sistema de inteligencia artificial revisa la evidencia disponible (fotos, GPS, chat, calificaciones) y emite un veredicto inicial en minutos. Si no estás de acuerdo, tienes 5 días hábiles para apelar — la apelación la resuelve siempre una persona real del equipo de Garden, nunca la IA, y esa decisión es la definitiva dentro de Garden. El pago, el cierre de cada servicio y el veredicto de cada disputa quedan registrados en la red Polygon, sin datos personales.',
  ),
  ContractSection(
    '12. Aceptación periódica cada 2 meses',
    'Estos documentos (Términos y Condiciones, Política de Privacidad y este contrato) debes aceptarlos de nuevo CADA 2 MESES (60 días), contados desde tu última aceptación, HAYAS O NO prestado servicios en ese período. También cuando Garden publique una versión nueva (tendrás 7 días para aceptarla).\n\n'
    'La aceptación se hace en la app, leyendo el texto vigente completo, y queda guardada en tu perfil — visible solo para el equipo de Garden — con fecha, hora, versión, dirección IP y dispositivo. Garden podrá usar ese registro como evidencia.\n\n'
    'Si tu aceptación vence, tu perfil deja de mostrarse en el marketplace y no puedes recibir reservas nuevas hasta que aceptes; vuelves a aparecer en cuanto lo hagas. Las reservas ya confirmadas o en curso se atienden hasta el final y tus pagos ya generados no se pierden. Te avisaremos por la app antes del vencimiento.',
  ),
  ContractSection(
    '13. Terminación',
    'Puedes dejar de ofrecer servicios en Garden cuando quieras, sin penalización, siempre que no tengas reservas confirmadas o en curso pendientes. Garden puede terminar tu participación en la Plataforma ante un incumplimiento grave de lo descrito arriba, notificándote el motivo a través de la app; esto no constituye un despido, porque no existe relación laboral.',
  ),
  ContractSection(
    '14. Aceptación',
    'Al tocar "Acepto" declaras que leíste este contrato completo, que participas de forma voluntaria y como prestador de servicios independiente (no como empleado de Garden), que asumes la responsabilidad total sobre las mascotas bajo tu custodia y la obligación de indemnidad descritas arriba, y que aceptas cumplir con todo lo descrito aquí como condición para operar como Cuidador en la plataforma Garden.',
  ),
];
