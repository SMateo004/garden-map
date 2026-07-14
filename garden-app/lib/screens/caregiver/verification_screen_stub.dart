import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';
import 'camera_overlay_screen.dart';
import 'liveness_detector_native.dart'
    if (dart.library.html) 'liveness_detector_web.dart';

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
  String _caregiverToken = '';
  String _verificationToken = '';
  bool _generatingToken = false;

  // Liveness (AWS Rekognition Face Liveness)
  String? _livenessSessionId;

  // Fotos capturadas
  Uint8List? _selfiePreview;
  Uint8List? _ciFrontPreview;
  Uint8List? _ciBackPreview;

  // Estado del proceso
  // 0: intro  1: selfie  2: CI frontal  3: CI trasero  4: enviando  5: resultado
  int _currentStep = 0;
  String _resultStatus = '';
  String _resultMessage = '';

  String get _baseUrl =>
      const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color get _bgColor =>
      _isDark ? GardenColors.darkBackground : GardenColors.lightBackground;

  Color get _surfaceColor =>
      _isDark ? GardenColors.darkSurface : GardenColors.lightSurface;

  Color get _textPrimary =>
      _isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;

  Color get _textSecondary =>
      _isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

  Color get _borderColor =>
      _isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    String token = AuthState.token;
    if (token.isEmpty) {
      token = const String.fromEnvironment('TEST_JWT', defaultValue: '');
    }
    setState(() => _caregiverToken = token);
  }

  /// Generates the short-lived verification token and creates an AWS
  /// FaceLiveness session, then opens the liveness check as a full-screen
  /// route. On success → proceeds to the selfie step.
  Future<void> _startProcess() async {
    setState(() => _generatingToken = true);
    try {
      // 1. Generate verification token
      final tokenRes = await http.post(
        Uri.parse('$_baseUrl/verification/generate-link'),
        headers: {'Authorization': 'Bearer $_caregiverToken'},
      );
      final tokenData = jsonDecode(tokenRes.body);
      if (tokenData['success'] != true) {
        throw Exception(tokenData['error']?['message'] ?? 'Error al generar token');
      }
      final vToken = tokenData['data']['token'] as String;

      // 2. Create FaceLiveness session
      String? sessionId;
      try {
        final lsRes = await http.post(
          Uri.parse('$_baseUrl/verification/create-liveness-session'),
          headers: {'Authorization': 'Bearer $_caregiverToken'},
        ).timeout(const Duration(seconds: 10));
        final lsData = jsonDecode(lsRes.body);
        if (lsData['success'] == true) {
          sessionId = lsData['data']['sessionId'] as String?;
        }
      } catch (_) {
        // Non-critical — handled below
      }

      if (!mounted) return;

      if (sessionId == null) {
        // AWS not configured or unreachable
        _showSnack(
          'El servicio de verificación de vida no está disponible. '
          'Por favor intenta más tarde.',
          isError: true,
        );
        return;
      }

      setState(() {
        _verificationToken = vToken;
        _livenessSessionId = sessionId;
        _generatingToken = false;
      });

      // 3. AWS Amplify's FaceLiveness native component only checks
      // (checkSelfPermission) for CAMERA access — it does not request it.
      // Without asking first, it throws cameraPermissionDenied instead of
      // showing the OS permission dialog.
      final cameraStatus = await Permission.camera.request();
      if (!mounted) return;
      if (!cameraStatus.isGranted) {
        _showSnack(
          'Necesitamos acceso a tu cámara para verificar tu identidad. '
          'Habilítalo en Ajustes.',
          isError: true,
        );
        return;
      }

      // 4. Show liveness check full-screen
      final passed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _LivenessCheckPage(sessionId: sessionId!),
        ),
      );

      if (!mounted) return;

      if (passed == true) {
        setState(() => _currentStep = 1); // → selfie
      } else {
        _showSnack(
          'La verificación de vida falló o fue cancelada. Inténtalo de nuevo.',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) _showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _generatingToken = false);
    }
  }

  Future<void> _capturePhoto(String type) async {
    final isSelfie = type == 'selfie';

    final String title;
    final String hint;
    final CameraFrameShape frameShape;
    final CameraLensDirection lensDir;

    if (isSelfie) {
      title = 'Toma tu selfie';
      hint = 'Centra tu rostro en el óvalo y mira directo a la cámara';
      frameShape = CameraFrameShape.oval;
      lensDir = CameraLensDirection.front;
    } else if (type == 'ciFront') {
      title = 'CI — Frente';
      hint = 'Coloca el documento dentro del marco. Asegúrate que sea legible.';
      frameShape = CameraFrameShape.rectangle;
      lensDir = CameraLensDirection.back;
    } else {
      title = 'CI — Reverso';
      hint = 'Coloca el reverso del documento dentro del marco.';
      frameShape = CameraFrameShape.rectangle;
      lensDir = CameraLensDirection.back;
    }

    try {
      final Uint8List? bytes = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => CameraOverlayScreen(
            frameShape: frameShape,
            title: title,
            hint: hint,
            lensDirection: lensDir,
          ),
        ),
      );

      if (bytes == null) return;

      setState(() {
        if (type == 'selfie') {
          _selfiePreview = bytes;
        } else if (type == 'ciFront') {
          _ciFrontPreview = bytes;
        } else {
          _ciBackPreview = bytes;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto capturada correctamente'),
            backgroundColor: GardenColors.success,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnack('No se pudo acceder a la cámara. Verifica los permisos de la app.', isError: true);
      }
    }
  }

  Future<void> _submitVerification() async {
    if (_selfiePreview == null || _ciFrontPreview == null || _ciBackPreview == null) {
      _showSnack('Captura las 3 fotos antes de continuar', isError: false);
      return;
    }

    setState(() => _currentStep = 4);

    try {
      final uri = Uri.parse('$_baseUrl/verification/submit');
      final request = http.MultipartRequest('POST', uri);

      request.fields['token'] = _verificationToken;
      if (_livenessSessionId != null) {
        request.fields['livenessSessionId'] = _livenessSessionId!;
      }

      for (final entry in [
        ('selfie', _selfiePreview),
        ('ciFront', _ciFrontPreview),
        ('ciBack', _ciBackPreview),
      ]) {
        if (entry.$2 == null) continue;
        request.files.add(http.MultipartFile.fromBytes(
          entry.$1,
          entry.$2!,
          filename: '${entry.$1}_${DateTime.now().millisecondsSinceEpoch}.jpg',
          contentType: MediaType.parse('image/jpeg'),
        ));
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      debugPrint('VERIFICATION RESPONSE: ${response.statusCode} ${response.body}');
      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          _currentStep = 5;
          _resultStatus = (data['data']['status'] ?? 'review').toString().toLowerCase();
          _resultMessage = data['data']['message'] ?? 'Tu verificacion esta siendo procesada';
        });
      } else {
        throw Exception(data['error']?['message'] ?? data['message'] ?? 'Error en verificacion');
      }
    } catch (e) {
      setState(() => _currentStep = 3);
      if (mounted) _showSnack(e.toString(), isError: true);
    }
  }

  Future<bool> _checkBlockchainBadge() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/caregiver/my-profile'),
        headers: {'Authorization': 'Bearer ${AuthState.token}'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        return data['data']?['isVerified'] == true ||
            data['data']?['verificationStatus'] == 'APPROVED' ||
            data['data']?['verificationStatus'] == 'VERIFIED';
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void _handleFinish() {
    if (widget.onComplete != null) {
      widget.onComplete!();
    } else {
      context.go('/caregiver/home');
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? GardenColors.error : GardenColors.success,
    ));
  }

  // ── BUILD INTRO ──────────────────────────────────────────────────────────

  Widget _buildIntro() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          const Icon(Icons.verified_user, color: GardenColors.primary, size: 80),
          const SizedBox(height: 24),
          Text(
            'Verifica tu identidad',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _textPrimary),
          ),
          const SizedBox(height: 12),
          Text(
            'Para garantizar la seguridad de nuestra comunidad, necesitamos verificar tu identidad usando IA. Ten tus documentos a mano.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _textSecondary, height: 1.5),
          ),
          const SizedBox(height: 32),
          _buildRequirementItem(Icons.face_rounded, 'Verificación de vida en tiempo real.'),
          _buildRequirementItem(Icons.photo_camera, 'Selfie nítida de tu rostro.'),
          _buildRequirementItem(Icons.credit_card, 'Foto del anverso (frente) de tu CI.'),
          _buildRequirementItem(Icons.credit_card_outlined, 'Foto del reverso (atrás) de tu CI.'),
          const SizedBox(height: 48),
          _generatingToken
              ? const CircularProgressIndicator(color: GardenColors.primary)
              : SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GardenColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(GardenRadius.md),
                      ),
                    ),
                    onPressed: _startProcess,
                    child: const Text(
                      'Comenzar verificacion',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildRequirementItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: GardenColors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(color: _textPrimary))),
        ],
      ),
    );
  }

  // ── BUILD CAPTURE STEP ───────────────────────────────────────────────────

  Widget _buildCaptureStep(
    String type,
    String title,
    String instruction,
    Uint8List? preview,
    VoidCallback onBack,
    VoidCallback onNext,
  ) {
    final displayStep = _currentStep; // 1, 2, or 3
    // La miniatura respeta la proporción real de la foto ya recortada por
    // CameraOverlayScreen: casi cuadrada para el rostro, apaisada tipo
    // carnet para el CI — así no se ve deformada al mostrarla.
    final isSelfie = type == 'selfie';
    const cardWidth = 280.0;
    final cardHeight = isSelfie ? cardWidth * 1.15 : cardWidth * 0.63;

    return Column(
      children: [
        LinearProgressIndicator(
          value: displayStep / 3,
          backgroundColor: _surfaceColor,
          color: GardenColors.primary,
          minHeight: 4,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: GardenColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(GardenRadius.full),
                  ),
                  child: Text(
                    'Paso $displayStep de 3',
                    style: const TextStyle(
                      color: GardenColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  instruction,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _textSecondary),
                ),
                const SizedBox(height: 32),

                // Photo capture card
                GestureDetector(
                  onTap: () => _capturePhoto(type),
                  child: Container(
                    width: cardWidth,
                    height: cardHeight,
                    decoration: BoxDecoration(
                      color: _surfaceColor,
                      borderRadius: BorderRadius.circular(GardenRadius.lg),
                      border: Border.all(
                        color: preview != null
                            ? GardenColors.success
                            : GardenColors.primary.withValues(alpha: 0.3),
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
                                Text('Toca para capturar', style: TextStyle(color: _textSecondary)),
                              ],
                            ),
                          ),
                        if (preview != null)
                          Positioned(
                            top: 12, right: 12,
                            child: Container(
                              decoration: const BoxDecoration(
                                color: GardenColors.success,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(2),
                              child: const Icon(Icons.check, color: Colors.white, size: 24),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                if (preview != null)
                  TextButton.icon(
                    onPressed: () => _capturePhoto(type),
                    icon: const Icon(Icons.refresh, size: 18, color: GardenColors.primary),
                    label: const Text('Volver a tomar', style: TextStyle(color: GardenColors.primary)),
                  ),

                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: _borderColor),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(GardenRadius.md),
                          ),
                        ),
                        onPressed: onBack,
                        child: Text('Atras', style: TextStyle(color: _textSecondary)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: GardenColors.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: GardenColors.primary.withValues(alpha: 0.3),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(GardenRadius.md),
                          ),
                        ),
                        onPressed: preview != null ? onNext : null,
                        child: Text(
                          _currentStep == 3 ? 'Enviar verificacion' : 'Continuar',
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

  // ── BUILD SUBMITTING ─────────────────────────────────────────────────────

  Widget _buildSubmitting() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 64, height: 64,
              child: CircularProgressIndicator(color: GardenColors.primary, strokeWidth: 3),
            ),
            const SizedBox(height: 32),
            Text(
              'Analizando tus documentos con IA...',
              style: TextStyle(color: _textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text('Esto puede tomar unos segundos',
                style: TextStyle(color: _textSecondary, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  // ── BUILD RESULT ─────────────────────────────────────────────────────────

  Widget _buildResult() {
    final isApproved = _resultStatus == 'approved' || _resultStatus == 'verified';
    final isReview = _resultStatus == 'review' || _resultStatus == 'pending_review';
    final isRejected = _resultStatus == 'rejected';

    final IconData icon;
    final Color iconColor;
    final String titleText;

    if (isApproved) {
      icon = Icons.check_circle;
      iconColor = GardenColors.success;
      titleText = 'Verificacion exitosa!';
    } else if (isReview) {
      icon = Icons.schedule;
      iconColor = GardenColors.warning;
      titleText = 'En revision';
    } else {
      icon = Icons.cancel;
      iconColor = GardenColors.error;
      titleText = 'Verificacion fallida';
    }

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isApproved)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 600),
              builder: (context, value, child) =>
                  Transform.scale(scale: value, child: Icon(icon, color: iconColor, size: 100)),
            )
          else
            Icon(icon, color: iconColor, size: 100),
          const SizedBox(height: 32),
          Text(
            titleText,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: iconColor),
          ),
          const SizedBox(height: 16),
          Text(
            _resultMessage,
            textAlign: TextAlign.center,
            style: TextStyle(color: _textSecondary, fontSize: 16, height: 1.5),
          ),

          if (isApproved)
            FutureBuilder<bool>(
              future: _checkBlockchainBadge(),
              builder: (context, snapshot) {
                if (snapshot.data == true) {
                  return Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: GardenColors.polygon.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(GardenRadius.md),
                      border: Border.all(color: GardenColors.polygon.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: GardenColors.polygon.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text('⬡',
                                style: TextStyle(color: GardenColors.polygon, fontSize: 16)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Badge registrado en Polygon',
                                style: TextStyle(
                                    color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const Text(
                                'Tu verificacion quedo registrada de forma inmutable en la blockchain',
                                style: TextStyle(color: GardenColors.polygon, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox();
              },
            ),

          const SizedBox(height: 48),

          SizedBox(
            width: double.infinity,
            child: isRejected
                ? ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GardenColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(GardenRadius.md)),
                    ),
                    onPressed: () => setState(() {
                      _currentStep = 0;
                      _verificationToken = '';
                      _livenessSessionId = null;
                      _selfiePreview = null;
                      _ciFrontPreview = null;
                      _ciBackPreview = null;
                    }),
                    child: const Text('Intentar de nuevo',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  )
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GardenColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(GardenRadius.md)),
                    ),
                    onPressed: _handleFinish,
                    child: const Text('Ir a mi panel',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
          ),
        ],
      ),
    );
  }

  // ── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Verificacion de identidad'),
              backgroundColor: _bgColor,
              foregroundColor: _textPrimary,
              elevation: 0,
              leading: _currentStep > 0 && _currentStep < 4
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => setState(() => _currentStep--),
                    )
                  : null,
            )
          : null,
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    switch (_currentStep) {
      case 0:
        return _buildIntro();
      case 1:
        return _buildCaptureStep(
          'selfie',
          'Toma tu selfie',
          'Asegurate de que tu rostro este bien iluminado y sea claramente visible.',
          _selfiePreview,
          () => setState(() => _currentStep = 0),
          () => setState(() => _currentStep = 2),
        );
      case 2:
        return _buildCaptureStep(
          'ciFront',
          'Foto del CI - Frente',
          'Asegurate de que el documento este bien iluminado y legible.',
          _ciFrontPreview,
          () => setState(() => _currentStep = 1),
          () => setState(() => _currentStep = 3),
        );
      case 3:
        return _buildCaptureStep(
          'ciBack',
          'Foto del CI - Reverso',
          'Asegurate de que el documento este bien iluminado y legible.',
          _ciBackPreview,
          () => setState(() => _currentStep = 2),
          _submitVerification,
        );
      case 4:
        return _buildSubmitting();
      case 5:
        return _buildResult();
      default:
        return _buildIntro();
    }
  }
}

// ── Liveness full-screen page (embedded — avoids separate file) ─────────────

class _LivenessCheckPage extends StatelessWidget {
  final String sessionId;

  const _LivenessCheckPage({required this.sessionId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: buildLivenessWidget(
          sessionId: sessionId,
          onComplete: () => Navigator.of(context).pop(true),
          onError: (code) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Error de verificación de vida ($code). Inténtalo de nuevo.'),
              backgroundColor: GardenColors.error,
            ));
            Navigator.of(context).pop(false);
          },
        ),
      ),
    );
  }
}
