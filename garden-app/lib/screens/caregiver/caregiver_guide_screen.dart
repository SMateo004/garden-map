import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/auth_state.dart';
import '../../theme/garden_theme.dart';
import '../../design/garden_icons.dart';

/// Guía completa para nuevos cuidadores GARDEN.
/// Ruta pública: /guia-cuidador — accesible desde el correo de bienvenida.
class CaregiverGuideScreen extends StatelessWidget {
  const CaregiverGuideScreen({super.key});

  static const _email = 'mailto:contactogardenbo@gmail.com?subject=Consulta%20cuidador%20GARDEN';

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // Todo el contacto directo con soporte pasa por el chat in-app — ya no hay
  // enlace a WhatsApp (mismo cambio que en help_center_screen.dart).
  void _openSupportChat(BuildContext context) {
    if (!AuthState.hasSession) {
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          icon: const GardenIcon(GIcon.soporte, size: GIconSize.xl, state: GIconState.active, color: GardenColors.primary),
          title: const Text('Inicia sesión para chatear'),
          content: const Text('Para hablar con nuestro equipo de soporte primero necesitas iniciar sesión.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/login');
              },
              child: const Text('Iniciar sesión'),
            ),
          ],
        ),
      );
      return;
    }
    context.push('/support-chat');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
        final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
        final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
        final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

        return Scaffold(
          backgroundColor: bg,
          body: SingleChildScrollView(
            child: Column(
              children: [
                // ── Hero header ─────────────────────────────────────────────
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF14532d), Color(0xFF16a34a)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 700),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 40, 24, 48),
                          child: Column(
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: GardenIcon(GIcon.huella, size: GIconSize.xl, state: GIconState.active),
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                '¡Bienvenido a GARDEN!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Guía completa para cuidadores nuevos — todo lo que necesitas saber para empezar a ganar dinero haciendo lo que te apasiona.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 15,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Body content ────────────────────────────────────────────
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 32, 20, 48),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [

                          // INDEX
                          _indexCard(surface, borderColor, textColor, subtextColor),
                          const SizedBox(height: 32),

                          // 1. CÓMO FUNCIONA GARDEN
                          _sectionHeader('1. ¿Cómo funciona GARDEN?', GIcon.ajustes, textColor),
                          const SizedBox(height: 12),
                          _card(surface, borderColor, [
                            _step(GIcon.huella, 'Dueños publican su mascota', 'Los clientes buscan cuidadores en el marketplace y te envían una solicitud de reserva.', textColor, subtextColor),
                            _divider(borderColor),
                            _step(GIcon.calendario, 'Tú decides si aceptas', 'Revisas la solicitud, la info de la mascota y aceptas o rechazas según tu disponibilidad.', textColor, subtextColor),
                            _divider(borderColor),
                            _step(GIcon.confirmado, 'El cliente paga y confirma', 'El pago se procesa en la app. Nada de efectivo al inicio — todo queda registrado.', textColor, subtextColor),
                            _divider(borderColor),
                            _step(GIcon.estrella, 'Completas el servicio y cobras', 'Al finalizar el servicio, el dinero entra automáticamente a tu billetera GARDEN.', textColor, subtextColor),
                          ]),
                          const SizedBox(height: 32),

                          // 2. CÓMO GANAS DINERO
                          _sectionHeader('2. ¿Cómo ganas dinero?', GIcon.billetera, textColor),
                          const SizedBox(height: 12),
                          _card(surface, borderColor, [
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Tú fijas tus propios precios', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Defines cuánto cobrar por cada servicio desde el paso de Precio en tu configuración. El servicio de GARDEN y los impuestos los paga el cliente aparte: tú recibes íntegro el precio que fijas.',
                                    style: TextStyle(color: subtextColor, fontSize: 14, height: 1.5),
                                  ),
                                  const SizedBox(height: 20),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: GardenColors.primary.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: GardenColors.primary.withValues(alpha: 0.2)),
                                    ),
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Ejemplo: tu precio → lo que recibes', style: TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w800, fontSize: 13)),
                                        const SizedBox(height: 12),
                                        _earningRow('Hospedaje (1 noche)', 'Bs 200', 'Bs 200', textColor, subtextColor),
                                        const SizedBox(height: 8),
                                        _earningRow('Paseo 60 min', 'Bs 80', 'Bs 80', textColor, subtextColor),
                                        const SizedBox(height: 8),
                                        _earningRow('Guardería (día)', 'Bs 120', 'Bs 120', textColor, subtextColor),
                                        const SizedBox(height: 12),
                                        Container(height: 1, color: GardenColors.primary.withValues(alpha: 0.15)),
                                        const SizedBox(height: 10),
                                        Text('La tarifa de GARDEN y los impuestos se suman aparte al precio que paga el cliente. Los montos son solo de referencia: tú decides qué cobrar.', style: TextStyle(color: subtextColor, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _infoChip(GIcon.estadisticas, '¡Recibes íntegro tu precio! No se descuenta nada de lo que fijas.', GardenColors.success, isDark),
                                ],
                              ),
                            ),
                          ]),
                          const SizedBox(height: 32),

                          // 3. CÓMO RECIBES RESERVAS
                          _sectionHeader('3. ¿Cómo recibes reservas?', GIcon.correo, textColor),
                          const SizedBox(height: 12),
                          _card(surface, borderColor, [
                            _step(GIcon.disponibilidad, 'Activa tu disponibilidad', 'Ve a Inicio → Disponibilidad y marca los días y horarios en que puedes atender. Sin disponibilidad activa, no apareces en el marketplace.', textColor, subtextColor),
                            _divider(borderColor),
                            _step(GIcon.notificaciones, 'Recibe una notificación', 'Cuando un dueño te envíe una solicitud, recibirás un push y una notificación dentro de la app.', textColor, subtextColor),
                            _divider(borderColor),
                            _step(GIcon.reservas, 'Revisa la solicitud', 'Entra a "Mis Reservas" y verás todos los detalles: mascota, fechas, notas especiales y el monto.', textColor, subtextColor),
                            _divider(borderColor),
                            _step(GIcon.confirmado, 'Acepta o rechaza (24 horas)', 'Tienes 24 horas para responder. Si no respondes, la solicitud se cancela automáticamente. Responder rápido mejora tu ranking.', textColor, subtextColor),
                          ]),
                          const SizedBox(height: 32),

                          // 4. CÓMO COBRAS TU DINERO
                          _sectionHeader('4. ¿Cómo cobras tu dinero?', GIcon.retiro, textColor),
                          const SizedBox(height: 12),
                          _card(surface, borderColor, [
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Tu billetera GARDEN', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Cada reserva completada y calificada por el cliente deposita automáticamente tus ganancias en tu billetera dentro de la app.',
                                    style: TextStyle(color: subtextColor, fontSize: 14, height: 1.5),
                                  ),
                                  const SizedBox(height: 20),
                                  _withdrawStep('1', 'Ve a la sección Billetera de tu perfil', textColor, subtextColor),
                                  const SizedBox(height: 12),
                                  _withdrawStep('2', 'Registra tu cuenta bancaria, Tigo Money o código QR', textColor, subtextColor),
                                  const SizedBox(height: 12),
                                  _withdrawStep('3', 'Solicita tu retiro — mínimo Bs 50', textColor, subtextColor),
                                  const SizedBox(height: 12),
                                  _withdrawStep('4', 'El equipo GARDEN procesa tu retiro en 1-3 días hábiles', textColor, subtextColor),
                                  const SizedBox(height: 16),
                                  _infoChip(GIcon.info, 'Bancos disponibles: Banco Unión, BCP, Banco Fassil, Tigo Money, entre otros.', GardenColors.primary, isDark),
                                ],
                              ),
                            ),
                          ]),
                          const SizedBox(height: 32),

                          // 5. REGLAS Y RESPONSABILIDADES
                          _sectionHeader('5. Reglas y responsabilidades', GIcon.reservas, textColor),
                          const SizedBox(height: 12),
                          _card(surface, borderColor, [
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _ruleItem(GIcon.huella, 'Bienestar de la mascota primero', 'La seguridad y bienestar del animal es tu responsabilidad total durante el servicio. Cualquier emergencia debe comunicarse al dueño de inmediato.', textColor, subtextColor),
                                  const SizedBox(height: 16),
                                  _ruleItem(GIcon.foto, 'Fotos de actualización', 'Envía fotos o videos al cliente durante el servicio. Los clientes que reciben actualizaciones dejan mejores reseñas.', textColor, subtextColor),
                                  const SizedBox(height: 16),
                                  _ruleItem(GIcon.alarma, 'Cumple los horarios', 'Si acordaste un horario, respétalo. Cancelaciones de último minuto afectan tu calificación y visibilidad en el marketplace.', textColor, subtextColor),
                                  const SizedBox(height: 16),
                                  _ruleItem(GIcon.bloqueado, 'Cero maltrato o negligencia', 'El maltrato animal está terminantemente prohibido y resulta en suspensión permanente de tu cuenta sin posibilidad de apelación.', textColor, subtextColor),
                                  const SizedBox(height: 16),
                                  _ruleItem(GIcon.telefono, 'Comunicación dentro de la app', 'Toda la comunicación con clientes debe realizarse a través del chat de GARDEN para protección de ambas partes.', textColor, subtextColor),
                                  const SizedBox(height: 16),
                                  _ruleItem(GIcon.estrella, 'Calificación mínima', 'Si acumulas 5 o más calificaciones de 1 o 2 estrellas, tu cuenta se suspende automáticamente como medida preventiva. Puedes pedirle al equipo GARDEN que revise tu caso y reactive tu cuenta.', textColor, subtextColor),
                                  const SizedBox(height: 16),
                                  _ruleItem(GIcon.bloqueado, 'Si el cliente no se presenta', 'Si un dueño no aparece para el servicio acordado, tienes hasta 24 horas después de la cancelación para reportarlo desde "Mis Reservas" y así proteger tu calificación y tu tiempo.', textColor, subtextColor),
                                ],
                              ),
                            ),
                          ]),
                          const SizedBox(height: 32),

                          // 6. MANUAL DE USO RÁPIDO
                          _sectionHeader('6. Manual de uso rápido', GIcon.dispositivo, textColor),
                          const SizedBox(height: 12),
                          _card(surface, borderColor, [
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _manualItem(GIcon.inicio, 'Inicio', 'Tu dashboard principal. Ve tus reservas activas, disponibilidad y estado del perfil de un vistazo.', textColor, subtextColor, borderColor),
                                  const SizedBox(height: 14),
                                  _manualItem(GIcon.calendario, 'Disponibilidad', 'Marca los días y horarios en que puedes atender. Solo apareces en búsquedas cuando tienes disponibilidad activa.', textColor, subtextColor, borderColor),
                                  const SizedBox(height: 14),
                                  _manualItem(GIcon.lista, 'Mis Reservas', 'Gestiona todas tus solicitudes pendientes, reservas activas e historial de servicios.', textColor, subtextColor, borderColor),
                                  const SizedBox(height: 14),
                                  _manualItem(GIcon.billetera, 'Billetera', 'Consulta tu saldo disponible y solicita retiros a tu cuenta bancaria o Tigo Money. Protegida con un PIN de 4 dígitos (o huella/Face ID) que tú configuras — te lo pedimos cada vez que entras.', textColor, subtextColor, borderColor),
                                  const SizedBox(height: 14),
                                  _manualItem(GIcon.perfil, 'Mi Perfil', 'Edita tu bio, fotos, servicios y tarifas. Un perfil completo y con buenas fotos recibe 3x más solicitudes.', textColor, subtextColor, borderColor),
                                  const SizedBox(height: 14),
                                  _manualItem(GIcon.estrella, 'Reseñas', 'Ve las valoraciones de clientes anteriores. Las reseñas positivas son tu mejor publicidad.', textColor, subtextColor, borderColor),
                                ],
                              ),
                            ),
                          ]),
                          const SizedBox(height: 32),

                          // 7. CONSEJOS PARA MÁS RESERVAS
                          _sectionHeader('7. Consejos para tener más reservas', GIcon.lanzar, textColor),
                          const SizedBox(height: 12),
                          _card(surface, borderColor, [
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _tipItem(GIcon.foto, 'Sube fotos de calidad', 'Cuidadores con fotos profesionales reciben hasta 5 veces más solicitudes. Muestra tu hogar, el espacio donde atenderás y tú con mascotas.', textColor, subtextColor),
                                  const SizedBox(height: 14),
                                  _tipItem(GIcon.editar, 'Escribe una bio convincente', 'Describe tu experiencia, por qué te gustan los animales y qué te diferencia. Los clientes buscan confianza, no solo precio.', textColor, subtextColor),
                                  const SizedBox(height: 14),
                                  _tipItem(GIcon.cronometro, 'Responde rápido', 'Responder solicitudes en menos de 2 horas mejora tu posición en el marketplace. GARDEN premia la rapidez.', textColor, subtextColor),
                                  const SizedBox(height: 14),
                                  _tipItem(GIcon.calendario, 'Mantén tu disponibilidad actualizada', 'Actualiza tu calendario cada semana. Si tu disponibilidad está vacía o desactualizada, pierdes oportunidades.', textColor, subtextColor),
                                  const SizedBox(height: 14),
                                  _tipItem(GIcon.chat, 'Pide reseñas con amabilidad', 'Al finalizar cada servicio, puedes pedir amablemente al cliente que deje una reseña. Las primeras 5 reseñas son cruciales.', textColor, subtextColor),
                                  const SizedBox(height: 14),
                                  _tipItem(GIcon.precio, 'Precio competitivo al inicio', 'Si eres nuevo sin reseñas, un precio ligeramente menor al promedio de tu zona te ayuda a conseguir tus primeros clientes.', textColor, subtextColor),
                                  const SizedBox(height: 14),
                                  _tipItem(GIcon.protegido, 'Sube tus antecedentes penales (opcional)', 'Desde tu perfil puedes subir tu certificado FELCC/REJAP para conseguir el distintivo "Antecedentes verificados" — genera más confianza y no es obligatorio para operar.', textColor, subtextColor),
                                ],
                              ),
                            ),
                          ]),
                          const SizedBox(height: 32),

                          // 8. SOPORTE
                          _sectionHeader('8. Contacto y soporte', GIcon.soporte, textColor),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: borderColor),
                            ),
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Estamos aquí para ayudarte',
                                  style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Si tienes dudas, problemas con una reserva o cualquier consulta, contáctanos directamente.',
                                  style: TextStyle(color: subtextColor, fontSize: 14, height: 1.5),
                                ),
                                const SizedBox(height: 20),
                                _contactButton(
                                  icon: GIcon.chat,
                                  label: 'Chatear con soporte',
                                  subtitle: 'Te respondemos lo antes posible',
                                  color: GardenColors.primary,
                                  onTap: () => _openSupportChat(context),
                                ),
                                const SizedBox(height: 12),
                                _contactButton(
                                  icon: GIcon.correo,
                                  label: 'Email',
                                  subtitle: 'contactogardenbo@gmail.com',
                                  color: GardenColors.primary,
                                  onTap: () => _launch(_email),
                                ),
                                const SizedBox(height: 20),
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: GardenColors.warning.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: GardenColors.warning.withValues(alpha: 0.25)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const GardenIcon(GIcon.reloj, size: GIconSize.sm, color: GardenColors.warning),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Tiempo de respuesta habitual: menos de 2 horas en horario laboral. Para emergencias con una mascota bajo tu cuidado durante un servicio activo, usa el botón de SOS dentro de la pantalla del servicio.',
                                          style: TextStyle(color: subtextColor, fontSize: 13, height: 1.4),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 40),

                          // Footer
                          Center(
                            child: Column(
                              children: [
                                const GardenIcon(GIcon.huella, size: GIconSize.xl, state: GIconState.active),
                                const SizedBox(height: 8),
                                Text(
                                  'GARDEN — Cuidadores de confianza',
                                  style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '¡Gracias por ser parte de nuestra familia!',
                                  style: TextStyle(color: subtextColor, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _indexCard(Color surface, Color border, Color text, Color subtext) {
    final items = [
      (GIcon.ajustes, '¿Cómo funciona GARDEN?'),
      (GIcon.billetera, '¿Cómo ganas dinero?'),
      (GIcon.correo, '¿Cómo recibes reservas?'),
      (GIcon.retiro, '¿Cómo cobras tu dinero?'),
      (GIcon.reservas, 'Reglas y responsabilidades'),
      (GIcon.dispositivo, 'Manual de uso rápido'),
      (GIcon.lanzar, 'Consejos para más reservas'),
      (GIcon.soporte, 'Contacto y soporte'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('En esta guía encontrarás:', style: TextStyle(color: text, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ...items.map((i) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              GardenIcon(i.$1, size: GIconSize.sm, state: GIconState.active),
              const SizedBox(width: 10),
              Text(i.$2, style: TextStyle(color: subtext, fontSize: 14)),
            ]),
          )),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, GIcon icon, Color textColor) {
    return Row(
      children: [
        GardenIcon(icon, size: GIconSize.lg, state: GIconState.active),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3),
          ),
        ),
      ],
    );
  }

  Widget _card(Color surface, Color border, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _step(GIcon icon, String title, String desc, Color text, Color subtext) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: GardenColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: GardenIcon(icon, state: GIconState.active)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: text, fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(desc, style: TextStyle(color: subtext, fontSize: 13, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(Color border) => Container(height: 1, color: border);

  Widget _earningRow(String service, String clientPays, String youReceive, Color text, Color subtext) {
    return Row(
      children: [
        Expanded(child: Text(service, style: TextStyle(color: subtext, fontSize: 13))),
        const SizedBox(width: 8),
        Text(clientPays, style: TextStyle(color: subtext, fontSize: 13)),
        const GardenIcon(GIcon.avanzar, size: GIconSize.xs, color: GardenColors.primary),
        Text(youReceive, style: const TextStyle(color: GardenColors.primary, fontSize: 14, fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _infoChip(GIcon icon, String text, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GardenIcon(icon, color: color, size: GIconSize.sm),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 12, height: 1.4))),
        ],
      ),
    );
  }

  Widget _withdrawStep(String number, String text, Color textColor, Color subtext) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: GardenColors.primary,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(text, style: TextStyle(color: textColor, fontSize: 14, height: 1.4)),
        )),
      ],
    );
  }

  Widget _ruleItem(GIcon icon, String title, String desc, Color text, Color subtext) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: GardenIcon(icon, state: GIconState.active),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: text, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(desc, style: TextStyle(color: subtext, fontSize: 13, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _manualItem(GIcon icon, String title, String desc, Color text, Color subtext, Color border) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: GardenColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Center(child: GardenIcon(icon, color: GardenColors.primary, size: GIconSize.md, state: GIconState.active)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: text, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(desc, style: TextStyle(color: subtext, fontSize: 13, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tipItem(GIcon icon, String title, String desc, Color text, Color subtext) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: GardenIcon(icon, state: GIconState.active),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: text, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(desc, style: TextStyle(color: subtext, fontSize: 13, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _contactButton({
    required GIcon icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Center(child: GardenIcon(icon, color: color, size: GIconSize.lg, state: GIconState.active)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 12)),
                ],
              ),
            ),
            GardenIcon(GIcon.siguiente, size: GIconSize.xs, color: color.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}
