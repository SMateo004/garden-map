import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';

class MobileSplashScreen extends StatefulWidget {
  const MobileSplashScreen({super.key});

  @override
  State<MobileSplashScreen> createState() => _MobileSplashScreenState();
}

class _MobileSplashScreenState extends State<MobileSplashScreen>
    with TickerProviderStateMixin {
  // ── Controladores ──
  late final AnimationController _bgCtrl;
  late final AnimationController _iconCtrl;
  late final AnimationController _textCtrl;
  late final AnimationController _taglineCtrl;
  late final AnimationController _exitCtrl;
  late final AnimationController _pulseCtrl;

  // ── Animaciones ──
  late final Animation<double> _bgOpacity;
  late final Animation<double> _iconScale;
  late final Animation<double> _iconOpacity;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _textOpacity;
  late final Animation<double> _taglineOpacity;
  late final Animation<double> _exitOpacity;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();

    _bgCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _iconCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _textCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _taglineCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _exitCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);

    _bgOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _bgCtrl, curve: Curves.easeIn),
    );

    _iconScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.15), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 0.9), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 20),
    ]).animate(CurvedAnimation(parent: _iconCtrl, curve: Curves.easeOut));

    _iconOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _iconCtrl, curve: const Interval(0, 0.3, curve: Curves.easeIn)),
    );

    _textSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
      CurvedAnimation(parent: _textCtrl, curve: Curves.easeOutCubic),
    );

    _textOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _textCtrl, curve: Curves.easeIn),
    );

    _taglineOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _taglineCtrl, curve: Curves.easeIn),
    );

    _exitOpacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _exitCtrl, curve: Curves.easeInOut),
    );

    _pulse = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _runSequence();
  }

  Future<void> _runSequence() async {
    // Fondo aparece
    await Future.delayed(const Duration(milliseconds: 100));
    _bgCtrl.forward();

    // Icono rebota
    await Future.delayed(const Duration(milliseconds: 300));
    _iconCtrl.forward();

    // Texto "GARDEN" sube
    await Future.delayed(const Duration(milliseconds: 800));
    _textCtrl.forward();

    // Tagline aparece
    await Future.delayed(const Duration(milliseconds: 600));
    _taglineCtrl.forward();

    // Espera (total ~4s desde inicio)
    await Future.delayed(const Duration(milliseconds: 1600));

    // Salida
    _pulseCtrl.stop();
    await _exitCtrl.forward();

    if (!mounted) return;
    await _navigate();
  }

  static const _baseUrl = String.fromEnvironment('API_URL',
      defaultValue: 'https://garden-api-1ldd.onrender.com/api');

  Future<void> _navigate() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('mobile_onboarding_seen') ?? false;
    if (!mounted) return;
    if (!seen) {
      context.go('/onboarding');
      return;
    }

    final role = prefs.getString('user_role') ?? '';

    // Los admins siempre pasan, nunca ven pantalla de mantenimiento
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
      return false; // Si falla la petición, no bloquear al usuario
    }
  }

  Future<void> _goToHome(SharedPreferences prefs) async {
    final token = prefs.getString('access_token') ?? '';
    final role = prefs.getString('user_role') ?? '';
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

    // CLIENT: verificar si tiene un paseo/hospedaje IN_PROGRESS → ir directo al servicio
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/bookings/my?limit=5&page=1'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final bookings = (data['data'] as List).cast<Map<String, dynamic>>();
          final active = bookings.where((b) => b['status'] == 'IN_PROGRESS').firstOrNull;
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
    _bgCtrl.dispose();
    _iconCtrl.dispose();
    _textCtrl.dispose();
    _taglineCtrl.dispose();
    _exitCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _bgCtrl, _iconCtrl, _textCtrl, _taglineCtrl, _exitCtrl, _pulseCtrl,
      ]),
      builder: (context, _) {
        return FadeTransition(
          opacity: _exitOpacity,
          child: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                // ── Fondo degradado ──
                FadeTransition(
                  opacity: _bgOpacity,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF4A6B28), GardenColors.primary, Color(0xFF2D5016)],
                      ),
                    ),
                  ),
                ),

                // ── Círculos decorativos de fondo ──
                FadeTransition(
                  opacity: _bgOpacity,
                  child: Stack(
                    children: [
                      Positioned(
                        top: -80, right: -60,
                        child: Container(
                          width: 260, height: 260,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: -100, left: -80,
                        child: Container(
                          width: 320, height: 320,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 120, right: 30,
                        child: Container(
                          width: 80, height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Contenido central ──
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo icono con bounce
                      ScaleTransition(
                        scale: _pulse,
                        child: ScaleTransition(
                          scale: _iconScale,
                          child: FadeTransition(
                            opacity: _iconOpacity,
                            child: Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(26),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 32,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.pets_rounded,
                                  color: GardenColors.primary,
                                  size: 52,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Texto "GARDEN"
                      SlideTransition(
                        position: _textSlide,
                        child: FadeTransition(
                          opacity: _textOpacity,
                          child: Text(
                            'GARDEN',
                            style: GardenText.h2.copyWith(
                              color: Colors.white,
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 10,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Tagline
                      FadeTransition(
                        opacity: _taglineOpacity,
                        child: Text(
                          'Cuidado de mascotas en Santa Cruz',
                          style: GardenText.body.copyWith(
                            color: Colors.white.withValues(alpha: 0.80),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Puntos animados en la parte inferior ──
                Positioned(
                  bottom: 60,
                  left: 0, right: 0,
                  child: FadeTransition(
                    opacity: _taglineOpacity,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(3, (i) {
                        final delay = i * 0.33;
                        final progress = (_pulseCtrl.value - delay).clamp(0.0, 1.0);
                        final size = 6.0 + progress * 4.0;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: size,
                          height: size,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.4 + progress * 0.6),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
