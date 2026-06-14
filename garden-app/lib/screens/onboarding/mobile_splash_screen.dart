import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_state.dart';

const _kSplashVersion = 'v4.0-fast';

class _NavTarget {
  final String path;
  final Object? extra;
  const _NavTarget(this.path, [this.extra]);
}

class MobileSplashScreen extends StatefulWidget {
  const MobileSplashScreen({super.key});

  @override
  State<MobileSplashScreen> createState() => _MobileSplashScreenState();
}

class _MobileSplashScreenState extends State<MobileSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fadeAnim;

  static const _baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://api.gardenbo.com/api',
  );

  @override
  void initState() {
    super.initState();
    debugPrint('[SPLASH $_kSplashVersion] initState');
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _run();
  }

  Future<void> _run() async {
    _ctrl.forward();

    // Compute destination and enforce minimum display time simultaneously.
    // We navigate only after both complete — no wasted 2.5s hardcoded delay.
    final results = await Future.wait<Object?>([
      _computeDestination(),
      Future.delayed(const Duration(seconds: 3)),
    ]);

    if (!mounted) return;
    final target = results[0] as _NavTarget;
    debugPrint('[SPLASH] navigating → ${target.path}');
    context.go(target.path, extra: target.extra);
  }

  Future<_NavTarget> _computeDestination() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool('mobile_onboarding_seen') ?? false;
      debugPrint('[SPLASH] onboarding_seen=$seen');

      if (!seen) return const _NavTarget('/onboarding');

      final role = prefs.getString('user_role') ?? '';
      debugPrint('[SPLASH] user_role=$role');

      if (role == 'ADMIN') return const _NavTarget('/admin');

      // Maintenance check + home resolution in parallel
      final token = AuthState.token;
      debugPrint('[SPLASH] token=${token.isEmpty ? "VACÍO" : "presente"}');

      final futures = await Future.wait([
        _checkMaintenance(),
        if (token.isNotEmpty && role != 'ADMIN') _fetchActiveBooking(token) else Future.value(null),
      ]);

      final inMaintenance = futures[0] as bool;
      if (inMaintenance) return const _NavTarget('/maintenance');

      if (token.isEmpty) return const _NavTarget('/service-selector');

      final activeBookingResult = futures.length > 1 ? futures[1] : null;

      final activeRole = prefs.getString('active_role') ?? '';
      final effectiveRole = activeRole.isNotEmpty ? activeRole : role;

      if (effectiveRole == 'CAREGIVER') return const _NavTarget('/caregiver/home');

      // Client: check for active / pending-payment booking returned from parallel call
      if (activeBookingResult is _NavTarget) return activeBookingResult;

      return const _NavTarget('/service-selector');
    } catch (e, st) {
      debugPrint('[SPLASH] ERROR: $e\n$st');
      return const _NavTarget('/login');
    }
  }

  Future<bool> _checkMaintenance() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/settings'))
          .timeout(const Duration(seconds: 3));
      final data = jsonDecode(res.body);
      return data['data']?['maintenanceMode'] == true;
    } catch (e) {
      debugPrint('[SPLASH] _checkMaintenance error: $e');
      return false;
    }
  }

  /// Returns a [_NavTarget] if there is a booking that needs immediate attention,
  /// or `null` to fall through to the default home screen.
  Future<_NavTarget?> _fetchActiveBooking(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/bookings/my?limit=5&page=1'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 3));

      debugPrint('[SPLASH] bookings status=${response.statusCode}');

      if (response.statusCode == 401) {
        AuthState.handleUnauthorized();
        return const _NavTarget('/login');
      }
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final bookings = (data['data'] as List).cast<Map<String, dynamic>>();

          // Active QR payment takes priority
          final pendingPayment = bookings.where((b) {
            if (b['status'] != 'PENDING_PAYMENT') return false;
            final qrId = b['qrId'];
            final qrExpiresAtStr = b['qrExpiresAt'];
            if (qrId == null || qrExpiresAtStr == null) return false;
            final expiry = DateTime.tryParse(qrExpiresAtStr.toString());
            return expiry != null && expiry.isAfter(DateTime.now());
          }).firstOrNull;

          if (pendingPayment != null) {
            return _NavTarget('/payment/${pendingPayment['id']}');
          }

          final active = bookings.where((b) => b['status'] == 'IN_PROGRESS').firstOrNull;
          if (active != null) {
            return _NavTarget(
              '/service/${active['id']}',
              {'role': 'CLIENT', 'token': token},
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[SPLASH] error bookings: $e');
    }
    return null;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF3B5E1A),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Center(
          child: Image.asset(
            'assets/images/garden_logo.png',
            width: MediaQuery.of(context).size.width * 0.75,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
