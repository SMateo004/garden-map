import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import '../../design/brote.dart';
import '../../design/garden_icons.dart';
import '../../theme/garden_motion.dart';
import '../../theme/garden_theme.dart';
import '../../utils/web_file_picker.dart';
import '../../widgets/garden_loading_indicator.dart';
import '../../utils/input_formatters.dart';

/// Presentar (o editar) una mascota en tres pasos cortos:
///   1. Quién es — foto, nombre y especie.
///   2. Cómo es — tamaño, edad, peso, sexo y raza.
///   3. Para cuidarla bien — salud, carácter, rutina y fotos (todo opcional).
///
/// Especie y tamaño son obligatorios: la reserva los compara con lo que acepta
/// cada cuidador. Con eso completo ya se puede guardar; el paso 3 se puede
/// dejar para después. Al editar, los tres pasos se recorren libremente y un
/// dato borrado se manda como null para que de verdad se borre.
class PetFormSheet extends StatefulWidget {
  final String token;
  final String baseUrl;
  final Map<String, dynamic>? existing;
  final VoidCallback onSaved;

  const PetFormSheet({
    super.key,
    required this.token,
    required this.baseUrl,
    required this.onSaved,
    this.existing,
  });

  /// Mismos rangos que ve el cuidador al elegir qué tamaños acepta.
  static const sizes = [
    ('SMALL', 'Pequeño', 'menos de 5 kg'),
    ('MEDIUM', 'Mediano', '5 a 20 kg'),
    ('LARGE', 'Grande', '20 a 40 kg'),
    ('GIANT', 'Gigante', 'más de 40 kg'),
  ];

  /// Tamaño que corresponde a un peso, con los rangos de [sizes].
  static String sizeForWeight(double kg) =>
      kg < 5 ? 'SMALL' : kg < 20 ? 'MEDIUM' : kg < 40 ? 'LARGE' : 'GIANT';

  /// Acepta "4,5" y "4.5" (en Bolivia se escribe con coma).
  static double? parseWeight(String raw) => parseDecimal(raw);

  static String? validateName(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return '¿Cómo se llama?';
    if (t.length < 2) return 'Escribe al menos 2 letras';
    if (t.length > 40) return 'Máximo 40 caracteres';
    if (!RegExp(r"[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]").hasMatch(t)) return 'El nombre necesita alguna letra';
    return null;
  }

  static String? validateWeight(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return null;
    final w = parseWeight(t);
    if (w == null) return 'Escribe solo el número, por ejemplo 4,5';
    if (w <= 0 || w > 120) return 'Revisa el peso: entre 0,1 y 120 kg';
    return null;
  }

  static String? validateMicrochip(String? v) {
    final t = v?.replaceAll(' ', '') ?? '';
    if (t.isEmpty) return null;
    if (!RegExp(r'^\d{9,15}$').hasMatch(t)) return 'El microchip tiene de 9 a 15 números';
    return null;
  }

  @override
  State<PetFormSheet> createState() => _PetFormSheetState();
}

class _PetFormSheetState extends State<PetFormSheet> {
  final _step1Key = GlobalKey<FormState>();
  final _step2Key = GlobalKey<FormState>();
  final _step3Key = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _breedCtrl;
  late final TextEditingController _weightCtrl;
  late final TextEditingController _colorCtrl;
  late final TextEditingController _microchipCtrl;
  late final TextEditingController _specialCtrl;
  late final TextEditingController _notesCtrl;

  int _step = 0;
  String? _animalType;
  String? _size;
  bool _sizeFromWeight = false;
  int? _age;
  String? _gender;
  bool? _sterilized;
  bool _isAggressive = false;
  String? _photoUrl;
  List<String> _extraPhotos = [];
  List<String> _vaccinePhotos = [];
  List<String> _documents = [];
  int _uploading = 0;
  bool _saving = false;
  bool _speciesMissing = false;
  bool _sizeMissing = false;
  String? _serverError;

