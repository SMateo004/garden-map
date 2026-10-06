import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:http/http.dart' as http;
import '../../design/brote.dart';
import '../../design/garden_icons.dart';
import '../../design/garden_pets.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';
import '../../widgets/garden_loading_indicator.dart';
import 'pet_form_sheet.dart';

class MyPetsScreen extends StatefulWidget {
  const MyPetsScreen({super.key});
  @override
  State<MyPetsScreen> createState() => _MyPetsScreenState();
}

class _MyPetsScreenState extends State<MyPetsScreen> {
  List<Map<String, dynamic>> _pets = [];
  bool _isLoading = true;
  String _token = '';

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _token = AuthState.token;
    await _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/client/pets'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() => _pets = (data['data'] as List).cast<Map<String, dynamic>>());
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _deletePet(String petId, String petName) async {
    final isDark = themeNotifier.isDark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => GardenGlassDialog(
        title: Text('¿Eliminar a $petName?'),
        content: Text('Esta acción no se puede deshacer.',
          style: TextStyle(color: isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
              style: TextStyle(color: isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: GardenColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    HapticFeedback.mediumImpact();
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/client/pets/$petId'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        await _load();
        if (mounted) GardenSnackBar.success(context, 'Quitamos a $petName de tus mascotas');
      } else if (mounted) {
        GardenSnackBar.error(context, (data['error']?['message'] as String?) ?? 'No pudimos quitar a $petName');
      }
    } catch (_) {
      if (mounted) GardenSnackBar.error(context, 'Sin conexión. Intenta de nuevo.');
    }
  }

  void _showPetForm({Map<String, dynamic>? pet}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PetFormSheet(
        token: _token,
        baseUrl: _baseUrl,
        existing: pet,
        onSaved: _load,
      ),
    );
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
          appBar: AppBar(
            backgroundColor: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
            elevation: 0,
            title: Text('Mis mascotas', style: GardenText.h4.copyWith(color: textColor)),
            centerTitle: true,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GardenPressable(
                  pressedScale: 0.88,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _showPetForm();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      gradient: GardenGradients.primary,
                      borderRadius: BorderRadius.circular(GardenRadius.full),
                      boxShadow: GardenShadows.primary,
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      GardenIcon(GIcon.agregar, color: Colors.white, size: GIconSize.sm, semanticLabel: 'Agregar mascota'),
                      SizedBox(width: 4),
                      Text('Agregar', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),
              ),
            ],
          ),
          body: _isLoading
              ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
              : _pets.isEmpty
                  ? _buildEmpty(textColor, subtextColor)
                  : RefreshIndicator(
                      color: GardenColors.primary,
                      onRefresh: _load,
                      child: LayoutBuilder(builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 700;
                        return Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: isWide ? 860 : double.infinity),
                            // Una columna en celular, dos en pantallas anchas.
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.fromLTRB(isWide ? 40 : 16, 14, isWide ? 40 : 16, 40),
                              children: [
                                Wrap(
                                  spacing: 14,
                                  runSpacing: 14,
                                  children: [
                                    for (final pet in _pets)
                                      SizedBox(
                                        width: isWide ? ((constraints.maxWidth.clamp(0, 860) - 80 - 14) / 2).floorToDouble() : double.infinity,
                                        child: Dismissible(
                                          key: Key(pet['id'] as String),
                                          direction: DismissDirection.endToStart,
                                          confirmDismiss: (_) async {
                                            await _deletePet(pet['id'] as String, pet['name'] as String? ?? 'Mascota');
                                            return false; // la lista se recarga en _deletePet
                                          },
                                          background: Container(
                                            decoration: BoxDecoration(
                                              color: GardenColors.error.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(22),
                                            ),
                                            alignment: Alignment.centerRight,
                                            padding: const EdgeInsets.only(right: 20),
                                            child: const GardenIcon(GIcon.eliminar, color: GardenColors.error, size: GIconSize.xl),
                                          ),
                                          child: GardenPetCard(
                                            pet: pet,
                                            onTap: () => _showPetForm(pet: pet),
                                            // Quitar también desde un menú: deslizar no se descubre solo.
                                            onDelete: () => _deletePet(pet['id'] as String, pet['name'] as String? ?? 'Mascota'),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                GardenAddPetTile(onTap: () {
                                  HapticFeedback.selectionClick();
                                  _showPetForm();
                                }),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
        );
      },
    );
  }

  Widget _buildEmpty(Color textColor, Color subtextColor) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Brote(pose: BrotePose.hola, size: 120),
            const SizedBox(height: 16),
            Text('Todavía no conocemos a tu mascota',
                textAlign: TextAlign.center, style: GardenText.h4.copyWith(color: textColor)),
            const SizedBox(height: 8),
            Text(
              'Cuéntanos su nombre, cómo es y qué necesita. Así su cuidador llega preparado.',
              textAlign: TextAlign.center,
              style: GardenText.bodyMedium.copyWith(color: subtextColor),
            ),
            const SizedBox(height: 20),
            GardenButton(label: 'Presentar a mi mascota', onPressed: () => _showPetForm()),
          ],
        ),
      ),
    );
  }
}
