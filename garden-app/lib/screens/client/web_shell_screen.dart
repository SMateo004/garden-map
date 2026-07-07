import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/garden_tutorial.dart';
import '../../widgets/notification_bell.dart';
import 'marketplace_screen.dart';
import 'my_bookings_screen.dart';
import 'my_pets_screen.dart';
import '../../services/auth_state.dart';
import '../../utils/web_redirect.dart';

/// Shell de navegación para el cliente en WEB.
/// Muestra las pestañas en el header (AppBar) en lugar de la barra inferior.
/// Solo debe usarse cuando [kIsWeb] es true.
class WebShellScreen extends StatefulWidget {
  final int initialTab;
  final String? initialService;
  final String? initialZone;
  final String? initialSize;
  final String? initialPetType;

  const WebShellScreen({
    super.key,
    this.initialTab = 0,
    this.initialService,
    this.initialZone,
    this.initialSize,
    this.initialPetType,
  });

  @override
  State<WebShellScreen> createState() => _WebShellScreenState();
}

class _WebShellScreenState extends State<WebShellScreen> {
  late int _selectedTab;
  String _authToken = '';
  String? _userName;
  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  // GlobalKeys para el tutorial web
  final GlobalKey _reservasKey = GlobalKey();
  final GlobalKey _mascotasKey = GlobalKey();
  final GlobalKey _profileKey = GlobalKey();

