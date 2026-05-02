import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _kSplashVersion = 'v3.0-logo-imagen';

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
    defaultValue: 'https://garden-api-1ldd.onrender.com/api',
  );

  @override
  void initState() {
    super.initState();
    debugPrint('[SPLASH $_kSplashVersion] initState');
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
    _run();
  }

  Future<void> _run() async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    _ctrl.forward();
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;
    await _navigate();
  }

  Future<void> _navigate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool('mobile_onboarding_seen') ?? false;
      debugPrint('[SPLASH] onboarding_seen=$seen');
      if (!mounted) return;

      if (!seen) {
        debugPrint('[SPLASH] → /onboarding');
        context.go('/onboarding');
        return;
      }

      final role = prefs.getString('user_role') ?? '';
      debugPrint('[SPLASH] user_role=$role');

      if (role != 'ADMIN') {
        final inMaintenance = await _checkMaintenance();
        if (!mounted) return;
        if (inMaintenance) {
          debugPrint('[SPLASH] → /maintenance');
          context.go('/maintenance');
          return;
        }
      }

      if (!mounted) return;
      await _goToHome(prefs);
    } catch (e, st) {
      debugPrint('[SPLASH] ERROR: $e\n$st');
      if (mounted) context.go('/login');
    }
  }

  Future<bool> _checkMaintenance() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/settings'))
          .timeout(const Duration(seconds: 6));
      final data = jsonDecode(res.body);
      return data['data']?['maintenanceMode'] == true;
    } catch (e) {
      debugPrint('[SPLASH] _checkMaintenance error: $e');
      return false;
    }
  }

  Future<void> _goToHome(SharedPreferences prefs) async {
    final token = prefs.getString('access_token') ?? '';
    final permanentRole = prefs.getString('user_role') ?? '';
    final activeRole = prefs.getString('active_role') ?? '';
    final role = activeRole.isNotEmpty ? activeRole : permanentRole;
    debugPrint('[SPLASH] token=${token.isEmpty ? "VACÍO" : "presente"} role=$role');

    if (token.isEmpty) {
      debugPrint('[SPLASH] → /login');
      if (mounted) context.go('/login');
      return;
    }
    if (role == 'ADMIN') {
      debugPrint('[SPLASH] → /admin');
      if (mounted) context.go('/admin');
      return;
    }
    if (role == 'CAREGIVER') {
      debugPrint('[SPLASH] → /caregiver/home');
      if (mounted) context.go('/caregiver/home');
      return;
    }

    debugPrint('[SPLASH] buscando reserva IN_PROGRESS...');
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/bookings/my?limit=5&page=1'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 6));
      debugPrint('[SPLASH] bookings status=${response.statusCode}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final bookings =
              (data['data'] as List).cast<Map<String, dynamic>>();
          final active =
              bookings.where((b) => b['status'] == 'IN_PROGRESS').firstOrNull;
          if (active != null && mounted) {
            debugPrint('[SPLASH] → /service/${active['id']}');
            context.go(
              '/service/${active['id']}',
              extra: {'role': 'CLIENT', 'token': token},
            );
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('[SPLASH] error bookings: $e');
    }

    debugPrint('[SPLASH] → /service-selector');
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
      backgroundColor: const Color(0xFF3B5E1A),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SizedBox.expand(
          child: Image.asset(
            'assets/images/garden_logo.png',
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
