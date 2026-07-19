import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';
import '../../widgets/address_section.dart';
import '../../services/cities_service.dart';
import '../../utils/input_formatters.dart';
import '../../widgets/garden_loading_indicator.dart';

class MyDataScreen extends StatefulWidget {
  const MyDataScreen({super.key});
  @override
  State<MyDataScreen> createState() => _MyDataScreenState();
}

class _MyDataScreenState extends State<MyDataScreen> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;
  String _token = '';
  Uint8List? _pendingPhotoBytes;

  late TextEditingController _firstCtrl;
  late TextEditingController _lastCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _bioCtrl;
  DateTime? _dateOfBirth;

  // Dirección detallada
  late TextEditingController _streetCtrl;
  late TextEditingController _numberCtrl;
  late TextEditingController _apartmentCtrl;
  late TextEditingController _condominioCtrl;
  late TextEditingController _referenceCtrl;
  String? _addressZone;
  double? _addressLat;
  double? _addressLng;
  bool _isApartment = false;
  // Ciudad/zona de Garden (multi-ciudad) — distinto de _selectedCity, que es
  // el departamento de Bolivia (dato general del perfil, ya existente).
  String? _gardenCityId;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  @override
  void initState() {
    super.initState();
    _firstCtrl = TextEditingController();
    _lastCtrl = TextEditingController();
    _emailCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _addressCtrl = TextEditingController();
    _bioCtrl = TextEditingController();
    _streetCtrl = TextEditingController();
    _numberCtrl = TextEditingController();
    _apartmentCtrl = TextEditingController();
    _condominioCtrl = TextEditingController();
    _referenceCtrl = TextEditingController();
    _loadData();
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _bioCtrl.dispose();
    _streetCtrl.dispose();
    _numberCtrl.dispose();
    _apartmentCtrl.dispose();
    _condominioCtrl.dispose();
    _referenceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    _token = AuthState.token;
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/auth/me'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        final user = data['data'] as Map<String, dynamic>;
        setState(() {
          _userData = user;
          _firstCtrl.text = user['firstName'] as String? ?? '';
          _lastCtrl.text = user['lastName'] as String? ?? '';
          _emailCtrl.text = user['email'] as String? ?? '';
          // Cuentas creadas vía login social sin teléfono real reciben un
          // placeholder interno ('social_pending_xxxxx') para satisfacer la
          // columna NOT NULL/UNIQUE — nunca debe mostrarse tal cual, el campo
          // debe quedar vacío para que el usuario cargue su número real.
          final rawPhone = user['phone'] as String? ?? '';
          _phoneCtrl.text = rawPhone.startsWith('social_pending_') ? '' : rawPhone;
          _addressCtrl.text = user['address'] as String? ?? '';
          _bioCtrl.text = user['bio'] as String? ?? '';
          _streetCtrl.text = user['addressStreet'] as String? ?? '';
          _numberCtrl.text = user['addressNumber'] as String? ?? '';
          _apartmentCtrl.text = user['addressApartment'] as String? ?? '';
          _condominioCtrl.text = user['addressCondominio'] as String? ?? '';
          _referenceCtrl.text = user['addressReference'] as String? ?? '';
          _addressZone = user['addressZone'] as String?;
          _gardenCityId = user['cityId'] as String?;
          _addressLat = (user['addressLat'] as num?)?.toDouble();
          _addressLng = (user['addressLng'] as num?)?.toDouble();
          _isApartment = (user['addressApartment'] as String? ?? '').isNotEmpty;
          final dob = user['dateOfBirth'] as String?;
          if (dob != null && dob.isNotEmpty) {
            try { _dateOfBirth = DateTime.parse(dob); } catch (_) {}
          }
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      final fileName = picked.name.isEmpty
          ? 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg'
          : picked.name;
      final uri = Uri.parse('$_baseUrl/upload/user-photo');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $_token';
      request.files.add(http.MultipartFile.fromBytes(
        'photo', bytes, filename: fileName,
        contentType: MediaType('image', 'jpeg'),
      ));
      final response = await http.Response.fromStream(await request.send());
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (response.statusCode == 200 && data['success'] == true) {
        // Use local bytes to display the photo immediately — avoids CORS issues
        // when Flutter web tries to load the storage URL (S3/CDN) directly.
        setState(() {
          _pendingPhotoBytes = bytes;
          _userData = {...?_userData, 'profilePicture': data['data']['url'] as String? ?? ''};
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Foto actualizada'), backgroundColor: GardenColors.success));
      } else {
        throw Exception((data['error'] as Map<String, dynamic>?)?['message'] ?? data['message'] ?? 'Error al subir foto');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: GardenColors.error));
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  String _buildFullAddress() {
    final parts = <String>[
      if (_streetCtrl.text.trim().isNotEmpty) _streetCtrl.text.trim(),
      if (_numberCtrl.text.trim().isNotEmpty) 'N° ${_numberCtrl.text.trim()}',
      if (_isApartment && _apartmentCtrl.text.trim().isNotEmpty) 'Dpto. ${_apartmentCtrl.text.trim()}',
      if (_isApartment && _condominioCtrl.text.trim().isNotEmpty) _condominioCtrl.text.trim(),
      if (_addressZone != null) _addressZone!,
      'Santa Cruz de la Sierra, Bolivia',
    ];
    return parts.isEmpty ? _addressCtrl.text.trim() : parts.join(', ');
  }

  /// Espejo en vivo de las validaciones de _save() (sin SnackBars), para
  /// deshabilitar "Guardar cambios" hasta que el perfil esté realmente
  /// completo — mismos campos que _isClientDataIncomplete en profile_screen.dart.
  bool get _canSave {
    final hasPhoto = _pendingPhotoBytes != null ||
        (_userData?['profilePicture'] as String? ?? '').trim().isNotEmpty;
    return _firstCtrl.text.trim().isNotEmpty &&
        _lastCtrl.text.trim().isNotEmpty &&
        RegExp(r'^[67][0-9]{7}$').hasMatch(_phoneCtrl.text.trim()) &&
        _streetCtrl.text.trim().isNotEmpty &&
        _dateOfBirth != null &&
        hasPhoto;
  }

  Future<void> _save() async {
    final fn = _firstCtrl.text.trim();
    final ln = _lastCtrl.text.trim();
    if (fn.isEmpty || ln.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nombre y apellido son requeridos')));
      return;
    }
    // Estos campos son EXACTAMENTE los que revisa _isClientDataIncomplete en
    // profile_screen.dart para apagar el indicador de "perfil incompleto" —
    // antes no se exigían aquí, así que el usuario podía guardar y seguir
    // viendo el pulso encendido sin entender por qué.
    final phone = _phoneCtrl.text.trim();
    if (!RegExp(r'^[67][0-9]{7}$').hasMatch(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un número de celular boliviano válido (ej: 71234567)')));
      return;
    }
    if (_streetCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La dirección (calle) es requerida')));
      return;
    }
    if (_dateOfBirth == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona tu fecha de nacimiento')));
      return;
    }
    // Foto obligatoria para dueños de mascota — si el usuario ya tiene una
    // (subida acá o heredada de su perfil de cuidador, si tiene doble rol),
    // esto no bloquea nada; solo exige que exista alguna.
    final hasPhoto = _pendingPhotoBytes != null ||
        (_userData?['profilePicture'] as String? ?? '').trim().isNotEmpty;
    if (!hasPhoto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La foto de perfil es obligatoria')));
      return;
    }
    setState(() => _saving = true);
    try {
      final emailVerified = _userData?['emailVerified'] == true;
      // 'city'/'country' ya no se piden en un dropdown propio — se derivan
      // de la ciudad Garden elegida en AddressSection (con 'Bolivia' fijo,
      // único país donde opera la app hoy).
      String cityName = 'Santa Cruz';
      if (_gardenCityId != null) {
        final cities = await CitiesService.getCities();
        final match = cities.where((c) => c.id == _gardenCityId).firstOrNull;
        if (match != null) cityName = match.name;
      }
      final body = <String, dynamic>{
        'firstName': fn,
        'lastName': ln,
        'phone': _phoneCtrl.text.trim(),
        'city': cityName,
        'country': 'Bolivia',
        'address': _buildFullAddress(),
        'bio': _bioCtrl.text.trim(),
        if (_dateOfBirth != null) 'dateOfBirth': _dateOfBirth!.toIso8601String(),
        if (!emailVerified && _emailCtrl.text.trim().isNotEmpty) 'email': _emailCtrl.text.trim(),
        if (_addressLat != null) 'addressLat': _addressLat,
        if (_addressLng != null) 'addressLng': _addressLng,
        if (_streetCtrl.text.trim().isNotEmpty) 'addressStreet': _streetCtrl.text.trim(),
        if (_numberCtrl.text.trim().isNotEmpty) 'addressNumber': _numberCtrl.text.trim(),
        if (_isApartment && _apartmentCtrl.text.trim().isNotEmpty) 'addressApartment': _apartmentCtrl.text.trim(),
        if (_isApartment && _condominioCtrl.text.trim().isNotEmpty) 'addressCondominio': _condominioCtrl.text.trim(),
        if (_referenceCtrl.text.trim().isNotEmpty) 'addressReference': _referenceCtrl.text.trim(),
        if (_addressZone != null) 'addressZone': _addressZone,
        if (_gardenCityId != null) 'cityId': _gardenCityId,
      };
      // Resolver el zoneId real (uuid) a partir del key elegido — el
      // dropdown de AddressSection trabaja con el key legible, no el id.
      if (_gardenCityId != null && _addressZone != null) {
        final zones = await CitiesService.getZones(_gardenCityId!);
        final match = zones.where((z) => z.key == _addressZone).firstOrNull;
        if (match != null) body['zoneId'] = match.id;
      }
      final res = await http.patch(
        Uri.parse('$_baseUrl/auth/me'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Datos actualizados'), backgroundColor: GardenColors.success));
        Navigator.pop(context, true); // true = reload profile
      } else {
        throw Exception(data['error']?['message'] ?? 'Error al actualizar');
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
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
        final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
        final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
        final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

        InputDecoration fieldDeco(String label, IconData icon) => InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: subtextColor, fontSize: 13),
          prefixIcon: Icon(icon, color: subtextColor, size: 20),
          filled: true, fillColor: surfaceEl,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        );

        final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;

        Widget formContent = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo section
            Center(
              child: Stack(
                children: [
                  GestureDetector(
                    onTap: _uploadingPhoto ? null : _pickAndUploadPhoto,
                    child: Container(
                      width: kIsWeb ? 88 : 100, height: kIsWeb ? 88 : 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: GardenColors.primary.withValues(alpha: 0.4), width: 2),
                      ),
                      child: _uploadingPhoto
                          ? Padding(
                              padding: EdgeInsets.all(kIsWeb ? 26 : 30),
                              child: const GardenLoadingIndicator(color: GardenColors.primary))
                          : ClipOval(
                              child: _pendingPhotoBytes != null
                                  ? Image.memory(_pendingPhotoBytes!,
                                      width: kIsWeb ? 88 : 100, height: kIsWeb ? 88 : 100, fit: BoxFit.cover)
                                  : _userData?['profilePicture'] != null
                                      ? Image.network(
                                          fixImageUrl(_userData!['profilePicture'] as String),
                                          width: kIsWeb ? 88 : 100, height: kIsWeb ? 88 : 100, fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => _avatarFallback(textColor),
                                        )
                                      : _avatarFallback(textColor),
                            ),
                    ),
                  ),
                  Positioned(
                    bottom: 0, right: 0,
                    child: GestureDetector(
                      onTap: _uploadingPhoto ? null : _pickAndUploadPhoto,
                      child: Container(
                        width: 28, height: 28,
                        decoration: const BoxDecoration(color: GardenColors.primary, shape: BoxShape.circle),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Center(child: Text('Toca para cambiar foto', style: TextStyle(color: subtextColor, fontSize: 12))),
            const SizedBox(height: 28),

            // Email
            if (_userData?['email'] != null) ...[
              Text('Correo electrónico', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              if (_userData?['emailVerified'] == true)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: surfaceEl.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor.withValues(alpha: 0.5)),
                  ),
                  child: Row(children: [
                    Icon(Icons.email_outlined, color: subtextColor, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_userData!['email'] as String,
                      style: TextStyle(color: subtextColor, fontSize: 14))),
                    const Icon(Icons.verified_outlined, color: GardenColors.success, size: 16),
                  ]),
                )
              else
                TextField(
                  controller: _emailCtrl,
                  style: TextStyle(color: textColor),
                  keyboardType: TextInputType.emailAddress,
                  decoration: fieldDeco('Correo electrónico', Icons.email_outlined).copyWith(
                    suffixIcon: const Tooltip(
                      message: 'Correo no verificado',
                      child: Icon(Icons.warning_amber_rounded, color: GardenColors.warning, size: 18),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
            ],

            // Name
            Text('Nombre', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: TextField(controller: _firstCtrl, style: TextStyle(color: textColor),
                  inputFormatters: [noDigitsFormatter],
                  onChanged: (_) => setState(() {}),
                  decoration: fieldDeco('Nombre *', Icons.person_outline))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _lastCtrl, style: TextStyle(color: textColor),
                  inputFormatters: [noDigitsFormatter],
                  onChanged: (_) => setState(() {}),
                  decoration: fieldDeco('Apellido *', Icons.person_outlined))),
            ]),
            const SizedBox(height: 16),

            // Phone
            Text('Teléfono', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(controller: _phoneCtrl, style: TextStyle(color: textColor),
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {}),
                decoration: fieldDeco('Número de teléfono', Icons.phone_outlined)),
            const SizedBox(height: 16),

            // Ciudad y país ya no se piden acá — la ciudad la define el
            // selector de AddressSection (más abajo), que reemplaza este dato
            // legado. Pedirlo dos veces confundía al usuario.

            // Address
            Text('Dirección', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            AddressSection(
              isDark: isDark,
              textColor: textColor,
              subtextColor: subtextColor,
              borderColor: borderColor,
              surfaceEl: surfaceEl,
              streetController: _streetCtrl,
              numberController: _numberCtrl,
              apartmentController: _apartmentCtrl,
              condominioController: _condominioCtrl,
              referenceController: _referenceCtrl,
              selectedZone: _addressZone,
              onZoneChanged: (val) => setState(() => _addressZone = val),
              initialCityId: _gardenCityId,
              onCityChanged: (cityId, _) => setState(() => _gardenCityId = cityId),
              onCityChangeReset: () => setState(() {
                _addressLat = null;
                _addressLng = null;
                _streetCtrl.clear();
                _numberCtrl.clear();
                _apartmentCtrl.clear();
                _condominioCtrl.clear();
                _referenceCtrl.clear();
              }),
              addressLat: _addressLat,
              addressLng: _addressLng,
              isApartment: _isApartment,
              purposeText: 'Tu dirección se usa para que el cuidador pueda recoger a tu mascota en los paseos. Solo se comparte con el cuidador que acepte tu reserva.',
              onMapResult: (result) => setState(() {
                _addressLat = result.lat;
                _addressLng = result.lng;
                if (result.formattedAddress != null && result.formattedAddress!.isNotEmpty) {
                  _streetCtrl.text = result.formattedAddress!;
                }
              }),
              onApartmentToggle: (val) => setState(() => _isApartment = val),
              onFieldsChanged: () => setState(() {}),
            ),
            const SizedBox(height: 16),

            // Date of birth
            Text('Fecha de nacimiento', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _dateOfBirth ?? DateTime(1995),
                  firstDate: DateTime(1940),
                  lastDate: DateTime.now().subtract(const Duration(days: 365 * 13)),
                );
                if (picked != null) setState(() => _dateOfBirth = picked);
              },
              child: Container(
                height: kIsWeb ? 46 : 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: surfaceEl,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Row(children: [
                  Icon(Icons.cake_outlined, color: subtextColor, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    _dateOfBirth == null
                        ? 'Seleccionar fecha'
                        : '${_dateOfBirth!.day.toString().padLeft(2, '0')}/${_dateOfBirth!.month.toString().padLeft(2, '0')}/${_dateOfBirth!.year}',
                    style: TextStyle(color: _dateOfBirth == null ? subtextColor : textColor, fontSize: 14),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),

            // Bio
            Text('Descripción', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _bioCtrl,
              maxLines: 3, maxLength: 300,
              style: TextStyle(color: textColor, fontSize: 14),
              decoration: fieldDeco('Una breve descripción de ti', Icons.description_outlined).copyWith(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(height: 16),

            // Save button
            if (kIsWeb)
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                SizedBox(
                  width: 180,
                  child: GardenButton(
                    label: _saving ? 'Guardando...' : 'Guardar cambios',
                    loading: _saving,
                    onPressed: (_saving || !_canSave) ? null : _save,
                  ),
                ),
              ])
            else
              SizedBox(
                width: double.infinity,
                child: GardenButton(
                  label: _saving ? 'Guardando...' : 'Guardar cambios',
                  loading: _saving,
                  onPressed: (_saving || !_canSave) ? null : _save,
                ),
              ),
            const SizedBox(height: 24),
          ],
        );

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            Navigator.of(context).pop(_pendingPhotoBytes != null);
          },
          child: Scaffold(
          backgroundColor: bg,
          appBar: kIsWeb ? null : AppBar(
            title: const Text('Mis Datos'),
            backgroundColor: surface,
            foregroundColor: textColor,
            elevation: 0,
          ),
          body: Column(
            children: [
              if (kIsWeb)
                Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: surface,
                    border: Border(bottom: BorderSide(color: borderColor)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back_rounded, color: textColor, size: 18),
                        onPressed: () => Navigator.of(context).pop(_pendingPhotoBytes != null),
                      ),
                      const SizedBox(width: 6),
                      Text('Mis Datos', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              Expanded(
                child: _isLoading
                    ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
                    : SingleChildScrollView(
                        padding: EdgeInsets.all(kIsWeb ? 28 : 24),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: kIsWeb ? 680.0 : double.infinity),
                            child: formContent,
                          ),
                        ),
                      ),
              ),
            ],
          ),
          ),
        );
      },
    );
  }

  Widget _avatarFallback(Color textColor) {
    final initials = '${_firstCtrl.text.isNotEmpty ? _firstCtrl.text[0] : ''}${_lastCtrl.text.isNotEmpty ? _lastCtrl.text[0] : ''}'.toUpperCase();
    return Container(
      width: 100, height: 100,
      color: GardenColors.primary.withValues(alpha: 0.15),
      child: Center(child: Text(initials.isEmpty ? '?' : initials,
        style: const TextStyle(color: GardenColors.primary, fontSize: 32, fontWeight: FontWeight.bold))),
    );
  }
}
