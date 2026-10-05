import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:http/http.dart' as http;
import '../../design/brote.dart';
import '../../design/garden_icons.dart';
import '../../design/garden_pet_avatar.dart';
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

  static const _sizeLabels = {'SMALL': 'Pequeño', 'MEDIUM': 'Mediano', 'LARGE': 'Grande', 'GIANT': 'Gigante'};

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
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: GardenColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(GardenRadius.sm),
                  ),
                  child: const GardenIcon(GIcon.mascotas, state: GIconState.active, size: GIconSize.md),
                ),
                const SizedBox(width: 10),
                Text('Mis mascotas', style: GardenText.h4.copyWith(color: textColor)),
              ],
            ),
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
                    child: const Center(
                        child: GardenIcon(GIcon.agregar, color: Colors.white, semanticLabel: 'Agregar mascota')),
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
                            child: ListView.builder(
                              padding: EdgeInsets.fromLTRB(isWide ? 40 : 16, 12, isWide ? 40 : 16, 100),
                              itemCount: _pets.length,
                              itemBuilder: (ctx, i) {
                          final pet = _pets[i];
                          return Dismissible(
                            key: Key(pet['id'] as String),
                            direction: DismissDirection.endToStart,
                            confirmDismiss: (_) async {
                              await _deletePet(pet['id'] as String, pet['name'] as String? ?? 'Mascota');
                              return false; // We handle reload ourselves
                            },
                            background: Container(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              decoration: BoxDecoration(
                                color: GardenColors.error.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const GardenIcon(GIcon.eliminar,
                                  color: GardenColors.error, size: GIconSize.xl),
                            ),
                            child: _PetCard(
                              pet: pet,
                              isDark: isDark,
                              textColor: textColor,
                              subtextColor: subtextColor,
                              sizeLabels: _sizeLabels,
                              onTap: () => _showPetForm(pet: pet),
                            ),
                          );
                        },
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

// ── PET CARD ──────────────────────────────────────────────────────────────────

class _PetCard extends StatelessWidget {
  final Map<String, dynamic> pet;
  final bool isDark;
  final Color textColor;
  final Color subtextColor;
  final Map<String, String> sizeLabels;
  final VoidCallback onTap;

  const _PetCard({
    required this.pet,
    required this.isDark,
    required this.textColor,
    required this.subtextColor,
    required this.sizeLabels,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final photoUrl = pet['photoUrl'] as String?;
    final name = pet['name'] as String? ?? 'Sin nombre';
    final breed = pet['breed'] as String?;
    final age = pet['age'];
    final size = pet['size'] as String?;
    final specialNeeds = pet['specialNeeds'] as String?;
    final animalType = pet['animalType'] as String?;
    final isAggressive = pet['isAggressive'] as bool? ?? false;
    final gender = pet['gender'] as String?;
    final weight = pet['weight'];
    final sterilized = pet['sterilized'] as bool?;
    final extraPhotos = (pet['extraPhotos'] as List?)?.cast<String>() ?? [];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(GardenRadius.xl),
          border: Border.all(color: borderColor),
          boxShadow: GardenShadows.card,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            // Photo
            Stack(
              children: [
                GardenPetAvatar(
                  name: name,
                  imageUrl: photoUrl,
                  species: animalType,
                  size: 68,
                  heroTag: 'pet-${pet['id']}',
                ),
                if (sterilized == true)
                  Positioned(
                    bottom: 0, right: 0,
                    child: Container(
                      width: 20, height: 20,
                      decoration: BoxDecoration(
                        color: GardenColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: surface, width: 1.5),
                      ),
                      child: const Center(
                          child: GardenIcon(GIcon.enviado, color: Colors.white, size: GIconSize.xs,
                              semanticLabel: 'Esterilizado')),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: GardenText.h4.copyWith(color: textColor, fontSize: 16)),
              if (breed != null && breed.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(breed, style: GardenText.bodyMedium.copyWith(color: subtextColor)),
              ],
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: [
                if (animalType == 'DOGS') _pill('Perro', GardenColors.primary, GIcon.perro),
                if (animalType == 'CATS') _pill('Gato', GardenColors.primary, GIcon.gato),
                if (animalType == null || size == null)
                  _pill('Completa especie y tamaño', GardenColors.warning, GIcon.advertencia),
                if (age != null)
                  _pill(age == 0 ? 'Menos de 1 año' : (age == 1 ? '1 año' : '$age años'), GardenColors.primary),
                if (size != null && sizeLabels.containsKey(size))
                  _pill(sizeLabels[size]!, GardenColors.primary, GIcon.huella),
                if (isAggressive) _pill('Agresiva', GardenColors.error, GIcon.conflicto),
                if (gender == 'MALE') _pill('Macho', GardenColors.textSecondary),
                if (gender == 'FEMALE') _pill('Hembra', GardenColors.textSecondary),
                if (weight != null) _pill('${weight.toString().replaceAll('.', ',')} kg', GardenColors.textSecondary),
                if (specialNeeds != null && specialNeeds.isNotEmpty)
                  _pill('Necesidades especiales', GardenColors.warning, GIcon.salud),
                if (extraPhotos.isNotEmpty) _pill('${extraPhotos.length}', GardenColors.primary, GIcon.galeria),
              ]),
            ])),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: GardenColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(GardenRadius.sm),
              ),
              child: const GardenIcon(GIcon.editar, color: GardenColors.primary, size: GIconSize.sm,
                  semanticLabel: 'Editar'),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _pill(String label, Color color, [GIcon? icon]) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[
        GardenIcon(icon, color: color, size: GIconSize.xs, state: GIconState.active),
        const SizedBox(width: 3),
      ],
      Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    ]),
  );
}
