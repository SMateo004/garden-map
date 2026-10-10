import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart' show openAppSettings;
import '../../theme/garden_motion.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/garden_loading_indicator.dart';
import '../../design/garden_icons.dart';

enum CameraFrameShape { oval, rectangle }

/// Recorte visible del marco guía, como fracción del tamaño de pantalla.
/// Única fuente de verdad compartida por los painters del overlay y por el
/// recorte real de la foto capturada — así lo que el usuario ve encuadrado
/// es exactamente lo que se guarda y se envía a verificación.
Rect frameCutoutRect(Size size, CameraFrameShape shape) {
  if (shape == CameraFrameShape.oval) {
    final w = size.width * 0.78;
    final h = w * 1.15;
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

class _CropParams {
  final Uint8List bytes;
  final double screenW;
  final double screenH;
  final CameraFrameShape shape;
  const _CropParams(this.bytes, this.screenW, this.screenH, this.shape);
}

/// Recorta la foto cruda de la cámara a la región exacta que mostraba el
/// marco guía en pantalla (óvalo del rostro o rectángulo del CI), para que
/// la imagen final no incluya fondo de sobra ni quede distorsionada al
/// mostrarla en miniaturas con otra proporción.
Uint8List _cropToFrame(_CropParams p) {
  var image = img.decodeImage(p.bytes);
  if (image == null) return p.bytes;
  image = img.bakeOrientation(image);

  final cutout = frameCutoutRect(Size(p.screenW, p.screenH), p.shape);

  final rawW = image.width.toDouble();
  final rawH = image.height.toDouble();
  final scale = (p.screenW / rawW > p.screenH / rawH)
      ? p.screenW / rawW
      : p.screenH / rawH;
  final visibleW = p.screenW / scale;
  final visibleH = p.screenH / scale;
  final offsetX = (rawW - visibleW) / 2;
  final offsetY = (rawH - visibleH) / 2;

  final fx = cutout.left / p.screenW;
  final fy = cutout.top / p.screenH;
  final fw = cutout.width / p.screenW;
  final fh = cutout.height / p.screenH;

  var cropLeft = offsetX + fx * visibleW;
  var cropTop = offsetY + fy * visibleH;
  var cropWidth = fw * visibleW;
  var cropHeight = fh * visibleH;

  cropLeft = cropLeft.clamp(0, rawW - 1);
  cropTop = cropTop.clamp(0, rawH - 1);
  cropWidth = cropWidth.clamp(1, rawW - cropLeft);
  cropHeight = cropHeight.clamp(1, rawH - cropTop);

  final cropped = img.copyCrop(
    image,
    x: cropLeft.round(),
    y: cropTop.round(),
    width: cropWidth.round(),
    height: cropHeight.round(),
  );

  return Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
}

/// Pantalla de cámara con marco guía y linterna. Después de tomar la foto la
/// muestra en el marco para revisarla (Repetir / Usar foto).
/// Devuelve los bytes JPG recortados al marco, o null si se cancela.
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
  bool _torchOn = false;
  bool _isCapturing = false;
  String? _errorMsg;

  /// El sistema negó la cámara: se ofrece abrir los ajustes y, al volver a la
  /// app, se reintenta solo.
  bool _permissionDenied = false;

  /// Foto ya recortada esperando que la persona confirme que se ve bien.
  Uint8List? _review;

  bool get _isDocument => widget.frameShape == CameraFrameShape.rectangle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      // Se suelta la cámara al salir de la app y se OLVIDA el controlador:
      // antes se liberaba pero la pantalla lo seguía usando, y al volver
      // fallaba con "CameraController was used after being disposed".
      final controller = _controller;
      if (controller == null) return;
      setState(() {
        _controller = null;
        _torchOn = false;
      });
      controller.dispose();
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    if (mounted) {
      setState(() {
        _errorMsg = null;
        _permissionDenied = false;
      });
    }
    try {
      // Con límite: si el sistema nunca responde, la pantalla no se queda
      // girando para siempre sino que ofrece reintentar.
      final cameras = await availableCameras().timeout(const Duration(seconds: 10));
      if (cameras.isEmpty) {
        if (mounted) setState(() => _errorMsg = 'Este dispositivo no tiene cámara disponible.');
        return;
      }
      final description = cameras.firstWhere(
        (c) => c.lensDirection == widget.lensDirection,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize().timeout(const Duration(seconds: 10));
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      if (_review != null) controller.pausePreview();
    } on CameraException catch (e) {
      if (!mounted) return;
      final denied = e.code.contains('AccessDenied') || e.code.contains('AccessRestricted') || e.code.contains('ermission');
      setState(() {
        _permissionDenied = denied;
        _errorMsg = denied
            ? 'Para tomar la foto, Garden necesita permiso para usar la cámara.'
            : 'No pudimos abrir la cámara. Cierra otras apps que la estén usando e intenta de nuevo.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _errorMsg = 'No pudimos abrir la cámara. Cierra otras apps que la estén usando e intenta de nuevo.');
      }
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    // Cámara frontal generalmente no tiene linterna
    if (widget.lensDirection == CameraLensDirection.front) return;
    try {
      final on = !_torchOn;
      await controller.setFlashMode(on ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torchOn = on);
    } catch (_) {}
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isCapturing) return;

    HapticFeedback.mediumImpact();
    setState(() => _isCapturing = true);
    try {
      final screenSize = MediaQuery.of(context).size;
      final xfile = await controller.takePicture();
      final rawBytes = await xfile.readAsBytes();
      final bytes = await compute(
        _cropToFrame,
        _CropParams(rawBytes, screenSize.width, screenSize.height, widget.frameShape),
      );
      if (!mounted) return;
      // Antes la foto se enviaba al instante; ahora se revisa primero.
      await controller.pausePreview();
      setState(() {
        _review = bytes;
        _isCapturing = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isCapturing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo tomar la foto. Intenta de nuevo.')),
        );
      }
    }
  }

  Future<void> _retake() async {
    HapticFeedback.selectionClick();
    setState(() => _review = null);
    try {
      await _controller?.resumePreview();
    } catch (_) {}
  }

  void _usePhoto() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(_review);
  }

  /// Lo que hace que la verificación pase a la primera.
  List<String> get _tips => _isDocument
      ? const ['Todo el carnet dentro', 'Sin reflejos', 'Que se lean los datos']
      : const ['Buena luz', 'Sin lentes ni gorra', 'Mira a la cámara'];

  @override
  Widget build(BuildContext context) {
    if (_errorMsg != null) return _buildError();

    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final cutout = frameCutoutRect(size, widget.frameShape);
        final reviewing = _review != null;

        return Stack(
          fit: StackFit.expand,
          children: [
            // ── Vista de la cámara (cover, sin estirar la imagen) ──
            if (controller != null && controller.value.isInitialized)
              ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: size.width,
                    height: size.width * controller.value.aspectRatio,
                    child: CameraPreview(controller),
                  ),
                ),
              )
            else if (!reviewing)
              const Center(child: GardenLoadingIndicator(color: Colors.white)),

            // ── Oscurece todo menos el marco ──
            CustomPaint(painter: _OverlayPainter(shape: widget.frameShape, dim: reviewing ? 0.85 : 0.55)),

            // ── La foto tomada, en el mismo lugar del marco ──
            if (reviewing)
              Positioned.fromRect(
                rect: cutout,
                child: ClipPath(
                  clipper: _FrameClipper(widget.frameShape),
                  child: Image.memory(_review!, fit: BoxFit.cover, gaplessPlayback: true),
                ),
              ),

            CustomPaint(painter: _FrameBorderPainter(shape: widget.frameShape, done: reviewing)),

            // ── Encabezado ──
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(8, MediaQuery.of(context).padding.top + 8, 8, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withValues(alpha: 0.65), Colors.transparent],
                  ),
                ),
                child: Row(children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const GardenIcon(GIcon.cerrar, size: GIconSize.md, color: Colors.white, semanticLabel: 'Cerrar'),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(widget.title,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                  ),
                  if (!reviewing && widget.lensDirection != CameraLensDirection.front)
                    IconButton(
                      onPressed: _toggleTorch,
                      icon: GardenIcon(GIcon.linterna,
                          size: GIconSize.lg,
                          color: _torchOn ? GardenColors.warning : Colors.white,
                          state: _torchOn ? GIconState.active : GIconState.idle),
                      tooltip: _torchOn ? 'Apagar linterna' : 'Encender linterna',
                    ),
                ]),
              ),
            ),

            // ── Indicaciones debajo del marco ──
            Positioned(
              top: cutout.bottom + 18,
              left: 24,
              right: 24,
              child: Column(children: [
                Text(
                  reviewing
                      ? (_isDocument ? '¿Se leen bien todos los datos?' : '¿Se te ve bien la cara?')
                      : widget.hint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: reviewing ? 17 : 14,
                    fontWeight: reviewing ? FontWeight.w800 : FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in _tips)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(GardenRadius.full),
                        ),
                        child: Text(t,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
              ]),
            ),

            // ── Acciones ──
            Positioned(
              left: 24,
              right: 24,
              bottom: MediaQuery.of(context).padding.bottom + 28,
              child: reviewing
                  ? Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _retake,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white, width: 1.5),
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GardenRadius.md)),
                          ),
                          child: const Text('Repetir', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: GardenButton(label: 'Usar foto', onPressed: _usePhoto)),
                    ])
                  : Center(
                      child: Semantics(
                        button: true,
                        label: 'Tomar foto',
                        child: GestureDetector(
                          onTap: _isCapturing || controller == null ? null : _capture,
                          child: AnimatedContainer(
                            duration: GardenMotion.resolve(context, GardenMotion.instant),
                            width: _isCapturing ? 70 : 76,
                            height: _isCapturing ? 70 : 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                            ),
                            padding: const EdgeInsets.all(5),
                            child: _isCapturing
                                ? const Padding(
                                    padding: EdgeInsets.all(14),
                                    child: GardenLoadingIndicator(color: Colors.white),
                                  )
                                : Container(
                                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                                  ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildError() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              GardenIcon(GIcon.foto, size: GIconSize.hero, color: Colors.white.withValues(alpha: 0.7)),
              const SizedBox(height: 18),
              Text(_permissionDenied ? 'Permite el acceso a la cámara' : 'La cámara no está disponible',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(_errorMsg!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 14, height: 1.45)),
              const SizedBox(height: 24),
              if (_permissionDenied)
                GardenButton(label: 'Abrir ajustes', onPressed: () => openAppSettings())
              else
                GardenButton(label: 'Intentar de nuevo', onPressed: _initCamera),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Volver', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Recorte de la foto revisada con la forma del marco ─────────────────────

class _FrameClipper extends CustomClipper<Path> {
  final CameraFrameShape shape;
  const _FrameClipper(this.shape);

  @override
  Path getClip(Size size) {
    final r = Offset.zero & size;
    return shape == CameraFrameShape.oval
        ? (Path()..addOval(r))
        : (Path()..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(16))));
  }

  @override
  bool shouldReclip(_FrameClipper old) => old.shape != shape;
}

// ── Painter: overlay oscuro con hueco central ──────────────────────────────

class _OverlayPainter extends CustomPainter {
  final CameraFrameShape shape;
  final double dim;
  const _OverlayPainter({required this.shape, this.dim = 0.55});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: dim);
    final cutout = frameCutoutRect(size, shape);
    final full = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final hole = shape == CameraFrameShape.oval
        ? (Path()..addOval(cutout))
        : (Path()..addRRect(RRect.fromRectAndRadius(cutout, const Radius.circular(16))));
    canvas.drawPath(Path.combine(PathOperation.difference, full, hole), paint);
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => old.shape != shape || old.dim != dim;
}

// ── Painter: borde del recorte ────────────────────────────────────────────

/// Óvalo con borde simple (antes llevaba arcos sueltos en las esquinas del
/// rectángulo que lo contiene, flotando fuera del óvalo); el carnet, con
/// esquinas de encuadre. En verde cuando la foto ya se tomó.
class _FrameBorderPainter extends CustomPainter {
  final CameraFrameShape shape;
  final bool done;
  const _FrameBorderPainter({required this.shape, this.done = false});

  @override
  void paint(Canvas canvas, Size size) {
    final cutout = frameCutoutRect(size, shape);
    final border = Paint()
      ..color = done ? GardenColors.success : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = done ? 3 : 2.5;

    if (shape == CameraFrameShape.oval) {
      canvas.drawOval(cutout, border);
      return;
    }
    canvas.drawRRect(RRect.fromRectAndRadius(cutout, const Radius.circular(16)), border);
    if (done) return;

    final corner = Paint()
      ..color = GardenColors.primaryLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const len = 26.0;
    final r = cutout;
    for (final c in [
      [Offset(r.left, r.top + len), r.topLeft, Offset(r.left + len, r.top)],
      [Offset(r.right - len, r.top), r.topRight, Offset(r.right, r.top + len)],
      [Offset(r.left, r.bottom - len), r.bottomLeft, Offset(r.left + len, r.bottom)],
      [Offset(r.right - len, r.bottom), r.bottomRight, Offset(r.right, r.bottom - len)],
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(c[0].dx, c[0].dy)
          ..lineTo(c[1].dx, c[1].dy)
          ..lineTo(c[2].dx, c[2].dy),
        corner,
      );
    }
  }

  @override
  bool shouldRepaint(_FrameBorderPainter old) => old.shape != shape || old.done != done;
}
