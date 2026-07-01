import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../theme/garden_theme.dart';

/// Blink liveness challenge for Flutter web (QR flow).
///
/// Shows a camera preview and guides the user through two eye-state frames:
///   1. Eyes OPEN  — auto-captured after a brief countdown.
///   2. Eyes CLOSED — auto-captured 1.8 s later.
///
/// Both frames are sent to `/verification/check-blink`.
/// Returns the `blinkLivenessToken` (String) on success, or `null` if the
/// user cancels or the challenge fails without a successful retry.
class BlinkChallengeScreen extends StatefulWidget {
  final String verificationToken;
  final String baseUrl;

  const BlinkChallengeScreen({
    super.key,
    required this.verificationToken,
    required this.baseUrl,
  });

  @override
  State<BlinkChallengeScreen> createState() => _BlinkChallengeScreenState();
}

enum _Phase {
  initializing,
  instructionOpen,
  capturingOpen,
  instructionClose,
  capturingClose,
  sending,
  failed,
}

class _BlinkChallengeScreenState extends State<BlinkChallengeScreen> {
  CameraController? _camera;
  _Phase _phase = _Phase.initializing;
  String _errorMsg = '';
  int _countdown = 3;
  Timer? _timer;
  Uint8List? _frameOpen;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(front, ResolutionPreset.medium, enableAudio: false);
      await ctrl.initialize();
      if (!mounted) return;
      setState(() {
        _camera = ctrl;
        _phase = _Phase.instructionOpen;
      });
      Future.delayed(const Duration(milliseconds: 1500), _startCountdown);
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _errorMsg = 'No se pudo acceder a la cámara. Verifica los permisos.';
        });
      }
    }
  }

  void _startCountdown() {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.capturingOpen;
      _countdown = 3;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) { t.cancel(); return; }
      if (_countdown > 1) {
        setState(() => _countdown--);
      } else {
        t.cancel();
        await _captureOpen();
      }
    });
  }

  Future<void> _captureOpen() async {
    try {
      final xfile = await _camera!.takePicture();
      _frameOpen = await xfile.readAsBytes();
      if (!mounted) return;
      setState(() => _phase = _Phase.instructionClose);
      Future.delayed(const Duration(milliseconds: 1800), _captureClose);
    } catch (e) {
      if (mounted) {
        setState(() { _phase = _Phase.failed; _errorMsg = 'Error al capturar imagen.'; });
      }
    }
  }

  Future<void> _captureClose() async {
    if (!mounted) return;
    setState(() => _phase = _Phase.capturingClose);
    await Future.delayed(const Duration(milliseconds: 700));
    try {
      final xfile = await _camera!.takePicture();
      final frameClosed = await xfile.readAsBytes();
      if (!mounted) return;
      setState(() => _phase = _Phase.sending);
      await _submit(_frameOpen!, frameClosed);
    } catch (e) {
      if (mounted) {
        setState(() { _phase = _Phase.failed; _errorMsg = 'Error al capturar imagen.'; });
      }
    }
  }

  Future<void> _submit(Uint8List open, Uint8List closed) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${widget.baseUrl}/verification/check-blink'),
      );
      request.fields['token'] = widget.verificationToken;
      request.files.add(http.MultipartFile.fromBytes(
        'frameOpen', open,
        filename: 'open.jpg',
        contentType: MediaType.parse('image/jpeg'),
      ));
      request.files.add(http.MultipartFile.fromBytes(
        'frameClosed', closed,
        filename: 'closed.jpg',
        contentType: MediaType.parse('image/jpeg'),
      ));

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final res = await http.Response.fromStream(streamed);
      final data = jsonDecode(res.body);

      if (!mounted) return;
      if (res.statusCode == 200 && data['success'] == true) {
        final token = data['data']['blinkLivenessToken'] as String?;
        Navigator.of(context).pop(token);
      } else {
        final msg = data['error']?['message'] as String? ??
            'No se detectó el parpadeo correctamente. Intenta de nuevo.';
        setState(() { _phase = _Phase.failed; _errorMsg = msg; });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _errorMsg = 'Error de conexión. Verifica tu red e intenta de nuevo.';
        });
      }
    }
  }

  void _retry() {
    _timer?.cancel();
    _frameOpen = null;
    setState(() {
      _phase = _Phase.instructionOpen;
      _errorMsg = '';
    });
    Future.delayed(const Duration(milliseconds: 400), _startCountdown);
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildCameraPreview(),
            // Dark scrim so text is readable over the camera feed
            Container(color: Colors.black.withValues(alpha: 0.30)),
            // Oval guide centered on the face
            Center(
              child: CustomPaint(
                size: const Size(200, 256),
                painter: _OvalPainter(),
              ),
            ),
            // Instruction card at the bottom
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: _buildInstructionCard(),
            ),
            // Close (cancel) button
            Positioned(
              top: 8, right: 8,
              child: Material(
                color: Colors.transparent,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(context).pop(null),
                  tooltip: 'Cancelar',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_camera == null || !_camera!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white38, strokeWidth: 2),
      );
    }
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _camera!.value.previewSize?.height ?? 480,
          height: _camera!.value.previewSize?.width ?? 640,
          child: CameraPreview(_camera!),
        ),
      ),
    );
  }

  Widget _buildInstructionCard() {
    if (_phase == _Phase.failed) return _buildFailedCard();
    return _buildStatusCard();
  }

  Widget _buildStatusCard() {
    final IconData icon;
    final Color color;
    final String title;
    final String? subtitle;

    switch (_phase) {
      case _Phase.initializing:
        icon = Icons.camera_alt_rounded;
        color = Colors.white70;
        title = 'Preparando cámara...';
        subtitle = null;
      case _Phase.instructionOpen:
        icon = Icons.visibility_rounded;
        color = Colors.greenAccent;
        title = 'Mantén los ojos\nBIEN ABIERTOS';
        subtitle = 'Mira directo a la cámara';
      case _Phase.capturingOpen:
        icon = Icons.fiber_manual_record_rounded;
        color = Colors.redAccent;
        title = 'Capturando... $_countdown';
        subtitle = 'Mantén los ojos abiertos';
      case _Phase.instructionClose:
        icon = Icons.visibility_off_rounded;
        color = Colors.amber;
        title = 'Ahora CIÉRRA\nlos ojos';
        subtitle = 'Ciérralos lentamente';
      case _Phase.capturingClose:
        icon = Icons.fiber_manual_record_rounded;
        color = Colors.redAccent;
        title = 'Capturando...';
        subtitle = 'Mantén los ojos cerrados';
      case _Phase.sending:
        icon = Icons.psychology_rounded;
        color = Colors.cyanAccent;
        title = 'Analizando...';
        subtitle = 'Verificando parpadeo con IA';
      case _Phase.failed:
        icon = Icons.error_outline;
        color = Colors.redAccent;
        title = _errorMsg;
        subtitle = null;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.80),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 36),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.70), fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFailedCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 40),
          const SizedBox(height: 12),
          Text(
            _errorMsg,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Reintentar', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: GardenColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}

class _OvalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawOval(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
