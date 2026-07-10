import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/garden_tutorial.dart';
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
    // Dar tiempo al marketplace para renderizar antes de mostrar el tutorial
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) _maybeShowTutorial();
    });
  }

  Future<void> _maybeShowTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? '';
    // Ver nota en web_shell_screen.dart: nunca mostrar con userId vacío/'anonymous'
    // — evita que el tutorial se marque "visto" bajo una clave que no es la
    // cuenta real y vuelva a aparecer luego con el userId correcto.
    if (userId.isEmpty || !mounted) return;
    GardenTutorial.maybeShow(
      context,
      prefKey: 'tutorial_client_v1_$userId',
      stepsBuilder: (size, bottom) {
        Offset nav(int i) => GardenTutorial.navItemOffset(i, 4, size, bottom);
        return [
          const TutorialStep(
            emoji: '🌿',
            title: '¡Bienvenido a GARDEN!',
            body: 'Tu app para encontrar cuidadores de confianza para tu mascota. Te mostramos cómo funciona en segundos.',
          ),
          TutorialStep(
            emoji: '🔍',
            title: 'Encuentra cuidadores',
            body: 'Busca y filtra cuidadores por servicio, zona y disponibilidad. Compara perfiles y reserva el que más te convenza.',
            spotlightCenter: nav(0),
          ),
          TutorialStep(
            emoji: '📅',
            title: 'Tus reservas',
            body: 'Sigue en tiempo real todas tus reservas: activas, pendientes de confirmación e historial de servicios pasados.',
            spotlightCenter: nav(1),
          ),
          TutorialStep(
            emoji: '🐾',
            title: 'Tus mascotas',
            body: 'Registra a tus peludos con su foto, vacunas y necesidades especiales para que el cuidador llegue preparado.',
            spotlightCenter: nav(2),
          ),
          TutorialStep(
            emoji: '👤',
            title: 'Tu perfil',
            body: 'Gestiona tu cuenta, tus datos y preferencias. ¡Todo listo para tu primera reserva! 🎉',
            spotlightCenter: nav(3),
          ),
        ];
      },
    );
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
