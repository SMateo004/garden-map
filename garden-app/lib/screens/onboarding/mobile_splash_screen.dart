import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class MobileSplashScreen extends StatefulWidget {
  const MobileSplashScreen({super.key});

  @override
  State<MobileSplashScreen> createState() => _MobileSplashScreenState();
}

class _MobileSplashScreenState extends State<MobileSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  static const _bg = Color(0xFF3B5E1A);
  static const _logoColor = Color(0xFFCDEBA0);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
    _scaleAnim = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _run();
  }

  Future<void> _run() async {
    await Future.delayed(const Duration(milliseconds: 150));
    _ctrl.forward();
    await Future.delayed(const Duration(milliseconds: 2800));
    if (!mounted) return;
    await _navigate();
  }

  static const _baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://garden-api-1ldd.onrender.com/api',
  );

  Future<void> _navigate() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('mobile_onboarding_seen') ?? false;
    if (!mounted) return;
    if (!seen) {
      context.go('/onboarding');
      return;
    }

    final role = prefs.getString('user_role') ?? '';
    if (role != 'ADMIN') {
      final inMaintenance = await _checkMaintenance();
      if (!mounted) return;
      if (inMaintenance) {
        context.go('/maintenance');
        return;
      }
    }

    if (!mounted) return;
    _goToHome(prefs);
  }

  Future<bool> _checkMaintenance() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/settings'))
          .timeout(const Duration(seconds: 6));
      final data = jsonDecode(res.body);
      return data['data']?['maintenanceMode'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _goToHome(SharedPreferences prefs) async {
    final token = prefs.getString('access_token') ?? '';
    final permanentRole = prefs.getString('user_role') ?? '';
    final activeRole = prefs.getString('active_role') ?? '';
    final role = activeRole.isNotEmpty ? activeRole : permanentRole;
    if (token.isEmpty) {
      context.go('/login');
      return;
    }
    if (role == 'ADMIN') {
      context.go('/admin');
      return;
    }
    if (role == 'CAREGIVER') {
      context.go('/caregiver/home');
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/bookings/my?limit=5&page=1'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final bookings = (data['data'] as List).cast<Map<String, dynamic>>();
          final active =
              bookings.where((b) => b['status'] == 'IN_PROGRESS').firstOrNull;
          if (active != null && mounted) {
            context.go(
              '/service/${active['id']}',
              extra: {'role': 'CLIENT', 'token': token},
            );
            return;
          }
        }
      }
    } catch (_) {}

    if (mounted) context.go('/service-selector');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: ScaleTransition(
          scale: _scaleAnim,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 190,
                  height: 190,
                  child: CustomPaint(
                    painter: _GardenLogoPainter(color: _logoColor),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'garden',
                  style: GoogleFonts.nunito(
                    color: _logoColor,
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
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

// ── Logo painter: paw print + leaf tree ───────────────────────────────────────

class _GardenLogoPainter extends CustomPainter {
  final Color color;
  const _GardenLogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()..color = color..style = PaintingStyle.fill;

    // ── Toe beans ─────────────────────────────────────────────────────────────
    // Center-left toe
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.365, h * 0.225),
        width: w * 0.255,
        height: h * 0.305,
      ),
      fill,
    );
    // Center-right toe
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.635, h * 0.225),
        width: w * 0.255,
        height: h * 0.305,
      ),
      fill,
    );
    // Left outer toe
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.158, h * 0.385),
        width: w * 0.235,
        height: h * 0.278,
      ),
      fill,
    );
    // Right outer toe
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.842, h * 0.385),
        width: w * 0.235,
        height: h * 0.278,
      ),
      fill,
    );

    // ── Main pad ──────────────────────────────────────────────────────────────
    final padRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.715),
        width: w * 0.76,
        height: h * 0.505,
      ),
      Radius.circular(w * 0.28),
    );
    canvas.drawRRect(padRect, fill);

    // ── Leaf / tree inside main pad ───────────────────────────────────────────
    final leafPaint = Paint()
      ..color = const Color(0xFF5DB840)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.048
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final cx = w * 0.5;
    final trunkTop = h * 0.495;
    final trunkBottom = h * 0.935;

    // Trunk
    canvas.drawLine(Offset(cx, trunkBottom), Offset(cx, trunkTop), leafPaint);

    // Upper branch pair
    canvas.drawLine(
      Offset(cx, h * 0.580),
      Offset(cx - w * 0.155, h * 0.510),
      leafPaint,
    );
    canvas.drawLine(
      Offset(cx, h * 0.580),
      Offset(cx + w * 0.155, h * 0.510),
      leafPaint,
    );

    // Middle branch pair
    canvas.drawLine(
      Offset(cx, h * 0.680),
      Offset(cx - w * 0.130, h * 0.615),
      leafPaint,
    );
    canvas.drawLine(
      Offset(cx, h * 0.680),
      Offset(cx + w * 0.130, h * 0.615),
      leafPaint,
    );

    // Lower branch pair
    canvas.drawLine(
      Offset(cx, h * 0.785),
      Offset(cx - w * 0.100, h * 0.728),
      leafPaint,
    );
    canvas.drawLine(
      Offset(cx, h * 0.785),
      Offset(cx + w * 0.100, h * 0.728),
      leafPaint,
    );
  }

  @override
  bool shouldRepaint(_GardenLogoPainter old) => old.color != color;
}
