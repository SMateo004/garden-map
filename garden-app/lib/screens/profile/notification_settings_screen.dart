import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_state.dart';
import '../../widgets/garden_loading_indicator.dart';
import '../../design/brote.dart';
import '../../design/garden_icons.dart';
import '../../design/garden_settings.dart';
import '../../widgets/garden_empty_state.dart';

/// Preferencias de notificación push/email — no afectan el historial in-app
/// (siempre queda), solo si se interrumpe al usuario. Lo transaccional (pago,
/// reserva aceptada/rechazada, reembolso) nunca se apaga acá — solo gatea
/// recordatorios (capacitación, calificación pendiente) y contenido
/// promocional (nueva zona disponible, anuncios del admin).
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  bool _loading = true;
  bool _saving = false;
  bool _notifyReminders = true;
  bool _notifyPromotions = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/auth/notification-preferences'),
        headers: {'Authorization': 'Bearer ${AuthState.token}'},
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        setState(() {
          _notifyReminders = data['data']['notifyReminders'] as bool? ?? true;
          _notifyPromotions = data['data']['notifyPromotions'] as bool? ?? true;
        });
      } else {
        setState(() => _error = 'No se pudieron cargar tus preferencias.');
      }
    } catch (_) {
      setState(() => _error = 'Error de conexión. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _update(String field, bool value) async {
    final prevReminders = _notifyReminders;
    final prevPromotions = _notifyPromotions;
    setState(() {
      _saving = true;
      if (field == 'notifyReminders') _notifyReminders = value;
      if (field == 'notifyPromotions') _notifyPromotions = value;
    });
    try {
      final res = await http.patch(
        Uri.parse('$_baseUrl/auth/notification-preferences'),
        headers: {'Authorization': 'Bearer ${AuthState.token}', 'Content-Type': 'application/json'},
        body: jsonEncode({field: value}),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode != 200 || data['success'] != true) {
        throw Exception('save failed');
      }
    } catch (_) {
      // Revertir si falló — no dejar la UI mintiendo sobre el estado guardado.
      if (mounted) {
        setState(() {
          _notifyReminders = prevReminders;
          _notifyPromotions = prevPromotions;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo guardar. Intenta de nuevo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    Widget toggle(bool value, ValueChanged<bool> onChanged) => Switch(
          value: value,
          onChanged: _saving ? null : onChanged,
          activeThumbColor: GardenColors.primary,
        );

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text('Notificaciones', style: TextStyle(color: textColor, fontWeight: FontWeight.w700)),
        iconTheme: IconThemeData(color: textColor),
      ),
      body: _loading
          ? const Center(child: GardenLoadingIndicator())
          : _error != null
              ? ListView(padding: const EdgeInsets.all(24), children: [
                  const SizedBox(height: 40),
                  GardenEmptyState(
                    type: GardenEmptyType.notifications,
                    brote: BrotePose.oops,
                    title: 'No pudimos cargar tus preferencias',
                    subtitle: _error!,
                    ctaLabel: 'Reintentar',
                    onCta: _load,
                  ),
                ])
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          // Lo que no se puede apagar, a la vista y con candado:
                          // antes era una frase gris arriba de todo.
                          const GardenSettingsGroup(title: 'Siempre activas', children: [
                            GardenSettingsRow(
                              icon: GIcon.pagoProtegido,
                              title: 'Reservas, pagos y reembolsos',
                              subtitle: 'Son importantes para tu dinero y tus servicios',
                              onTap: null,
                              trailing: GardenIcon(GIcon.seguridad, size: GIconSize.sm),
                            ),
                          ]),
                          GardenSettingsGroup(title: 'Puedes elegir', children: [
                            GardenSettingsRow(
                              icon: GIcon.alarma,
                              title: 'Recordatorios',
                              subtitle: 'Capacitaciones pendientes y servicios por calificar',
                              onTap: () => _update('notifyReminders', !_notifyReminders),
                              trailing: toggle(_notifyReminders, (v) => _update('notifyReminders', v)),
                            ),
                            GardenSettingsRow(
                              icon: GIcon.anuncio,
                              title: 'Promociones y novedades',
                              subtitle: 'Nueva cobertura en tu zona y anuncios de GARDEN',
                              onTap: () => _update('notifyPromotions', !_notifyPromotions),
                              trailing: toggle(_notifyPromotions, (v) => _update('notifyPromotions', v)),
                            ),
                          ]),
                          GardenSettingsGroup(title: 'Privacidad', children: [
                            GardenSettingsRow(
                              icon: GIcon.estadisticas,
                              title: 'Ayúdanos a mejorar',
                              subtitle: 'Datos anónimos de uso (pantallas y tiempos). Nunca incluyen tus datos personales.',
                              onTap: () async {
                                await Analytics.instance.setEnabled(!Analytics.instance.enabled);
                                if (mounted) setState(() {});
                              },
                              trailing: Switch(
                                value: Analytics.instance.enabled,
                                activeThumbColor: GardenColors.primary,
                                onChanged: (v) async {
                                  await Analytics.instance.setEnabled(v);
                                  if (mounted) setState(() {});
                                },
                              ),
                            ),
                          ]),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              'Estas opciones cambian solo los avisos al teléfono y al correo. Todo queda igual en tus notificaciones dentro de la app.',
                              style: TextStyle(color: subtextColor, fontSize: 12, height: 1.4),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
    );
  }
}
