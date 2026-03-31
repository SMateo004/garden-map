import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';

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
  bool _isLoading = false;
  bool _generatingToken = false;

  // Fotos capturadas
  Uint8List? _selfiePreview;
  Uint8List? _ciFrontPreview;
  Uint8List? _ciBackPreview;

  final ImagePicker _picker = ImagePicker();

  // Estado del proceso
  // 0: intro, 1: selfie, 2: CI frontal, 3: CI trasero, 4: enviando, 5: resultado
  int _currentStep = 0;
  String _resultStatus = ''; // 'approved', 'review', 'rejected'
  String _resultMessage = '';

  String get _baseUrl =>
      const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api');

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
    final prefs = await SharedPreferences.getInstance();
    String token = prefs.getString('access_token') ?? '';
    if (token.isEmpty) {
      token = const String.fromEnvironment('TEST_JWT', defaultValue: '');
    }
    setState(() => _caregiverToken = token);
  }

  Future<void> _generateVerificationToken() async {
    setState(() => _generatingToken = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/verification/generate-link'),
        headers: {'Authorization': 'Bearer $_caregiverToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _verificationToken = data['data']['token'];
          _currentStep = 1;
        });
      } else {
        throw Exception(data['error']?['message'] ?? 'Error al generar token');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingToken = false);
    }
  }

  Future<void> _capturePhoto(String type) async {
    try {
      final preferredCamera =
          type == 'selfie' ? CameraDevice.front : CameraDevice.rear;

      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: preferredCamera,
        imageQuality: 85,
        maxWidth: 1280,
        maxHeight: 1280,
      );

      if (photo == null) return; // User cancelled

      final bytes = await photo.readAsBytes();

      setState(() {
        if (type == 'selfie') {
          _selfiePreview = bytes;
        } else if (type == 'ciFront') {
          _ciFrontPreview = bytes;
        } else if (type == 'ciBack') {
          _ciBackPreview = bytes;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto capturada correctamente'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'No se pudo acceder a la camara. Verifica los permisos de la app.'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _submitVerification() async {
    if (_selfiePreview == null ||
        _ciFrontPreview == null ||
        _ciBackPreview == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Captura las 3 fotos antes de continuar')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _currentStep = 4;
    });

    try {
      final uri = Uri.parse('$_baseUrl/verification/submit');
      final request = http.MultipartRequest('POST', uri);

      request.fields['token'] = _verificationToken;

      final imageData = [
        ('selfie', _selfiePreview),
        ('ciFront', _ciFrontPreview),
        ('ciBack', _ciBackPreview),
      ];

      for (final entry in imageData) {
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
          _resultStatus =
              (data['data']['status'] ?? 'review').toString().toLowerCase();
          _resultMessage =
              data['data']['message'] ?? 'Tu verificacion esta siendo procesada';
        });
      } else {
        throw Exception(
            data['error']?['message'] ?? data['message'] ?? 'Error en verificacion');
      }
    } catch (e) {
      setState(() => _currentStep = 3);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _checkBlockchainBadge() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? _caregiverToken;
      final response = await http.get(
        Uri.parse('$_baseUrl/caregiver/my-profile'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        return data['data']?['isVerified'] == true ||
            data['data']?['verificationStatus'] == 'APPROVED' ||
            data['data']?['verificationStatus'] == 'VERIFIED';
      }
      return false;
    } catch (e) {
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
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Para garantizar la seguridad de nuestra comunidad, necesitamos verificar tu identidad usando IA. Ten tus documentos a mano.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _textSecondary, height: 1.5),
          ),
          const SizedBox(height: 32),
          _buildRequirementItem('Toma una selfie nitida de tu rostro.'),
          _buildRequirementItem('Foto del anverso (frente) de tu CI.'),
          _buildRequirementItem('Foto del reverso (atras) de tu CI.'),
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
                    onPressed: _generateVerificationToken,
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

  Widget _buildRequirementItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 20),
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
    final stepNumber = _currentStep; // 1, 2, or 3

    return Column(
      children: [
        // Progress indicator
        LinearProgressIndicator(
          value: stepNumber / 3,
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
                // Step counter
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: GardenColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(GardenRadius.full),
                  ),
                  child: Text(
                    'Paso $stepNumber de 3',
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
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      color: _surfaceColor,
                      borderRadius: BorderRadius.circular(GardenRadius.lg),
                      border: Border.all(
                        color: preview != null
                            ? Colors.green
                            : GardenColors.primary.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        if (preview != null)
                          Positioned.fill(
                            child: Image.memory(preview, fit: BoxFit.cover),
                          )
                        else
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.camera_alt,
                                    size: 64, color: GardenColors.primary),
                                const SizedBox(height: 12),
                                Text('Toca para capturar',
                                    style: TextStyle(color: _textSecondary)),
                              ],
                            ),
                          ),
                        if (preview != null)
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(2),
                              child: const Icon(Icons.check,
                                  color: Colors.white, size: 24),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                // Retake hint
                if (preview != null)
                  TextButton.icon(
                    onPressed: () => _capturePhoto(type),
                    icon: const Icon(Icons.refresh,
                        size: 18, color: GardenColors.primary),
                    label: const Text('Volver a tomar',
                        style: TextStyle(color: GardenColors.primary)),
                  ),

                const SizedBox(height: 32),

                // Navigation buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: _borderColor),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(GardenRadius.md),
                          ),
                        ),
                        onPressed: onBack,
                        child: Text('Atras',
                            style: TextStyle(color: _textSecondary)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: GardenColors.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              GardenColors.primary.withValues(alpha: 0.3),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(GardenRadius.md),
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
              width: 64,
              height: 64,
              child: CircularProgressIndicator(
                color: GardenColors.primary,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Analizando tus documentos con IA...',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Esto puede tomar unos segundos',
              style: TextStyle(color: _textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ── BUILD RESULT ─────────────────────────────────────────────────────────

  Widget _buildResult() {
    final isApproved =
        _resultStatus == 'approved' || _resultStatus == 'verified';
    final isReview = _resultStatus == 'review' ||
        _resultStatus == 'pending_review';
    final isRejected = _resultStatus == 'rejected';

    final IconData icon;
    final Color iconColor;
    final String titleText;

    if (isApproved) {
      icon = Icons.check_circle;
      iconColor = Colors.green;
      titleText = 'Verificacion exitosa!';
    } else if (isReview) {
      icon = Icons.schedule;
      iconColor = Colors.orange;
      titleText = 'En revision';
    } else {
      icon = Icons.cancel;
      iconColor = Colors.red;
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
              builder: (context, value, child) => Transform.scale(
                scale: value,
                child: Icon(icon, color: iconColor, size: 100),
              ),
            )
          else
            Icon(icon, color: iconColor, size: 100),
          const SizedBox(height: 32),
          Text(
            titleText,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: iconColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _resultMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textSecondary,
              fontSize: 16,
              height: 1.5,
            ),
          ),

          // Blockchain badge (approved only)
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
                      border: Border.all(
                          color: GardenColors.polygon.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: GardenColors.polygon.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text(
                              '\u2B21',
                              style: TextStyle(
                                  color: GardenColors.polygon, fontSize: 16),
                            ),
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
                                  color: _textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const Text(
                                'Tu verificacion quedo registrada de forma inmutable en la blockchain',
                                style: TextStyle(
                                    color: GardenColors.polygon, fontSize: 11),
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
                        borderRadius:
                            BorderRadius.circular(GardenRadius.md),
                      ),
                    ),
                    onPressed: () => setState(() {
                      _currentStep = 0;
                      _verificationToken = '';
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
                        borderRadius:
                            BorderRadius.circular(GardenRadius.md),
                      ),
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
