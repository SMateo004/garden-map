import 'package:flutter/material.dart';
import '../../theme/garden_theme.dart';
import 'marketplace_screen.dart';
import 'my_bookings_screen.dart';
import 'my_pets_screen.dart';
import '../profile/profile_screen.dart';

/// Shell de navegación para el cliente en móvil.
/// Envuelve las 4 pantallas principales con un LiquidGlassNavBar flotante.
class ClientShellScreen extends StatefulWidget {
  final int initialTab;
  final String? initialService;
  const ClientShellScreen({super.key, this.initialTab = 0, this.initialService});

  @override
  State<ClientShellScreen> createState() => _ClientShellScreenState();
}

class _ClientShellScreenState extends State<ClientShellScreen> {
  late int _selectedTab;

  static const _items = [
    GardenNavItem(Icons.search_outlined,         Icons.search_rounded,        'Inicio'),
    GardenNavItem(Icons.list_alt_outlined,       Icons.list_alt_rounded,      'Reservas'),
    GardenNavItem(Icons.pets_outlined,           Icons.pets,                  'Mascotas'),
    GardenNavItem(Icons.person_outline_rounded,  Icons.person_rounded,        'Mi Perfil'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        return Scaffold(
          backgroundColor: isDark ? GardenColors.darkBackground : GardenColors.lightBackground,
          body: IndexedStack(
            index: _selectedTab,
            children: [
              MarketplaceScreen(isMobileShell: true, initialService: widget.initialService),
              const MyBookingsScreen(),
              const MyPetsScreen(),
              const ProfileScreen(),
            ],
          ),
          bottomNavigationBar: LiquidGlassNavBar(
            selectedIndex: _selectedTab,
            onTap: (i) => setState(() => _selectedTab = i),
            items: _items,
          ),
        );
      },
    );
  }
}
