import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/garden_theme.dart';

/// Pantalla de verificación de identidad para móvil.
/// Se accede escaneando el QR que muestra la web — el token llega como parámetro.
/// NO requiere sesión de usuario: el token de verificación es suficiente.
class MobileVerifyScreen extends StatefulWidget {
  final String token;
  const MobileVerifyScreen({super.key, required this.token});

  @override
  State<MobileVerifyScreen> createState() => _MobileVerifyScreenState();
}

class _MobileVerifyScreenState extends State<MobileVerifyScreen> {
  // 0: intro  1: selfie  2: CI frente  3: CI dorso  4: enviando  5: éxito  6: rechazado
  int _step = 0;
  bool _tokenValid = false;
  bool _validating = true;
  String _validationError = '';

  // Liveness detection
  String? _livenessSessionId;
  bool _livenessChecked = false;
  bool _livenessAvailable = false;

  Uint8List? _selfieBytes;
  Uint8List? _ciFrontBytes;
  Uint8List? _ciBackBytes;

  final ImagePicker _picker = ImagePicker();

  String get _baseUrl => const String.fromEnvironment(
      'API_URL', defaultValue: 'https://api.gardenbo.com/api');

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _bg => _isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
  Color get _surface => _isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
  Color get _text => _isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
  Color get _subtext => _isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
  Color get _border => _isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

  @override
  void initState() {
    super.initState();
    _validateToken();
  }

  Future<void> _validateToken() async {
    debugPrint('[MobileVerify] Validando token: ${widget.token.substring(0, widget.token.length.clamp(0, 20))}...');
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/verification/validate?token=${Uri.encodeComponent(widget.token)}'),
      );
      final data = jsonDecode(res.body);
      debugPrint('[MobileVerify] validate response: ${res.statusCode} $data');
      if (!mounted) return;

      final valid = data['valid'] == true || data['success'] == true;
      setState(() {
        _tokenValid = valid;
        if (!valid) _validationError = data['message'] as String? ?? 'Token inválido o expirado';
      });

