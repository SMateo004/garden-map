import 'package:flutter/material.dart';
import '../../theme/garden_theme.dart';
import 'marketplace_screen.dart';
import 'my_bookings_screen.dart';
import 'my_pets_screen.dart';
import '../profile/profile_screen.dart';

/// Shell de navegación para el cliente en WEB.
/// Muestra las pestañas en el header (AppBar) en lugar de la barra inferior.
/// Solo debe usarse cuando [kIsWeb] es true.
class WebShellScreen extends StatefulWidget {
  final int initialTab;
  final String? initialService;
  final String? initialZone;
  final String? initialSize;

  const WebShellScreen({
    super.key,
    this.initialTab = 0,
    this.initialService,
    this.initialZone,
    this.initialSize,
  });

  @override
  State<WebShellScreen> createState() => _WebShellScreenState();
}

class _WebShellScreenState extends State<WebShellScreen> {
  late int _selectedTab;

  static const _tabs = [
    _NavTab(icon: Icons.search_outlined, activeIcon: Icons.search_rounded, label: 'Inicio'),
    _NavTab(icon: Icons.list_alt_outlined, activeIcon: Icons.list_alt_rounded, label: 'Reservas'),
    _NavTab(icon: Icons.pets_outlined, activeIcon: Icons.pets, label: 'Mascotas'),
    _NavTab(icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, label: 'Mi Perfil'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    debugPrint('[WebShell] init tab=${widget.initialTab}');
  }

  Widget _buildBody() {
    switch (_selectedTab) {
      case 0:
        return MarketplaceScreen(
          isMobileShell: false,
          initialService: widget.initialService,
          initialZone: widget.initialZone,
          initialSize: widget.initialSize,
        );
      case 1:
        return const MyBookingsScreen();
      case 2:
        return const MyPetsScreen();
      case 3:
        return const ProfileScreen();
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
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
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
                    color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
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
                      // Logo / Brand
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: GardenColors.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.eco_rounded, color: GardenColors.primary, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Garden',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Nav tabs
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(_tabs.length, (i) {
                          final tab = _tabs[i];
                          final isActive = _selectedTab == i;
                          return Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: _WebNavButton(
                              icon: isActive ? tab.activeIcon : tab.icon,
                              label: tab.label,
                              isActive: isActive,
                              isDark: isDark,
                              onTap: () {
                                debugPrint('[WebShell] Tab tapped: $i (${tab.label})');
                                setState(() => _selectedTab = i);
                              },
                            ),
                          );
                        }),
                      ),
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

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? GardenColors.primary.withOpacity(0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isActive
              ? Border.all(color: GardenColors.primary.withOpacity(0.25), width: 1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: isActive ? activeColor : inactiveColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive ? activeColor : inactiveColor,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
