import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/garden_theme.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  String _selectedService = 'paseo'; // 'paseo' o 'hospedaje'
  String? _selectedZone;
  String? _selectedPetType; // 'Perro', 'Gato'
  String? _selectedSize; // 'PEQUEÑO', 'MEDIANO', 'GRANDE', 'GIGANTE'

  final Map<String, String> _zoneLabels = {
    'EQUIPETROL': 'Equipetrol',
    'URBARI': 'Urbari',
    'NORTE': 'Norte',
    'LAS_PALMAS': 'Las Palmas',
    'CENTRO_SAN_MARTIN': 'Centro/San Martín',
    'OTROS': 'Otros',
  };

  void _onSearch() {
    String query = '?service=$_selectedService';
    if (_selectedZone != null) query += '&zone=${_selectedZone!}';
    if (_selectedSize != null) query += '&size=${_selectedSize!}';
    if (_selectedPetType != null) query += '&petType=${_selectedPetType!}';
    
    context.go('/marketplace$query');
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
        final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

        return Scaffold(
          backgroundColor: bg,
          body: CustomScrollView(
            slivers: [
              // HEADER COMERCIAL
              SliverAppBar(
                backgroundColor: bg,
                elevation: 0,
                pinned: true,
                title: const Text(
                  'GARDEN',
                  style: TextStyle(
                    color: GardenColors.primary,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => context.go('/register'), // "Quiero ser cuidador" puede guiar a registro y role
                    child: const Text('Convertirse en cuidador', style: TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: Text('Iniciar sesión', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(right: 16.0, top: 10, bottom: 10),
                    child: GardenButton(
                      label: 'Registrarse',
                      width: 120,
                      onPressed: () => context.go('/register'),
                    ),
                  ),
                ],
              ),

              // HERO SECTION CON BUSCADOR
              SliverToBoxAdapter(
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 550),
                  decoration: BoxDecoration(
                    color: isDark ? GardenColors.darkSurfaceElevated : GardenColors.primary.withOpacity(0.05),
                    image: DecorationImage(
                      image: const NetworkImage('https://images.unsplash.com/photo-1548199973-03cce0bbc87b?auto=format&fit=crop&q=80'),
                      fit: BoxFit.cover,
                      colorFilter: ColorFilter.mode(
                        Colors.black.withOpacity(isDark ? 0.7 : 0.4),
                        BlendMode.darken,
                      ),
                    ),
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Encuentra el cuidado perfecto\npara tu mejor amigo.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 42,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                              letterSpacing: -1.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Paseadores y anfitriones verificados por IA y respaldados con Escrow Blockchain.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 48),

                          // Buscador Flotante Estilo Rover/Airbnb
                          Container(
                            constraints: const BoxConstraints(maxWidth: 1050),
                            decoration: BoxDecoration(
                              color: isDark ? GardenColors.darkSurface : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                alignment: WrapAlignment.center,
                                spacing: 12,
                                runSpacing: 16,
                                children: [
                                  // 1. Selector de Servicio
                                  SizedBox(
                                    width: 250,
                                    child: _buildServiceToggle(textColor, subtextColor),
                                  ),
                                  
                                  // 2. Selector de Zona
                                  Container(
                                    width: 200,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isDark ? GardenColors.darkBackground : GardenColors.lightBackground,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: _selectedZone,
                                        hint: Text('Zona', style: TextStyle(color: subtextColor, fontWeight: FontWeight.w600)),
                                        isExpanded: true,
                                        icon: const Icon(Icons.location_on_rounded, color: GardenColors.primary),
                                        dropdownColor: surface,
                                        style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14),
                                        items: _zoneLabels.entries.map((e) {
                                          return DropdownMenuItem(value: e.key, child: Text(e.value));
                                        }).toList(),
                                        onChanged: (val) => setState(() => _selectedZone = val),
                                      ),
                                    ),
                                  ),

                                  // 3. Mascota
                                  Container(
                                    width: 140,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isDark ? GardenColors.darkBackground : GardenColors.lightBackground,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: _selectedPetType,
                                        hint: Text('Mascota', style: TextStyle(color: subtextColor, fontWeight: FontWeight.w600)),
                                        isExpanded: true,
                                        icon: const Icon(Icons.pets, color: GardenColors.primary, size: 20),
                                        dropdownColor: surface,
                                        style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14),
                                        items: ['Perro', 'Gato'].map((e) {
                                          return DropdownMenuItem(value: e, child: Text(e));
                                        }).toList(),
                                        onChanged: (val) => setState(() => _selectedPetType = val),
                                      ),
                                    ),
                                  ),

                                  // 4. Tamaño
                                  Container(
                                    width: 160,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isDark ? GardenColors.darkBackground : GardenColors.lightBackground,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: _selectedSize,
                                        hint: Text('Tamaño', style: TextStyle(color: subtextColor, fontWeight: FontWeight.w600)),
                                        isExpanded: true,
                                        icon: const Icon(Icons.straighten, color: GardenColors.primary, size: 20),
                                        dropdownColor: surface,
                                        style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14),
                                        items: ['PEQUEÑO', 'MEDIANO', 'GRANDE', 'GIGANTE'].map((e) {
                                          return DropdownMenuItem(value: e, child: Text(
                                            e[0] + e.substring(1).toLowerCase()
                                          ));
                                        }).toList(),
                                        onChanged: (val) => setState(() => _selectedSize = val),
                                      ),
                                    ),
                                  ),
                                  
                                  // 5. Botón de Búsqueda
                                  SizedBox(
                                    width: 140,
                                    height: 52,
                                    child: GardenButton(
                                      label: 'Buscar',
                                      icon: Icons.search_rounded,
                                      onPressed: _onSearch,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              
              // SECCIÓN DE INSPIRACIÓN O EXTRAS (Ej. "¿Por qué elegirnos?")
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 80.0),
                  child: Column(
                    children: [
                      Text('¿Por qué GARDEN?', style: TextStyle(color: textColor, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1)),
                      const SizedBox(height: 48),
                      // Grid para mostrar los features
                      LayoutBuilder(
                        builder: (context, constraints) {
                          bool isSmall = constraints.maxWidth < 600;
                          return Wrap(
                            spacing: 32,
                            runSpacing: 48,
                            alignment: WrapAlignment.center,
                            children: [
                              _buildFeatureColumn(
                                isSmall: isSmall,
                                icon: Icons.shield_rounded,
                                title: 'Máxima Seguridad',
                                desc: 'Verificación fotométrica e IA para cuidar de tu ser querido.',
                                textColor: textColor,
                                subtextColor: subtextColor,
                                color: GardenColors.primary,
                              ),
                              _buildFeatureColumn(
                                isSmall: isSmall,
                                icon: Icons.gavel_rounded,
                                title: 'Contratos Inteligentes',
                                desc: 'Escrow en Polygon. El pago del servicio está 100% asegurado ante disputas.',
                                textColor: textColor,
                                subtextColor: subtextColor,
                                color: GardenColors.polygon,
                              ),
                              _buildFeatureColumn(
                                isSmall: isSmall,
                                icon: Icons.medical_services_rounded,
                                title: 'Soporte Vital',
                                desc: 'Nuestra red cubre emergencias de tus consentidos.',
                                textColor: textColor,
                                subtextColor: subtextColor,
                                color: GardenColors.success,
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildServiceToggle(Color textColor, Color subtextColor) {
    return Container(
      decoration: BoxDecoration(
        color: themeNotifier.isDark ? GardenColors.darkBackground : GardenColors.lightBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: themeNotifier.isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedService = 'paseo'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _selectedService == 'paseo' ? GardenColors.primary.withOpacity(0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Center(
                  child: Text(
                    'Paseo 🦮',
                    style: TextStyle(
                      color: _selectedService == 'paseo' ? GardenColors.primary : subtextColor,
                      fontWeight: _selectedService == 'paseo' ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(width: 1, height: 24, color: themeNotifier.isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedService = 'hospedaje'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _selectedService == 'hospedaje' ? GardenColors.primary.withOpacity(0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Center(
                  child: Text(
                    'Hospedaje 🏠',
                    style: TextStyle(
                      color: _selectedService == 'hospedaje' ? GardenColors.primary : subtextColor,
                      fontWeight: _selectedService == 'hospedaje' ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureColumn({
    required bool isSmall,
    required IconData icon,
    required String title,
    required String desc,
    required Color textColor,
    required Color subtextColor,
    required Color color,
  }) {
    return SizedBox(
      width: isSmall ? double.infinity : 280,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 40),
          ),
          const SizedBox(height: 24),
          Text(title, style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(
            desc,
            textAlign: TextAlign.center,
            style: TextStyle(color: subtextColor, fontSize: 15, height: 1.5),
          ),
        ],
      ),
    );
  }
}
