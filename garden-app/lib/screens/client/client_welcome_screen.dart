import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/garden_theme.dart';

class ClientWelcomeScreen extends StatefulWidget {
  const ClientWelcomeScreen({Key? key}) : super(key: key);

  @override
  State<ClientWelcomeScreen> createState() => _ClientWelcomeScreenState();
}

class _ClientWelcomeScreenState extends State<ClientWelcomeScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      context.go('/marketplace');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
        final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

        return Scaffold(
          backgroundColor: bg,
          body: SafeArea(
            child: Column(
              children: [
                // Barra de salto
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (_currentPage < 2)
                        TextButton(
                          onPressed: () => context.go('/marketplace'),
                          child: Text(
                            'Omitir',
                            style: TextStyle(color: subtextColor, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    children: [
                      // Paso 1
                      _buildPage(
                        imageIcon: Icons.search_rounded,
                        title: 'Encuentra al paseador ideal',
                        description: 'Filtra por zona, especialidad y reseñas para proteger a tu mascota.',
                        color: GardenColors.primary,
                        textColor: textColor,
                        subtextColor: subtextColor,
                      ),
                      // Paso 2
                      _buildPage(
                        imageIcon: Icons.shield_outlined,
                        title: '100% Protegido',
                        description: 'Tus pagos se retienen de forma segura en Polygon Blockchain hasta que se complete el servicio.',
                        color: GardenColors.success,
                        textColor: textColor,
                        subtextColor: subtextColor,
                      ),
                      // Paso 3
                      _buildPage(
                        imageIcon: Icons.pets_rounded,
                        title: 'Relájate y disfruta',
                        description: 'Recibe fotos y seguimiento real-time desde la app. Nosotros nos encargamos del resto.',
                        color: const Color(0xFFFF6B35),
                        textColor: textColor,
                        subtextColor: subtextColor,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          3,
                          (index) => AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            height: 8,
                            width: _currentPage == index ? 24 : 8,
                            decoration: BoxDecoration(
                              color: _currentPage == index ? GardenColors.primary : subtextColor.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      GardenButton(
                        label: _currentPage == 2 ? 'Explorar Cuidadores' : 'Siguiente',
                        width: double.infinity,
                        icon: _currentPage == 2 ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded,
                        onPressed: _nextPage,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPage({
    required IconData imageIcon,
    required String title,
    required String description,
    required Color color,
    required Color textColor,
    required Color subtextColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              imageIcon,
              size: 100,
              color: color,
            ),
          ),
          const SizedBox(height: 48),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: subtextColor,
              fontSize: 16,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
