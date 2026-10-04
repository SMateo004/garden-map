import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/garden_theme.dart';
import './garden_loading_indicator.dart';
import '../design/garden_icons.dart';

/// Muestra el perfil completo de una mascota en un bottom sheet.
/// Si se pasa [bookingId], se obtiene de GET /api/caregiver/bookings/:bookingId/pet.
/// Si se pasa [petId] (sin bookingId), se obtiene de GET /api/caregiver/pets/:petId
/// (sin restricción de estado de reserva — usado para el historial de mascotas
/// del cuidador).
Future<void> showPetProfileSheet({
  required BuildContext context,
  String? bookingId,
  String? petId,
  required String token,
  required String petName,
}) async {
  assert(bookingId != null || petId != null,
      'showPetProfileSheet requiere bookingId o petId');
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PetProfileSheet(
      bookingId: bookingId,
      petId: petId,
      token: token,
      petName: petName,
    ),
  );
}

class _PetProfileSheet extends StatefulWidget {
  final String? bookingId;
  final String? petId;
  final String token;
  final String petName;

  const _PetProfileSheet({
    this.bookingId,
    this.petId,
    required this.token,
    required this.petName,
  });

  @override
  State<_PetProfileSheet> createState() => _PetProfileSheetState();
}

class _PetProfileSheetState extends State<_PetProfileSheet> {
  static const String _baseUrl =
      String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  Map<String, dynamic>? _pet;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPet();
  }

  Future<void> _loadPet() async {
    try {
      final uri = widget.bookingId != null
          ? Uri.parse('$_baseUrl/caregiver/bookings/${widget.bookingId}/pet')
          : Uri.parse('$_baseUrl/caregiver/pets/${widget.petId}');
      final res = await http.get(
        uri,
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && body['success'] == true) {
        setState(() {
          _pet = body['data'] as Map<String, dynamic>;
          _loading = false;
        });
      } else {
        setState(() {
          _error = (body['error']?['message'] as String?) ?? 'Error al cargar perfil de mascota';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'No se pudo conectar al servidor';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subtextColor = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final chipBg = isDark ? const Color(0xFF2A2A3E) : const Color(0xFFF3F4F6);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: subtextColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  const GardenIcon(GIcon.huella, size: GIconSize.md, state: GIconState.active, color: GardenColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Perfil de ${widget.petName}',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: GardenIcon(GIcon.cerrar, size: GIconSize.md, color: subtextColor),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Body
            Expanded(
              child: _loading
                  ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error!, style: TextStyle(color: subtextColor), textAlign: TextAlign.center),
                          ),
                        )
                      : _buildContent(controller, isDark, textColor, subtextColor, chipBg),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    ScrollController controller,
    bool isDark,
    Color textColor,
    Color subtextColor,
    Color chipBg,
  ) {
    final pet = _pet!;
    final photoUrl = pet['photoUrl'] as String?;
    final extraPhotos = (pet['extraPhotos'] as List? ?? []).cast<String>();
    final vaccinePhotos = (pet['vaccinePhotos'] as List? ?? []).cast<String>();
    final documents = (pet['documents'] as List? ?? []).cast<String>();

    String sizeLabel(String? s) {
      switch (s) {
        case 'SMALL': return 'Pequeño';
        case 'MEDIUM': return 'Mediano';
        case 'LARGE': return 'Grande';
        case 'GIANT': return 'Gigante';
        default: return s ?? '—';
      }
    }

    String genderLabel(String? g) {
      switch (g) {
        case 'MALE': return 'Macho';
        case 'FEMALE': return 'Hembra';
        default: return g ?? '—';
      }
    }

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        // Foto principal
        if (photoUrl != null && photoUrl.isNotEmpty)
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                fixImageUrl(photoUrl),
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: GardenColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(child: GardenIcon(GIcon.huella, size: GIconSize.hero, state: GIconState.active, color: GardenColors.primary)),
                ),
              ),
            ),
          )
        else
          Center(
            child: Container(
              height: 120,
              width: 120,
              decoration: BoxDecoration(
                color: GardenColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(60),
              ),
              child: const Center(child: GardenIcon(GIcon.huella, size: GIconSize.hero, state: GIconState.active, color: GardenColors.primary)),
            ),
          ),

        const SizedBox(height: 20),

        // Nombre
        Center(
          child: Text(
            pet['name'] as String? ?? '—',
            style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ),
        if (pet['breed'] != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                pet['breed'] as String,
                style: TextStyle(color: subtextColor, fontSize: 14),
              ),
            ),
          ),

        const SizedBox(height: 20),

        // Info chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (pet['age'] != null)
              _infoChip(context, GIcon.cumpleanos, '${pet['age']} años', chipBg, textColor),
            if (pet['size'] != null)
              _infoChip(context, GIcon.medida, sizeLabel(pet['size'] as String?), chipBg, textColor),
            if (pet['gender'] != null)
              _infoChip(context, GIcon.sexo, genderLabel(pet['gender'] as String?), chipBg, textColor),
            if (pet['weight'] != null)
              _infoChip(context, GIcon.peso, '${pet['weight']} kg', chipBg, textColor),
            if (pet['color'] != null)
              _infoChip(context, GIcon.apariencia, pet['color'] as String, chipBg, textColor),
            if (pet['sterilized'] == true)
              _infoChip(context, GIcon.confirmado, 'Esterilizado/a', chipBg, GardenColors.success),
            if (pet['microchipNumber'] != null)
              _infoChip(context, GIcon.pagarQr, 'Chip: ${pet['microchipNumber']}', chipBg, textColor),
          ],
        ),

        // Necesidades especiales
        if (pet['specialNeeds'] != null && (pet['specialNeeds'] as String).isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionLabel('Necesidades especiales', subtextColor),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: GardenColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: GardenColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const GardenIcon(GIcon.advertencia, size: GIconSize.sm, color: GardenColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pet['specialNeeds'] as String,
                    style: TextStyle(color: textColor, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Notas
        if (pet['notes'] != null && (pet['notes'] as String).isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionLabel('Notas del dueño', subtextColor),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: GardenColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: GardenColors.primary.withValues(alpha: 0.15)),
            ),
            child: Text(
              pet['notes'] as String,
              style: TextStyle(color: textColor, fontSize: 13),
            ),
          ),
        ],

        // Fotos adicionales
        if (extraPhotos.isNotEmpty) ...[
          const SizedBox(height: 24),
          _sectionLabel('Fotos adicionales', subtextColor),
          const SizedBox(height: 10),
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: extraPhotos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  fixImageUrl(extraPhotos[i]),
                  width: 100,
                  height: 100,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 100,
                    height: 100,
                    color: GardenColors.primary.withValues(alpha: 0.08),
                    child: const GardenIcon(GIcon.sinImagen, size: GIconSize.lg, color: GardenColors.primary),
                  ),
                ),
              ),
            ),
          ),
        ],

        // Fotos de vacunas / documentos veterinarios
        if (vaccinePhotos.isNotEmpty) ...[
          const SizedBox(height: 24),
          _sectionLabel('Vacunas y documentos veterinarios', subtextColor),
          const SizedBox(height: 10),
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: vaccinePhotos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  children: [
                    Image.network(
                      fixImageUrl(vaccinePhotos[i]),
                      width: 110,
                      height: 110,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 110,
                        height: 110,
                        color: GardenColors.success.withValues(alpha: 0.08),
                        child: const GardenIcon(GIcon.vacuna, size: GIconSize.lg, color: GardenColors.success),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: GardenColors.success.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const GardenIcon(GIcon.vacuna, size: GIconSize.xs, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],

        // Documentos
        if (documents.isNotEmpty) ...[
          const SizedBox(height: 24),
          _sectionLabel('Documentos', subtextColor),
          const SizedBox(height: 8),
          ...documents.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: chipBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const GardenIcon(GIcon.documento, size: GIconSize.sm, color: GardenColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Documento ${e.key + 1}',
                    style: TextStyle(color: textColor, fontSize: 13),
                  ),
                ],
              ),
            ),
          )),
        ],

        const SizedBox(height: 16),
      ],
    );
  }

  Widget _infoChip(BuildContext context, GIcon icon, String label, Color bg, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GardenIcon(icon, size: GIconSize.xs, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label, Color color) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}
