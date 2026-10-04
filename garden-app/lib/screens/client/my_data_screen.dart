import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, FilteringTextInputFormatter;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';
import '../../widgets/address_section.dart';
import '../../services/cities_service.dart';
import '../../utils/input_formatters.dart';
import '../../widgets/garden_loading_indicator.dart';
import '../../widgets/phone_change_flow.dart';
import '../../design/garden_icons.dart';
import '../support/support_chat_screen.dart';

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
  // Teléfono: una vez verificado queda BLOQUEADO (es el canal de contacto). Solo
  // se cambia con una ventana que abre el bot de soporte desde el chat
  // (_phoneChangeAuthorized), y el número nuevo solo reemplaza al anterior si
  // se confirma con el código — ver widgets/phone_change_flow.dart.
  // _savedPhone es el número que YA está guardado en el servidor (distinto de
  // lo que el usuario esté tipeando sin guardar en _phoneCtrl).
  bool _phoneVerified = false;
  bool _phoneChangeAuthorized = false;
  DateTime? _phoneChangeUntil;
  String _savedPhone = '';
  bool get _phoneLocked => _phoneVerified && !_phoneChangeAuthorized;
  // Tras un intento de guardar con datos faltantes, los campos vacíos se marcan en rojo.
  bool _showErrors = false;

  late TextEditingController _firstCtrl;
  late TextEditingController _lastCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _bioCtrl;
  late TextEditingController _nitCtrl;
  late TextEditingController _nitRazonSocialCtrl;
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
    _nitCtrl = TextEditingController();
    _nitRazonSocialCtrl = TextEditingController();
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
    _nitCtrl.dispose();
    _nitRazonSocialCtrl.dispose();
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
          _savedPhone = rawPhone.startsWith('social_pending_') ? '' : rawPhone;
          _phoneCtrl.text = _savedPhone;
          // Estado del teléfono a nivel de usuario (viene en /auth/me).
          _phoneVerified = user['phoneVerified'] == true;
          final pc = user['phoneChange'] as Map<String, dynamic>?;
          _phoneChangeAuthorized = pc?['canChange'] == true;
          final until = pc?['changeAuthorizedUntil'] as String?;
          _phoneChangeUntil = until != null ? DateTime.tryParse(until)?.toLocal() : null;
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
      // NIT/Carnet vive en ClientProfile, no en User — /auth/me no lo trae,
      // se carga aparte del mismo endpoint que usa payment_screen.dart.
      final profileRes = await http.get(
        Uri.parse('$_baseUrl/client/my-profile'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final profileData = jsonDecode(profileRes.body);
      if (profileData['success'] == true && profileData['data'] != null) {
        final profile = profileData['data'] as Map<String, dynamic>;
        setState(() {
          _nitCtrl.text = profile['nit'] as String? ?? '';
          _nitRazonSocialCtrl.text = profile['nitRazonSocial'] as String? ?? '';
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  /// Guarda NIT/Carnet y razón social por separado — viven en ClientProfile
  /// y se actualizan vía PATCH /api/client/profile (mismo endpoint que
  /// payment_screen.dart usa al pagar), no vía PATCH /auth/me.
  Future<bool> _saveBillingInfo() async {
    try {
      final res = await http.patch(
        Uri.parse('$_baseUrl/client/profile'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'nit': _nitCtrl.text.trim(),
          'nitRazonSocial': _nitRazonSocialCtrl.text.trim(),
        }),
      );
      final data = jsonDecode(res.body);
      return data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Verifica el número guardado con un código por SMS.
  Future<void> _startPhoneVerification() async {
    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PhoneOtpDialog(baseUrl: _baseUrl, token: _token, phone: _savedPhone),
    );
    if (verified == true && mounted) {
      setState(() => _phoneVerified = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Teléfono verificado'), backgroundColor: GardenColors.success));
    }
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
        GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
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

  bool get _hasPhoto =>
      _pendingPhotoBytes != null || (_userData?['profilePicture'] as String? ?? '').trim().isNotEmpty;

  static final _phoneRegex = RegExp(r'^[67][0-9]{7}$');
  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// TODOS los datos son obligatorios: devuelve el nombre de cada campo que
  /// falta (vacío si está completo). Los mismos campos que mira
  /// _isClientDataIncomplete en profile_screen.dart para el aviso pulsante, más
  /// NIT/Carnet y razón social, que solo viven acá. Departamento y condominio
  /// solo se piden si marcó que vive en departamento.
  List<String> _missingFields() {
    final missing = <String>[];
    if (_firstCtrl.text.trim().isEmpty) missing.add('Nombre');
    if (_lastCtrl.text.trim().isEmpty) missing.add('Apellido');
    // Con el correo ya verificado el campo no se edita (y siempre tiene valor).
    if (_userData?['emailVerified'] != true && !_emailRegex.hasMatch(_emailCtrl.text.trim())) {
      missing.add('Correo electrónico válido');
    }
    if (!_phoneRegex.hasMatch(_phoneCtrl.text.trim())) missing.add('Teléfono (8 dígitos, empieza con 6 o 7)');
    if (_gardenCityId == null) missing.add('Ciudad');
    if (_addressZone == null) missing.add('Zona');
    if (_streetCtrl.text.trim().isEmpty) missing.add('Calle');
    if (_numberCtrl.text.trim().isEmpty) missing.add('Número de la dirección');
    if (_isApartment) {
      if (_apartmentCtrl.text.trim().isEmpty) missing.add('Departamento');
      if (_condominioCtrl.text.trim().isEmpty) missing.add('Condominio o edificio');
    }
    if (_referenceCtrl.text.trim().isEmpty) missing.add('Referencia de la dirección');
    if (_addressLat == null || _addressLng == null) missing.add('Ubicación exacta en el mapa');
    if (_dateOfBirth == null) missing.add('Fecha de nacimiento');
    if (_bioCtrl.text.trim().isEmpty) missing.add('Descripción');
    if (!_hasPhoto) missing.add('Foto de perfil');
    if (_nitCtrl.text.trim().isEmpty) missing.add('NIT o Carnet');
    if (_nitRazonSocialCtrl.text.trim().isEmpty) missing.add('Razón social');
    return missing;
  }

  Future<void> _showMissingDialog(List<String> missing) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Faltan datos por completar'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Para guardar, completa todos los campos:', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 10),
              for (final m in missing)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('•  $m', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
      ),
    );
  }

  /// PATCH /auth/me con el número solo: deja guardado el teléfono corregido para
  /// poder mandarle el código enseguida, sin esperar al resto del guardado.
  Future<String?> _patchPhoneOnly(String phone) async {
    try {
      final res = await http.patch(
        Uri.parse('$_baseUrl/auth/me'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) return null;
      return (data['error'] as Map<String, dynamic>?)?['message'] as String? ?? 'No se pudo guardar el teléfono';
    } catch (_) {
      return 'Error de conexión, intenta de nuevo.';
    }
  }

  /// Guarda los datos del perfil (PATCH /auth/me + NIT/Carnet). Nunca lanza:
  /// devuelve el error, así _save puede correrlo en paralelo al código del teléfono.
  Future<({String? error, bool billingOk})> _persistData() async {
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
        'firstName': _firstCtrl.text.trim(),
        'lastName': _lastCtrl.text.trim(),
        // Verificado = no se manda: el servidor tampoco lo acepta por esta vía. El
        // cambio autorizado va por PhoneChangeFlow.
        if (!_phoneVerified) 'phone': _phoneCtrl.text.trim(),
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
      if (data['success'] != true) {
        return (error: (data['error'] as Map<String, dynamic>?)?['message'] as String? ?? 'Error al actualizar', billingOk: false);
      }
      return (error: null, billingOk: await _saveBillingInfo());
    } catch (e) {
      return (error: e.toString().replaceFirst('Exception: ', ''), billingOk: false);
    }
  }

  Future<void> _save() async {
    // 1) Todos los campos completos, ANTES de tocar la red. Se avisa cuáles faltan.
    final missing = _missingFields();
    if (missing.isNotEmpty) {
      setState(() => _showErrors = true);
      await _showMissingDialog(missing);
      return;
    }

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final phoneNow = _phoneCtrl.text.trim();
    final phoneEdited = phoneNow != _savedPhone;

    // 2) Cambio de teléfono: el código sale LO PRIMERO al tocar Guardar y el
    //    resto de los datos se guarda en paralelo. La verificación es inmediata
    //    y obligatoria: si no se confirma, el número no cambia.
    Future<({String? error, bool billingOk})>? saved;
    var phoneChangeIncomplete = false;
    if (phoneEdited && _phoneVerified && _phoneChangeAuthorized) {
      final codeSent = PhoneChangeFlow.start(messenger, baseUrl: _baseUrl, token: _token, newPhone: phoneNow);
      saved = _persistData();
      if (await codeSent && mounted) {
        final confirmed = await PhoneChangeFlow.confirm(context, baseUrl: _baseUrl, token: _token, newPhone: phoneNow);
        if (!confirmed) phoneChangeIncomplete = true;
      } else {
        phoneChangeIncomplete = true;
      }
    } else if (phoneEdited && !_phoneVerified) {
      // Número sin verificar que se corrigió: primero queda guardado el número
      // solo (una llamada corta) para poder mandarle el código al instante.
      final phoneError = await _patchPhoneOnly(phoneNow);
      if (phoneError != null) {
        if (mounted) {
          setState(() => _saving = false);
          GardenErrorDialog.show(context, phoneError);
        }
        return;
      }
      saved = _persistData();
      if (mounted) {
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => PhoneOtpDialog(baseUrl: _baseUrl, token: _token, phone: phoneNow),
        );
      }
    }

    // 3) Resto de los datos (en los casos de arriba ya venían corriendo en paralelo).
    final result = await (saved ?? _persistData());
    if (!mounted) return;
    if (result.error != null) {
      setState(() => _saving = false);
      GardenErrorDialog.show(context, result.error!);
      return;
    }
    if (phoneChangeIncomplete) {
      // Lo demás se guardó, pero el número NO cambió: se queda en la pantalla para
      // que pueda corregir el número nuevo y reintentar mientras siga abierta la
      // autorización de soporte (cancelar no la cierra).
      setState(() => _saving = false);
      messenger.showSnackBar(const SnackBar(
        content: Text('Tus demás datos se guardaron, pero tu teléfono no cambió. Corrige el número nuevo y vuelve a guardar.'),
        backgroundColor: GardenColors.warning,
      ));
      return;
    }
    messenger.showSnackBar(SnackBar(
      content: Text(result.billingOk ? 'Datos actualizados' : 'Datos actualizados (no se pudo guardar el NIT/Carnet, intenta de nuevo)'),
      backgroundColor: result.billingOk ? GardenColors.success : GardenColors.warning,
    ));
    Navigator.pop(context, true); // true = reload profile
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

        InputDecoration fieldDeco(String label, IconData icon, {bool missing = false}) => InputDecoration(
          labelText: label,
          errorText: (_showErrors && missing) ? 'Requerido' : null,
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
                  GardenPressable(
                    pressedScale: 0.94,
                    borderRadius: BorderRadius.circular(kIsWeb ? 44 : 50),
                    onTap: _uploadingPhoto ? null : () {
                      HapticFeedback.selectionClick();
                      _pickAndUploadPhoto();
                    },
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
                    child: GardenPressable(
                      pressedScale: 0.85,
                      borderRadius: BorderRadius.circular(14),
                      onTap: _uploadingPhoto ? null : () {
                        HapticFeedback.selectionClick();
                        _pickAndUploadPhoto();
                      },
                      child: Container(
                        width: 28, height: 28,
                        decoration: const BoxDecoration(color: GardenColors.primary, shape: BoxShape.circle),
                        child: const GardenIcon(GIcon.foto, size: GIconSize.xs, color: Colors.white),
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
                    GardenIcon(GIcon.correo, size: GIconSize.md, color: subtextColor),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_userData!['email'] as String,
                      style: TextStyle(color: subtextColor, fontSize: 14))),
                    const GardenIcon(GIcon.verificado, size: GIconSize.sm, color: GardenColors.success),
                  ]),
                )
              else
                TextField(
                  controller: _emailCtrl,
                  style: TextStyle(color: textColor),
                  keyboardType: TextInputType.emailAddress,
                  decoration: fieldDeco('Correo electrónico', Icons.email_outlined, missing: !_emailRegex.hasMatch(_emailCtrl.text.trim())).copyWith(
                    suffixIcon: const Tooltip(
                      message: 'Correo no verificado',
                      child: GardenIcon(GIcon.advertencia, size: GIconSize.sm, color: GardenColors.warning),
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
                  decoration: fieldDeco('Nombre *', Icons.person_outline, missing: _firstCtrl.text.trim().isEmpty))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _lastCtrl, style: TextStyle(color: textColor),
                  inputFormatters: [noDigitsFormatter],
                  onChanged: (_) => setState(() {}),
                  decoration: fieldDeco('Apellido *', Icons.person_outlined, missing: _lastCtrl.text.trim().isEmpty))),
            ]),
            const SizedBox(height: 16),

            // Phone — verificado = bloqueado (solo cambia con autorización de
            // soporte); sin verificar = editable y con aviso para verificar.
            Row(children: [
              Text('Teléfono', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
              if (_savedPhone.isNotEmpty && _phoneCtrl.text.trim() == _savedPhone) ...[
                const SizedBox(width: 8),
                if (_phoneVerified)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const GardenIcon(GIcon.verificado, size: GIconSize.xs, color: GardenColors.success),
                    const SizedBox(width: 3),
                    Text('Verificado', style: TextStyle(color: GardenColors.success, fontSize: 11.5)),
                  ])
                else
                  GestureDetector(
                    onTap: _startPhoneVerification,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: GardenColors.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: GardenColors.warning),
                      ),
                      child: const Text('Sin verificar · Verificar ahora',
                          style: TextStyle(color: GardenColors.warning, fontSize: 11.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
              ],
            ]),
            const SizedBox(height: 6),
            TextField(controller: _phoneCtrl, style: TextStyle(color: textColor),
                keyboardType: TextInputType.phone,
                readOnly: _phoneLocked,
                onChanged: (_) => setState(() {}),
                decoration: fieldDeco('Número de teléfono', Icons.phone_outlined, missing: !_phoneRegex.hasMatch(_phoneCtrl.text.trim())).copyWith(
                  suffixIcon: _phoneLocked ? Padding(padding: const EdgeInsets.all(14), child: GardenIcon(GIcon.seguridad, size: GIconSize.sm, color: subtextColor)) : null,
                )),
            if (_phoneLocked) ...[
              const SizedBox(height: 6),
              Text('Tu teléfono está verificado y no se puede editar. Si necesitas cambiarlo, solicítalo por el chat de soporte.',
                  style: TextStyle(color: subtextColor, fontSize: 11.5)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportChatScreen())),
                  icon: const GardenIcon(GIcon.soporte, size: GIconSize.sm),
                  label: const Text('Pedir cambio por el chat'),
                ),
              ),
            ] else if (_phoneVerified && _phoneChangeAuthorized) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: GardenColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: GardenColors.primary.withValues(alpha: 0.5)),
                ),
                child: Text(
                  'Cambio autorizado por soporte${_phoneChangeUntil != null ? ' (hasta las ${_phoneChangeUntil!.hour.toString().padLeft(2, '0')}:${_phoneChangeUntil!.minute.toString().padLeft(2, '0')})' : ''}. '
                  'Escribe tu número nuevo y guarda: te enviaremos un código a ESE número. Si no lo confirmas, se mantiene el anterior.',
                  style: TextStyle(color: textColor, fontSize: 11.5),
                ),
              ),
            ],
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
                  GardenIcon(GIcon.cumpleanos, size: GIconSize.md, color: subtextColor),
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
            if (_showErrors && _dateOfBirth == null)
              const Padding(
                padding: EdgeInsets.only(top: 4, left: 4),
                child: Text('Requerido', style: TextStyle(color: GardenColors.error, fontSize: 12)),
              ),
            const SizedBox(height: 16),

            // Bio
            Text('Descripción', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _bioCtrl,
              maxLines: 3, maxLength: 300,
              style: TextStyle(color: textColor, fontSize: 14),
              decoration: fieldDeco('Una breve descripción de ti', Icons.description_outlined, missing: _bioCtrl.text.trim().isEmpty).copyWith(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(height: 20),

            // NIT / Carnet — dato de facturación, vive en el perfil (no en
            // cada reserva) para no tener que volver a escribirlo cada vez
            // que se paga un servicio. Acepta tanto NIT como número de
            // Carnet (CI) — ambos son válidos para emitir la factura.
            Row(children: [
              GardenIcon(GIcon.recibo, size: GIconSize.sm, color: textColor),
              const SizedBox(width: 6),
              Text('NIT o Carnet (facturación)', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 4),
            Text(
              'Puedes usar tu NIT o tu número de Carnet de Identidad — cualquiera de los dos sirve para tu factura. Se guarda acá y se pre-carga cada vez que pagues un servicio, pero puedes cambiarlo cuando quieras.',
              style: TextStyle(color: subtextColor, fontSize: 11.5),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nitCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(color: textColor),
              decoration: fieldDeco('NIT o Carnet', Icons.badge_outlined, missing: _nitCtrl.text.trim().isEmpty),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nitRazonSocialCtrl,
              style: TextStyle(color: textColor),
              decoration: fieldDeco('Razón social', Icons.article_outlined, missing: _nitRazonSocialCtrl.text.trim().isEmpty),
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
                    onPressed: _saving ? null : _save,
                  ),
                ),
              ])
            else
              SizedBox(
                width: double.infinity,
                child: GardenButton(
                  label: _saving ? 'Guardando...' : 'Guardar cambios',
                  loading: _saving,
                  onPressed: _saving ? null : _save,
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
                        icon: GardenIcon(GIcon.atras, size: GIconSize.sm, color: textColor),
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

/// Diálogo de verificación de teléfono para el cliente — envía el código al
/// abrirse (una sola vez, vía initState) y lo verifica al confirmar.
/// Devuelve `true` (Navigator.pop) si la verificación fue exitosa.
