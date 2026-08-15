import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';
import '../../widgets/garden_loading_indicator.dart';

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
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

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
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, style: TextStyle(color: subtextColor), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      TextButton(onPressed: _load, child: const Text('Reintentar')),
                    ]),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12, left: 4, right: 4),
                      child: Text(
                        'Los avisos de pagos, reservas y reembolsos siempre te llegan — acá controlas el resto.',
                        style: TextStyle(color: subtextColor, fontSize: 13),
                      ),
                    ),
                    _toggleTile(
                      surface: surface,
                      borderColor: borderColor,
                      textColor: textColor,
                      subtextColor: subtextColor,
                      icon: Icons.alarm_outlined,
                      title: 'Recordatorios',
                      subtitle: 'Capacitaciones pendientes, calificaciones sin completar.',
                      value: _notifyReminders,
                      onChanged: (v) => _update('notifyReminders', v),
                    ),
                    const SizedBox(height: 12),
                    _toggleTile(
                      surface: surface,
                      borderColor: borderColor,
                      textColor: textColor,
                      subtextColor: subtextColor,
                      icon: Icons.campaign_outlined,
                      title: 'Promociones y novedades',
                      subtitle: 'Nueva cobertura en tu zona, anuncios de Garden.',
                      value: _notifyPromotions,
                      onChanged: (v) => _update('notifyPromotions', v),
                    ),
                  ],
                ),
    );
  }

  Widget _toggleTile({
    required Color surface,
    required Color borderColor,
    required Color textColor,
    required Color subtextColor,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GardenRadius.md),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: GardenColors.primary, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: subtextColor, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: _saving ? null : onChanged,
            activeThumbColor: GardenColors.primary,
          ),
        ],
      ),
    );
  }
}
