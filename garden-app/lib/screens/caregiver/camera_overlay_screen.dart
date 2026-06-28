import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../theme/garden_theme.dart';

enum CameraFrameShape { oval, rectangle }

/// Pantalla de cámara con overlay guía + linterna.
/// Devuelve [File] con la foto capturada, o null si el usuario cancela.
class CameraOverlayScreen extends StatefulWidget {
  final CameraFrameShape frameShape;
  final String title;
  final String hint;
  final CameraLensDirection lensDirection;

  const CameraOverlayScreen({
    super.key,
    required this.frameShape,
    required this.title,
    required this.hint,
    this.lensDirection = CameraLensDirection.back,
  });

  @override
  State<CameraOverlayScreen> createState() => _CameraOverlayScreenState();
}

class _CameraOverlayScreenState extends State<CameraOverlayScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _torchOn = false;
  bool _isCapturing = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() => _errorMsg = 'No se encontró ninguna cámara.');
        return;
      }

      final description = _cameras!.firstWhere(
        (c) => c.lensDirection == widget.lensDirection,
        orElse: () => _cameras!.first,
      );

      final controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      if (!mounted) return;

      setState(() {
        _controller = controller;
        _isInitialized = true;
      });
    } catch (e) {
      if (mounted) setState(() => _errorMsg = 'Error al iniciar cámara: $e');
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    // Cámara frontal generalmente no tiene linterna
    if (widget.lensDirection == CameraLensDirection.front) return;
    try {
      _torchOn = !_torchOn;
      await controller.setFlashMode(_torchOn ? FlashMode.torch : FlashMode.off);
      setState(() {});
    } catch (_) {}
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isCapturing) return;

    setState(() => _isCapturing = true);
    try {
      // Apagar linterna antes de capturar (evita sobreexposición)
      if (_torchOn) {
        await controller.setFlashMode(FlashMode.off);
      }
      final xfile = await controller.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(File(xfile.path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al capturar: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isCapturing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMsg != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.no_photography_rounded, color: Colors.white.withValues(alpha: 0.54), size: 64),
                const SizedBox(height: 16),
                Text(_errorMsg!,
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Volver'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Preview de cámara ──────────────────────────────────────────
          CameraPreview(_controller!),

          // ── Overlay oscuro con recorte ─────────────────────────────────
          CustomPaint(
            painter: _OverlayPainter(shape: widget.frameShape),
          ),

          // ── Borde del marco ─────────────────────────────────────────────
          CustomPaint(
            painter: _FrameBorderPainter(shape: widget.frameShape),
          ),

          // ── Header: botón back + título ──────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                8,
                MediaQuery.of(context).padding.top + 8,
                8,
                12,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.65),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  // Linterna (solo cámara trasera)
                  if (widget.lensDirection != CameraLensDirection.front)
                    IconButton(
                      onPressed: _toggleTorch,
                      icon: Icon(
                        _torchOn
                            ? Icons.flashlight_on_rounded
                            : Icons.flashlight_off_rounded,
                        color: _torchOn ? Colors.amber : Colors.white,
                        size: 28,
                      ),
                      tooltip: _torchOn ? 'Apagar linterna' : 'Encender linterna',
                    ),
                ],
              ),
            ),
          ),

          // ── Hint debajo del marco ─────────────────────────────────────────
          Align(
            alignment: const Alignment(0, 0.42),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(GardenRadius.full),
              ),
              child: Text(
                widget.hint,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          // ── Botón de captura ──────────────────────────────────────────────
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _isCapturing ? null : _capture,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: _isCapturing ? 70 : 76,
                  height: _isCapturing ? 70 : 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: Colors.white, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: _isCapturing
                      ? const Padding(
                          padding: EdgeInsets.all(18),
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: GardenColors.primary,
                          ),
                        )
                      : Container(
                          margin: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: GardenColors.primary,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Painter: overlay oscuro con hueco central ──────────────────────────────

class _OverlayPainter extends CustomPainter {
  final CameraFrameShape shape;
  const _OverlayPainter({required this.shape});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.55);

    final cutout = _cutoutRect(size);

    final full = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final hole = shape == CameraFrameShape.oval
        ? (Path()..addOval(cutout))
        : (Path()
          ..addRRect(RRect.fromRectAndRadius(
              cutout, const Radius.circular(16))));

    final overlayPath =
        Path.combine(PathOperation.difference, full, hole);
    canvas.drawPath(overlayPath, paint);
  }

  Rect _cutoutRect(Size size) {
    if (shape == CameraFrameShape.oval) {
      final w = size.width * 0.72;
      final h = w * 1.28;
      final cx = size.width / 2;
      final cy = size.height * 0.44;
      return Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
    } else {
      final w = size.width * 0.82;
      final h = w * 0.63;
      final cx = size.width / 2;
      final cy = size.height * 0.42;
      return Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => old.shape != shape;
}

// ── Painter: borde del recorte ────────────────────────────────────────────

class _FrameBorderPainter extends CustomPainter {
  final CameraFrameShape shape;
  const _FrameBorderPainter({required this.shape});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final dashedPaint = Paint()
      ..color = GardenColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final cutout = _cutoutRect(size);

    if (shape == CameraFrameShape.oval) {
      // Borde sólido blanco
      canvas.drawOval(cutout, paint);
      // Esquinas decorativas de color primario (arcos en las esquinas del bounding box)
      _drawCornerArcs(canvas, cutout, dashedPaint);
    } else {
      final rrect =
          RRect.fromRectAndRadius(cutout, const Radius.circular(16));
      canvas.drawRRect(rrect, paint);
      _drawCornerLines(canvas, cutout, dashedPaint);
    }
  }

  Rect _cutoutRect(Size size) {
    if (shape == CameraFrameShape.oval) {
      final w = size.width * 0.72;
      final h = w * 1.28;
      final cx = size.width / 2;
      final cy = size.height * 0.44;
      return Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
    } else {
      final w = size.width * 0.82;
      final h = w * 0.63;
      final cx = size.width / 2;
      final cy = size.height * 0.42;
      return Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
    }
  }

  void _drawCornerArcs(Canvas canvas, Rect r, Paint p) {
    const sweep = 0.5; // radianes
    final paths = [
      (Offset(r.left, r.top), 3.14 + 0.3, sweep),
      (Offset(r.right, r.top), -0.3, sweep),
      (Offset(r.left, r.bottom), 3.14 - sweep - 0.3, sweep),
      (Offset(r.right, r.bottom), 0.3, sweep),
    ];
    for (final item in paths) {
      canvas.drawArc(
        Rect.fromCenter(center: item.$1, width: 24, height: 24),
        item.$2,
        item.$3,
        false,
        p..strokeWidth = 3.5,
      );
    }
  }

  void _drawCornerLines(Canvas canvas, Rect r, Paint p) {
    const len = 22.0;
    final corners = [
      [Offset(r.left, r.top + len), r.topLeft, Offset(r.left + len, r.top)],
      [Offset(r.right - len, r.top), r.topRight, Offset(r.right, r.top + len)],
      [Offset(r.left, r.bottom - len), r.bottomLeft, Offset(r.left + len, r.bottom)],
      [Offset(r.right - len, r.bottom), r.bottomRight, Offset(r.right, r.bottom - len)],
    ];
    for (final c in corners) {
      final path = Path()
        ..moveTo(c[0].dx, c[0].dy)
        ..lineTo(c[1].dx, c[1].dy)
        ..lineTo(c[2].dx, c[2].dy);
      canvas.drawPath(path, p..strokeWidth = 3.5..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_FrameBorderPainter old) => old.shape != shape;
}
