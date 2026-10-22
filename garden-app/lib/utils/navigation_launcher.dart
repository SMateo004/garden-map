import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design/garden_icons.dart';
import '../theme/garden_theme.dart';

/// "Navegar" hasta una dirección (la casa del dueño) con la app que elija el cuidador:
/// Google Maps, Waze o (en iPhone) Apple Maps — con la ruta ya trazada en modo auto.
///
/// Usa enlaces https universales lanzados directo (sin canLaunchUrl): abren la app si
/// está instalada y el navegador si no, y no dependen de declarar <queries> en Android
/// 11+ ni LSApplicationQueriesSchemes en iOS. Recuerda la última app elegida.
class NavigationLauncher {
  NavigationLauncher._();

  static const _prefKey = 'nav_app_choice';

  @visibleForTesting
  static Uri uriFor(String app, double lat, double lng) => _uri(app, lat, lng);

  static Uri _uri(String app, double lat, double lng) => switch (app) {
        'waze' => Uri.parse('https://waze.com/ul?ll=$lat,$lng&navigate=yes'),
        'apple' => Uri.parse('https://maps.apple.com/?daddr=$lat,$lng&dirflg=d'),
        _ => Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving'),
      };

  static bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Abre la navegación. Si ya eligió una app antes, va directo; [choose] fuerza el menú.
  static Future<void> open(BuildContext context, {required double lat, required double lng, String? label, bool choose = false}) async {
    String? app;
    try {
      final prefs = await SharedPreferences.getInstance();
      app = choose ? null : prefs.getString(_prefKey);
      if (app == 'apple' && !_isIOS) app = null;
    } catch (_) {}
    if (app == null) {
      if (!context.mounted) return;
      app = await _pick(context, label);
      if (app == null) return;
      try {
        (await SharedPreferences.getInstance()).setString(_prefKey, app);
      } catch (_) {}
    }
    bool ok = false;
    try {
      ok = await launchUrl(_uri(app, lat, lng), mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      // Último recurso: Google Maps en el navegador.
      try {
        ok = await launchUrl(_uri('google', lat, lng), mode: LaunchMode.platformDefault);
      } catch (_) {}
    }
    if (!ok && context.mounted) {
      GardenErrorDialog.show(context, 'No pudimos abrir la navegación. Revisa que tengas Google Maps o Waze.');
    }
  }

  static Future<String?> _pick(BuildContext context, String? label) {
    return showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(label == null ? '¿Con qué app navegas?' : 'Ir a: $label',
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            ListTile(
              leading: const GardenIcon(GIcon.mapa, color: GardenColors.primary),
              title: const Text('Google Maps'),
              onTap: () => Navigator.pop(ctx, 'google'),
            ),
            ListTile(
              leading: const GardenIcon(GIcon.auto, color: GardenColors.primary),
              title: const Text('Waze'),
              onTap: () => Navigator.pop(ctx, 'waze'),
            ),
            if (_isIOS)
              ListTile(
                leading: const GardenIcon(GIcon.ubicacion, color: GardenColors.primary),
                title: const Text('Apple Maps'),
                onTap: () => Navigator.pop(ctx, 'apple'),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Botón "Navegar a su casa" (abre la app de mapas con la ruta). Mantener presionado
/// permite cambiar de app.
class GardenNavigateButton extends StatelessWidget {
  final double lat;
  final double lng;
  final String? label;
  final String text;
  final bool outline;
  const GardenNavigateButton({
    super.key,
    required this.lat,
    required this.lng,
    this.label,
    this.text = 'Navegar a su casa',
    this.outline = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => NavigationLauncher.open(context, lat: lat, lng: lng, label: label, choose: true),
      child: GardenButton(
        label: text,
        gIcon: GIcon.enVivo,
        outline: outline,
        onPressed: () => NavigationLauncher.open(context, lat: lat, lng: lng, label: label),
      ),
    );
  }
}
