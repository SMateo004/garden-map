import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:image_picker/image_picker.dart';
import '../../theme/garden_theme.dart';
import '../../services/caregiver_crm_service.dart';
import '../../utils/web_file_picker.dart';
import '../../widgets/garden_loading_indicator.dart';

/// Ficha completa de una mascota walk-in — mismos campos/agrupamiento que
/// el formulario de mascota real (my_pets_screen.dart _PetFormSheet), pero
/// como pantalla completa: en modo edición muestra debajo el historial de
/// visitas (WalkInVisit), que un bottom sheet no tiene espacio para mostrar
/// junto al resto del form.
class WalkInPetFormScreen extends StatefulWidget {
  final CaregiverCrmService service;
  final String clientId;
  final Map<String, dynamic>? existingPet;
  const WalkInPetFormScreen({super.key, required this.service, required this.clientId, this.existingPet});

  @override
  State<WalkInPetFormScreen> createState() => _WalkInPetFormScreenState();
}

class _WalkInPetFormScreenState extends State<WalkInPetFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _breedCtrl;
  late TextEditingController _ageCtrl;
  late TextEditingController _weightCtrl;
  late TextEditingController _colorCtrl;
  late TextEditingController _microchipCtrl;
  late TextEditingController _specialCtrl;
  String? _size;
  String? _animalType;
  bool _isAggressive = false;
  String? _gender;
  bool? _sterilized;
  String? _photoUrl;
  List<String> _extraPhotos = [];
  List<String> _vaccinePhotos = [];
  List<String> _documents = [];
  bool _uploadingPhoto = false;
  bool _uploadingExtra = false;
  bool _uploadingVaccine = false;
  bool _uploadingDocument = false;
  bool _saving = false;
  bool _loadingHistory = false;
  List<Map<String, dynamic>> _visits = [];

  bool get _isEditing => widget.existingPet != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existingPet;
    _nameCtrl = TextEditingController(text: p?['name'] as String? ?? '');
    _breedCtrl = TextEditingController(text: p?['breed'] as String? ?? '');
    _ageCtrl = TextEditingController(text: p?['age']?.toString() ?? '');
    _weightCtrl = TextEditingController(text: p?['weight']?.toString() ?? '');
    _colorCtrl = TextEditingController(text: p?['color'] as String? ?? '');
    _microchipCtrl = TextEditingController(text: p?['microchipNumber'] as String? ?? '');
    _specialCtrl = TextEditingController(text: p?['specialNeeds'] as String? ?? '');
    _size = p?['size'] as String?;
    _animalType = p?['animalType'] as String?;
    _isAggressive = p?['isAggressive'] as bool? ?? false;
    _gender = p?['gender'] as String?;
    _sterilized = p?['sterilized'] as bool?;
    _photoUrl = p?['photoUrl'] as String?;
    _extraPhotos = (p?['extraPhotos'] as List?)?.cast<String>() ?? [];
    _vaccinePhotos = (p?['vaccinePhotos'] as List?)?.cast<String>() ?? [];
    _documents = (p?['documents'] as List?)?.cast<String>() ?? [];
    if (_isEditing) _loadHistory();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _breedCtrl.dispose();
    _ageCtrl.dispose();
    _weightCtrl.dispose();
    _colorCtrl.dispose();
    _microchipCtrl.dispose();
    _specialCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final detail = await widget.service.getPet(widget.existingPet!['id'] as String);
      if (mounted) {
        setState(() => _visits = (detail['visits'] as List?)?.cast<Map<String, dynamic>>() ?? []);
      }
    } catch (_) {
      // Si falla la carga del historial, el resto del form sigue usable.
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<({Uint8List bytes, String name})?> _pickImageBytes({int quality = 85}) async {
    if (kIsWeb) {
      return pickImageFromWebInput();
    } else {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: quality);
      if (picked == null) return null;
      final bytes = await picked.readAsBytes();
      final name = picked.name.isEmpty ? 'walkin_pet_${DateTime.now().millisecondsSinceEpoch}.jpg' : picked.name;
      return (bytes: bytes, name: name);
    }
  }

  Future<void> _pickPhoto() async {
    final img = await _pickImageBytes(quality: 85);
    if (img == null) return;
    setState(() => _uploadingPhoto = true);
    try {
      final url = await widget.service.uploadPetPhoto(img.bytes, img.name);
      if (mounted) setState(() => _photoUrl = url);
    } catch (e) {
      if (mounted) GardenSnackBar.error(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _pickInto(List<String> Function() get, void Function(List<String>) set, void Function(bool) setUploading, int maxCount, String label, {int quality = 80}) async {
    if (get().length >= maxCount) {
      GardenSnackBar.warning(context, 'Máximo $maxCount $label');
      return;
    }
    final img = await _pickImageBytes(quality: quality);
    if (img == null) return;
    setState(() => setUploading(true));
    try {
      final url = await widget.service.uploadPetPhoto(img.bytes, img.name);
      if (mounted) setState(() => set([...get(), url]));
    } catch (e) {
      if (mounted) GardenSnackBar.error(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => setUploading(false));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    HapticFeedback.lightImpact();
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{'name': _nameCtrl.text.trim()};
      if (_breedCtrl.text.trim().isNotEmpty) body['breed'] = _breedCtrl.text.trim();
      final age = int.tryParse(_ageCtrl.text.trim());
      if (age != null) body['age'] = age;
      final weight = double.tryParse(_weightCtrl.text.trim());
      if (weight != null) body['weight'] = weight;
      if (_colorCtrl.text.trim().isNotEmpty) body['color'] = _colorCtrl.text.trim();
      if (_microchipCtrl.text.trim().isNotEmpty) body['microchipNumber'] = _microchipCtrl.text.trim();
      if (_size != null) body['size'] = _size;
      if (_animalType != null) body['animalType'] = _animalType;
      body['isAggressive'] = _isAggressive;
      if (_gender != null) body['gender'] = _gender;
      if (_sterilized != null) body['sterilized'] = _sterilized;
      if (_specialCtrl.text.trim().isNotEmpty) body['specialNeeds'] = _specialCtrl.text.trim();
      if (_photoUrl != null) body['photoUrl'] = _photoUrl;
      body['extraPhotos'] = _extraPhotos;
      body['vaccinePhotos'] = _vaccinePhotos;
      body['documents'] = _documents;

      if (_isEditing) {
        await widget.service.updatePet(widget.existingPet!['id'] as String, body);
      } else {
        await widget.service.createPet(widget.clientId, body);
      }
      if (!mounted) return;
      GardenSnackBar.success(context, _isEditing ? 'Mascota actualizada' : 'Mascota agregada');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        GardenSnackBar.error(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  String _serviceEmoji(String type) {
    switch (type) {
      case 'HOSPEDAJE':
        return '🏠';
      case 'GUARDERIA':
        return '🏡';
      default:
        return '🐕';
    }
  }

  String _fmtDate(String iso) {
    final d = DateTime.parse(iso).toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _duration(String startIso, String? endIso) {
    final start = DateTime.parse(startIso);
    final end = endIso != null ? DateTime.parse(endIso) : DateTime.now();
    final diff = end.difference(start);
    if (diff.inHours >= 24) return '${diff.inDays}d';
    if (diff.inHours >= 1) return '${diff.inHours}h ${diff.inMinutes % 60}m';
    return '${diff.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
        final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
        final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
        final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

        InputDecoration fieldDeco(String label, {IconData? icon}) => InputDecoration(
              labelText: label,
              labelStyle: TextStyle(color: subtextColor, fontSize: 13),
              filled: true,
              fillColor: surfaceEl,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              prefixIcon: icon != null ? Icon(icon, color: GardenColors.primary, size: 18) : null,
            );

        Widget sectionHeader(String emoji, String title) => Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 12),
              child: Row(children: [
                Text(emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Expanded(child: Divider(color: borderColor, thickness: 1)),
              ]),
            );

        Widget chip(String label, bool selected, VoidCallback onTap) => Expanded(
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: selected ? GardenColors.primary.withValues(alpha: 0.1) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: selected ? GardenColors.primary : borderColor),
                  ),
                  child: Center(child: Text(label, style: TextStyle(color: selected ? GardenColors.primary : textColor, fontWeight: FontWeight.w600, fontSize: 13))),
                ),
              ),
            );

        Widget toggle(String label, bool active, Color activeColor, VoidCallback onTap) => GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: active ? activeColor.withValues(alpha: 0.08) : surfaceEl,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: active ? activeColor.withValues(alpha: 0.4) : borderColor),
                ),
                child: Row(children: [
                  Icon(active ? Icons.check_circle_rounded : Icons.circle_outlined, color: active ? activeColor : subtextColor, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(label, style: TextStyle(color: active ? activeColor : textColor, fontWeight: FontWeight.w600, fontSize: 14))),
                ]),
              ),
            );

        Widget photoGrid(List<String> photos, bool uploading, VoidCallback onAdd, void Function(int) onRemove) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...photos.asMap().entries.map((e) => Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(fixImageUrl(e.value),
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                              width: 72,
                              height: 72,
                              color: GardenColors.primary.withValues(alpha: 0.1),
                              child: const Icon(Icons.broken_image_outlined, color: GardenColors.primary, size: 24))),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () => onRemove(e.key),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(color: GardenColors.error, shape: BoxShape.circle),
                          child: const Icon(Icons.close, color: Colors.white, size: 10),
                        ),
                      ),
                    ),
                  ])),
              GestureDetector(
                onTap: uploading ? null : onAdd,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: GardenColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: GardenColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: uploading
                      ? const Padding(padding: EdgeInsets.all(22), child: GardenLoadingIndicator(color: GardenColors.primary))
                      : const Icon(Icons.add_photo_alternate_outlined, color: GardenColors.primary, size: 24),
                ),
              ),
            ],
          );
        }

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            elevation: 0,
            iconTheme: IconThemeData(color: textColor),
            title: Text(_isEditing ? 'Editar mascota' : 'Nueva mascota', style: TextStyle(color: textColor, fontWeight: FontWeight.w800)),
          ),
          body: SafeArea(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  Center(
                    child: Column(children: [
                      GestureDetector(
                        onTap: _uploadingPhoto ? null : _pickPhoto,
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: GardenColors.primary.withValues(alpha: 0.4), width: 2),
                            color: surfaceEl,
                          ),
                          child: _uploadingPhoto
                              ? const Padding(padding: EdgeInsets.all(28), child: GardenLoadingIndicator(color: GardenColors.primary))
                              : _photoUrl != null && _photoUrl!.isNotEmpty
                                  ? ClipOval(
                                      child: Image.network(fixImageUrl(_photoUrl!),
                                          width: 90,
                                          height: 90,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const Icon(Icons.pets_rounded, color: GardenColors.primary, size: 36)))
                                  : const Icon(Icons.add_a_photo_outlined, color: GardenColors.primary, size: 36),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('Foto de perfil', style: TextStyle(color: subtextColor, fontSize: 11)),
                    ]),
                  ),
                  sectionHeader('🐾', 'Información básica'),
                  TextFormField(
                    controller: _nameCtrl,
                    style: TextStyle(color: textColor),
                    decoration: fieldDeco('Nombre *', icon: Icons.badge_outlined),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  Text('Tipo de mascota', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(children: [
                    chip('🐕 Perro', _animalType == 'DOGS', () => setState(() => _animalType = _animalType == 'DOGS' ? null : 'DOGS')),
                    const SizedBox(width: 10),
                    chip('🐈 Gato', _animalType == 'CATS', () => setState(() => _animalType = _animalType == 'CATS' ? null : 'CATS')),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: TextFormField(controller: _breedCtrl, style: TextStyle(color: textColor), decoration: fieldDeco('Raza', icon: Icons.category_outlined))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: TextFormField(
                      controller: _ageCtrl,
                      style: TextStyle(color: textColor),
                      keyboardType: TextInputType.number,
                      decoration: fieldDeco('Edad (años)', icon: Icons.cake_outlined),
                    )),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: DropdownButtonFormField<String>(
                      initialValue: _size,
                      decoration: fieldDeco('Tamaño'),
                      dropdownColor: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
                      style: TextStyle(color: textColor, fontSize: 14),
                      items: const [
                        DropdownMenuItem(value: 'SMALL', child: Text('Pequeño')),
                        DropdownMenuItem(value: 'MEDIUM', child: Text('Mediano')),
                        DropdownMenuItem(value: 'LARGE', child: Text('Grande')),
                        DropdownMenuItem(value: 'GIANT', child: Text('Gigante')),
                      ],
                      onChanged: (v) => setState(() => _size = v),
                    )),
                    const SizedBox(width: 12),
                    Expanded(
                        child: TextFormField(
                      controller: _weightCtrl,
                      style: TextStyle(color: textColor),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: fieldDeco('Peso (kg)', icon: Icons.monitor_weight_outlined),
                    )),
                  ]),
                  const SizedBox(height: 12),
                  TextFormField(controller: _colorCtrl, style: TextStyle(color: textColor), decoration: fieldDeco('Color / pelaje', icon: Icons.palette_outlined)),
                  sectionHeader('💉', 'Salud e identificación'),
                  Text('Género', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(children: [
                    chip('♂ Macho', _gender == 'MALE', () => setState(() => _gender = _gender == 'MALE' ? null : 'MALE')),
                    const SizedBox(width: 10),
                    chip('♀ Hembra', _gender == 'FEMALE', () => setState(() => _gender = _gender == 'FEMALE' ? null : 'FEMALE')),
                  ]),
                  const SizedBox(height: 14),
                  toggle('Esterilizado/a', _sterilized == true, GardenColors.success, () => setState(() => _sterilized = !(_sterilized ?? false))),
                  const SizedBox(height: 10),
                  toggle('Puede mostrar agresividad con extraños', _isAggressive, GardenColors.warning, () => setState(() => _isAggressive = !_isAggressive)),
                  const SizedBox(height: 12),
                  TextFormField(controller: _microchipCtrl, style: TextStyle(color: textColor), decoration: fieldDeco('Número de microchip (opcional)', icon: Icons.memory_outlined)),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _specialCtrl,
                    style: TextStyle(color: textColor),
                    maxLines: 2,
                    decoration: fieldDeco('Necesidades especiales / alergias (opcional)', icon: Icons.medical_services_outlined),
                  ),
                  sectionHeader('📷', 'Fotos adicionales'),
                  Text('Para conocer mejor a la mascota. Máx. 4 fotos.', style: TextStyle(color: subtextColor, fontSize: 12)),
                  const SizedBox(height: 10),
                  photoGrid(
                    _extraPhotos,
                    _uploadingExtra,
                    () => _pickInto(() => _extraPhotos, (v) => _extraPhotos = v, (b) => _uploadingExtra = b, 4, 'fotos adicionales'),
                    (i) => setState(() => _extraPhotos = [..._extraPhotos]..removeAt(i)),
                  ),
                  sectionHeader('🔬', 'Fotos de vacunas (opcional)'),
                  Text('Fotos del carnet de vacunación.', style: TextStyle(color: subtextColor, fontSize: 12)),
                  const SizedBox(height: 10),
                  photoGrid(
                    _vaccinePhotos,
                    _uploadingVaccine,
                    () => _pickInto(() => _vaccinePhotos, (v) => _vaccinePhotos = v, (b) => _uploadingVaccine = b, 4, 'fotos de vacunas'),
                    (i) => setState(() => _vaccinePhotos = [..._vaccinePhotos]..removeAt(i)),
                  ),
                  sectionHeader('📋', 'Documentos (opcional)'),
                  Text('Pedigree, registros veterinarios u otros documentos.', style: TextStyle(color: subtextColor, fontSize: 12)),
                  const SizedBox(height: 10),
                  photoGrid(
                    _documents,
                    _uploadingDocument,
                    () => _pickInto(() => _documents, (v) => _documents = v, (b) => _uploadingDocument = b, 4, 'documentos', quality: 90),
                    (i) => setState(() => _documents = [..._documents]..removeAt(i)),
                  ),
                  if (_isEditing) ...[
                    sectionHeader('🕓', 'Historial de visitas'),
                    if (_loadingHistory)
                      const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: GardenLoadingIndicator(color: GardenColors.primary)))
                    else if (_visits.isEmpty)
                      Text('Todavía no registró ninguna visita.', style: TextStyle(color: subtextColor, fontSize: 12.5))
                    else
                      for (final v in _visits)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: surfaceEl,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: borderColor),
                          ),
                          child: Row(children: [
                            Text(_serviceEmoji(v['serviceType'] as String), style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_fmtDate(v['checkedInAt'] as String), style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                                  Text(
                                    v['checkedOutAt'] == null ? 'En curso' : 'Duró ${_duration(v['checkedInAt'] as String, v['checkedOutAt'] as String?)}',
                                    style: TextStyle(color: v['checkedOutAt'] == null ? GardenColors.warning : subtextColor, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ]),
                        ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: GardenButton(
                      label: _saving ? 'Guardando...' : (_isEditing ? 'Guardar cambios' : 'Agregar mascota'),
                      loading: _saving,
                      onPressed: _submit,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