  bool get _isEditing => widget.existing != null;
  String get _petName {
    final n = _nameCtrl.text.trim();
    return n.isEmpty ? 'tu mascota' : n;
  }

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    String txt(String k) => (p?[k] ?? '').toString();
    _nameCtrl = TextEditingController(text: txt('name'))..addListener(() => setState(() {}));
    _breedCtrl = TextEditingController(text: txt('breed'));
    _weightCtrl = TextEditingController(
        text: p?['weight'] == null ? '' : _num(p!['weight']).toString().replaceAll('.', ','));
    _colorCtrl = TextEditingController(text: txt('color'));
    _microchipCtrl = TextEditingController(text: txt('microchipNumber'));
    _specialCtrl = TextEditingController(text: txt('specialNeeds'));
    _notesCtrl = TextEditingController(text: txt('notes'));
    _animalType = p?['animalType'] as String?;
    _size = p?['size'] as String?;
    _age = (p?['age'] as num?)?.toInt();
    _gender = p?['gender'] as String?;
    _sterilized = p?['sterilized'] as bool?;
    _isAggressive = p?['isAggressive'] as bool? ?? false;
    _photoUrl = p?['photoUrl'] as String?;
    _extraPhotos = (p?['extraPhotos'] as List?)?.cast<String>() ?? [];
    _vaccinePhotos = (p?['vaccinePhotos'] as List?)?.cast<String>() ?? [];
    _documents = (p?['documents'] as List?)?.cast<String>() ?? [];
  }

  num _num(dynamic v) => v is num ? (v % 1 == 0 ? v.toInt() : v) : 0;

  @override
  void dispose() {
    for (final c in [_nameCtrl, _breedCtrl, _weightCtrl, _colorCtrl, _microchipCtrl, _specialCtrl, _notesCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Fotos ────────────────────────────────────────────────────────────────

  Future<({Uint8List bytes, String name})?> _pickImageBytes({int quality = 85}) async {
    if (kIsWeb) return pickImageFromWebInput();
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: quality);
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    final name = picked.name.isEmpty ? 'pet_${DateTime.now().millisecondsSinceEpoch}.jpg' : picked.name;
    return (bytes: bytes, name: name);
  }

  Future<String> _uploadFile(Uint8List bytes, String fileName) async {
    if (widget.token.isEmpty) throw Exception('No hay sesión activa. Vuelve a iniciar sesión.');
    final request = http.MultipartRequest('POST', Uri.parse('${widget.baseUrl}/upload/pet-photo'));
    request.headers['Authorization'] = 'Bearer ${widget.token}';
    request.files.add(http.MultipartFile.fromBytes('photo', bytes,
        filename: fileName, contentType: MediaType('image', 'jpeg')));
    final res = await http.Response.fromStream(await request.send());
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode == 200 && data['success'] == true) return data['data']['url'] as String;
    throw Exception((data['error'] as Map<String, dynamic>?)?['message'] ??
        data['message'] ??
        'No pudimos subir la foto (error ${res.statusCode})');
  }

  /// Sube una imagen y la entrega a [onDone]. Mientras sube, no se puede guardar.
  Future<void> _addImage(void Function(String url) onDone, {int quality = 85}) async {
    final img = await _pickImageBytes(quality: quality);
    if (img == null) return;
    setState(() => _uploading++);
    try {
      final url = await _uploadFile(img.bytes, img.name);
      if (mounted) setState(() => onDone(url));
    } catch (e) {
      if (mounted) GardenSnackBar.error(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _uploading--);
    }
  }

  // ── Pasos y validación ───────────────────────────────────────────────────

  bool _validateStep(int step) {
    switch (step) {
      case 0:
        final ok = _step1Key.currentState?.validate() ?? false;
        setState(() => _speciesMissing = _animalType == null);
        return ok && _animalType != null;
      case 1:
        final ok = _step2Key.currentState?.validate() ?? true;
        setState(() => _sizeMissing = _size == null);
        return ok && _size != null;
      default:
        return _step3Key.currentState?.validate() ?? true;
    }
  }

  /// Valida todo antes de guardar y lleva al primer paso con algo pendiente.
  bool _validateAll() {
    for (var s = 0; s < 3; s++) {
      // Los pasos no visitados no tienen FormState: se validan con los datos.
      final ok = switch (s) {
        0 => PetFormSheet.validateName(_nameCtrl.text) == null && _animalType != null,
        1 => _size != null && PetFormSheet.validateWeight(_weightCtrl.text) == null,
        _ => PetFormSheet.validateMicrochip(_microchipCtrl.text) == null,
      };
      if (!ok) {
        setState(() => _step = s);
        WidgetsBinding.instance.addPostFrameCallback((_) => _validateStep(s));
        return false;
      }
    }
    return true;
  }

  void _next() {
    if (!_validateStep(_step)) {
      HapticFeedback.selectionClick();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _step++);
  }

  void _onWeightChanged(String v) {
    final w = PetFormSheet.parseWeight(v);
    if (w != null && w > 0 && w <= 120 && (_size == null || _sizeFromWeight)) {
      setState(() {
        _size = PetFormSheet.sizeForWeight(w);
        _sizeFromWeight = true;
        _sizeMissing = false;
      });
    }
  }

  Map<String, dynamic> _body() {
    String? opt(TextEditingController c) {
      final t = c.text.trim();
      return t.isEmpty ? null : t;
    }

    final body = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'animalType': _animalType,
      'size': _size,
      'isAggressive': _isAggressive,
      'extraPhotos': _extraPhotos,
      'vaccinePhotos': _vaccinePhotos,
      'documents': _documents,
    };
    final optional = <String, dynamic>{
      'breed': opt(_breedCtrl),
      'age': _age,
      'weight': PetFormSheet.parseWeight(_weightCtrl.text),
      'color': opt(_colorCtrl),
      'microchipNumber': opt(_microchipCtrl)?.replaceAll(' ', ''),
      'specialNeeds': opt(_specialCtrl),
      'notes': opt(_notesCtrl),
      'gender': _gender,
      'sterilized': _sterilized,
      'photoUrl': _photoUrl,
    };
    // Al crear, lo vacío no se manda. Al editar se manda null: así un dato
    // que el dueño borró se borra de verdad (antes quedaba el valor viejo).
    optional.forEach((k, v) {
      if (v != null || _isEditing) body[k] = v;
    });
    return body;
  }

  Future<void> _save() async {
    if (_uploading > 0 || _saving) return;
    if (!_validateAll()) {
      HapticFeedback.selectionClick();
      return;
    }
    FocusScope.of(context).unfocus();
    HapticFeedback.mediumImpact();
    setState(() {
      _saving = true;
      _serverError = null;
    });
    try {
      final headers = {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'};
      final res = _isEditing
          ? await http.patch(Uri.parse('${widget.baseUrl}/client/pets/${widget.existing!['id']}'),
              headers: headers, body: jsonEncode(_body()))
          : await http.post(Uri.parse('${widget.baseUrl}/client/pets'), headers: headers, body: jsonEncode(_body()));
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (data['success'] == true) {
        GardenSnackBar.success(context, _isEditing ? 'Guardamos los cambios de $_petName' : '¡Listo! Ya conocemos a $_petName');
        widget.onSaved();
        Navigator.pop(context);
        return;
      }
      setState(() {
        _saving = false;
        // El backend manda { error: { message } } o, si falla la validación,
        // { errors: [{ field, message }] }.
        final listed = (data['errors'] as List?)?.map((e) => e['message']).whereType<String>().join(' · ');
        _serverError = (data['error']?['message'] as String?) ??
            ((listed != null && listed.isNotEmpty) ? listed : null) ??
            'No pudimos guardar. Revisa los datos e intenta de nuevo.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _serverError = 'Sin conexión. Revisa tu internet e intenta de nuevo.';
        });
      }
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final c = _Palette(isDark);
    final steps = ['Quién es', 'Cómo es', 'Para cuidarlo bien'];
    final media = MediaQuery.of(context);

    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.92),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Encabezado: título, pasos y cerrar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
          child: Column(children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Text(
                  _isEditing ? 'Editar a $_petName' : (_step == 0 ? 'Presenta a tu mascota' : 'Conozcamos a $_petName'),
                  style: GardenText.h4.copyWith(color: c.text, fontSize: 19),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: GardenIcon(GIcon.cerrar, color: c.sub, semanticLabel: 'Cerrar'),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              for (var i = 0; i < steps.length; i++) ...[
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    // Al editar se puede saltar entre pasos; al crear, solo hacia atrás.
                    onTap: (_isEditing || i < _step) ? () => setState(() => _step = i) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        AnimatedContainer(
                          duration: GardenMotion.resolve(context, GardenMotion.standard),
                          curve: GardenMotion.enter,
                          height: 4,
                          decoration: BoxDecoration(
                            color: i <= _step ? GardenColors.primary : c.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(steps[i],
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: i == _step ? FontWeight.w800 : FontWeight.w600,
                              color: i == _step ? c.text : c.sub,
                            )),
                      ]),
                    ),
                  ),
                ),
                if (i < steps.length - 1) const SizedBox(width: 8),
              ],
            ]),
          ]),
        ),
        // Contenido del paso
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: AnimatedSwitcher(
              duration: GardenMotion.resolve(context, GardenMotion.standard),
              switchInCurve: GardenMotion.enter,
              switchOutCurve: GardenMotion.exit,
              child: KeyedSubtree(
                key: ValueKey(_step),
                child: switch (_step) {
                  0 => _stepWho(c),
                  1 => _stepHow(c),
                  _ => _stepCare(c),
                },
              ),
            ),
          ),
        ),
        // Pie: error del servidor y botones
        Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + media.padding.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_serverError != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: GardenColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const GardenIcon(GIcon.advertencia, size: GIconSize.md, color: GardenColors.error),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_serverError!, style: const TextStyle(color: GardenColors.error, fontSize: 13))),
                ]),
              ),
            _footer(c),
          ]),
        ),
      ]),
    );
  }

  Widget _footer(_Palette c) {
    final uploading = _uploading > 0;
    final saveLabel = uploading
        ? 'Subiendo foto…'
        : (_isEditing ? 'Guardar cambios' : 'Agregar a $_petName');
    final save = GardenButton(
      label: saveLabel,
      gIcon: uploading ? null : GIcon.confirmado,
      loading: _saving,
      onPressed: (uploading || _saving) ? null : _save,
    );
    if (_isEditing) return SizedBox(width: double.infinity, child: save);

    return Row(children: [
      if (_step > 0) ...[
        GardenButton(
          label: 'Atrás',
          outline: true,
          width: 104,
          onPressed: _saving ? null : () => setState(() => _step--),
        ),
        const SizedBox(width: 10),
      ],
      Expanded(
        child: _step < 2
            ? GardenButton(label: 'Siguiente', gIcon: GIcon.siguiente, onPressed: _next)
            : save,
      ),
    ]);
  }

  // Paso 1 ───────────────────────────────────────────────────────────────
  Widget _stepWho(_Palette c) {
    return Form(
      key: _step1Key,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: GestureDetector(
            onTap: _uploading > 0 ? null : () => _addImage((u) => _photoUrl = u),
            child: Column(children: [
              Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.surfaceEl,
                    border: Border.all(color: GardenColors.primary.withValues(alpha: 0.35), width: 2),
                  ),
                  child: ClipOval(
                    child: _photoUrl != null && _photoUrl!.isNotEmpty
                        ? Image.network(fixImageUrl(_photoUrl!), fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                                child: GardenIcon(GIcon.sinImagen, size: GIconSize.xl, color: GardenColors.primary)))
                        : const Center(child: Brote(pose: BrotePose.hola, size: 72)),
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: GardenColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.surface, width: 2),
                    ),
                    child: Center(
                      child: _uploading > 0
                          ? const SizedBox(width: 16, height: 16, child: GardenLoadingIndicator(color: Colors.white))
                          : const GardenIcon(GIcon.foto, size: GIconSize.sm, color: Colors.white),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Text(_photoUrl == null ? 'Agrega una foto (opcional)' : 'Cambiar foto',
                  style: const TextStyle(color: GardenColors.primary, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
        const SizedBox(height: 18),
        _label(c, '¿Cómo se llama?'),
        TextFormField(
          controller: _nameCtrl,
          autofocus: !_isEditing,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          maxLength: 40,
          inputFormatters: [LengthLimitingTextInputFormatter(40)],
          style: TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.w700),
          decoration: _deco(c, 'Ej: Luna', counter: false),
          validator: PetFormSheet.validateName,
        ),
        const SizedBox(height: 10),
        _label(c, '¿Es perro o gato?'),
        Row(children: [
          Expanded(child: _bigChoice(c, GIcon.perro, 'Perro', _animalType == 'DOGS',
              () => setState(() { _animalType = 'DOGS'; _speciesMissing = false; }))),
          const SizedBox(width: 12),
          Expanded(child: _bigChoice(c, GIcon.gato, 'Gato', _animalType == 'CATS',
              () => setState(() { _animalType = 'CATS'; _speciesMissing = false; }))),
        ]),
        if (_speciesMissing) _error('Elige si es perro o gato'),
        const SizedBox(height: 8),
        _hint(c, 'Lo usamos para mostrarte solo cuidadores que aceptan a tu mascota.'),
      ]),
    );
  }

  // Paso 2 ───────────────────────────────────────────────────────────────
  Widget _stepHow(_Palette c) {
    return Form(
      key: _step2Key,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label(c, '¿De qué tamaño es $_petName?'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.4,
          children: [
            for (final (value, label, range) in PetFormSheet.sizes)
              _sizeChoice(c, label, range, _size == value,
                  () => setState(() { _size = value; _sizeFromWeight = false; _sizeMissing = false; })),
          ],
        ),
        if (_sizeMissing) _error('Elige un tamaño: el cuidador lo necesita para saber si puede atenderlo'),
        if (_sizeFromWeight) _hint(c, 'Lo elegimos por el peso que escribiste. Puedes cambiarlo.'),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label(c, 'Edad'),
              _ageStepper(c),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label(c, 'Peso (opcional)'),
              TextFormField(
                controller: _weightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')), LengthLimitingTextInputFormatter(5)],
                style: TextStyle(color: c.text),
                decoration: _deco(c, 'Ej: 4,5', suffix: 'kg'),
                validator: PetFormSheet.validateWeight,
                onChanged: _onWeightChanged,
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        _label(c, 'Sexo (opcional)'),
        Row(children: [
          Expanded(child: _chip(c, 'Macho', _gender == 'MALE', () => setState(() => _gender = _gender == 'MALE' ? null : 'MALE'))),
          const SizedBox(width: 10),
          Expanded(child: _chip(c, 'Hembra', _gender == 'FEMALE', () => setState(() => _gender = _gender == 'FEMALE' ? null : 'FEMALE'))),
        ]),
        const SizedBox(height: 14),
        _label(c, 'Raza (opcional)'),
        TextFormField(
          controller: _breedCtrl,
          textCapitalization: TextCapitalization.words,
          inputFormatters: [LengthLimitingTextInputFormatter(60)],
          style: TextStyle(color: c.text),
          decoration: _deco(c, _animalType == 'CATS' ? 'Ej: Siamés' : 'Ej: Labrador'),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final b in (_animalType == 'CATS'
              ? const ['Mestizo', 'Siamés', 'Persa', 'Angora']
              : const ['Mestizo', 'Labrador', 'Poodle', 'Shih Tzu', 'Pastor Alemán']))
            ActionChip(
              label: Text(b, style: const TextStyle(fontSize: 12)),
              onPressed: () => setState(() => _breedCtrl.text = b),
              visualDensity: VisualDensity.compact,
            ),
        ]),
        const SizedBox(height: 14),
        _label(c, 'Color o pelaje (opcional)'),
        TextFormField(
          controller: _colorCtrl,
          inputFormatters: [LengthLimitingTextInputFormatter(60)],
          style: TextStyle(color: c.text),
          decoration: _deco(c, 'Ej: café con manchas blancas'),
        ),
        if (!_isEditing) ...[
          const SizedBox(height: 14),
          _hint(c, 'Lo que sigue es opcional, pero ayuda mucho al cuidador. También puedes completarlo después.'),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              onPressed: _saving ? null : () {
                if (_validateStep(1)) _save();
              },
              child: const Text('Guardar ahora y completar después',
                  style: TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ]),
    );
  }

  // Paso 3 ───────────────────────────────────────────────────────────────
  Widget _stepCare(_Palette c) {
    return Form(
      key: _step3Key,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _hint(c, 'Todo es opcional. Lo que cuentes acá lo ve el cuidador antes de cada servicio.'),
        const SizedBox(height: 12),
        _toggle(c, GIcon.salud, 'Está esterilizado/a', _sterilized == true,
            () => setState(() => _sterilized = !(_sterilized ?? false)), GardenColors.success),
        const SizedBox(height: 10),
        _toggle(c, GIcon.advertencia, 'Puede reaccionar mal con extraños', _isAggressive,
            () => setState(() => _isAggressive = !_isAggressive), GardenColors.warning,
            detail: 'Solo te mostraremos cuidadores que aceptan este caso.'),
        const SizedBox(height: 14),
        _label(c, 'Rutina, gustos y miedos'),
        TextFormField(
          controller: _notesCtrl,
          maxLines: 3,
          maxLength: 500,
          style: TextStyle(color: c.text),
          decoration: _deco(c, 'Ej: come a las 8 y a las 19, le asustan los truenos, ama la pelota'),
        ),
        const SizedBox(height: 6),
        _label(c, 'Salud y cuidados especiales'),
        TextFormField(
          controller: _specialCtrl,
          maxLines: 2,
          maxLength: 500,
          style: TextStyle(color: c.text),
          decoration: _deco(c, 'Ej: medicación, alergias, dieta especial'),
        ),
        const SizedBox(height: 6),
        _label(c, 'Número de microchip'),
        TextFormField(
          controller: _microchipCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')), LengthLimitingTextInputFormatter(19)],
          style: TextStyle(color: c.text),
          decoration: _deco(c, '15 números, si tiene'),
          validator: PetFormSheet.validateMicrochip,
        ),
        const SizedBox(height: 16),
        _photosBlock(c, GIcon.galeria, 'Más fotos', 'Para que el cuidador la reconozca.', _extraPhotos,
            (u) => _extraPhotos = [..._extraPhotos, u], (i) => _extraPhotos = [..._extraPhotos]..removeAt(i)),
        _photosBlock(c, GIcon.vacuna, 'Carnet de vacunas', 'Una foto de cada página.', _vaccinePhotos,
            (u) => _vaccinePhotos = [..._vaccinePhotos, u], (i) => _vaccinePhotos = [..._vaccinePhotos]..removeAt(i)),
        _photosBlock(c, GIcon.documento, 'Otros documentos', 'Pedigrí o registros del veterinario.', _documents,
            (u) => _documents = [..._documents, u], (i) => _documents = [..._documents]..removeAt(i)),
      ]),
    );
  }

  // ── piezas ───────────────────────────────────────────────────────────────

  Widget _label(_Palette c, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: TextStyle(color: c.text, fontSize: 13.5, fontWeight: FontWeight.w700)),
      );

  Widget _hint(_Palette c, String t) => Text(t, style: TextStyle(color: c.sub, fontSize: 12, height: 1.4));

  Widget _error(String t) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(t, style: const TextStyle(color: GardenColors.error, fontSize: 12, fontWeight: FontWeight.w600)),
      );

  InputDecoration _deco(_Palette c, String hint, {String? suffix, bool counter = true}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: c.sub.withValues(alpha: 0.7), fontSize: 13.5),
        suffixText: suffix,
        counterText: counter ? null : '',
        filled: true,
        fillColor: c.surfaceEl,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.error)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.error, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      );

  Widget _bigChoice(_Palette c, GIcon icon, String label, bool selected, VoidCallback onTap) => GardenPressable(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: GardenMotion.resolve(context, GardenMotion.quick),
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: selected ? GardenColors.primary.withValues(alpha: 0.10) : c.surfaceEl,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? GardenColors.primary : c.border, width: selected ? 2 : 1),
          ),
          child: Column(children: [
            GardenIcon(icon, size: GIconSize.xl,
                state: selected ? GIconState.active : GIconState.idle,
                color: selected ? GardenColors.primary : c.sub),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(color: selected ? GardenColors.primary : c.text,
                fontWeight: FontWeight.w800, fontSize: 15)),
          ]),
        ),
      );

  Widget _sizeChoice(_Palette c, String label, String range, bool selected, VoidCallback onTap) => GardenPressable(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: GardenMotion.resolve(context, GardenMotion.quick),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? GardenColors.primary.withValues(alpha: 0.10) : c.surfaceEl,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? GardenColors.primary : c.border, width: selected ? 2 : 1),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: selected ? GardenColors.primary : c.text,
                fontWeight: FontWeight.w800, fontSize: 14)),
            Text(range, style: TextStyle(color: c.sub, fontSize: 11.5)),
          ]),
        ),
      );

  Widget _chip(_Palette c, String label, bool selected, VoidCallback onTap) => GardenPressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: GardenMotion.resolve(context, GardenMotion.quick),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? GardenColors.primary.withValues(alpha: 0.10) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? GardenColors.primary : c.border, width: selected ? 1.5 : 1),
          ),
          child: Center(
            child: Text(label, style: TextStyle(color: selected ? GardenColors.primary : c.text,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600, fontSize: 13.5)),
          ),
        ),
      );

  Widget _ageStepper(_Palette c) {
    final label = _age == null ? '—' : (_age == 0 ? 'Menos de 1 año' : (_age == 1 ? '1 año' : '$_age años'));
    Widget btn(GIcon icon, String semantic, VoidCallback? onTap) => IconButton(
          onPressed: onTap,
          icon: GardenIcon(icon, size: GIconSize.sm, color: onTap == null ? c.border : GardenColors.primary,
              semanticLabel: semantic),
          visualDensity: VisualDensity.compact,
        );
    return Container(
      height: 50,
      decoration: BoxDecoration(color: c.surfaceEl, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
      child: Row(children: [
        btn(GIcon.quitar, 'Menos edad', (_age ?? 0) > 0 ? () => setState(() => _age = (_age ?? 1) - 1) : null),
        Expanded(
          child: Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _age == null ? c.sub : c.text, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
        btn(GIcon.agregar, 'Más edad', (_age ?? 0) < 30 ? () => setState(() => _age = _age == null ? 1 : _age! + 1) : null),
      ]),
    );
  }

  Widget _toggle(_Palette c, GIcon icon, String label, bool on, VoidCallback onTap, Color color, {String? detail}) =>
      GardenPressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: GardenMotion.resolve(context, GardenMotion.quick),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: on ? color.withValues(alpha: 0.08) : c.surfaceEl,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? color.withValues(alpha: 0.5) : c.border),
          ),
          child: Row(children: [
            GardenIcon(icon, size: GIconSize.md, state: on ? GIconState.active : GIconState.idle, color: on ? color : c.sub),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 14)),
                if (detail != null && on) Text(detail, style: TextStyle(color: c.sub, fontSize: 12)),
              ]),
            ),
            Switch.adaptive(value: on, onChanged: (_) => onTap(), activeTrackColor: color),
          ]),
        ),
      );

  Widget _photosBlock(_Palette c, GIcon icon, String title, String hint, List<String> photos,
      void Function(String) onAdd, void Function(int) onRemove) {
    const max = 4;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GardenIcon(icon, size: GIconSize.md, state: GIconState.active),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 13.5)),
          const Spacer(),
          Text('${photos.length}/$max', style: TextStyle(color: c.sub, fontSize: 12)),
        ]),
        const SizedBox(height: 2),
        _hint(c, hint),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < photos.length; i++)
            Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(fixImageUrl(photos[i]), width: 68, height: 68, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(width: 68, height: 68, color: c.surfaceEl,
                        child: const Center(child: GardenIcon(GIcon.sinImagen, color: GardenColors.primary)))),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: () => setState(() => onRemove(i)),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(color: GardenColors.error, shape: BoxShape.circle),
                    child: const GardenIcon(GIcon.cerrar, size: GIconSize.xs, color: Colors.white, semanticLabel: 'Quitar'),
                  ),
                ),
              ),
            ]),
          if (photos.length < max)
            GestureDetector(
              onTap: _uploading > 0 ? null : () => _addImage(onAdd, quality: 80),
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: GardenColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: GardenColors.primary.withValues(alpha: 0.3)),
                ),
                child: const Center(child: GardenIcon(GIcon.agregar, color: GardenColors.primary, semanticLabel: 'Agregar foto')),
              ),
            ),
        ]),
      ]),
    );
  }
}

class _Palette {
  final Color surface, surfaceEl, text, sub, border;
  _Palette(bool isDark)
      : surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
        surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated,
        text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary,
        sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary,
        border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
}
