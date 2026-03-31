import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';

class MyPetsScreen extends StatefulWidget {
  const MyPetsScreen({super.key});
  @override
  State<MyPetsScreen> createState() => _MyPetsScreenState();
}

class _MyPetsScreenState extends State<MyPetsScreen> {
  List<Map<String, dynamic>> _pets = [];
  bool _isLoading = true;
  String _token = '';

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api');

  static const _sizeLabels = {'SMALL': 'Pequeño', 'MEDIUM': 'Mediano', 'LARGE': 'Grande', 'GIANT': 'Gigante'};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('access_token') ?? '';
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
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/client/pets/$petId'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (jsonDecode(res.body)['success'] == true) {
        await _load();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$petName eliminado'), backgroundColor: GardenColors.success));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al eliminar'), backgroundColor: GardenColors.error));
    }
  }

  void _showPetForm({Map<String, dynamic>? pet}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PetFormSheet(
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
            title: const Text('Mis Mascotas'),
            backgroundColor: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
            foregroundColor: textColor,
            elevation: 0,
          ),
          floatingActionButton: FloatingActionButton(
            heroTag: 'myPetsFAB',
            backgroundColor: GardenColors.primary,
            onPressed: () => _showPetForm(),
            child: const Icon(Icons.add, color: Colors.white),
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
              : _pets.isEmpty
                  ? _buildEmpty(textColor, subtextColor)
                  : RefreshIndicator(
                      color: GardenColors.primary,
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
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
                              child: const Icon(Icons.delete_outline_rounded,
                                color: GardenColors.error, size: 28),
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
      },
    );
  }

  Widget _buildEmpty(Color textColor, Color subtextColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.pets_rounded, size: 80,
            color: GardenColors.primary.withValues(alpha: 0.35)),
          const SizedBox(height: 20),
          Text('Aún no tienes mascotas',
            style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Agrega a tus peludos y gestiona su información',
            style: TextStyle(color: subtextColor, fontSize: 13),
            textAlign: TextAlign.center),
          const SizedBox(height: 28),
          GardenButton(
            label: 'Agregar mascota',
            onPressed: () => _showPetForm(),
          ),
        ]),
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
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            // Photo
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: GardenColors.primary.withValues(alpha: 0.3), width: 1.5),
                color: GardenColors.primary.withValues(alpha: 0.08),
              ),
              child: ClipOval(
                child: photoUrl != null && photoUrl.isNotEmpty
                    ? Image.network(fixImageUrl(photoUrl),
                        width: 64, height: 64, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _iconFallback())
                    : _iconFallback(),
              ),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
              if (breed != null && breed.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(breed, style: TextStyle(color: subtextColor, fontSize: 13)),
              ],
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                if (age != null)
                  _pill('$age años', GardenColors.primary),
                if (size != null && sizeLabels.containsKey(size))
                  _pill(sizeLabels[size]!, GardenColors.accent),
                if (gender == 'MALE') _pill('♂ Macho', GardenColors.secondary),
                if (gender == 'FEMALE') _pill('♀ Hembra', GardenColors.accent),
                if (weight != null) _pill('${weight}kg', GardenColors.primary),
                if (sterilized == true) _pill('Esterilizado', GardenColors.success),
                if (specialNeeds != null && specialNeeds.isNotEmpty)
                  _pill('Necesidades especiales', GardenColors.warning),
                if (extraPhotos.isNotEmpty) _pill('${extraPhotos.length} fotos', GardenColors.primary),
              ]),
            ])),
            Icon(Icons.edit_outlined, color: subtextColor, size: 18),
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

// ── PET FORM SHEET ────────────────────────────────────────────────────────────

class _PetFormSheet extends StatefulWidget {
  final String token;
  final String baseUrl;
  final Map<String, dynamic>? existing;
  final VoidCallback onSaved;

  const _PetFormSheet({
    required this.token,
    required this.baseUrl,
    required this.onSaved,
    this.existing,
  });

  @override
  State<_PetFormSheet> createState() => _PetFormSheetState();
}