  // Tab 0 (Inicio/Marketplace) se activa con el logo — no aparece en el nav
  static const _tabs = [
    _NavTab(icon: Icons.list_alt_outlined, activeIcon: Icons.list_alt_rounded, label: 'Reservas'),
    _NavTab(icon: Icons.pets_outlined, activeIcon: Icons.pets, label: 'Mascotas'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    debugPrint('[WebShell] init tab=${widget.initialTab}');
    _loadAuth();
  }

  Future<void> _loadAuth() async {
    final token = AuthState.token;
    String? name;
    if (token.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      name = prefs.getString('user_name');
    }
    if (mounted) {
      setState(() {
        _authToken = token;
        _userName = name;
      });
    }
    // Verificar si hay un QR de pago activo pendiente y redirigir
    if (token.isNotEmpty) {
      await _checkPendingPayment(token);
    }
    // Tutorial primera sesión (solo usuarios logueados)
    if (token.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeShowTutorial();
      });
    }
  }

  Future<void> _maybeShowTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? 'anonymous';
    if (!mounted) return;
    GardenTutorial.maybeShow(
      context,
      prefKey: 'tutorial_client_web_v1_$userId',
      stepsBuilder: (_, __) => [
        const TutorialStep(
          emoji: '🌿',
          title: '¡Bienvenido a GARDEN!',
          body: 'Tu plataforma para encontrar cuidadores de confianza para tu mascota. Te mostramos cómo funciona en segundos.',
        ),
        const TutorialStep(
          emoji: '🔍',
          title: 'Encuentra cuidadores',
          body: 'En el panel principal puedes buscar y filtrar cuidadores por servicio, zona y disponibilidad. Compara perfiles y reserva el mejor.',
        ),
        TutorialStep(
          emoji: '📅',
          title: 'Tus reservas',
          body: 'Sigue en tiempo real todas tus reservas: activas, pendientes de confirmación e historial de servicios pasados.',
          targetKey: _reservasKey,
          spotlightRadius: 36,
        ),
        TutorialStep(
          emoji: '🐾',
          title: 'Tus mascotas',
          body: 'Registra a tus peludos con su foto, vacunas y necesidades especiales para que el cuidador llegue siempre preparado.',
          targetKey: _mascotasKey,
          spotlightRadius: 36,
        ),
        TutorialStep(
          emoji: '👤',
          title: 'Tu perfil',
          body: 'Gestiona tu cuenta, tus datos y preferencias. ¡Todo listo para tu primera reserva! 🎉',
          targetKey: _profileKey,
          spotlightRadius: 36,
        ),
      ],
    );
  }

  Future<void> _checkPendingPayment(String token) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/bookings/my?limit=5&page=1'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 4));
      if (!mounted || res.statusCode != 200) return;
      final data = jsonDecode(res.body);
      if (data['success'] != true) return;
      final bookings = (data['data'] as List).cast<Map<String, dynamic>>();
      final pending = bookings.where((b) {
        if (b['status'] != 'PENDING_PAYMENT') return false;
        final qrId = b['qrId'];
        final expiresAtStr = b['qrExpiresAt'];
        if (qrId == null || expiresAtStr == null) return false;
        final expiry = DateTime.tryParse(expiresAtStr.toString());
        return expiry != null && expiry.isAfter(DateTime.now());
      }).firstOrNull;
      if (pending != null && mounted) {
        context.go('/payment/${pending['id']}');
      }
    } catch (_) {}
  }

  Widget _buildBody() {
    switch (_selectedTab) {
      case 0:
        return MarketplaceScreen(
          isMobileShell: false,
          initialService: widget.initialService,
          initialZone: widget.initialZone,
          initialSize: widget.initialSize,
          initialPetType: widget.initialPetType,
        );
      case 1:
        return const MyBookingsScreen();
      case 2:
        return const MyPetsScreen();
      default:
        return MarketplaceScreen(isMobileShell: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
        final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
        final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

        return Scaffold(
          backgroundColor: bg,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: Container(
              decoration: BoxDecoration(
                color: surface,
                border: Border(bottom: BorderSide(color: borderColor, width: 1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      // Logo → siempre vuelve al landing de React
                      GestureDetector(
                        onTap: () => redirectToReactLanding(),
                        child: Image.asset(
                          isDark
                              ? 'assets/images/logo-horizontal-dark.png'
                              : 'assets/images/logo-horizontal.png',
                          height: 125,
                        ),
                      ),
                      const Spacer(),
                      // Header público (sin sesión) — igual al home
                      if (_authToken.isEmpty) ...[
                        TextButton(
                          onPressed: () => context.push('/become-caregiver'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          child: const Text(
                            'Convertirse en cuidador',
                            style: TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w700, fontSize: 13),
                            maxLines: 1,
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.push('/login'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          child: Text(
                            'Iniciar sesión',
                            style: TextStyle(
                              color: isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 8, left: 4),
                          child: GardenButton(
                            label: 'Registrarse',
                            width: 150,
                            height: 38,
                            onPressed: () => context.push('/register'),
                          ),
                        ),
                      ] else ...[
                        // Header logueado — notificaciones + tabs + perfil
                        NotificationBell(token: _authToken, baseUrl: _baseUrl),
                        const SizedBox(width: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(_tabs.length, (i) {
                            final tab = _tabs[i];
                            final tabIndex = i + 1;
                            final isActive = _selectedTab == tabIndex;
                            // Keys: i==0 → Reservas, i==1 → Mascotas
                            final navKey = i == 0 ? _reservasKey : _mascotasKey;
                            return SizedBox(
                              key: navKey,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: _WebNavButton(
                                  icon: isActive ? tab.activeIcon : tab.icon,
                                  label: tab.label,
                                  isActive: isActive,
                                  isDark: isDark,
                                  onTap: () => setState(() => _selectedTab = tabIndex),
                                ),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _authToken.isNotEmpty
                              ? context.push('/profile')
                              : context.push('/login'),
                          child: SizedBox(
                            key: _profileKey,
                            child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              border: Border.all(color: GardenColors.primary.withValues(alpha: 0.4)),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(
                                _authToken.isNotEmpty
                                    ? (_userName?.split(' ').first ?? 'Perfil')
                                    : 'Iniciar sesión',
                                style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                _authToken.isNotEmpty
                                    ? Icons.account_circle_outlined
                                    : Icons.login_outlined,
                                size: 18,
                                color: GardenColors.primary,
                              ),
                            ]),
                          ),
                        ),
                      ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          body: _buildBody(),
          bottomNavigationBar: _HelpFooterBar(isDark: isDark),
        );
      },
    );
  }
}

/// Pie de página fijo con acceso al Centro de Ayuda — visible en todas las
/// pestañas de la web app (Marketplace, Reservas, Mascotas), tanto para
/// visitantes públicos como para usuarios logueados.
class _HelpFooterBar extends StatelessWidget {
  final bool isDark;
  const _HelpFooterBar({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final textColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: borderColor, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Row(
            children: [
              Text(
                '© ${DateTime.now().year} Garden Bolivia',
                style: TextStyle(color: textColor, fontSize: 12),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => context.push('/help-center'),
                icon: const Icon(Icons.help_outline_rounded, size: 18, color: GardenColors.primary),
                label: const Text(
                  'Centro de Ayuda',
                  style: TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTab {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavTab({required this.icon, required this.activeIcon, required this.label});
}

class _WebNavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  const _WebNavButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = GardenColors.primary;
    final inactiveColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return Tooltip(
      message: label,
      preferBelow: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isActive ? GardenColors.primary.withValues(alpha: 0.10) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isActive
                ? Border.all(color: GardenColors.primary.withValues(alpha: 0.25), width: 1)
                : null,
          ),
          child: Icon(icon, size: 22, color: isActive ? activeColor : inactiveColor),
        ),
      ),
    );
  }
}
