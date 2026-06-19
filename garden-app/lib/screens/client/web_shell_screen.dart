import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/notification_bell.dart';
import 'marketplace_screen.dart';
import 'my_bookings_screen.dart';
import 'my_pets_screen.dart';
import '../../services/auth_state.dart';

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
    // Solo mostrar nombre si hay sesión activa
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
                      // Logo (40% más pequeño que el original)
                      GestureDetector(
                        onTap: () => setState(() => _selectedTab = 0),
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
                          onPressed: () => context.go('/become-caregiver'),
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
                          onPressed: () => context.go('/login'),
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
                            onPressed: () => context.go('/register'),
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
                            return Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: _WebNavButton(
                                icon: isActive ? tab.activeIcon : tab.icon,
                                label: tab.label,
                                isActive: isActive,
                                isDark: isDark,
                                onTap: () => setState(() => _selectedTab = tabIndex),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _authToken.isNotEmpty
                              ? context.push('/profile')
                              : context.push('/login'),
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
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          body: _buildBody(),
        );
      },
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
