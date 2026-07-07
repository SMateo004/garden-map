import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/garden_theme.dart';

/// Guía completa para nuevos cuidadores GARDEN.
/// Ruta pública: /guia-cuidador — accesible desde el correo de bienvenida.
class CaregiverGuideScreen extends StatelessWidget {
  const CaregiverGuideScreen({super.key});

  static const _whatsApp = 'https://wa.me/59175933133?text=Hola%2C%20soy%20cuidador%20nuevo%20en%20GARDEN%20y%20necesito%20ayuda%20%F0%9F%8C%BF';
  static const _email = 'mailto:contactogardenbo@gmail.com?subject=Consulta%20cuidador%20GARDEN';

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
                                  child: Text('🌿', style: TextStyle(fontSize: 40)),
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
                          _sectionHeader('1. ¿Cómo funciona GARDEN?', '⚙️', textColor),
                          const SizedBox(height: 12),
                          _card(surface, borderColor, [
                            _step('🐾', 'Dueños publican su mascota', 'Los clientes buscan cuidadores en el marketplace y te envían una solicitud de reserva.', textColor, subtextColor),
                            _divider(borderColor),
                            _step('📅', 'Tú decides si aceptas', 'Revisas la solicitud, la info de la mascota y aceptas o rechazas según tu disponibilidad.', textColor, subtextColor),
                            _divider(borderColor),
                            _step('✅', 'El cliente paga y confirma', 'El pago se procesa en la app. Nada de efectivo al inicio — todo queda registrado.', textColor, subtextColor),
                            _divider(borderColor),
                            _step('🌟', 'Completas el servicio y cobras', 'Al finalizar el servicio, el dinero entra automáticamente a tu billetera GARDEN.', textColor, subtextColor),
                          ]),
                          const SizedBox(height: 32),

