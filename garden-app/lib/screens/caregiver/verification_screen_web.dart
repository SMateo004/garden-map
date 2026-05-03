// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';

/// Implementación WEB de la pantalla de verificación de identidad.
/// Muestra un QR que el cuidador escanea con su teléfono.
/// El teléfono abre /mobile-verify?token=... y realiza la verificación con fotos.
/// Esta pantalla hace polling cada 4 segundos a /api/caregiver/my-profile:
///   - Si identityVerificationStatus == VERIFIED → avanza al siguiente paso.
///   - Si identityVerificationStatus == REJECTED → muestra estado "rechazado, intenta de nuevo"
///     (genera un nuevo QR con un token fresco).
///   - Si REVIEW → sigue esperando (el admin puede aprobar → VERIFIED).
class VerificationScreen extends StatefulWidget {
  final VoidCallback? onComplete;
  final bool showAppBar;

  const VerificationScreen({
    super.key,
    this.onComplete,
    this.showAppBar = true,
  });

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  // 0=intro  1=qr+polling  2=rejected(retry)  3=review(polling)
  int _step = 0;

  String _caregiverToken = '';
  String _qrUrl = '';

  bool _generatingToken = false;

  Timer? _pollTimer;
  int _pollCount = 0;

  String get _baseUrl => const String.fromEnvironment(
      'API_URL', defaultValue: 'https://garden-api-1ldd.onrender.com/api');

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _bg => _isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
  Color get _surface => _isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
  Color get _text => _isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
  Color get _subtext => _isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    String token = prefs.getString('access_token') ?? '';
    if (token.isEmpty) token = const String.fromEnvironment('TEST_JWT', defaultValue: '');
    setState(() => _caregiverToken = token);
    debugPrint('[VerifyWeb] caregiverToken cargado: ${token.length > 20 ? token.substring(0, 20) : token}...');
  }

  Future<void> _generateQR() async {
    if (_generatingToken) return;
    setState(() => _generatingToken = true);
    _stopPolling();
    try {
      debugPrint('[VerifyWeb] Generando token de verificación...');
      final res = await http.post(
        Uri.parse('$_baseUrl/verification/generate-link'),
        headers: {'Authorization': 'Bearer $_caregiverToken'},
      );
      final data = jsonDecode(res.body);
      debugPrint('[VerifyWeb] generate-link response: ${res.statusCode} $data');

      if (data['success'] == true) {
        final token = data['data']['token'] as String;
        // Hash routing (#/) — GoRouter lee window.location.hash, no pathname.
        // Sin el # el token carga la landing page en vez de /mobile-verify.
        final origin = html.window.location.origin;
        final url = '$origin/#/mobile-verify?token=${Uri.encodeComponent(token)}';
        debugPrint('[VerifyWeb] QR URL generada (hash routing): $url');
        setState(() {
          _qrUrl = url;
          _step = 1;
          _pollCount = 0;
        });
        _startPolling();
      } else {
        throw Exception(data['error']?['message'] ?? 'Error al generar QR');
      }
    } catch (e) {
      debugPrint('[VerifyWeb] ERROR generando token: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red.shade700,
        ));
      }
    } finally {
      if (mounted) setState(() => _generatingToken = false);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    debugPrint('[VerifyWeb] Iniciando polling cada 4s...');
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _pollStatus());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    debugPrint('[VerifyWeb] Polling detenido (pollCount=$_pollCount)');
  }

  Future<void> _pollStatus() async {
    if (!mounted) { _stopPolling(); return; }
    _pollCount++;
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/caregiver/my-profile'),
        headers: {'Authorization': 'Bearer $_caregiverToken'},
      );
      final data = jsonDecode(res.body);
      // El campo puede venir como identityVerificationStatus o verificationStatus
      final status = (
        data['data']?['identityVerificationStatus'] ??
        data['data']?['verificationStatus'] ??
        'PENDING'
      ).toString().toUpperCase();

      debugPrint('[VerifyWeb] poll #$_pollCount → identityStatus=$status');

      if (!mounted) return;

      if (status == 'VERIFIED') {
        _stopPolling();
        debugPrint('[VerifyWeb] ✅ VERIFIED — avanzando wizard');
        if (widget.onComplete != null) {
          widget.onComplete!();
        } else {
          context.go('/caregiver/home');
        }
      } else if (status == 'REJECTED') {
        _stopPolling();
        debugPrint('[VerifyWeb] ❌ REJECTED — mostrando pantalla de reintento');
        setState(() { _step = 2; });
      }
      // REVIEW y PENDING → seguir esperando
    } catch (e) {
      debugPrint('[VerifyWeb] poll error (no crítico): $e');
    }
  }

  // ── BUILDS ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: widget.showAppBar
          ? AppBar(
              backgroundColor: _surface,
              elevation: 0,
              title: Text('Verificación de identidad', style: TextStyle(color: _text)),
              leading: _step == 2
                  ? IconButton(
                      icon: Icon(Icons.arrow_back, color: _text),
                      onPressed: () => setState(() { _step = 0; _stopPolling(); }),
                    )
                  : null,
            )
          : null,
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case 0: return _buildIntro();
      case 1: return _buildQrScreen();
      case 2: return _buildRejected();
      default: return _buildIntro();
    }
  }

  // ── INTRO ────────────────────────────────────────────────────────────────

  Widget _buildIntro() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Container(
            width: 90, height: 90,
            decoration: BoxDecoration(
              color: GardenColors.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.qr_code_scanner_rounded, color: GardenColors.primary, size: 48),
          ),
          const SizedBox(height: 24),
          Text('Verifica tu identidad con tu teléfono',
              style: TextStyle(color: _text, fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            'Como estás registrándote desde una computadora, usaremos tu teléfono para tomar las fotos. '
            'Al presionar "Generar QR" aparecerá un código que deberás escanear.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _subtext, height: 1.6),
          ),
          const SizedBox(height: 28),
          _step0Item('1', 'Presiona "Generar QR" abajo'),
          _step0Item('2', 'Escanea el QR con la cámara de tu teléfono'),
          _step0Item('3', 'Toma la selfie y las fotos de tu CI en el teléfono'),
          _step0Item('4', 'Esta pantalla avanzará automáticamente al verificarse'),
          const SizedBox(height: 36),
          SizedBox(
            width: double.infinity,
            child: _generatingToken
                ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
                : ElevatedButton.icon(
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: const Text('Generar QR',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GardenColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _generateQR,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _step0Item(String num, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28, height: 28,
            decoration: const BoxDecoration(
              color: GardenColors.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(num,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(label, style: TextStyle(color: _text, fontSize: 14, height: 1.4)),
          )),
        ],
      ),
    );
  }

  // ── QR + POLLING ─────────────────────────────────────────────────────────

  Widget _buildQrScreen() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Escanea el QR con tu teléfono',
                style: TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Abre la cámara o la app de lectura de QR de tu teléfono y apunta al código.',
              style: TextStyle(color: _subtext, fontSize: 13, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),

            // QR Code
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8)),
                ],
              ),
              child: QrImageView(
                data: _qrUrl,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF3D6B1A),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF3D6B1A),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Estado de espera
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: GardenColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: GardenColors.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(color: GardenColors.primary, strokeWidth: 2.5),
                  ),
                  const SizedBox(width: 12),
                  Text('Esperando verificación desde tu teléfono...',
                      style: TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
            ),

            const SizedBox(height: 12),
            Text(
              'Esta pantalla avanzará automáticamente cuando tu identidad sea verificada.',
              style: TextStyle(color: _subtext, fontSize: 12, height: 1.4),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // Botón regenerar QR (por si expira)
            TextButton.icon(
              onPressed: _generatingToken ? null : _generateQR,
              icon: const Icon(Icons.refresh_rounded, size: 18, color: GardenColors.primary),
              label: const Text('Generar nuevo QR',
                  style: TextStyle(color: GardenColors.primary, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  // ── REJECTED ─────────────────────────────────────────────────────────────

  Widget _buildRejected() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cancel_rounded, color: Colors.red, size: 90),
            const SizedBox(height: 24),
            Text('Verificación rechazada',
                style: TextStyle(color: _text, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            Text(
              'La verificación no pasó el análisis de IA. Debes intentarlo de nuevo para continuar el registro.\n\n'
              'Consejos:\n• Buena iluminación, sin sombras en el rostro\n'
              '• CI sin reflejos, completamente legible\n'
              '• Selfie sin gafas y de frente',
              textAlign: TextAlign.center,
              style: TextStyle(color: _subtext, height: 1.65, fontSize: 14),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.qr_code_2_rounded),
                label: const Text('Generar nuevo QR e intentar de nuevo',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GardenColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _generatingToken ? null : _generateQR,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