      if (valid) await _checkLiveness();
    } catch (e) {
      debugPrint('[MobileVerify] validate error: $e');
      if (mounted) {
        setState(() {
          _validating = false;
          _validationError = 'Error al validar: $e';
        });
      }
    }
  }

  Future<void> _checkLiveness() async {
    debugPrint('[MobileVerify] Verificando disponibilidad de liveness...');
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/verification/create-liveness-session'),
        headers: {'x-verification-token': widget.token},
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body);
      debugPrint('[MobileVerify] liveness session response: ${res.statusCode} $data');

      if (res.statusCode == 200 && data['success'] == true) {
        final sessionId = data['data']?['sessionId'] as String?;
        if (mounted) {
          setState(() {
            _livenessSessionId = sessionId;
            _livenessAvailable = sessionId != null;
            _livenessChecked = true;
            _validating = false;
          });
        }
      } else {
        if (mounted) setState(() { _livenessAvailable = false; _livenessChecked = true; _validating = false; });
      }
    } catch (e) {
      debugPrint('[MobileVerify] liveness check error: $e');
      if (mounted) setState(() { _livenessAvailable = false; _livenessChecked = true; _validating = false; });
    }
  }

  Future<void> _capturePhoto(String type) async {
    try {
      final device = type == 'selfie' ? CameraDevice.front : CameraDevice.rear;
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: device,
        imageQuality: 85,
        maxWidth: 1280,
        maxHeight: 1280,
      );
      if (photo == null) return;
      final bytes = await photo.readAsBytes();
      debugPrint('[MobileVerify] Foto capturada: $type — ${bytes.length} bytes');
      if (mounted) setState(() {
        if (type == 'selfie') _selfieBytes = bytes;
        else if (type == 'ciFront') _ciFrontBytes = bytes;
        else _ciBackBytes = bytes;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Foto capturada correctamente'),
          backgroundColor: GardenColors.success,
          duration: Duration(seconds: 2),
        ));
      }
    } catch (e) {
      debugPrint('[MobileVerify] Error capturando foto: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('No se pudo acceder a la cámara. Verifica los permisos.'),
          backgroundColor: GardenColors.error,
        ));
      }
    }
  }

  Future<void> _submit() async {
    if (_selfieBytes == null || _ciFrontBytes == null || _ciBackBytes == null) return;
    setState(() => _step = 4);
    try {
      final uri = Uri.parse('$_baseUrl/verification/submit');
      final request = http.MultipartRequest('POST', uri);
      request.fields['token'] = widget.token;
      if (_livenessSessionId != null) {
        request.fields['livenessSessionId'] = _livenessSessionId!;
      }

      for (final entry in [
        ('selfie', _selfieBytes!),
        ('ciFront', _ciFrontBytes!),
        ('ciBack', _ciBackBytes!),
      ]) {
        request.files.add(http.MultipartFile.fromBytes(
          entry.$1, entry.$2,
          filename: '${entry.$1}_${DateTime.now().millisecondsSinceEpoch}.jpg',
          contentType: MediaType.parse('image/jpeg'),
        ));
      }

      debugPrint('[MobileVerify] Enviando fotos a /verification/submit...');
      final streamed = await request.send();
      final res = await http.Response.fromStream(streamed);
      debugPrint('[MobileVerify] submit response: ${res.statusCode} ${res.body}');
      final data = jsonDecode(res.body);

      if (res.statusCode == 200 && data['success'] == true) {
        final status = (data['data']?['status'] ?? 'review').toString().toLowerCase();
        debugPrint('[MobileVerify] submit status: $status');
        if (mounted) setState(() => _step = status == 'rejected' ? 6 : 5);
      } else {
        throw Exception(data['error']?['message'] ?? data['message'] ?? 'Error en verificación');
      }
    } catch (e) {
      debugPrint('[MobileVerify] submit error: $e');
      if (mounted) {
        setState(() => _step = 3);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: GardenColors.error,
        ));
      }
    }
  }

  void _reset() {
    setState(() {
      _step = 0;
      _selfieBytes = null;
      _ciFrontBytes = null;
      _ciBackBytes = null;
    });
  }

  // ── BUILDS ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified_user_rounded, color: GardenColors.primary, size: 20),
            const SizedBox(width: 8),
            Text('Verificación · Garden', style: TextStyle(color: _text, fontWeight: FontWeight.w700, fontSize: 16)),
          ],
        ),
        centerTitle: true,
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_validating) return _buildLoading('Preparando verificación...');
    if (!_tokenValid) return _buildInvalidToken();
    if (_livenessChecked && !_livenessAvailable) return _buildLivenessUnavailable();
    switch (_step) {
      case 0: return _buildIntro();
      case 1: return _buildCaptureStep('selfie', 'Toma tu selfie',
          'Centra tu rostro, buena iluminación y sin gafas.', _selfieBytes,
          () => setState(() => _step = 0), () => setState(() => _step = 2));
      case 2: return _buildCaptureStep('ciFront', 'CI – Anverso (Frente)',
          'Asegúrate de que el documento esté bien iluminado y legible.', _ciFrontBytes,
          () => setState(() => _step = 1), () => setState(() => _step = 3));
      case 3: return _buildCaptureStep('ciBack', 'CI – Reverso (Dorso)',
          'Asegúrate de que el documento esté bien iluminado y legible.', _ciBackBytes,
          () => setState(() => _step = 2), _submit);
      case 4: return _buildLoading('Analizando con IA...\nEsto puede tomar unos segundos.');
      case 5: return _buildSuccess();
      case 6: return _buildRejected();
      default: return _buildIntro();
    }
  }

  Widget _buildLoading(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 64, height: 64,
              child: CircularProgressIndicator(color: GardenColors.primary, strokeWidth: 3)),
            const SizedBox(height: 28),
            Text(msg, textAlign: TextAlign.center,
                style: TextStyle(color: _text, fontSize: 16, height: 1.6)),
          ],
        ),
      ),
    );
  }

  Widget _buildLivenessUnavailable() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                color: GardenColors.warning.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.videocam_off_rounded, color: GardenColors.warning, size: 46),
            ),
            const SizedBox(height: 24),
            Text(
              'Detección de vida no disponible',
              style: TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            Text(
              'El servicio de detección de vida en tiempo real no está disponible en este momento. '
              'Este filtro es obligatorio para garantizar la seguridad del proceso de verificación.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _subtext, height: 1.65, fontSize: 14),
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
                children: [
                  const Icon(Icons.info_outline_rounded, color: GardenColors.warning, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Por favor, inténtalo de nuevo más tarde o contacta con soporte si el problema persiste.',
                      style: TextStyle(color: _subtext, fontSize: 13, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            OutlinedButton.icon(
              onPressed: () {
                setState(() { _livenessChecked = false; _validating = true; });
                _checkLiveness();
              },
              icon: const Icon(Icons.refresh_rounded, color: GardenColors.primary),
              label: const Text('Reintentar', style: TextStyle(color: GardenColors.primary)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: GardenColors.primary),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvalidToken() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.link_off_rounded, color: GardenColors.error, size: 80),
            const SizedBox(height: 24),
            Text('Enlace inválido o expirado', style: TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(_validationError, textAlign: TextAlign.center, style: TextStyle(color: _subtext, height: 1.5)),
            const SizedBox(height: 24),
            Text('Escanea el QR de nuevo desde tu computadora para obtener un enlace válido.',
                textAlign: TextAlign.center, style: TextStyle(color: _subtext, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 90, height: 90,
            decoration: BoxDecoration(
              color: GardenColors.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_user_rounded, color: GardenColors.primary, size: 48),
          ),
          const SizedBox(height: 24),
          Text('Verificación de identidad', style: TextStyle(color: _text, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(
            'Necesitamos verificar tu identidad con 3 fotos. '
            'Asegúrate de tener buena iluminación y tu CI a mano.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _subtext, height: 1.6),
          ),
          const SizedBox(height: 28),
          _req(Icons.face_rounded, 'Selfie de tu rostro'),
          _req(Icons.credit_card_rounded, 'Foto del anverso (frente) de tu CI'),
          _req(Icons.credit_card_outlined, 'Foto del reverso (dorso) de tu CI'),
          const SizedBox(height: 36),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: GardenColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => setState(() => _step = 1),
              child: const Text('Comenzar verificación', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _req(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: GardenColors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(color: _text))),
        ],
      ),
    );
  }

  Widget _buildCaptureStep(
    String type, String title, String instruction,
    Uint8List? preview,
    VoidCallback onBack, VoidCallback onNext,
  ) {
    final stepNum = _step; // 1, 2, 3
    final isLast = stepNum == 3;

    return Column(
      children: [
        LinearProgressIndicator(
          value: stepNum / 3,
          backgroundColor: _surface,
          color: GardenColors.primary,
          minHeight: 4,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: GardenColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Paso $stepNum de 3',
                      style: const TextStyle(color: GardenColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 16),
                Text(title, style: TextStyle(color: _text, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(instruction, textAlign: TextAlign.center, style: TextStyle(color: _subtext)),
                const SizedBox(height: 28),
                // Zona de captura
                GestureDetector(
                  onTap: () => _capturePhoto(type),
                  child: Container(
                    width: 280, height: 280,
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: preview != null ? GardenColors.success : GardenColors.primary.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        if (preview != null)
                          Positioned.fill(child: Image.memory(preview, fit: BoxFit.cover))
                        else
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.camera_alt, size: 64, color: GardenColors.primary),
                                const SizedBox(height: 12),
                                Text('Toca para abrir cámara', style: TextStyle(color: _subtext)),
                              ],
                            ),
                          ),
                        if (preview != null)
                          Positioned(
                            top: 10, right: 10,
                            child: Container(
                              decoration: const BoxDecoration(color: GardenColors.success, shape: BoxShape.circle),
                              padding: const EdgeInsets.all(2),
                              child: const Icon(Icons.check, color: Colors.white, size: 22),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (preview != null) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () => _capturePhoto(type),
                    icon: const Icon(Icons.refresh, size: 18, color: GardenColors.primary),
                    label: const Text('Volver a tomar', style: TextStyle(color: GardenColors.primary)),
                  ),
                ],
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onBack,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: _border),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text('Atrás', style: TextStyle(color: _subtext)),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: preview != null ? onNext : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: GardenColors.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: GardenColors.primary.withValues(alpha: 0.3),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          isLast ? 'Enviar verificación' : 'Continuar',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 600),
              builder: (_, v, __) => Transform.scale(
                scale: v,
                child: const Icon(Icons.check_circle_rounded, color: GardenColors.success, size: 100),
              ),
            ),
            const SizedBox(height: 28),
            Text('¡Verificación enviada!',
                style: TextStyle(color: _text, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text(
              'Tus fotos fueron enviadas correctamente.\n'
              'Regresa a tu computadora — el formulario avanzará automáticamente cuando se confirme tu identidad.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _subtext, height: 1.6, fontSize: 15),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: GardenColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: GardenColors.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.computer_rounded, color: GardenColors.primary, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Ya puedes cerrar esta ventana en el teléfono.',
                      style: TextStyle(color: _text, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRejected() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cancel_rounded, color: GardenColors.error, size: 90),
            const SizedBox(height: 24),
            Text('Verificación rechazada',
                style: TextStyle(color: _text, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            Text(
              'La verificación no pasó el análisis de IA. '
              'Por favor intenta de nuevo con mejor iluminación y asegurándote de que tu CI sea legible.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _subtext, height: 1.6),
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Intentar de nuevo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GardenColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _reset,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