                          // 2. CÓMO GANAS DINERO
                          _sectionHeader('2. ¿Cómo ganas dinero?', '💰', textColor),
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
                                    'Defines cuánto cobrar por cada servicio desde el paso de Precio en tu configuración. GARDEN retiene una comisión del 10% como tarifa de plataforma — el 90% restante es tuyo.',
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
                                        Text('Ejemplo real', style: TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w800, fontSize: 13)),
                                        const SizedBox(height: 12),
                                        _earningRow('Hospedaje (1 noche)', 'Bs 200', 'Bs 180', textColor, subtextColor),
                                        const SizedBox(height: 8),
                                        _earningRow('Paseo 60 min', 'Bs 80', 'Bs 72', textColor, subtextColor),
                                        const SizedBox(height: 8),
                                        _earningRow('Guardería (día)', 'Bs 120', 'Bs 108', textColor, subtextColor),
                                        const SizedBox(height: 12),
                                        Container(height: 1, color: GardenColors.primary.withValues(alpha: 0.15)),
                                        const SizedBox(height: 10),
                                        Text('Los precios son solo de referencia. Tú decides qué cobrar.', style: TextStyle(color: subtextColor, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _infoChip(Icons.trending_up_rounded, '¡Sin comisión adicional! Solo 10% fijo por reserva completada.', GardenColors.success, isDark),
                                ],
                              ),
                            ),
                          ]),
                          const SizedBox(height: 32),

                          // 3. CÓMO RECIBES RESERVAS
                          _sectionHeader('3. ¿Cómo recibes reservas?', '📩', textColor),
                          const SizedBox(height: 12),
                          _card(surface, borderColor, [
                            _step('🟢', 'Activa tu disponibilidad', 'Ve a Inicio → Disponibilidad y marca los días y horarios en que puedes atender. Sin disponibilidad activa, no apareces en el marketplace.', textColor, subtextColor),
                            _divider(borderColor),
                            _step('🔔', 'Recibe una notificación', 'Cuando un dueño te envíe una solicitud, recibirás un push y una notificación dentro de la app.', textColor, subtextColor),
                            _divider(borderColor),
                            _step('📋', 'Revisa la solicitud', 'Entra a "Mis Reservas" y verás todos los detalles: mascota, fechas, notas especiales y el monto.', textColor, subtextColor),
                            _divider(borderColor),
                            _step('✅ / ❌', 'Acepta o rechaza (24 horas)', 'Tienes 24 horas para responder. Si no respondes, la solicitud se cancela automáticamente. Responder rápido mejora tu ranking.', textColor, subtextColor),
                          ]),
                          const SizedBox(height: 32),

                          // 4. CÓMO COBRAS TU DINERO
                          _sectionHeader('4. ¿Cómo cobras tu dinero?', '🏦', textColor),
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
                                  _withdrawStep('1', 'Ve a la sección Billetera (ícono 💳 en tu perfil)', textColor, subtextColor),
                                  const SizedBox(height: 12),
                                  _withdrawStep('2', 'Registra tu cuenta bancaria, Tigo Money o código QR', textColor, subtextColor),
                                  const SizedBox(height: 12),
                                  _withdrawStep('3', 'Solicita tu retiro — mínimo Bs 50', textColor, subtextColor),
                                  const SizedBox(height: 12),
                                  _withdrawStep('4', 'El equipo GARDEN procesa tu retiro en 1-3 días hábiles', textColor, subtextColor),
                                  const SizedBox(height: 16),
                                  _infoChip(Icons.info_outline_rounded, 'Bancos disponibles: Banco Unión, BCP, Banco Fassil, Tigo Money, entre otros.', GardenColors.primary, isDark),
                                ],
                              ),
                            ),
                          ]),
                          const SizedBox(height: 32),

                          // 5. REGLAS Y RESPONSABILIDADES
                          _sectionHeader('5. Reglas y responsabilidades', '📋', textColor),
                          const SizedBox(height: 12),
                          _card(surface, borderColor, [
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _ruleItem('🐾', 'Bienestar de la mascota primero', 'La seguridad y bienestar del animal es tu responsabilidad total durante el servicio. Cualquier emergencia debe comunicarse al dueño de inmediato.', textColor, subtextColor),
                                  const SizedBox(height: 16),
                                  _ruleItem('📸', 'Fotos de actualización', 'Envía fotos o videos al cliente durante el servicio. Los clientes que reciben actualizaciones dejan mejores reseñas.', textColor, subtextColor),
                                  const SizedBox(height: 16),
                                  _ruleItem('⏰', 'Cumple los horarios', 'Si acordaste un horario, respétalo. Cancelaciones de último minuto afectan tu calificación y visibilidad en el marketplace.', textColor, subtextColor),
                                  const SizedBox(height: 16),
                                  _ruleItem('🚫', 'Cero maltrato o negligencia', 'El maltrato animal está terminantemente prohibido y resulta en suspensión permanente de tu cuenta sin posibilidad de apelación.', textColor, subtextColor),
                                  const SizedBox(height: 16),
                                  _ruleItem('📞', 'Comunicación dentro de la app', 'Toda la comunicación con clientes debe realizarse a través del chat de GARDEN para protección de ambas partes.', textColor, subtextColor),
                                  const SizedBox(height: 16),
                                  _ruleItem('⭐', 'Calificación mínima', 'Si tu calificación promedio baja de 3.5 ⭐, tu perfil puede ser pausado temporalmente para revisión del equipo GARDEN.', textColor, subtextColor),
                                ],
                              ),
                            ),
                          ]),
                          const SizedBox(height: 32),

                          // 6. MANUAL DE USO RÁPIDO
                          _sectionHeader('6. Manual de uso rápido', '📱', textColor),
                          const SizedBox(height: 12),
                          _card(surface, borderColor, [
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _manualItem(Icons.home_rounded, 'Inicio', 'Tu dashboard principal. Ve tus reservas activas, disponibilidad y estado del perfil de un vistazo.', textColor, subtextColor, borderColor),
                                  const SizedBox(height: 14),
                                  _manualItem(Icons.calendar_month_rounded, 'Disponibilidad', 'Marca los días y horarios en que puedes atender. Solo apareces en búsquedas cuando tienes disponibilidad activa.', textColor, subtextColor, borderColor),
                                  const SizedBox(height: 14),
                                  _manualItem(Icons.list_alt_rounded, 'Mis Reservas', 'Gestiona todas tus solicitudes pendientes, reservas activas e historial de servicios.', textColor, subtextColor, borderColor),
                                  const SizedBox(height: 14),
                                  _manualItem(Icons.account_balance_wallet_rounded, 'Billetera', 'Consulta tu saldo disponible y solicita retiros a tu cuenta bancaria o Tigo Money.', textColor, subtextColor, borderColor),
                                  const SizedBox(height: 14),
                                  _manualItem(Icons.person_outline_rounded, 'Mi Perfil', 'Edita tu bio, fotos, servicios y tarifas. Un perfil completo y con buenas fotos recibe 3x más solicitudes.', textColor, subtextColor, borderColor),
                                  const SizedBox(height: 14),
                                  _manualItem(Icons.star_outline_rounded, 'Reseñas', 'Ve las valoraciones de clientes anteriores. Las reseñas positivas son tu mejor publicidad.', textColor, subtextColor, borderColor),
                                ],
                              ),
                            ),
                          ]),
                          const SizedBox(height: 32),

                          // 7. CONSEJOS PARA MÁS RESERVAS
                          _sectionHeader('7. Consejos para tener más reservas', '🚀', textColor),
                          const SizedBox(height: 12),
                          _card(surface, borderColor, [
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _tipItem('📷', 'Sube fotos de calidad', 'Cuidadores con fotos profesionales reciben hasta 5 veces más solicitudes. Muestra tu hogar, el espacio donde atenderás y tú con mascotas.', textColor, subtextColor),
                                  const SizedBox(height: 14),
                                  _tipItem('✍️', 'Escribe una bio convincente', 'Describe tu experiencia, por qué te gustan los animales y qué te diferencia. Los clientes buscan confianza, no solo precio.', textColor, subtextColor),
                                  const SizedBox(height: 14),
                                  _tipItem('⚡', 'Responde rápido', 'Responder solicitudes en menos de 2 horas mejora tu posición en el marketplace. GARDEN premia la rapidez.', textColor, subtextColor),
                                  const SizedBox(height: 14),
                                  _tipItem('📅', 'Mantén tu disponibilidad actualizada', 'Actualiza tu calendario cada semana. Si tu disponibilidad está vacía o desactualizada, pierdes oportunidades.', textColor, subtextColor),
                                  const SizedBox(height: 14),
                                  _tipItem('💬', 'Pide reseñas con amabilidad', 'Al finalizar cada servicio, puedes pedir amablemente al cliente que deje una reseña. Las primeras 5 reseñas son cruciales.', textColor, subtextColor),
                                  const SizedBox(height: 14),
                                  _tipItem('💲', 'Precio competitivo al inicio', 'Si eres nuevo sin reseñas, un precio ligeramente menor al promedio de tu zona te ayuda a conseguir tus primeros clientes.', textColor, subtextColor),
                                ],
                              ),
                            ),
                          ]),
                          const SizedBox(height: 32),

                          // 8. SOPORTE
                          _sectionHeader('8. Contacto y soporte', '🆘', textColor),
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
                                  icon: Icons.chat_rounded,
                                  label: 'WhatsApp Soporte',
                                  subtitle: '+591 75933133 · Lunes a Sábado 9:00–20:00',
                                  color: const Color(0xFF25D366),
                                  onTap: () => _launch(_whatsApp),
                                ),
                                const SizedBox(height: 12),
                                _contactButton(
                                  icon: Icons.email_outlined,
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
                                      const Icon(Icons.access_time_rounded, color: GardenColors.warning, size: 18),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Tiempo de respuesta habitual: menos de 2 horas en horario laboral. Para emergencias con una mascota bajo tu cuidado, usa WhatsApp.',
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
                                const Text('🌿', style: TextStyle(fontSize: 32)),
                                const SizedBox(height: 8),
                                Text(
                                  'GARDEN — Cuidadores de confianza',
                                  style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '¡Gracias por ser parte de nuestra familia! 🐾',
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
      ('⚙️', '¿Cómo funciona GARDEN?'),
      ('💰', '¿Cómo ganas dinero?'),
      ('📩', '¿Cómo recibes reservas?'),
      ('🏦', '¿Cómo cobras tu dinero?'),
      ('📋', 'Reglas y responsabilidades'),
      ('📱', 'Manual de uso rápido'),
      ('🚀', 'Consejos para más reservas'),
      ('🆘', 'Contacto y soporte'),
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
              Text(i.$1, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 10),
              Text(i.$2, style: TextStyle(color: subtext, fontSize: 14)),
            ]),
          )),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, String emoji, Color textColor) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
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

  Widget _step(String icon, String title, String desc, Color text, Color subtext) {
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
            child: Center(child: Text(icon, style: const TextStyle(fontSize: 18))),
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
        const Icon(Icons.arrow_forward_rounded, size: 14, color: GardenColors.primary),
        Text(youReceive, style: const TextStyle(color: GardenColors.primary, fontSize: 14, fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _infoChip(IconData icon, String text, Color color, bool isDark) {
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
          Icon(icon, color: color, size: 16),
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

  Widget _ruleItem(String emoji, String title, String desc, Color text, Color subtext) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
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

  Widget _manualItem(IconData icon, String title, String desc, Color text, Color subtext, Color border) {
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
          child: Icon(icon, color: GardenColors.primary, size: 22),
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

  Widget _tipItem(String emoji, String title, String desc, Color text, Color subtext) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
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
    required IconData icon,
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
              child: Icon(icon, color: color, size: 24),
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
            Icon(Icons.arrow_forward_ios_rounded, color: color.withValues(alpha: 0.5), size: 14),
          ],
        ),
      ),
    );
  }
}
