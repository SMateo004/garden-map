import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';
import '../../widgets/garden_empty_state.dart';
import '../../widgets/pet_profile_sheet.dart';
import '../../services/auth_state.dart';
import '../../widgets/garden_loading_indicator.dart';

/// Pantalla de solo lectura para que un cuidador vea las mascotas que ha
/// cuidado (o va a cuidar). No incluye alta/edición/eliminación — el
/// cuidador no es dueño de la mascota.
class CaregiverPetsScreen extends StatefulWidget {
  const CaregiverPetsScreen({super.key});
  @override
  State<CaregiverPetsScreen> createState() => _CaregiverPetsScreenState();
}

class _CaregiverPetsScreenState extends State<CaregiverPetsScreen> {
  List<Map<String, dynamic>> _pets = [];
  bool _isLoading = true;
  bool _hasError = false;
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
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/caregiver/pets'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() => _pets = (data['data'] as List).cast<Map<String, dynamic>>());
      } else {
        setState(() => _hasError = true);
      }
    } catch (_) {
      setState(() => _hasError = true);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _openPetDetail(Map<String, dynamic> pet) {
    showPetProfileSheet(
      context: context,
      petId: pet['id'] as String,
      token: _token,
      petName: pet['name'] as String? ?? 'Mascota',
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
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 20),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: GardenColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(GardenRadius.sm),
                  ),
                  child: const Icon(Icons.pets_rounded, color: GardenColors.primary, size: 18),
                ),
                const SizedBox(width: 10),
                Text('Mascotas', style: GardenText.h4.copyWith(color: textColor)),
              ],
            ),
            centerTitle: true,
          ),
          body: _isLoading
              ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
              : _hasError
                  ? _buildErrorState(textColor, subtextColor)
                  : _pets.isEmpty
                      ? _buildEmpty(textColor, subtextColor)
                      : _buildList(isDark, textColor, subtextColor),
        );
      },
    );
  }

  Widget _buildList(bool isDark, Color textColor, Color subtextColor) {
    final upcoming = _pets.where((p) => p['upcoming'] == true).toList();
    final past = _pets.where((p) => p['upcoming'] != true).toList();

    return RefreshIndicator(
      color: GardenColors.primary,
      onRefresh: _load,
      child: LayoutBuilder(builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? 860 : double.infinity),
            child: ListView(
              padding: EdgeInsets.fromLTRB(isWide ? 40 : 16, 12, isWide ? 40 : 16, 100),
              children: [
                if (upcoming.isNotEmpty) ...[
                  _sectionHeader('Próximas', textColor),
                  const SizedBox(height: 8),
                  ...upcoming.map((pet) => _PetCard(
                        pet: pet,
                        isDark: isDark,
                        textColor: textColor,
                        subtextColor: subtextColor,
                        sizeLabels: _sizeLabels,
                        onTap: () => _openPetDetail(pet),
                      )),
                  const SizedBox(height: 20),
                ],
                if (past.isNotEmpty) ...[
                  _sectionHeader('Ya cuidadas', textColor),
                  const SizedBox(height: 8),
                  ...past.map((pet) => _PetCard(
                        pet: pet,
                        isDark: isDark,
                        textColor: textColor,
                        subtextColor: subtextColor,
                        sizeLabels: _sizeLabels,
                        onTap: () => _openPetDetail(pet),
                      )),
                ],
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _sectionHeader(String label, Color textColor) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(label, style: GardenText.h4.copyWith(color: textColor, fontSize: 15)),
  );

  Widget _buildEmpty(Color textColor, Color subtextColor) {
    return const GardenEmptyState(
      type: GardenEmptyType.pets,
      title: 'Aún no has cuidado mascotas',
      subtitle: 'Cuando aceptes o completes una reserva, sus mascotas aparecerán aquí.',
    );
  }

  Widget _buildErrorState(Color textColor, Color subtextColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: subtextColor, size: 40),
            const SizedBox(height: 12),
            Text('No se pudo cargar la información',
                style: TextStyle(color: textColor, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextButton(onPressed: _load, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

// ── PET CARD (solo lectura) ───────────────────────────────────────────────────

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
    final size = pet['size'] as String?;
    final specialNeeds = pet['specialNeeds'] as String?;
    final animalType = pet['animalType'] as String?;
    final isAggressive = pet['isAggressive'] as bool? ?? false;

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
            Container(
              width: 68, height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [GardenColors.lime, GardenColors.lime.withValues(alpha: 0.4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: ClipOval(
                child: photoUrl != null && photoUrl.isNotEmpty
                    ? Image.network(fixImageUrl(photoUrl),
                        width: 68, height: 68, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _iconFallback())
                    : _iconFallback(),
              ),
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
                if (animalType == 'DOGS') _pill('🐕 Perro', GardenColors.info),
                if (animalType == 'CATS') _pill('🐈 Gato', GardenColors.accent),
                if (size != null && sizeLabels.containsKey(size))
                  _pill(sizeLabels[size]!, GardenColors.primaryLight),
                if (isAggressive) _pill('⚡ Agresiva', GardenColors.error),
                if (specialNeeds != null && specialNeeds.isNotEmpty)
                  _pill('⚠ Especial', GardenColors.warning),
              ]),
            ])),
            Icon(Icons.arrow_forward_ios_rounded, color: subtextColor, size: 14),
          ]),
        ),
      ),
    );
  }

  Widget _iconFallback() => const Center(
    child: Icon(Icons.pets_rounded, color: GardenColors.primary, size: 28));

  Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}
