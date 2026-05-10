import 'package:flutter/material.dart';
import '../../theme/garden_theme.dart';

/// Pantalla genérica para documentos legales (Política + Términos).
/// Se instancia con [title] y [sections] — cada sección tiene título y párrafo.
class LegalScreen extends StatelessWidget {
  final String title;
  final String lastUpdated;
  final List<_LegalSection> sections;

  const LegalScreen({
    super.key,
    required this.title,
    required this.lastUpdated,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? GardenColors.background : const Color(0xFFF7F9F4);
    final surface = isDark ? GardenColors.surface : Colors.white;
    final text = isDark ? GardenColors.textPrimary : const Color(0xFF1A2E0A);
    final subtext = isDark ? GardenColors.textSecondary : const Color(0xFF5A7040);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: text, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: TextStyle(color: text, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Chip de última actualización
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: GardenColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Última actualización: $lastUpdated',
              style: TextStyle(color: GardenColors.primary, fontSize: 12, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),

          ...sections.map((s) => _SectionWidget(section: s, textColor: text, subtextColor: subtext, surface: surface)),

          const SizedBox(height: 40),

          // Footer
          Text(
            '© 2025 Garden Bolivia. Todos los derechos reservados.\nSanta Cruz de la Sierra, Bolivia.',
            style: TextStyle(color: subtext, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionWidget extends StatelessWidget {
  final _LegalSection section;
  final Color textColor;
  final Color subtextColor;
  final Color surface;

  const _SectionWidget({
    required this.section,
    required this.textColor,
    required this.subtextColor,
    required this.surface,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: TextStyle(
              color: textColor,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            section.body,
            style: TextStyle(
              color: subtextColor,
              fontSize: 13.5,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalSection {
  final String title;
  final String body;
  const _LegalSection(this.title, this.body);
}

// ── Política de Privacidad ────────────────────────────────────────────────────

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LegalScreen(
      title: 'Política de Privacidad',
      lastUpdated: 'Enero 2025',
      sections: const [
        _LegalSection(
          '1. ¿Quiénes somos?',
          'Garden Bolivia es una plataforma de servicios de cuidado de mascotas que conecta a dueños de mascotas con cuidadores verificados en Santa Cruz de la Sierra, Bolivia. Operamos bajo la normativa boliviana de protección de datos personales.',
        ),
        _LegalSection(
          '2. Datos que recopilamos',
          'Recopilamos los siguientes datos para operar el servicio:\n\n'
          '• Datos de cuenta: nombre, apellido, correo electrónico, teléfono y contraseña (cifrada).\n'
          '• Datos de perfil: foto de perfil, dirección, información sobre tu mascota (nombre, raza, edad, necesidades especiales).\n'
          '• Datos de verificación: para cuidadores, fotografía del carnet de identidad (CI) para validar la identidad.\n'
          '• Datos de uso: reservas, pagos, mensajes de chat, calificaciones y reseñas.\n'
          '• Datos técnicos: dirección IP, tipo de dispositivo, sistema operativo, identificadores únicos del dispositivo.',
        ),
        _LegalSection(
          '3. ¿Para qué usamos tus datos?',
          '• Crear y gestionar tu cuenta en Garden.\n'
          '• Procesar reservas y pagos entre clientes y cuidadores.\n'
          '• Verificar la identidad de los cuidadores para garantizar la seguridad.\n'
          '• Enviarte notificaciones relacionadas con tus reservas y actividad.\n'
          '• Mejorar nuestros servicios mediante análisis de uso agregado y anónimo.\n'
          '• Detectar y prevenir fraudes o actividades no autorizadas.\n'
          '• Cumplir con obligaciones legales aplicables en Bolivia.',
        ),
        _LegalSection(
          '4. Compartición de datos',
          'Garden no vende ni alquila tus datos personales a terceros. Solo compartimos información cuando es necesario para prestar el servicio:\n\n'
          '• Entre clientes y cuidadores: nombre, foto y datos de la reserva visibles para ambas partes.\n'
          '• Proveedores de servicio: Stripe (pagos), Cloudinary (imágenes), Firebase (notificaciones), AWS (verificación de identidad). Todos operan bajo acuerdos de confidencialidad.\n'
          '• Autoridades: solo cuando la ley boliviana lo exija con orden judicial válida.',
        ),
        _LegalSection(
          '5. Almacenamiento y seguridad',
          'Tus datos se almacenan en servidores seguros con cifrado en tránsito (HTTPS/TLS) y en reposo. Las contraseñas se almacenan como hashes bcrypt y nunca en texto plano. Los tokens de sesión tienen expiración automática. Monitoreamos activamente incidentes de seguridad mediante Sentry.',
        ),
        _LegalSection(
          '6. Tus derechos',
          'Tienes derecho a:\n\n'
          '• Acceder a los datos personales que tenemos sobre ti.\n'
          '• Rectificar datos incorrectos o desactualizados.\n'
          '• Solicitar la eliminación de tu cuenta y datos asociados.\n'
          '• Oponerte al procesamiento de tus datos para fines de marketing.\n\n'
          'Para ejercer estos derechos, escríbenos a privacidad@garden.bo.',
        ),
        _LegalSection(
          '7. Cookies y rastreo',
          'La app móvil no utiliza cookies. La versión web puede utilizar cookies técnicas estrictamente necesarias para mantener tu sesión. No utilizamos cookies de rastreo de terceros.',
        ),
        _LegalSection(
          '8. Menores de edad',
          'Garden está destinada a mayores de 18 años. No recopilamos conscientemente datos de menores. Si detectas que un menor ha creado una cuenta, contáctanos a privacidad@garden.bo para eliminarla.',
        ),
        _LegalSection(
          '9. Cambios a esta política',
          'Podemos actualizar esta Política de Privacidad para reflejar cambios en nuestras prácticas o por requerimientos legales. Te notificaremos por correo electrónico o mediante una notificación en la app con al menos 15 días de anticipación.',
        ),
        _LegalSection(
          '10. Contacto',
          'Para consultas sobre privacidad:\n'
          'Email: privacidad@garden.bo\n'
          'Teléfono: +591 7XXXXXXX\n'
          'Dirección: Santa Cruz de la Sierra, Bolivia.',
        ),
      ],
    );
  }
}

// ── Términos y Condiciones Completos ─────────────────────────────────────────

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LegalScreen(
      title: 'Términos y Condiciones',
      lastUpdated: 'Mayo 2026',
      sections: const [

        // ── 1. QUIÉNES SOMOS ─────────────────────────────────────────────────
        _LegalSection(
          '1. Quiénes somos y qué es Garden',
          'Garden Bolivia ("Garden", "la Plataforma", "nosotros") es una plataforma tecnológica de intermediación que conecta a dueños de mascotas ("Clientes" o "Dueños") con personas que ofrecen servicios de cuidado de animales domésticos ("Cuidadores") en Santa Cruz de la Sierra, Bolivia.\n\n'
          'Garden NO es una empresa de cuidado de mascotas ni empleadora de cuidadores. Actuamos exclusivamente como intermediario tecnológico que facilita el encuentro entre oferta y demanda, procesa pagos de forma segura y ofrece herramientas de comunicación y seguimiento del servicio.\n\n'
          'Nos respaldamos en tecnología blockchain (red Polygon) para registrar contratos de servicio de manera inmutable y transparente, garantizando que ninguna de las partes pueda modificar retroactivamente los términos acordados.',
        ),

        // ── 2. DEFINICIONES ──────────────────────────────────────────────────
        _LegalSection(
          '2. Definiciones clave',
          '• CLIENTE / DUEÑO: persona natural mayor de 18 años que usa Garden para contratar servicios de cuidado para su mascota.\n\n'
          '• CUIDADOR: persona natural mayor de 18 años, verificada por Garden, que ofrece servicios de cuidado de mascotas a través de la Plataforma. Los Cuidadores son prestadores de servicios independientes, NO empleados ni dependientes de Garden.\n\n'
          '• RESERVA: acuerdo de servicio entre un Cliente y un Cuidador, confirmado y pagado a través de la Plataforma.\n\n'
          '• SERVICIO: cualquier modalidad de cuidado de mascotas ofrecida en la Plataforma (hospedaje, guardería, paseo, visita domiciliaria, baño y estética).\n\n'
          '• SMART CONTRACT: contrato inteligente desplegado en la red Polygon que registra los términos de cada Reserva (precio, fechas, condiciones) de forma inmutable. Una vez confirmada la Reserva, sus términos no pueden modificarse unilateralmente.\n\n'
          '• BILLETERA GARDEN: saldo virtual en Bolivianos acumulado en la cuenta del usuario, producto de reembolsos u otros créditos otorgados por Garden.\n\n'
          '• COMISIÓN DE PLATAFORMA: tarifa que Garden cobra sobre el valor de cada Reserva por el uso de la infraestructura tecnológica, procesamiento de pagos y garantías del servicio.\n\n'
          '• FONDO DE GARANTÍA GARDEN: reserva económica administrada por Garden destinada a cubrir situaciones excepcionales contempladas en estos Términos.',
        ),

        // ── 3. REQUISITOS DE REGISTRO ────────────────────────────────────────
        _LegalSection(
          '3. Requisitos para registrarse',
          'TODOS LOS USUARIOS:\n'
          '• Ser persona natural mayor de 18 años.\n'
          '• Proporcionar nombre completo real, correo electrónico válido y número de teléfono activo en Bolivia.\n'
          '• Aceptar estos Términos y la Política de Privacidad de forma expresa antes de completar el registro.\n'
          '• No haber sido suspendido o baneado previamente de la Plataforma.\n\n'
          'CUIDADORES (requisitos adicionales):\n'
          '• Presentar Cédula de Identidad (CI) boliviana vigente para verificación de identidad mediante IA.\n'
          '• Completar el proceso de verificación facial de identidad antes de ofrecer servicios.\n'
          '• Proporcionar una dirección física verificable en Santa Cruz de la Sierra (para servicios en domicilio del cuidador).\n'
          '• No tener antecedentes penales relacionados con maltrato animal o violencia (Garden puede verificar esto en coordinación con autoridades).\n'
          '• Aceptar expresamente la Política de Bienestar Animal de Garden.\n\n'
          'La información falsa en el registro constituye causal de suspensión inmediata y permanente de la cuenta, sin derecho a reembolso de saldos pendientes, y puede derivar en acciones legales al amparo del Código Penal Boliviano (Decreto Ley N° 10426, Art. 335 - Estelionato y Art. 199 - Falsedad material).',
        ),

        // ── 4. SERVICIOS DISPONIBLES ─────────────────────────────────────────
        _LegalSection(
          '4. Servicios disponibles en la Plataforma',
          'HOSPEDAJE: La mascota pernocta en el domicilio del Cuidador. El Cuidador asume responsabilidad de custodia plena durante todo el período contratado, incluyendo alimentación, acceso a agua, ejercicio básico y atención en caso de emergencia.\n\n'
          'GUARDERÍA DIURNA: La mascota permanece en el domicilio del Cuidador durante el día (máx. 12 horas). Mismo nivel de responsabilidad que el hospedaje.\n\n'
          'PASEO: El Cuidador retira a la mascota en el domicilio del Cliente, la pasea por una ruta predefinida (visible en tiempo real mediante GPS en la app) y la devuelve. El paseo estándar es de 30 minutos; el paseo extendido es de 60 minutos.\n\n'
          'VISITA DOMICILIARIA: El Cuidador visita el domicilio del Cliente para alimentar, jugar y verificar el bienestar de la mascota. Duración estándar: 30 minutos por visita.\n\n'
          'BAÑO Y ESTÉTICA: El Cuidador realiza aseo básico (baño, secado, cepillado) en el domicilio del Cuidador o del Cliente según se acuerde.\n\n'
          'MEET & GREET: Reunión presencial gratuita de 20-30 minutos entre el Cliente, el Cuidador y la mascota antes de confirmar la Reserva. Obligatoria para servicios de hospedaje y guardería en primera reserva.',
        ),

        // ── 5. COMISIONES Y PRECIOS ──────────────────────────────────────────
        _LegalSection(
          '5. Comisiones, precios y estructura de pagos',
          'PRECIOS: Los Cuidadores establecen libremente sus tarifas dentro de los rangos permitidos por Garden. Los precios se muestran en Bolivianos (Bs.) e incluyen todos los impuestos aplicables.\n\n'
          'COMISIÓN DE PLATAFORMA: Garden cobra una comisión del 15% sobre el valor bruto de cada Reserva. Esta comisión cubre el procesamiento seguro del pago, la garantía del servicio, el soporte al usuario y el mantenimiento de la infraestructura tecnológica.\n\n'
          'DISTRIBUCIÓN DEL PAGO:\n'
          '  → El Cliente paga el 100% al confirmar la Reserva.\n'
          '  → El Cuidador recibe el 85% del valor acordado.\n'
          '  → Garden retiene el 15% como comisión de plataforma.\n'
          '  → El pago al Cuidador se libera dentro de las 24 horas siguientes a la confirmación de finalización del servicio por ambas partes, o automáticamente a las 72 horas si el Cliente no confirma ni disputa.\n\n'
          'SMART CONTRACT: Cada Reserva genera un contrato inteligente en la red Polygon que registra: monto pagado, identidad de las partes (hash), fechas del servicio y condiciones acordadas. Este registro es permanente, público y no puede ser alterado por ninguna de las partes ni por Garden.\n\n'
          'IVA E IMPUESTOS: Los precios de los Cuidadores deben incluir el IVA (13%) según la normativa tributaria boliviana. Garden emite facturas electrónicas por su comisión al amparo de la Ley N° 812 (Factura Electrónica) y las disposiciones del Servicio de Impuestos Nacionales (SIN).\n\n'
          'PROPINAS: Los Clientes pueden dejar propinas voluntarias al finalizar el servicio. Las propinas van íntegramente al Cuidador (0% de comisión sobre propinas).',
        ),

        // ── 6. CANCELACIONES Y REEMBOLSOS ────────────────────────────────────
        _LegalSection(
          '6. Política de cancelación y reembolsos',
          'HOSPEDAJE Y GUARDERÍA:\n'
          '• Cancelación con más de 72 horas de anticipación: reembolso del 100%.\n'
          '• Cancelación entre 24 y 72 horas de anticipación: reembolso del 50%.\n'
          '• Cancelación con menos de 24 horas o sin presentación (no-show): sin reembolso.\n\n'
          'PASEO Y VISITA DOMICILIARIA:\n'
          '• Cancelación con más de 12 horas de anticipación: reembolso del 100%.\n'
          '• Cancelación entre 2 y 12 horas de anticipación: reembolso del 50%.\n'
          '• Cancelación con menos de 2 horas o sin presentación: sin reembolso.\n\n'
          'BAÑO Y ESTÉTICA:\n'
          '• Cancelación con más de 24 horas de anticipación: reembolso del 100%.\n'
          '• Cancelación con menos de 24 horas: reembolso del 50%.\n\n'
          'CANCELACIÓN POR EL CUIDADOR: Si el Cuidador cancela con menos de 24 horas de anticipación, el Cliente recibe reembolso del 100% y el Cuidador recibe una penalización en su perfil. Tres cancelaciones tardías en 90 días resultan en suspensión temporal de 30 días.\n\n'
          'REEMBOLSOS: Los reembolsos se acreditan en la Billetera Garden en un plazo de 1-3 días hábiles. El retiro a cuenta bancaria puede demorar hasta 5 días hábiles adicionales.',
        ),

        // ── 7. QUÉ PUEDE HACER UN DUEÑO DE MASCOTA ──────────────────────────
        _LegalSection(
          '7. Derechos y facultades del Dueño de mascota',
          'El Dueño de mascota PUEDE:\n\n'
          '✓ Buscar y comparar perfiles de cuidadores verificados con reseñas reales.\n'
          '✓ Solicitar un Meet & Greet gratuito antes de confirmar cualquier reserva de hospedaje.\n'
          '✓ Ver en tiempo real la ubicación GPS de su mascota durante los paseos.\n'
          '✓ Recibir fotos y actualizaciones durante el servicio a través del chat integrado.\n'
          '✓ Calificar al Cuidador con estrellas y dejar una reseña escrita al finalizar el servicio.\n'
          '✓ Abrir una disputa dentro de las 72 horas siguientes a la finalización del servicio si considera que este no fue prestado correctamente.\n'
          '✓ Indicar necesidades especiales de su mascota (medicamentos, alergias, traumas, comportamiento con otros animales) que el Cuidador deberá respetar.\n'
          '✓ Solicitar acceso a las imágenes y registros de GPS de su servicio por hasta 30 días después de su finalización.\n'
          '✓ Cancelar su cuenta y solicitar la eliminación de sus datos personales en cualquier momento.',
        ),

        // ── 8. QUÉ NO PUEDE HACER UN DUEÑO DE MASCOTA ───────────────────────
        _LegalSection(
          '8. Prohibiciones para el Dueño de mascota',
          'El Dueño de mascota NO PUEDE:\n\n'
          '✗ Acordar pagos directos con el Cuidador para evadir la Plataforma ni la comisión de Garden. Esto constituye incumplimiento grave y puede resultar en suspensión permanente de ambas cuentas.\n'
          '✗ Proporcionar información falsa sobre el comportamiento, estado de salud o vacunación de su mascota. Los daños causados por ocultamiento de información son responsabilidad exclusiva del Dueño.\n'
          '✗ Entregar una mascota diferente a la registrada en la Reserva sin notificación previa al Cuidador.\n'
          '✗ Solicitar al Cuidador que realice actividades no acordadas en la Reserva (ej.: compras, mensajería, tareas domésticas).\n'
          '✗ Acosar, amenazar, insultar o discriminar a los Cuidadores por ningún medio dentro o fuera de la Plataforma.\n'
          '✗ Publicar reseñas falsas, difamatorias o malintencionadas.\n'
          '✗ Registrar más de una cuenta personal.\n'
          '✗ Ceder o compartir el acceso a su cuenta con terceros.\n'
          '✗ Usar la Plataforma para fines comerciales (reventa de servicios, agencias de mascotas, etc.) sin acuerdo escrito previo con Garden.',
        ),

        // ── 9. QUÉ PUEDE HACER UN CUIDADOR ──────────────────────────────────
        _LegalSection(
          '9. Derechos y facultades del Cuidador',
          'El Cuidador PUEDE:\n\n'
          '✓ Establecer sus propios precios, horarios y disponibilidad.\n'
          '✓ Aceptar o rechazar cualquier solicitud de Reserva sin necesidad de justificación.\n'
          '✓ Cancelar una Reserva activa si detecta que la mascota representa un riesgo para su seguridad o la de otros animales a su cuidado, notificando inmediatamente a Garden.\n'
          '✓ Recibir el 85% del valor acordado en cada Reserva.\n'
          '✓ Construir un perfil público con fotos, descripción y reseñas de sus servicios.\n'
          '✓ Comunicarse con los Clientes a través del chat integrado para coordinación del servicio.\n'
          '✓ Solicitar información adicional sobre la mascota antes de confirmar la Reserva.\n'
          '✓ Establecer límites razonables (máx. número de mascotas simultáneas, razas que no acepta, peso máximo).\n'
          '✓ Recibir un comprobante de transacción registrado en blockchain por cada servicio completado.',
        ),

        // ── 10. QUÉ NO PUEDE HACER UN CUIDADOR ──────────────────────────────
        _LegalSection(
          '10. Prohibiciones para el Cuidador',
          'El Cuidador NO PUEDE:\n\n'
          '✗ Solicitar o aceptar pagos fuera de la Plataforma para servicios originados en Garden.\n'
          '✗ Delegar el cuidado de la mascota a otra persona no registrada en Garden sin autorización expresa del Cliente y de Garden.\n'
          '✗ Transportar a la mascota en vehículo sin las condiciones mínimas de seguridad (jaula o arnés homologado).\n'
          '✗ Administrar medicamentos a la mascota sin instrucciones escritas del Dueño y del veterinario.\n'
          '✗ Mezclar mascotas con animales enfermos o sin vacunas al día en el espacio de hospedaje.\n'
          '✗ Publicar fotos o videos de las mascotas a su cuidado en redes sociales sin autorización expresa del Cliente.\n'
          '✗ Abandono de mascota: dejar de atender a una mascota bajo su custodia constituye maltrato animal y puede ser denunciado ante la Defensoría de la Madre Tierra y el Gobierno Autónomo Municipal de Santa Cruz.\n'
          '✗ Acosar, insultar o discriminar a los Clientes.\n'
          '✗ Inflar artificialmente sus calificaciones mediante reseñas falsas o acuerdos con terceros.\n'
          '✗ Usar las fotos, datos o información de las mascotas de los Clientes con fines distintos a la prestación del servicio.',
        ),

        // ── 11. RESPONSABILIDAD: MASCOTA LASTIMADA O FALLECIDA ───────────────
        _LegalSection(
          '11. ¿Qué pasa si la mascota se lastima, enferma o fallece?',
          'La seguridad y bienestar de la mascota es responsabilidad primaria del Cuidador durante todo el período en que la mascota esté bajo su custodia.\n\n'
          'SITUACIONES CUBIERTAS POR EL CUIDADOR:\n'
          'Si la mascota sufre lesiones, enferma o fallece por negligencia comprobable del Cuidador (descuido, violencia, falta de agua/alimentación, accidente por falta de supervisión), el Cuidador es civilmente responsable conforme al Art. 984 del Código Civil Boliviano (D.L. N° 12760) que establece la obligación de reparar el daño causado por culpa o negligencia.\n\n'
          'En estos casos, el Cuidador deberá:\n'
          '1. Notificar al Cliente de forma inmediata (dentro de los 30 minutos siguientes al incidente).\n'
          '2. Trasladar a la mascota al veterinario más cercano o al indicado por el Cliente.\n'
          '3. Cubrir el 100% de los gastos veterinarios de emergencia generados por su negligencia, hasta un monto de Bs. 5.000. Para montos superiores, Garden mediará la disputa.\n'
          '4. En caso de fallecimiento por negligencia, el Cuidador pagará al Cliente una compensación de hasta Bs. 3.000 adicionales por daño moral, a determinar por mediación de Garden.\n\n'
          'SITUACIONES NO CUBIERTAS POR EL CUIDADOR:\n'
          '• Condición médica preexistente no informada por el Dueño al momento de la Reserva.\n'
          '• Enfermedad por vacunas vencidas u omitidas (responsabilidad del Dueño).\n'
          '• Muerte natural por edad avanzada o enfermedad terminal conocida.\n'
          '• Accidente causado directamente por el comportamiento agresivo de la propia mascota.\n\n'
          'PROCEDIMIENTO DE EMERGENCIA VETERINARIA:\n'
          '1. El Cuidador lleva a la mascota al veterinario inmediatamente.\n'
          '2. El Cuidador notifica a Garden a través de la app (botón de emergencia).\n'
          '3. Garden notifica al Cliente y coordina comunicación.\n'
          '4. Los gastos se documentan con facturas. Garden determina quién los asume según la causa.\n'
          '5. Si hay disputa, Garden actúa como mediador con un plazo de 5 días hábiles.\n\n'
          'FONDO DE GARANTÍA GARDEN: Garden mantiene un Fondo de Garantía para casos excepcionales donde la responsabilidad no sea clara o el Cuidador sea insolvente. La cobertura máxima del Fondo es de Bs. 2.000 por incidente.',
        ),

        // ── 12. RESPONSABILIDAD: CUIDADOR LASTIMADO ──────────────────────────
        _LegalSection(
          '12. ¿Qué pasa si el Cuidador se lastima?',
          'Los Cuidadores son prestadores de servicios independientes y NO empleados de Garden. Por lo tanto, Garden no está obligada a proveer seguro de accidentes laborales ni de salud.\n\n'
          'HERIDA O MORDIDA POR LA MASCOTA DEL CLIENTE:\n'
          'Conforme al Art. 990 del Código Civil Boliviano, el dueño de un animal es responsable por los daños que éste cause a terceros. Si la mascota del Cliente muerde o lesiona al Cuidador, el CLIENTE es civilmente responsable de los gastos médicos resultantes.\n\n'
          'El Cuidador debe:\n'
          '1. Documentar el incidente con fotos, video y reporte médico.\n'
          '2. Notificar a Garden dentro de las 2 horas siguientes.\n'
          '3. Interponer disputa en la Plataforma para reclamación al Cliente.\n\n'
          'Garden mediará la disputa y podrá retener fondos del Cliente para cubrir los gastos médicos documentados del Cuidador, hasta Bs. 3.000 por incidente.\n\n'
          'ACCIDENTES INDEPENDIENTES DE LA MASCOTA:\n'
          'Caídas, accidentes de tránsito, u otros incidentes que no sean causados directamente por la mascota son responsabilidad del Cuidador. Garden recomienda encarecidamente que los Cuidadores contraten un seguro de accidentes personales.\n\n'
          'ACUERDO DE RIESGO: Al registrarse como Cuidador, el usuario reconoce expresamente que el cuidado de animales conlleva riesgos inherentes (mordeduras, arañazos, caídas, alérgenos) y acepta estos riesgos de forma voluntaria e informada.',
        ),

        // ── 13. PROCESO DE DISPUTAS ──────────────────────────────────────────
        _LegalSection(
          '13. Proceso de resolución de disputas',
          'Garden ofrece un sistema de mediación interno antes de recurrir a instancias judiciales.\n\n'
          'PASO 1 — APERTURA DE DISPUTA:\n'
          'Cualquier parte puede abrir una disputa desde la app dentro de las 72 horas siguientes a la finalización del servicio. Pasado este plazo, el pago se libera definitivamente al Cuidador y no procede reclamación.\n\n'
          'PASO 2 — PRESENTACIÓN DE EVIDENCIA:\n'
          'Ambas partes tienen 48 horas para presentar: fotos, videos, mensajes del chat, registros GPS, reportes veterinarios u otros documentos relevantes.\n\n'
          'PASO 3 — MEDIACIÓN GARDEN:\n'
          'El equipo de Garden analiza la evidencia en un plazo de 5 días hábiles y emite una resolución. Garden puede:\n'
          '• Liberar el pago total al Cuidador.\n'
          '• Reembolsar parcial o totalmente al Cliente.\n'
          '• Dividir el monto según grado de responsabilidad.\n'
          '• Suspender o banear cuentas si hay evidencia de mala fe.\n\n'
          'PASO 4 — APELACIÓN:\n'
          'Cualquier parte puede apelar la resolución de Garden en un plazo de 5 días hábiles, presentando nueva evidencia. La decisión de apelación es definitiva.\n\n'
          'PASO 5 — VÍA JUDICIAL:\n'
          'Si ninguna parte está satisfecha con la resolución de Garden, pueden recurrir a la Defensa del Consumidor (Ley N° 453) o a los tribunales civiles de Santa Cruz de la Sierra. Garden colaborará con las autoridades proporcionando todos los registros disponibles.',
        ),

        // ── 14. SMART CONTRACTS Y BLOCKCHAIN ────────────────────────────────
        _LegalSection(
          '14. Smart Contracts y tecnología blockchain',
          'Garden utiliza la red blockchain Polygon para registrar los contratos de cada Reserva de forma descentralizada e inmutable.\n\n'
          'QUÉ SE REGISTRA EN BLOCKCHAIN:\n'
          '• Hash de identidad de ambas partes (no datos personales directos).\n'
          '• Valor acordado del servicio.\n'
          '• Fechas y tipo de servicio.\n'
          '• Confirmación de pago y de finalización.\n'
          '• Resultado de disputas si las hubiere.\n\n'
          'QUÉ IMPLICA ESTO PARA EL USUARIO:\n'
          '• Los términos de la Reserva no pueden ser alterados retroactivamente por ninguna de las partes.\n'
          '• Existe un registro permanente y verificable de cada servicio completado, accesible por el usuario a través de su panel.\n'
          '• En caso de litigio judicial, el registro blockchain puede ser presentado como evidencia documental.\n\n'
          'LIMITACIÓN: El registro blockchain es una herramienta de transparencia y no reemplaza las obligaciones legales establecidas en el Código Civil Boliviano ni en ninguna otra norma aplicable.',
        ),

        // ── 15. VERIFICACIÓN DE IDENTIDAD ────────────────────────────────────
        _LegalSection(
          '15. Verificación de identidad de Cuidadores',
          'Todos los Cuidadores pasan por un proceso de verificación de identidad mediante inteligencia artificial antes de poder ofrecer servicios en la Plataforma:\n\n'
          '1. Fotografía del Carnet de Identidad (CI) boliviano (anverso y reverso).\n'
          '2. Selfie en tiempo real para comparación facial.\n'
          '3. Validación automática de coincidencia de rostro con foto del CI.\n\n'
          'IMPORTANTE: La verificación confirma que la persona que se registra coincide con el documento presentado. NO implica que Garden avala el carácter, antecedentes penales o capacidad profesional del Cuidador.\n\n'
          'Los datos biométricos recopilados se usan exclusivamente para el proceso de verificación y no se comparten con terceros. Se almacenan cifrados por un máximo de 12 meses desde la última actividad del Cuidador en la Plataforma.',
        ),

        // ── 16. ALCANCE GEOGRÁFICO DEL SERVICIO ─────────────────────────────
        _LegalSection(
          '16. Alcance del servicio',
          'Garden opera actualmente en Santa Cruz de la Sierra, Bolivia. Los servicios están disponibles únicamente dentro del área metropolitana de Santa Cruz (Plan 3000, Equipetrol, Urubó, Los Lotes, Palmasola y zonas aledañas).\n\n'
          'Servicios que implican traslado de mascota (paseo, hospedaje): el Cuidador no puede transportar la mascota fuera del perímetro de Santa Cruz de la Sierra sin autorización escrita del Cliente.\n\n'
          'Garden no garantiza disponibilidad de Cuidadores en zonas rurales o localidades fuera del área metropolitana.',
        ),

        // ── 17. BIENESTAR ANIMAL ─────────────────────────────────────────────
        _LegalSection(
          '17. Política de bienestar animal',
          'Garden está comprometida con el bienestar de los animales. Todo usuario de la Plataforma acepta lo siguiente:\n\n'
          '• Queda expresamente prohibido el maltrato físico, psicológico o por negligencia de cualquier animal, bajo pena de suspensión inmediata y denuncia ante las autoridades competentes.\n\n'
          '• El maltrato animal en Bolivia puede ser sancionado bajo el Código Penal (Art. 347 Bis sobre daño a bienes con especial consideración para animales domésticos) y ordenanzas municipales del Gobierno Autónomo Municipal de Santa Cruz de la Sierra.\n\n'
          '• Los Cuidadores se comprometen a:\n'
          '  → Alimentar a la mascota con la frecuencia y tipo de alimento indicado por el Dueño.\n'
          '  → Proveer agua fresca permanentemente.\n'
          '  → Garantizar un espacio limpio, seguro y libre de amenazas.\n'
          '  → No usar collares de pinchos, descargas eléctricas u otros dispositivos de corrección agresiva.\n'
          '  → Reportar de inmediato cualquier cambio en el estado de salud o comportamiento de la mascota.',
        ),

        // ── 18. SEGUROS RECOMENDADOS ─────────────────────────────────────────
        _LegalSection(
          '18. Seguros recomendados',
          'Bolivia no cuenta actualmente con un seguro obligatorio específico para servicios de cuidado de mascotas. Sin embargo, Garden recomienda encarecidamente:\n\n'
          'PARA DUEÑOS DE MASCOTAS:\n'
          '• Contratar un seguro veterinario para su mascota que cubra urgencias y hospitalizaciones.\n'
          '• Verificar que su póliza de seguro de hogar o de responsabilidad civil incluya daños causados por su mascota a terceros.\n\n'
          'PARA CUIDADORES:\n'
          '• Contratar un seguro de accidentes personales que cubra actividades de cuidado de animales.\n'
          '• Verificar que su seguro de hogar cubra daños a terceros y a animales bajo su custodia.\n\n'
          'La ausencia de seguro no exime a ninguna parte de sus responsabilidades civiles establecidas en el Código Civil Boliviano.',
        ),

        // ── 19. CONDUCTA PROHIBIDA GENERAL ───────────────────────────────────
        _LegalSection(
          '19. Conducta prohibida y sanciones',
          'Está terminantemente prohibido para TODOS los usuarios:\n\n'
          '✗ Acordar o realizar transacciones económicas fuera de la Plataforma por servicios originados en Garden (circunvención de plataforma). Primera infracción: suspensión de 90 días. Segunda infracción: suspensión permanente.\n\n'
          '✗ Crear perfiles falsos, usar identidades de terceros o proporcionar documentos falsificados. Sanción: suspensión permanente y denuncia penal.\n\n'
          '✗ Publicar reseñas, calificaciones o comentarios falsos o manipulados. Sanción: eliminación del contenido y suspensión.\n\n'
          '✗ Acosar, amenazar, extorsionar o discriminar a otros usuarios por cualquier medio. Sanción: suspensión inmediata y denuncia ante el Ministerio Público si corresponde.\n\n'
          '✗ Usar Garden para actividades ilegales, incluyendo tráfico de animales, lavado de activos o cualquier actividad penada por las leyes bolivianas. Sanción: suspensión permanente y denuncia a las autoridades.\n\n'
          '✗ Registrar cuentas múltiples para evadir sanciones previas.\n\n'
          '✗ Intentar acceder, hackear o dañar los sistemas informáticos de Garden, lo cual constituye delito informático conforme a la Ley N° 164 de Telecomunicaciones de Bolivia.',
        ),

        // ── 20. PRIVACIDAD Y DATOS ───────────────────────────────────────────
        _LegalSection(
          '20. Privacidad y protección de datos',
          'El tratamiento de tus datos personales se rige por la Política de Privacidad de Garden, disponible en la app y en garden.bo/privacidad.\n\n'
          'Garden cumple con los principios de protección de datos establecidos en la Constitución Política del Estado Plurinacional de Bolivia (Art. 130 — Habeas Data) y la Ley N° 164 de Telecomunicaciones.\n\n'
          'Tienes derecho a acceder, corregir y solicitar la eliminación de tus datos personales en cualquier momento contactando a privacidad@garden.bo.',
        ),

        // ── 21. PROPIEDAD INTELECTUAL ────────────────────────────────────────
        _LegalSection(
          '21. Propiedad intelectual',
          'Todo el contenido de Garden (nombre comercial, logotipo, diseño de interfaz, código fuente, algoritmos, base de datos de cuidadores) es propiedad exclusiva de Garden Bolivia y está protegido por la Ley N° 1322 de Derechos de Autor de Bolivia y los tratados internacionales suscritos por Bolivia (Convenio de Berna, ADPIC/TRIPS).\n\n'
          'Queda prohibido reproducir, distribuir, modificar, hacer ingeniería inversa o crear obras derivadas de cualquier elemento de Garden sin autorización escrita previa.\n\n'
          'Los Cuidadores otorgan a Garden una licencia no exclusiva para usar sus fotografías de perfil y reseñas con fines de promoción de la Plataforma, pudiendo revocarla por escrito en cualquier momento.',
        ),

        // ── 22. LIMITACIÓN DE RESPONSABILIDAD DE GARDEN ─────────────────────
        _LegalSection(
          '22. Limitación de responsabilidad de Garden',
          'Garden actúa como intermediario tecnológico y no es parte del contrato de servicio entre Cliente y Cuidador. En consecuencia:\n\n'
          '• Garden NO garantiza la calidad, seguridad ni resultado de los servicios prestados por los Cuidadores.\n\n'
          '• Garden NO asume responsabilidad por daños, lesiones, pérdidas o fallecimiento de mascotas durante el servicio, salvo los casos expresamente cubiertos por el Fondo de Garantía Garden (Sección 11).\n\n'
          '• La responsabilidad máxima de Garden ante cualquier reclamación está limitada al monto total pagado en la Reserva en disputa.\n\n'
          '• Garden no es responsable por interrupciones del servicio causadas por fuerza mayor, fallas de terceros proveedores (internet, energía eléctrica, blockchain) o ataques cibernéticos externos.\n\n'
          '• Garden no es responsable por el uso que los Cuidadores o Clientes hagan de la información intercambiada fuera de la Plataforma.',
        ),

        // ── 23. MODIFICACIONES ───────────────────────────────────────────────
        _LegalSection(
          '23. Modificaciones a estos Términos',
          'Garden puede actualizar estos Términos y Condiciones en cualquier momento. Los cambios significativos serán notificados:\n\n'
          '• Por correo electrónico al email registrado en la cuenta, con al menos 15 días de anticipación.\n'
          '• Mediante notificación push en la app.\n'
          '• Con un aviso visible al iniciar sesión.\n\n'
          'El uso continuo de la Plataforma después del plazo de notificación implica la aceptación tácita de los nuevos términos. Si no estás de acuerdo con las modificaciones, puedes cerrar tu cuenta sin costo adicional dentro del plazo de notificación.',
        ),

        // ── 24. LEY APLICABLE ────────────────────────────────────────────────
        _LegalSection(
          '24. Ley aplicable y jurisdicción',
          'Estos Términos y Condiciones se rigen por las leyes de la República Plurinacional de Bolivia, incluyendo pero no limitado a:\n\n'
          '• Código Civil Boliviano (D.L. N° 12760): contratos, responsabilidad civil, obligaciones.\n'
          '• Ley N° 453 del Consumidor y del Usuario: derechos del consumidor de servicios.\n'
          '• Ley N° 164 de Telecomunicaciones y TIC: servicios digitales y protección de datos.\n'
          '• Ley N° 1322 de Derechos de Autor: propiedad intelectual.\n'
          '• Código Penal Boliviano (D.L. N° 10426): delitos informáticos, fraude, falsedad.\n'
          '• Constitución Política del Estado Plurinacional de Bolivia (2009): derechos fundamentales.\n\n'
          'Para cualquier controversia no resuelta mediante el proceso interno de Garden (Sección 13), las partes se someten expresamente a la jurisdicción de los Juzgados y Tribunales competentes de la ciudad de Santa Cruz de la Sierra, Bolivia, renunciando a cualquier otro fuero que pudiera corresponderles.',
        ),

        // ── 25. CONTACTO ─────────────────────────────────────────────────────
        _LegalSection(
          '25. Contacto y soporte',
          'Para consultas, reportes o ejercicio de derechos:\n\n'
          '📧 Legal: legal@garden.bo\n'
          '📧 Privacidad: privacidad@garden.bo\n'
          '📧 Soporte general: hola@garden.bo\n'
          '📞 WhatsApp: +591 7XXXXXXX\n'
          '📍 Dirección: Santa Cruz de la Sierra, Bolivia\n\n'
          'Horario de atención: Lunes a Viernes, 8:00 a 18:00 (GMT-4, hora Bolivia).\n\n'
          '© 2026 Garden Bolivia. Todos los derechos reservados.',
        ),
      ],
    );
  }
}
