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
              color: GardenColors.primary.withOpacity(0.1),
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

// ── Términos de Servicio ──────────────────────────────────────────────────────

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LegalScreen(
      title: 'Términos de Servicio',
      lastUpdated: 'Enero 2025',
      sections: const [
        _LegalSection(
          '1. Aceptación de los términos',
          'Al crear una cuenta o utilizar Garden Bolivia ("la Plataforma"), aceptas estos Términos de Servicio en su totalidad. Si no estás de acuerdo, no debes usar la Plataforma.',
        ),
        _LegalSection(
          '2. El servicio que ofrecemos',
          'Garden es una plataforma tecnológica que facilita la conexión entre dueños de mascotas (Clientes) y personas que ofrecen servicios de cuidado (Cuidadores) en Santa Cruz de la Sierra. Garden no es una empresa de servicios de cuidado de mascotas: actuamos como intermediario tecnológico.',
        ),
        _LegalSection(
          '3. Cuentas y registro',
          '• Debes tener al menos 18 años para registrarte.\n'
          '• La información que proporcionas debe ser veraz, actual y completa.\n'
          '• Eres responsable de mantener la confidencialidad de tu contraseña.\n'
          '• No puedes transferir tu cuenta a otra persona.\n'
          '• Nos reservamos el derecho de suspender cuentas con información falsa o que violen estos términos.',
        ),
        _LegalSection(
          '4. Cuidadores verificados',
          'Los cuidadores pasan por un proceso de verificación que incluye validación de identidad mediante carnet (CI). La verificación reduce pero no elimina el riesgo. Garden no garantiza el comportamiento de los cuidadores y no se hace responsable por daños derivados de la prestación del servicio.',
        ),
        _LegalSection(
          '5. Reservas y pagos',
          '• Las reservas se confirman cuando el cuidador las acepta y el pago es procesado.\n'
          '• Los precios son establecidos por los cuidadores. Garden cobra una comisión de plataforma del 10%.\n'
          '• Los pagos se procesan de forma segura. Garden retiene el pago hasta que el servicio concluye satisfactoriamente.\n'
          '• En caso de disputa, Garden puede mediar y resolver a su criterio según la evidencia disponible.',
        ),
        _LegalSection(
          '6. Política de cancelación',
          'HOSPEDAJE:\n'
          '• Cancelación con +48 h de anticipación: reembolso del 100%.\n'
          '• Cancelación con 24-48 h: reembolso del 50%.\n'
          '• Cancelación con menos de 24 h: sin reembolso.\n\n'
          'PASEO:\n'
          '• Cancelación con +12 h de anticipación: reembolso del 100%.\n'
          '• Cancelación con 6-12 h: reembolso del 50%.\n'
          '• Cancelación con menos de 6 h: sin reembolso.\n\n'
          'Los montos de reembolso se depositan a la billetera virtual del Cliente en un plazo de 3-5 días hábiles.',
        ),
        _LegalSection(
          '7. Responsabilidades y limitaciones',
          'Garden actúa como intermediario tecnológico y no es parte del contrato de servicio entre Cliente y Cuidador. En consecuencia:\n\n'
          '• Garden no asume responsabilidad por daños, lesiones o pérdidas de mascotas durante el servicio.\n'
          '• La responsabilidad máxima de Garden ante cualquier reclamación está limitada al monto de la última transacción realizada.\n'
          '• Recomendamos a los Clientes verificar que sus mascotas cuenten con vacunas al día antes de cualquier servicio.',
        ),
        _LegalSection(
          '8. Conducta prohibida',
          'Está prohibido:\n'
          '• Proporcionar información falsa o fraudulenta.\n'
          '• Acordar pagos fuera de la plataforma para evadir comisiones.\n'
          '• Acosar, amenazar o discriminar a otros usuarios.\n'
          '• Usar la Plataforma para actividades ilegales.\n'
          '• Crear cuentas múltiples para evadir suspensiones.\n\n'
          'El incumplimiento puede resultar en suspensión permanente y, en casos graves, denuncia a las autoridades bolivianas.',
        ),
        _LegalSection(
          '9. Propiedad intelectual',
          'Todo el contenido de Garden (nombre, logo, diseño, código) es propiedad de Garden Bolivia y está protegido por las leyes de propiedad intelectual de Bolivia. No puedes reproducir, distribuir o crear obras derivadas sin autorización expresa.',
        ),
        _LegalSection(
          '10. Modificaciones y terminación',
          'Garden puede modificar estos Términos notificándote con 15 días de anticipación. El uso continuo de la Plataforma después de ese plazo implica aceptación de los nuevos términos. Puedes cancelar tu cuenta en cualquier momento desde la configuración del perfil.',
        ),
        _LegalSection(
          '11. Ley aplicable',
          'Estos Términos se rigen por las leyes de la República Plurinacional de Bolivia. Cualquier disputa se someterá a los tribunales competentes de la ciudad de Santa Cruz de la Sierra.',
        ),
        _LegalSection(
          '12. Contacto',
          'Para consultas sobre estos Términos:\n'
          'Email: legal@garden.bo\n'
          'Teléfono: +591 7XXXXXXX\n'
          'Dirección: Santa Cruz de la Sierra, Bolivia.',
        ),
      ],
    );
  }
}
