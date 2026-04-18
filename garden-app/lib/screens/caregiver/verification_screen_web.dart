import 'dart:convert' show base64Decode, jsonDecode;
import 'dart:html' as html;
import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';
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
  bool _generatingToken = false;

  // Fotos capturadas
  Uint8List? _selfiePreview;
  Uint8List? _ciFrontPreview;
  Uint8List? _ciBackPreview;

  // Variables de cámara
  html.MediaStream? _mediaStream;
  html.VideoElement? _videoElement;

  // Estado del proceso
  int _currentStep = 0; // 0: intro, 1: selfie, 2: CI frontal, 3: CI trasero, 4: enviando, 5: resultado
  String _resultStatus = ''; // 'approved', 'review', 'rejected'
  String _resultMessage = '';

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://garden-api-1ldd.onrender.com/api');

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  @override
  void dispose() {
    _stopCamera();
    super.dispose();
  }

  void _stopCamera() {
    _mediaStream?.getTracks().forEach((t) => t.stop());
    _mediaStream = null;
    _videoElement = null;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _generatingToken = false);
    }
  }

  Future<void> _openCamera(String type) async {

    try {
      // Solicitar stream de cámara
      final stream = await html.window.navigator.mediaDevices!.getUserMedia({
        'video': {
          'facingMode': type == 'selfie' ? 'user' : 'environment',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        },
        'audio': false,
      });

      _mediaStream = stream;
      _videoElement = html.VideoElement()
        ..srcObject = stream
        ..autoplay = true
        ..muted = true
        ..setAttribute('playsinline', 'true')
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover';

      if (type == 'selfie') {
        _videoElement!.style.transform = 'scaleX(-1)';
      }

      // Registrar el view factory con timestamp único para evitar conflictos
      final viewId = 'garden-camera-${DateTime.now().millisecondsSinceEpoch}';
      // ignore: undefined_prefixed_name
      ui_web.platformViewRegistry.registerViewFactory(
        viewId,
        (int id) => _videoElement!,
      );

      if (mounted) {
        await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.black,
          isDismissible: false,
          builder: (ctx) => _buildCameraSheet(type, viewId, ctx),
        );
      }

    } catch (e) {
      _stopCamera();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No se pudo acceder a la cámara. Verifica los permisos del navegador.'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Widget _buildCameraSheet(String type, String viewId, BuildContext sheetContext) {
    final title = type == 'selfie' ? 'Toma tu selfie'
      : type == 'ciFront' ? 'CI - Frente'
      : 'CI - Reverso';

    final instruction = type == 'selfie'
      ? 'Centra tu rostro en el encuadre y asegúrate de tener buena iluminación'
      : 'Asegúrate de que el documento esté bien iluminado y legible';

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(title,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(instruction,
            style: const TextStyle(color: Colors.white60, fontSize: 13),
            textAlign: TextAlign.center),
          const SizedBox(height: 12),

          // Preview de cámara
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            height: 320,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kPrimaryColor, width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: HtmlElementView(viewType: viewId),
            ),
          ),
          const SizedBox(height: 20),

          // Botones
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white30),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () {
                      _stopCamera();
                      Navigator.pop(sheetContext);
                    },
                    child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.camera_alt, color: Colors.white),
                    label: const Text('Capturar foto',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: () => _captureAndClose(type, sheetContext),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _captureAndClose(String type, BuildContext sheetContext) async {
    if (_videoElement == null) return;

    try {
      // Capturar frame actual del video
      final canvas = html.CanvasElement(
        width: _videoElement!.videoWidth > 0 ? _videoElement!.videoWidth : 1280,
        height: _videoElement!.videoHeight > 0 ? _videoElement!.videoHeight : 720,
      );

      // Aplicar mirror para selfie
      if (type == 'selfie') {
        canvas.context2D
          ..translate(canvas.width!.toDouble(), 0)
          ..scale(-1, 1);
      }

      canvas.context2D.drawImage(_videoElement!, 0, 0);
      final dataUrl = canvas.toDataUrl('image/jpeg', 0.9);
      final base64Str = dataUrl.split(',')[1];
      final bytes = base64Decode(base64Str);

      _stopCamera();

      setState(() {
        if (type == 'selfie') {
          _selfiePreview = bytes;
        } else if (type == 'ciFront') _ciFrontPreview = bytes;
        else if (type == 'ciBack') _ciBackPreview = bytes;
      });

      if (mounted) {
        Navigator.pop(sheetContext);
        
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
          SnackBar(content: Text('Error al capturar: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  Future<void> _submitVerification() async {
    if (_selfiePreview == null || _ciFrontPreview == null || _ciBackPreview == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Captura las 3 fotos antes de continuar')),
      );
      return;
    }
    setState(() { _currentStep = 4; });
    try {
      final uri = Uri.parse('$_baseUrl/verification/submit');
      final request = http.MultipartRequest('POST', uri);

      // Agregar token como campo de texto
      request.fields['token'] = _verificationToken;

      // Agregar las 3 imágenes
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
          _resultStatus = (data['data']['status'] ?? 'review').toString().toLowerCase();
          _resultMessage = data['data']['message'] ?? 'Tu verificación está siendo procesada';
        });
      } else {
        throw Exception(data['error']?['message'] ?? data['message'] ?? 'Error en verificación');
      }
    } catch (e) {
      setState(() => _currentStep = 3);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade700),
      );
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

  Widget _buildIntro() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.verified_user, color: kPrimaryColor, size: 80),
          const SizedBox(height: 24),
          const Text(
            'Verifica tu identidad',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 12),
          const Text(
            'Para garantizar la seguridad de nuestra comunidad, necesitamos verificar tu identidad usando IA. Ten tus documentos a mano.',
            textAlign: TextAlign.center,
            style: TextStyle(color: kTextSecondary, height: 1.5),
          ),
          const SizedBox(height: 32),
          _buildRequirementItem('Toma una selfie nítida de tu rostro.'),
          _buildRequirementItem('Foto del anverso (frente) de tu CI.'),
          _buildRequirementItem('Foto del reverso (atrás) de tu CI.'),
          const SizedBox(height: 48),
          _generatingToken
              ? const CircularProgressIndicator(color: kPrimaryColor)
              : ElevatedButton(
                  onPressed: _generateVerificationToken,
                  child: const Text('Comenzar verificación'),
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
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  Widget _buildCaptureStep(String type, String title, String instruction, Uint8List? preview, VoidCallback onBack, VoidCallback onNext) {
    return Column(
      children: [
        LinearProgressIndicator(value: _currentStep / 3, backgroundColor: kSurfaceColor, color: kPrimaryColor),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 8),
                Text(instruction, textAlign: TextAlign.center, style: const TextStyle(color: kTextSecondary)),
                const SizedBox(height: 48),
                GestureDetector(
                  onTap: () => _openCamera(type),
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      color: kSurfaceColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: preview != null ? Colors.green : kPrimaryColor.withOpacity(0.3), width: 2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        if (preview != null)
                          Positioned.fill(child: Image.memory(preview, fit: BoxFit.cover))
                        else
                          const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.camera_alt, size: 64, color: kPrimaryColor),
                                SizedBox(height: 12),
                                Text('Toca para capturar', style: TextStyle(color: kTextSecondary)),
                              ],
                            ),
                          ),
                        if (preview != null)
                          const Positioned(
                            top: 12,
                            right: 12,
                            child: Icon(Icons.check_circle, color: Colors.green, size: 32),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 64),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onBack,
                        child: const Text('Atrás'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: preview != null ? onNext : null,
                        child: const Text('Continuar'),
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

  Widget _buildSubmitting() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: kPrimaryColor),
          SizedBox(height: 24),
          Text('Analizando tus documentos con IA...', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('Esto puede tomar unos segundos', style: TextStyle(color: kTextSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildResult() {
    bool isApproved = _resultStatus == 'approved' || _resultStatus == 'verified';
    bool isReview = _resultStatus == 'review' || _resultStatus == 'pending_review' || _resultStatus == 'review';
    bool isRejected = _resultStatus == 'rejected';

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
                child: const Icon(Icons.check_circle, color: Colors.green, size: 100),
              ),
            )
          else if (isReview)
            const Icon(Icons.schedule, color: Colors.orange, size: 100)
          else
            const Icon(Icons.cancel, color: Colors.red, size: 100),
          
          const SizedBox(height: 32),
          Text(
            isApproved ? '¡Verificación exitosa!' : isReview ? 'En revisión' : 'Verificación fallida',
            style: TextStyle(
              fontSize: 24, 
              fontWeight: FontWeight.bold, 
              color: isApproved ? Colors.green : isReview ? Colors.orange : Colors.red
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _resultMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kTextSecondary, fontSize: 16, height: 1.5),
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
                      color: GardenColors.navy,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: GardenColors.polygon.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: GardenColors.polygon.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text('⬡', style: TextStyle(color: GardenColors.polygon, fontSize: 16)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Badge registrado en Polygon',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              Text('Tu verificación quedó registrada de forma inmutable en la blockchain',
                                style: TextStyle(color: GardenColors.polygon, fontSize: 11)),
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
          if (isRejected)
            ElevatedButton(
              onPressed: () => setState(() {
                _currentStep = 0;
                _verificationToken = '';
                _selfiePreview = null;
                _ciFrontPreview = null;
                _ciBackPreview = null;
              }),
              child: const Text('Intentar de nuevo'),
            )
          else
            ElevatedButton(
              onPressed: () {
                if (widget.onComplete != null) {
                  widget.onComplete!();
                } else {
                  context.go('/caregiver/home');
                }
              },
              child: Text(widget.onComplete != null ? 'Continuar' : 'Ir a mi panel'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Verificación de identidad'),
              leading: _currentStep > 0 && _currentStep < 5 ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _currentStep--),
              ) : null,
            )
          : null,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_currentStep) {
      case 0: return _buildIntro();
      case 1: return _buildCaptureStep(
        'selfie', 
        'Toma tu selfie', 
        'Asegúrate de que tu rostro esté bien iluminado y sea claramente visible.', 
        _selfiePreview, 
        () => setState(() => _currentStep = 0), 
        () => setState(() => _currentStep = 2)
      );
      case 2: return _buildCaptureStep(
        'ciFront', 
        'Foto del CI - Frente', 
        'Sube una foto nítida del anverso de tu documento de identidad.', 
        _ciFrontPreview, 
        () => setState(() => _currentStep = 1), 
        () => setState(() => _currentStep = 3)
      );
      case 3: return _buildCaptureStep(
        'ciBack', 
        'Foto del CI - Reverso', 
        'Sube una foto nítida del reverso de tu documento de identidad.', 
        _ciBackPreview, 
        () => setState(() => _currentStep = 2), 
        _submitVerification
      );
      case 4: return _buildSubmitting();
      case 5: return _buildResult();
      default: return _buildIntro();
    }
  }
}
