import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/auth_state.dart';

/// Pantalla de actualización obligatoria — bloquea el acceso a la app cuando
/// la versión instalada es menor a `minAppVersion` (AppSettings).
///
/// Revisa automáticamente cada 30s si `minAppVersion` bajó (ej. el admin
/// corrigió un valor mal puesto) y deja salir al usuario sin reiniciar la app.
class UpdateRequiredScreen extends StatefulWidget {
  final String storeUrl;

  const UpdateRequiredScreen({super.key, required this.storeUrl});

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  static const _baseUrl = String.fromEnvironment('API_URL',
      defaultValue: 'https://api.gardenbo.com/api');

  Timer? _checkTimer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _checkTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkStatus());
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    super.dispose();
  }

  int _compareVersions(String a, String b) {
    final pa = a.split('+').first.split('.');
    final pb = b.split('+').first.split('.');
    for (var i = 0; i < 3; i++) {
      final na = i < pa.length ? int.tryParse(pa[i]) ?? 0 : 0;
      final nb = i < pb.length ? int.tryParse(pb[i]) ?? 0 : 0;
      if (na != nb) return na - nb;
    }
    return 0;
  }

  Future<void> _checkStatus() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/settings'))
          .timeout(const Duration(seconds: 8));
      final data = jsonDecode(res.body);
      final forced = data['data']?['forceUpdateEnabled'] == true;
      final minVersion = data['data']?['minAppVersion']?.toString();
      final info = await PackageInfo.fromPlatform();

      final belowMinVersion = minVersion != null &&
          minVersion.isNotEmpty &&
          _compareVersions(info.version, minVersion) < 0;
      final stillBlocked = forced || belowMinVersion;

      if (!stillBlocked && mounted) {
        _checkTimer?.cancel();
        final prefs = await SharedPreferences.getInstance();
        final role = prefs.getString('user_role') ?? '';
        final token = AuthState.token;
        if (!mounted) return;
        if (token.isEmpty) {
          context.go('/login');
        } else if (role == 'CAREGIVER') {
          context.go('/caregiver/home');
        } else {
          context.go('/service-selector');
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _openStore() async {
    if (widget.storeUrl.isEmpty) return;
    final uri = Uri.tryParse(widget.storeUrl);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4A90D9).withValues(alpha: 0.3),
                        blurRadius: 40,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.system_update_rounded, color: Colors.white, size: 52),
                ),
                const SizedBox(height: 40),
                const Text(
                  'Nueva versión disponible',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                Text(
                  'Hemos mejorado GARDEN.\nActualiza la app para seguir usándola.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 15,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                if (widget.storeUrl.isNotEmpty) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _openStore,
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Actualizar ahora'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4A90D9),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Verificando cada 30 segundos...',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextButton.icon(
                  onPressed: _checking ? null : _checkStatus,
                  icon: _checking
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                        )
                      : const Icon(Icons.refresh_rounded, color: Colors.white54, size: 16),
                  label: Text(
                    _checking ? 'Verificando...' : 'Ya actualicé / verificar ahora',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