class _PetFormSheetState extends State<_PetFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _breedCtrl;
  late TextEditingController _ageCtrl;
  late TextEditingController _weightCtrl;
  late TextEditingController _colorCtrl;
  late TextEditingController _microchipCtrl;
  late TextEditingController _specialCtrl;
  String? _size;
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

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _nameCtrl = TextEditingController(text: p?['name'] as String? ?? '');
    _breedCtrl = TextEditingController(text: p?['breed'] as String? ?? '');
    _ageCtrl = TextEditingController(text: p?['age']?.toString() ?? '');
    _weightCtrl = TextEditingController(text: p?['weight']?.toString() ?? '');
    _colorCtrl = TextEditingController(text: p?['color'] as String? ?? '');
    _microchipCtrl = TextEditingController(text: p?['microchipNumber'] as String? ?? '');
    _specialCtrl = TextEditingController(text: p?['specialNeeds'] as String? ?? '');
    _size = p?['size'] as String?;
    _gender = p?['gender'] as String?;
    _sterilized = p?['sterilized'] as bool?;
    _photoUrl = p?['photoUrl'] as String?;
    _extraPhotos = (p?['extraPhotos'] as List?)?.cast<String>() ?? [];
    _vaccinePhotos = (p?['vaccinePhotos'] as List?)?.cast<String>() ?? [];
    _documents = (p?['documents'] as List?)?.cast<String>() ?? [];
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

  Future<String?> _uploadFile(List<int> bytes, String fileName) async {
    final uri = Uri.parse('${widget.baseUrl}/upload/pet-photo');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer ${widget.token}';
    request.files.add(http.MultipartFile.fromBytes(
      'photo', bytes, filename: fileName,
      contentType: MediaType('image', 'jpeg'),
    ));
    final res = await http.Response.fromStream(await request.send());
    final data = jsonDecode(res.body);
    if (res.statusCode == 200 && data['success'] == true) {
      return data['data']['url'] as String;
    }
    throw Exception(data['message'] ?? 'Error al subir archivo');
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _uploadingPhoto = true);
    try {
      final url = await _uploadFile(
        await picked.readAsBytes(),
        picked.name.isEmpty ? 'pet_${DateTime.now().millisecondsSinceEpoch}.jpg' : picked.name,
      );
      if (url != null) setState(() => _photoUrl = url);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: GardenColors.error));
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _pickExtraPhoto() async {
    if (_extraPhotos.length >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Máximo 4 fotos adicionales'), backgroundColor: GardenColors.warning));
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    setState(() => _uploadingExtra = true);
    try {
      final url = await _uploadFile(
        await picked.readAsBytes(),
        picked.name.isEmpty ? 'extra_${DateTime.now().millisecondsSinceEpoch}.jpg' : picked.name,
      );
      if (url != null) setState(() => _extraPhotos = [..._extraPhotos, url]);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: GardenColors.error));
    } finally {
      if (mounted) setState(() => _uploadingExtra = false);
    }
  }

  Future<void> _pickVaccinePhoto() async {
    if (_vaccinePhotos.length >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Máximo 4 fotos de vacunas'), backgroundColor: GardenColors.warning));
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    setState(() => _uploadingVaccine = true);
    try {
      final url = await _uploadFile(
        await picked.readAsBytes(),
        picked.name.isEmpty ? 'vaccine_${DateTime.now().millisecondsSinceEpoch}.jpg' : picked.name,
      );
      if (url != null) setState(() => _vaccinePhotos = [..._vaccinePhotos, url]);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: GardenColors.error));
    } finally {
      if (mounted) setState(() => _uploadingVaccine = false);
    }
  }

  Future<void> _pickDocument() async {
    if (_documents.length >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Máximo 4 documentos'), backgroundColor: GardenColors.warning));
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;
    setState(() => _uploadingDocument = true);
    try {
      final url = await _uploadFile(
        await picked.readAsBytes(),
        picked.name.isEmpty ? 'doc_${DateTime.now().millisecondsSinceEpoch}.jpg' : picked.name,
      );
      if (url != null) setState(() => _documents = [..._documents, url]);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: GardenColors.error));
    } finally {
      if (mounted) setState(() => _uploadingDocument = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
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
      if (_gender != null) body['gender'] = _gender;
      if (_sterilized != null) body['sterilized'] = _sterilized;
      if (_specialCtrl.text.trim().isNotEmpty) body['specialNeeds'] = _specialCtrl.text.trim();
      if (_photoUrl != null) body['photoUrl'] = _photoUrl;
      body['extraPhotos'] = _extraPhotos;
      body['vaccinePhotos'] = _vaccinePhotos;
      body['documents'] = _documents;

      http.Response res;
      if (_isEditing) {
        res = await http.patch(
          Uri.parse('${widget.baseUrl}/client/pets/${widget.existing!['id']}'),
          headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        );
      } else {
        res = await http.post(
          Uri.parse('${widget.baseUrl}/client/pets'),
          headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        );
      }
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (data['success'] == true) {
        widget.onSaved();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isEditing ? '✅ Mascota actualizada' : '✅ Mascota agregada'),
          backgroundColor: GardenColors.success));
      } else {
        throw Exception(data['error']?['message'] ?? 'Error al guardar');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: GardenColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    InputDecoration fieldDeco(String label, {IconData? icon}) => InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: subtextColor, fontSize: 13),
      filled: true, fillColor: surfaceEl,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      prefixIcon: icon != null ? Icon(icon, color: GardenColors.primary, size: 18) : null,
    );

    Widget sectionHeader(String emoji, String title) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: borderColor, thickness: 1)),
      ]),
    );

    Widget photoGrid(List<String> photos, bool uploading, VoidCallback onAdd, void Function(int) onRemove) {
      return Wrap(
        spacing: 8, runSpacing: 8,
        children: [
          ...photos.asMap().entries.map((e) => Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(fixImageUrl(e.value),
                  width: 72, height: 72, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 72, height: 72,
                    color: GardenColors.primary.withValues(alpha: 0.1),
                    child: const Icon(Icons.broken_image_outlined, color: GardenColors.primary, size: 24),
                  )),
              ),
              Positioned(
                top: 2, right: 2,
                child: GestureDetector(
                  onTap: () => onRemove(e.key),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(color: GardenColors.error, shape: BoxShape.circle),
                    child: const Icon(Icons.close, color: Colors.white, size: 10),
                  ),
                ),
              ),
            ],
          )),
          GestureDetector(
            onTap: uploading ? null : onAdd,
            child: Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: GardenColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: GardenColors.primary.withValues(alpha: 0.3), style: BorderStyle.solid),
              ),
              child: uploading
                  ? const Padding(padding: EdgeInsets.all(22),
                      child: CircularProgressIndicator(color: GardenColors.primary, strokeWidth: 2))
                  : const Icon(Icons.add_photo_alternate_outlined, color: GardenColors.primary, size: 24),
            ),
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Handle
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Center(child: Text(_isEditing ? 'Editar Mascota' : 'Nueva Mascota',
              style: TextStyle(color: textColor, fontSize: 19, fontWeight: FontWeight.w800))),
            const SizedBox(height: 20),

            // ── Foto principal ──────────────────────────────────────────
            Center(
              child: Column(children: [
                GestureDetector(
                  onTap: _uploadingPhoto ? null : _pickPhoto,
                  child: Container(
                    width: 90, height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: GardenColors.primary.withValues(alpha: 0.4), width: 2),
                      color: surfaceEl,
                    ),
                    child: _uploadingPhoto
                        ? const Padding(padding: EdgeInsets.all(28),
                            child: CircularProgressIndicator(color: GardenColors.primary, strokeWidth: 2))
                        : _photoUrl != null && _photoUrl!.isNotEmpty
                            ? ClipOval(child: Image.network(fixImageUrl(_photoUrl!),
                                width: 90, height: 90, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.pets_rounded,
                                  color: GardenColors.primary, size: 36)))
                            : const Icon(Icons.add_a_photo_outlined, color: GardenColors.primary, size: 36),
                  ),
                ),
                const SizedBox(height: 4),
                Text('Foto de perfil', style: TextStyle(color: subtextColor, fontSize: 11)),
              ]),
            ),
            const SizedBox(height: 20),

            // ── Información básica ──────────────────────────────────────
            sectionHeader('🐾', 'Información básica'),
            TextFormField(
              controller: _nameCtrl,
              style: TextStyle(color: textColor),
              decoration: fieldDeco('Nombre *', icon: Icons.badge_outlined),
              validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(
                controller: _breedCtrl,
                style: TextStyle(color: textColor),
                decoration: fieldDeco('Raza', icon: Icons.category_outlined),
              )),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(
                controller: _ageCtrl,
                style: TextStyle(color: textColor),
                keyboardType: TextInputType.number,
                decoration: fieldDeco('Edad (años)', icon: Icons.cake_outlined),
              )),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                value: _size,
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
              Expanded(child: TextFormField(
                controller: _weightCtrl,
                style: TextStyle(color: textColor),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: fieldDeco('Peso (kg)', icon: Icons.monitor_weight_outlined),
              )),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: _colorCtrl,
              style: TextStyle(color: textColor),
              decoration: fieldDeco('Color / pelaje', icon: Icons.palette_outlined),
            ),

            // ── Salud ───────────────────────────────────────────────────
            sectionHeader('💉', 'Salud e identificación'),
            Text('Género', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _GenderChip(
                value: 'MALE', label: '♂ Macho',
                selected: _gender == 'MALE',
                isDark: isDark, borderColor: borderColor,
                onTap: () => setState(() => _gender = _gender == 'MALE' ? null : 'MALE'),
              )),
              const SizedBox(width: 10),
              Expanded(child: _GenderChip(
                value: 'FEMALE', label: '♀ Hembra',
                selected: _gender == 'FEMALE',
                isDark: isDark, borderColor: borderColor,
                onTap: () => setState(() => _gender = _gender == 'FEMALE' ? null : 'FEMALE'),
              )),
            ]),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () => setState(() => _sterilized = !(_sterilized ?? false)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: (_sterilized == true)
                      ? GardenColors.success.withValues(alpha: 0.08)
                      : surfaceEl,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (_sterilized == true)
                        ? GardenColors.success.withValues(alpha: 0.4)
                        : borderColor,
                  ),
                ),
                child: Row(children: [
                  Icon(
                    _sterilized == true ? Icons.check_circle_rounded : Icons.circle_outlined,
                    color: _sterilized == true ? GardenColors.success : subtextColor,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text('Esterilizado/a',
                    style: TextStyle(
                      color: _sterilized == true ? GardenColors.success : textColor,
                      fontWeight: FontWeight.w600, fontSize: 14)),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _microchipCtrl,
              style: TextStyle(color: textColor),
              decoration: fieldDeco('Número de microchip (opcional)', icon: Icons.memory_outlined),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _specialCtrl,
              style: TextStyle(color: textColor),
              maxLines: 2,
              decoration: fieldDeco('Necesidades especiales', icon: Icons.medical_services_outlined),
            ),

            // ── Fotos adicionales ──────────────────────────────────────
            sectionHeader('📷', 'Fotos adicionales'),
            Text('Para que el cuidador conozca mejor a tu mascota. Máx. 4 fotos.',
              style: TextStyle(color: subtextColor, fontSize: 12)),
            const SizedBox(height: 10),
            photoGrid(
              _extraPhotos, _uploadingExtra, _pickExtraPhoto,
              (i) => setState(() => _extraPhotos = [..._extraPhotos]..removeAt(i)),
            ),

            // ── Fotos de vacunas ───────────────────────────────────────
            sectionHeader('🔬', 'Fotos de vacunas (opcional)'),
            Text('Sube fotos del carnet de vacunación.',
              style: TextStyle(color: subtextColor, fontSize: 12)),
            const SizedBox(height: 10),
            photoGrid(
              _vaccinePhotos, _uploadingVaccine, _pickVaccinePhoto,
              (i) => setState(() => _vaccinePhotos = [..._vaccinePhotos]..removeAt(i)),
            ),

            // ── Documentos ────────────────────────────────────────────
            sectionHeader('📋', 'Documentos (opcional)'),
            Text('Pedigree, registros veterinarios u otros documentos relevantes.',
              style: TextStyle(color: subtextColor, fontSize: 12)),
            const SizedBox(height: 10),
            photoGrid(
              _documents, _uploadingDocument, _pickDocument,
              (i) => setState(() => _documents = [..._documents]..removeAt(i)),
            ),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: GardenButton(
                label: _saving ? 'Guardando...' : (_isEditing ? 'Guardar cambios' : 'Agregar mascota'),
                loading: _saving,
                onPressed: _submit,
              ),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }
}

class _GenderChip extends StatelessWidget {
  final String value;
  final String label;
  final bool selected;
  final bool isDark;
  final Color borderColor;
  final VoidCallback onTap;

  const _GenderChip({
    required this.value,
    required this.label,
    required this.selected,
    required this.isDark,
    required this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = value == 'MALE' ? GardenColors.secondary : GardenColors.accent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : borderColor, width: selected ? 1.5 : 1),
        ),
        child: Center(child: Text(label, style: TextStyle(
          color: selected ? color : (isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary),
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500, fontSize: 13))),
      ),
    );
  }
}
