/// Pantalla de registro para EMPRESAS (hoteles, hostales, guarderías, etc.).
///
/// Flujo (11 pasos, 0-indexed):
///   0  — Código de empresa (valida contra /api/auth/validate-company-code)
///   1  — Datos de la empresa (nombre, tipo, email, contraseña, teléfono, descripción)
///   2  — Ubicación (mapa + zona + dirección)
///   3  — Servicios que ofrece
///   ── [REGISTRO] → POST /api/auth/register-company → obtiene token ──
///   4  — Disponibilidad
///   5  — Fotos (caregiverPhotos "fotos de servicios" + placePhotos por secciones)
///   6  — Precios
///   7  — Logo de la empresa
///   8  — Verificación de teléfono (OTP)
///   9  — Verificación de correo
///   10 — Perfil detallado empresa (CaregiverProfileDataScreen, isCompany:true)
///
/// Al completar navega a /caregiver/home.

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart' as image_picker_pkg;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart' show GardenColors, GardenButton, GardenInput, themeNotifier;
import '../../services/auth_state.dart';
import '../../widgets/address_section.dart';
import 'caregiver_profile_data_screen.dart';
import 'phone_verification_screen.dart';
import 'email_verification_screen.dart';

class CompanyRegisterScreen extends StatefulWidget {
  const CompanyRegisterScreen({super.key});

  @override
  State<CompanyRegisterScreen> createState() => _CompanyRegisterScreenState();
}

class _CompanyRegisterScreenState extends State<CompanyRegisterScreen> {
  int _currentStep = 0;
  bool _isLoading = false;
  String _authToken = '';

  static const _baseUrl = String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  // ── Paso 0: Código ─────────────────────────────────────────────────────────
  final _codeCtrl = TextEditingController();
  bool _codeValid = false;

  // ── Paso 1: Datos de la empresa ────────────────────────────────────────────
  final _companyNameCtrl   = TextEditingController();
  final _emailCtrl         = TextEditingController();
  final _passwordCtrl      = TextEditingController();
  final _phoneCtrl         = TextEditingController();
  final _bioCtrl           = TextEditingController();
  String _businessType     = 'HOTEL';
  bool _obscurePassword    = true;

  static const _businessTypes = [
    ('HOTEL',       '🏨 Hotel'),
    ('HOSTAL',      '🛏️ Hostal'),
    ('GUARDERIA',   '🏡 Guardería'),
    ('PET_HOTEL',   '🐾 Hotel para mascotas'),
    ('OTHER',       '🏢 Otro'),
  ];

  // ── Paso 2: Ubicación ──────────────────────────────────────────────────────
  final _addressCtrl      = TextEditingController(); // kept for composed address string
  final _streetCtrl       = TextEditingController();
  final _numberCtrl       = TextEditingController();
  final _apartmentCtrl    = TextEditingController();
  final _condominioCtrl   = TextEditingController();
  final _referenceCtrl    = TextEditingController();
  bool _isApartment       = false;
  double? _lat;
  double? _lng;
  String? _zone;

  // ── Paso 3: Servicios ──────────────────────────────────────────────────────
  final List<String> _services = [];
  static const _serviceOptions = [
    ('PASEO',      '🦮', 'Paseo'),
    ('HOSPEDAJE',  '🏠', 'Hospedaje'),
    ('GUARDERIA',  '🏡', 'Guardería'),
  ];

  // ── Paso 4: Disponibilidad ─────────────────────────────────────────────────
  bool _weekdays  = true;
  bool _weekends  = false;
  bool _holidays  = false;
  bool _morning   = true;
  bool _afternoon = true;
  bool _night     = false;

  // ── Paso 5: Fotos ──────────────────────────────────────────────────────────
  List<String> _caregiverPhotoUrls = [];
  List<({Uint8List bytes, String name, String mimeType})> _localCaregiverPhotos = [];
  bool _uploadingCaregiverPhoto = false;

  Map<String, List<String>> _placePhotoUrls = {};
  Map<String, List<({Uint8List bytes, String name, String mimeType})>> _localPlacePhotos = {};
  bool _uploadingPlacePhoto = false;

  static const _placeSections = [
    ('sala',         '🛋️ Sala / Área principal',   true),
    ('descanso',     '🛏️ Zona de descanso',         true),
    ('alimentacion', '🍽️ Área de alimentación',     true),
    ('jardin',       '🌿 Jardín / Patio',            false),
    ('juego',        '🎾 Área de juego',             false),
  ];

  // ── Paso 6: Precios ────────────────────────────────────────────────────────
  double _precioHospedaje  = 90.0;
  double _precioPaseo      = 90.0;
  double _precioGuarderia  = 90.0;
  // Límites reales configurados por el admin (mismo endpoint que usa el
  // wizard de cuidador individual) — antes esta pantalla usaba un rango fijo
  // 10-500 sin relación con lo que el admin configura ni con lo que valida
  // el backend, permitiendo precios muy por fuera de lo esperado.
  double _paseoMin = 10.0;   double _paseoMax = 400.0;
  double _hospMin  = 10.0;   double _hospMax  = 400.0;
  double _guarMin  = 10.0;   double _guarMax  = 400.0;

  @override
  void initState() {
    super.initState();
    _loadPriceLimits();
  }

  Future<void> _loadPriceLimits() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/settings/price-limits'));
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        final s = data['data'];
        setState(() {
          _paseoMin = (s['paseoMinPrice'] as num?)?.toDouble() ?? 10;
          _paseoMax = (s['paseoMaxPrice'] as num?)?.toDouble() ?? 400;
          _hospMin  = (s['hospedajeMinPrice'] as num?)?.toDouble() ?? 10;
          _hospMax  = (s['hospedajeMaxPrice'] as num?)?.toDouble() ?? 400;
          _guarMin  = (s['guarderiaMinPrice'] as num?)?.toDouble() ?? 10;
          _guarMax  = (s['guarderiaMaxPrice'] as num?)?.toDouble() ?? 400;
          _precioHospedaje = _precioHospedaje.clamp(_hospMin, _hospMax);
          _precioPaseo = _precioPaseo.clamp(_paseoMin, _paseoMax);
          _precioGuarderia = _precioGuarderia.clamp(_guarMin, _guarMax);
        });
      }
    } catch (_) {
      // mantiene los valores por defecto (10-400) si falla la carga
    }
  }

  // ── Paso 7: Logo ───────────────────────────────────────────────────────────
  String? _logoUrl;
  ({Uint8List bytes, String name, String mimeType})? _localLogo;

  // ── Helpers ────────────────────────────────────────────────────────────────
  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: GardenColors.error,
      duration: const Duration(seconds: 5),
    ));
  }

  bool get _needsPlacePhotos =>
      _services.contains('HOSPEDAJE') || _services.contains('GUARDERIA');

  // ── Step 0: Validate code ──────────────────────────────────────────────────
  Future<void> _validateCode() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) { _showError('Ingresa el código de registro'); return; }
    setState(() => _isLoading = true);
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/validate-company-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': code}),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() { _codeValid = true; _currentStep = 1; });
      } else {
        _showError(data['error']?['message'] ?? 'Código inválido');
      }
    } catch (_) {
      _showError('Error de conexión. Verifica tu internet.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Step 1→2 transition: Register ─────────────────────────────────────────
  Future<bool> _registerCompany() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/register-company'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': _codeCtrl.text.trim(),
          'companyName': _companyNameCtrl.text.trim(),
          'businessType': _businessType,
          'email': _emailCtrl.text.trim(),
          'password': _passwordCtrl.text,
          'phone': _phoneCtrl.text.trim(),
          'bio': _bioCtrl.text.trim(),
          'zone': _zone,
          'address': [_streetCtrl.text.trim(), _numberCtrl.text.trim(), _referenceCtrl.text.trim()]
              .where((s) => s.isNotEmpty).join(', '),
          if (_lat != null) 'lat': _lat,
          if (_lng != null) 'lng': _lng,
          'services': _services,
        }),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        final d = data['data'];
        _authToken = d['accessToken'] as String;
        await AuthState.update(_authToken);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', _authToken);
        await prefs.setString('user_role', 'CAREGIVER');
        await prefs.setString('active_role', 'CAREGIVER');
        await prefs.setString('user_name', _companyNameCtrl.text.trim());
        final refreshToken = d['refreshToken'] as String?;
        if (refreshToken != null) await prefs.setString('refresh_token', refreshToken);
        return true;
      } else {
        _showError(data['error']?['message'] ?? 'Error al registrar empresa');
        return false;
      }
    } catch (e) {
      _showError('Error: ${e.toString().replaceFirst('Exception: ', '')}');
      return false;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _patchProfile(Map<String, dynamic> data) async {
    if (_authToken.isEmpty) return;
    try {
      await http.patch(
        Uri.parse('$_baseUrl/caregiver/profile'),
        headers: {'Authorization': 'Bearer $_authToken', 'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
    } catch (_) {}
  }

  // ── Next step logic ────────────────────────────────────────────────────────
  Future<void> _next() async {
    if (!_validateStep()) return;

    // Step 3→4: create account
    if (_currentStep == 3) {
      final ok = await _registerCompany();
      if (!ok) return;
      // PATCH availability after creation
      setState(() => _currentStep = 4);
      return;
    }

    // Step 4: patch availability
    if (_currentStep == 4) {
      await _patchProfile({
        'serviceDetails': {
          'availability': {
            'weekdays': _weekdays, 'weekends': _weekends, 'holidays': _holidays,
            'slots': {'morning': _morning, 'afternoon': _afternoon, 'night': _night},
          },
        },
        'defaultAvailabilitySchedule': {
          'weekdays': _weekdays, 'weekends': _weekends, 'holidays': _holidays,
        },
      });
    }

    // Step 5: upload pending photos
    if (_currentStep == 5) {
      await _uploadPendingCaregiverPhotos();
      await _uploadPendingPlacePhotos();
    }

    // Step 6: patch prices
    if (_currentStep == 6) {
      final body = <String, dynamic>{};
      if (_services.contains('HOSPEDAJE')) {
        body['pricePerDay'] = _precioHospedaje.toInt();
      }
      if (_services.contains('PASEO')) {
        body['pricePerWalk60'] = _precioPaseo.toInt();
        body['pricePerWalk30'] = (_precioPaseo / 2).round();
      }
      if (_services.contains('GUARDERIA')) {
        body['pricePerGuarderia'] = _precioGuarderia.toInt();
      }
      await _patchProfile(body);
    }

    // Step 7: upload logo
    if (_currentStep == 7) {
      await _uploadLogo();
    }

    setState(() => _currentStep++);
  }

  bool _validateStep() {
    switch (_currentStep) {
      case 0:
        if (!_codeValid) { _showError('Valida el código primero'); return false; }
        return true;
      case 1:
        if (_companyNameCtrl.text.trim().isEmpty) { _showError('Ingresa el nombre de la empresa'); return false; }
        if (_emailCtrl.text.trim().isEmpty) { _showError('Ingresa el correo de la empresa'); return false; }
        if (_passwordCtrl.text.length < 6) { _showError('La contraseña debe tener al menos 6 caracteres'); return false; }
        if (_phoneCtrl.text.trim().isEmpty) { _showError('Ingresa el teléfono de la empresa'); return false; }
        if (_bioCtrl.text.trim().length < 20) { _showError('La descripción debe tener al menos 20 caracteres'); return false; }
        return true;
      case 2:
        if (_zone == null) { _showError('Selecciona la zona de la empresa'); return false; }
        return true;
      case 3:
        if (_services.isEmpty) { _showError('Selecciona al menos un servicio'); return false; }
        return true;
      case 4:
        if (!_weekdays && !_weekends && !_holidays) { _showError('Selecciona al menos un día disponible'); return false; }
        if (!_morning && !_afternoon && !_night) { _showError('Selecciona al menos un horario'); return false; }
        return true;
      case 5:
        // Debe coincidir con minPhotos del backend (caregiver-profile-completion.helper.ts):
        // 2 si SOLO ofrece Paseo, 4 en cualquier otro caso. Antes esta pantalla
        // siempre pedía 2 aunque la empresa ofreciera Hospedaje/Guardería,
        // dejando el registro pasar con menos fotos de las que exige el backend.
        final onlyPaseo = _services.length == 1 && _services.contains('PASEO');
        final minCaregiverPhotos = onlyPaseo ? 2 : 4;
        final totalCaregiver = _caregiverPhotoUrls.length + _localCaregiverPhotos.length;
        if (totalCaregiver < minCaregiverPhotos) { _showError('Sube al menos $minCaregiverPhotos fotos de servicios'); return false; }
        if (_needsPlacePhotos) {
          for (final (key, label, req) in _placeSections) {
            if (!req) continue;
            final count = (_placePhotoUrls[key]?.length ?? 0) + (_localPlacePhotos[key]?.length ?? 0);
            if (count < 1) { _showError('Sube al menos 1 foto de: $label'); return false; }
          }
        }
        return true;
      case 6:
        if (_services.contains('HOSPEDAJE') && _precioHospedaje <= 0) { _showError('Ingresa el precio de Hospedaje'); return false; }
        if (_services.contains('PASEO') && _precioPaseo <= 0) { _showError('Ingresa el precio de Paseo'); return false; }
        if (_services.contains('GUARDERIA') && _precioGuarderia <= 0) { _showError('Ingresa el precio de Guardería'); return false; }
        return true;
      case 7:
        if (_logoUrl == null && _localLogo == null) { _showError('Sube el logo o foto de la empresa'); return false; }
        return true;
      default:
        return true;
    }
  }

  // ── Photo upload helpers ───────────────────────────────────────────────────
  Future<void> _pickCaregiverPhoto() async {
    final total = _caregiverPhotoUrls.length + _localCaregiverPhotos.length;
    if (total >= 6) { _showError('Máximo 6 fotos de servicios'); return; }
    final picked = await image_picker_pkg.ImagePicker().pickImage(
        source: image_picker_pkg.ImageSource.gallery, imageQuality: kIsWeb ? null : 85);
    if (picked == null) return;
    final bytes = Uint8List.fromList(await picked.readAsBytes());
    setState(() => _localCaregiverPhotos.add((bytes: bytes, name: picked.name, mimeType: 'image/jpeg')));
  }

  Future<void> _uploadPendingCaregiverPhotos() async {
    if (_localCaregiverPhotos.isEmpty) return;
    setState(() => _uploadingCaregiverPhoto = true);
    try {
      for (final photo in List.from(_localCaregiverPhotos)) {
        final req = http.MultipartRequest('POST', Uri.parse('$_baseUrl/caregiver/profile/caregiver-photo'));
        req.headers['Authorization'] = 'Bearer $_authToken';
        req.files.add(http.MultipartFile.fromBytes('caregiverPhoto', photo.bytes,
            filename: photo.name.isEmpty ? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg' : photo.name,
            contentType: MediaType('image', 'jpeg')));
        final resp = await req.send();
        final data = jsonDecode(await resp.stream.bytesToString());
        if (data['success'] == true) {
          setState(() { _caregiverPhotoUrls.add(data['data']['photoUrl'] as String); _localCaregiverPhotos.removeAt(0); });
        }
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _uploadingCaregiverPhoto = false);
    }
  }

  Future<void> _pickPlacePhoto(String section) async {
    final total = (_placePhotoUrls[section]?.length ?? 0) + (_localPlacePhotos[section]?.length ?? 0);
    if (total >= 3) { _showError('Máximo 3 fotos por sección'); return; }
    final picked = await image_picker_pkg.ImagePicker().pickImage(
        source: image_picker_pkg.ImageSource.gallery, imageQuality: kIsWeb ? null : 85);
    if (picked == null) return;
    final bytes = Uint8List.fromList(await picked.readAsBytes());
    setState(() {
      _localPlacePhotos[section] = [...(_localPlacePhotos[section] ?? []),
        (bytes: bytes, name: picked.name, mimeType: 'image/jpeg')];
    });
  }

  Future<void> _uploadPendingPlacePhotos() async {
    if (_localPlacePhotos.isEmpty) return;
    setState(() => _uploadingPlacePhoto = true);
    try {
      for (final section in _localPlacePhotos.keys.toList()) {
        final localList = List.from(_localPlacePhotos[section] ?? []);
        for (final photo in localList) {
          final req = http.MultipartRequest('POST', Uri.parse('$_baseUrl/caregiver/profile/place-photo'));
          req.headers['Authorization'] = 'Bearer $_authToken';
          req.fields['section'] = section;
          req.files.add(http.MultipartFile.fromBytes('placePhoto', photo.bytes,
              filename: photo.name.isEmpty ? 'place_${DateTime.now().millisecondsSinceEpoch}.jpg' : photo.name,
              contentType: MediaType('image', 'jpeg')));
          final resp = await req.send();
          final data = jsonDecode(await resp.stream.bytesToString());
          if (data['success'] == true) {
            setState(() {
              _placePhotoUrls[section] = [...(_placePhotoUrls[section] ?? []), data['data']['photoUrl'] as String];
              _localPlacePhotos[section] = (_localPlacePhotos[section] ?? []).skip(1).toList();
            });
          }
        }
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _uploadingPlacePhoto = false);
    }
  }

  Future<void> _uploadLogo() async {
    if (_localLogo == null) return;
    setState(() => _isLoading = true);
    try {
      final req = http.MultipartRequest('POST', Uri.parse('$_baseUrl/caregiver/profile/photo'));
      req.headers['Authorization'] = 'Bearer $_authToken';
      req.files.add(http.MultipartFile.fromBytes('photo', _localLogo!.bytes,
          filename: _localLogo!.name.isEmpty ? 'logo_${DateTime.now().millisecondsSinceEpoch}.jpg' : _localLogo!.name,
          contentType: MediaType('image', 'jpeg')));
      final resp = await req.send();
      final data = jsonDecode(await resp.stream.bytesToString());
      if (data['success'] == true) {
        _logoUrl = data['data']['profilePhoto'] as String? ?? data['data']['profilePicture'] as String?;
        setState(() => _localLogo = null);
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickLogo() async {
    final picked = await image_picker_pkg.ImagePicker().pickImage(
        source: image_picker_pkg.ImageSource.gallery, imageQuality: kIsWeb ? null : 85);
    if (picked == null) return;
    final bytes = Uint8List.fromList(await picked.readAsBytes());
    setState(() => _localLogo = (bytes: bytes, name: picked.name, mimeType: 'image/jpeg'));
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    // Steps 8 and 9 are full-screen verification widgets
    if (_currentStep == 8) {
      return PhoneVerificationScreen(
        phoneNumber: _phoneCtrl.text.trim(),
        onComplete: () => setState(() => _currentStep = 9),
      );
    }
    if (_currentStep == 9) {
      return EmailVerificationScreen(
        onComplete: () => setState(() => _currentStep = 10),
      );
    }
    // Step 10: embedded company profile
    if (_currentStep == 10) {
      return CaregiverProfileDataScreen(
        embeddedMode: true,
        isCompany: true,
        servicesOffered: _services,
        onSaveComplete: () => context.go('/caregiver/home'),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: _currentStep > 0
            ? IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 20),
                onPressed: () => setState(() => _currentStep--),
              )
            : null,
        title: Text(
          _stepTitle(_currentStep),
          style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 17),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_currentStep + 1) / 11,
            backgroundColor: borderColor,
            valueColor: const AlwaysStoppedAnimation<Color>(GardenColors.primary),
            minHeight: 3,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _buildCurrentStep(surface, textColor, subtextColor, borderColor, isDark),
              ),
            ),
            _buildBottomBar(textColor, borderColor),
          ],
        ),
      ),
    );
  }

  String _stepTitle(int step) {
    switch (step) {
      case 0: return 'Código de empresa';
      case 1: return 'Datos de la empresa';
      case 2: return 'Ubicación';
      case 3: return 'Servicios';
      case 4: return 'Disponibilidad';
      case 5: return 'Fotos';
      case 6: return 'Precios';
      case 7: return 'Logo';
      default: return 'Registro de empresa';
    }
  }

  Widget _buildCurrentStep(Color surface, Color textColor, Color subtextColor, Color borderColor, bool isDark) {
    switch (_currentStep) {
      case 0: return _buildStep0(surface, textColor, subtextColor, borderColor);
      case 1: return _buildStep1(surface, textColor, subtextColor, borderColor);
      case 2: return _buildStep2(surface, textColor, subtextColor, borderColor);
      case 3: return _buildStep3(surface, textColor, subtextColor, borderColor);
      case 4: return _buildStep4(surface, textColor, subtextColor, borderColor);
      case 5: return _buildStep5(surface, textColor, subtextColor, borderColor);
      case 6: return _buildStep6(surface, textColor, subtextColor, borderColor);
      case 7: return _buildStep7(surface, textColor, subtextColor, borderColor);
      default: return const SizedBox.shrink();
    }
  }

  Widget _buildBottomBar(Color textColor, Color borderColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: GardenButton(
        label: _currentStep < 7 ? 'Continuar' : 'Siguiente',
        loading: _isLoading,
        onPressed: _isLoading ? null : _next,
      ),
    );
  }

  // ── Step 0: Código ─────────────────────────────────────────────────────────
  Widget _buildStep0(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.business_rounded, color: GardenColors.primary, size: 48),
        const SizedBox(height: 16),
        Text('Registro para empresas', style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('Hoteles, hostales, guarderías y más pueden registrarse aquí con un código autorizado por el equipo GARDEN.',
            style: TextStyle(color: subtextColor, fontSize: 14)),
        const SizedBox(height: 32),
        GardenInput(
          hint: 'Código de registro',
          controller: _codeCtrl,
          keyboardType: TextInputType.text,
          onChanged: (_) => setState(() => _codeValid = false),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _isLoading ? null : _validateCode,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: GardenColors.primary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: GardenColors.primary))
                : Text('Verificar código', style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w600)),
          ),
        ),
        if (_codeValid) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: GardenColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: GardenColors.success.withValues(alpha: 0.4)),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: GardenColors.success, size: 18),
                SizedBox(width: 8),
                Text('✓ Código válido', style: TextStyle(color: GardenColors.success, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── Step 1: Datos de la empresa ────────────────────────────────────────────
  Widget _buildStep1(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Información de la empresa', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 24),
        GardenInput(hint: 'Nombre de la empresa *', controller: _companyNameCtrl),
        const SizedBox(height: 12),
        Text('Tipo de negocio', style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _businessTypes.map((e) {
            final type = e.$1;
            final label = e.$2;
            final sel = _businessType == type;
            return GestureDetector(
              onTap: () => setState(() => _businessType = type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? GardenColors.primary : surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? GardenColors.primary : borderColor),
                ),
                child: Text(label, style: TextStyle(color: sel ? Colors.white : subtextColor, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        GardenInput(hint: 'Correo electrónico *', controller: _emailCtrl, keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 12),
        GardenInput(
          hint: 'Contraseña *',
          controller: _passwordCtrl,
          obscureText: _obscurePassword,
          suffixIcon: IconButton(
            icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        const SizedBox(height: 12),
        GardenInput(hint: 'Teléfono de contacto *', controller: _phoneCtrl, keyboardType: TextInputType.phone),
        const SizedBox(height: 12),
        GardenInput(
          hint: 'Descripción del negocio * (mín. 20 caracteres)',
          controller: _bioCtrl,
          maxLines: 4,
          maxLength: 500,
        ),
      ],
    );
  }

  // ── Step 2: Ubicación ──────────────────────────────────────────────────────
  Widget _buildStep2(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final isDark = themeNotifier.isDark;
    final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ubicación de la empresa', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('Indica dónde se ubica tu negocio para que los dueños puedan encontrarte.',
            style: TextStyle(color: subtextColor, fontSize: 14)),
        const SizedBox(height: 20),
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
          selectedZone: _zone,
          onZoneChanged: (val) => setState(() => _zone = val),
          addressLat: _lat,
          addressLng: _lng,
          isApartment: _isApartment,
          purposeText: 'Tu dirección es privada. Solo se comparte con clientes que aceptes atender.',
          onMapResult: (result) => setState(() {
            _lat = result.lat;
            _lng = result.lng;
          }),
          onApartmentToggle: (val) => setState(() => _isApartment = val),
        ),
      ],
    );
  }

  // ── Step 3: Servicios ──────────────────────────────────────────────────────
  Widget _buildStep3(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Servicios que ofrece', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('Selecciona todos los servicios que tu empresa brinda.',
            style: TextStyle(color: subtextColor, fontSize: 14)),
        const SizedBox(height: 24),
        for (final (key, emoji, label) in _serviceOptions)
          GestureDetector(
            onTap: () => setState(() => _services.contains(key) ? _services.remove(key) : _services.add(key)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _services.contains(key) ? GardenColors.primary.withValues(alpha: 0.08) : surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _services.contains(key) ? GardenColors.primary : borderColor,
                  width: _services.contains(key) ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 14),
                  Text(label, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (_services.contains(key))
                    const Icon(Icons.check_circle_rounded, color: GardenColors.primary),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ── Step 4: Disponibilidad ─────────────────────────────────────────────────
  Widget _buildStep4(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    Widget tog(String label, bool value, ValueChanged<bool> onChange) => SwitchListTile(
      title: Text(label, style: TextStyle(color: textColor, fontSize: 14)),
      value: value,
      activeColor: GardenColors.primary,
      onChanged: onChange,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Disponibilidad', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 24),
        Text('Días', style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w600)),
        tog('Días de semana (Lun–Vie)', _weekdays,  (v) => setState(() => _weekdays  = v)),
        tog('Fines de semana',           _weekends, (v) => setState(() => _weekends  = v)),
        tog('Feriados',                  _holidays, (v) => setState(() => _holidays  = v)),
        const Divider(height: 32),
        Text('Horarios', style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w600)),
        tog('Mañana (08:00–12:00)',    _morning,   (v) => setState(() => _morning   = v)),
        tog('Tarde (13:00–18:00)',     _afternoon, (v) => setState(() => _afternoon = v)),
        tog('Noche (19:00–22:00)',     _night,     (v) => setState(() => _night     = v)),
      ],
    );
  }

  // ── Step 5: Fotos ──────────────────────────────────────────────────────────
  Widget _buildStep5(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fotos', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 24),

        // Caregiver photos = service photos for companies
        Text('📸 Fotos de servicios', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Muestra tu empresa en acción '
            '(mín. ${_services.length == 1 && _services.contains('PASEO') ? 2 : 4}, máx. 6)',
            style: TextStyle(color: subtextColor, fontSize: 13)),
        const SizedBox(height: 12),
        if (_uploadingCaregiverPhoto) const LinearProgressIndicator(color: GardenColors.primary),
        _buildCaregiverPhotoGrid(borderColor),

        if (_needsPlacePhotos) ...[
          const SizedBox(height: 28),
          Text('🏠 Fotos del lugar', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Muestra las instalaciones por secciones',
              style: TextStyle(color: subtextColor, fontSize: 13)),
          const SizedBox(height: 12),
          if (_uploadingPlacePhoto) const LinearProgressIndicator(color: GardenColors.primary),
          for (final (key, label, required) in _placeSections)
            _buildPlaceSectionBlock(key, label, required, borderColor, textColor, subtextColor),
        ],
      ],
    );
  }

  Widget _buildCaregiverPhotoGrid(Color borderColor) {
    final urls = _caregiverPhotoUrls;
    final locals = _localCaregiverPhotos;
    final total = urls.length + locals.length;
    final canAdd = total < 6;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
      itemCount: canAdd ? total + 1 : total,
      itemBuilder: (_, i) {
        if (i == total && canAdd) {
          return GestureDetector(
            onTap: _pickCaregiverPhoto,
            child: Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: GardenColors.primary.withValues(alpha: 0.4))),
              child: const Icon(Icons.add_a_photo_outlined, color: GardenColors.primary),
            ),
          );
        }
        if (i < urls.length) {
          return Stack(children: [
            Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
                image: DecorationImage(image: NetworkImage(urls[i]), fit: BoxFit.cover))),
            Positioned(right: 4, top: 4, child: GestureDetector(
              onTap: () => setState(() => _caregiverPhotoUrls.removeAt(i)),
              child: Container(padding: const EdgeInsets.all(3), decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: Colors.white, size: 14)),
            )),
          ]);
        }
        final li = i - urls.length;
        return Stack(children: [
          Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
              image: DecorationImage(image: MemoryImage(locals[li].bytes), fit: BoxFit.cover))),
          Positioned(right: 4, top: 4, child: GestureDetector(
            onTap: () => setState(() => _localCaregiverPhotos.removeAt(li)),
            child: Container(padding: const EdgeInsets.all(3), decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close, color: Colors.white, size: 14)),
          )),
        ]);
      },
    );
  }

  Widget _buildPlaceSectionBlock(String key, String label, bool required, Color borderColor, Color textColor, Color subtextColor) {
    final urls = _placePhotoUrls[key] ?? [];
    final locals = _localPlacePhotos[key] ?? [];
    final total = urls.length + locals.length;
    final canAdd = total < 3;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(label, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Text(required ? 'obligatorio' : 'opcional',
                style: TextStyle(color: required ? GardenColors.error : GardenColors.textSecondary, fontSize: 11)),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              for (int i = 0; i < urls.length; i++)
                SizedBox(width: 80, height: 80, child: Stack(children: [
                  Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
                      image: DecorationImage(image: NetworkImage(urls[i]), fit: BoxFit.cover))),
                  Positioned(right: 2, top: 2, child: GestureDetector(
                    onTap: () => setState(() { final l = List<String>.from(urls)..removeAt(i); _placePhotoUrls[key] = l; }),
                    child: Container(padding: const EdgeInsets.all(3), decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.close, color: Colors.white, size: 12)),
                  )),
                ])),
              for (int i = 0; i < locals.length; i++)
                SizedBox(width: 80, height: 80, child: Stack(children: [
                  Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
                      image: DecorationImage(image: MemoryImage(locals[i].bytes), fit: BoxFit.cover))),
                  Positioned(right: 2, top: 2, child: GestureDetector(
                    onTap: () => setState(() { final l = List.from(locals)..removeAt(i); _localPlacePhotos[key] = l.cast(); }),
                    child: Container(padding: const EdgeInsets.all(3), decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.close, color: Colors.white, size: 12)),
                  )),
                ])),
              if (canAdd)
                GestureDetector(
                  onTap: () => _pickPlacePhoto(key),
                  child: Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: required && total == 0 ? GardenColors.error.withValues(alpha: 0.5) : borderColor),
                    ),
                    child: Icon(Icons.add_photo_alternate_outlined,
                        color: required && total == 0 ? GardenColors.error : GardenColors.primary, size: 28),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Step 6: Precios ────────────────────────────────────────────────────────
  Widget _buildStep6(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Precios', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('Define los precios para los servicios que ofrece tu empresa.',
            style: TextStyle(color: subtextColor, fontSize: 14)),
        const SizedBox(height: 24),
        if (_services.contains('HOSPEDAJE'))
          _buildPriceCard('Hospedaje', '/ noche', '🏠', _precioHospedaje, (v) => setState(() => _precioHospedaje = v), textColor, subtextColor, surface, borderColor,
              min: _hospMin, max: _hospMax),
        if (_services.contains('PASEO'))
          _buildPriceCard('Paseo (1 hora)', '/ hora', '🦮', _precioPaseo, (v) => setState(() => _precioPaseo = v), textColor, subtextColor, surface, borderColor,
              min: _paseoMin, max: _paseoMax,
              note: 'El precio de 30 min será la mitad: Bs ${(_precioPaseo / 2).round()}'),
        if (_services.contains('GUARDERIA'))
          _buildPriceCard('Guardería', '/ día', '🏡', _precioGuarderia, (v) => setState(() => _precioGuarderia = v), textColor, subtextColor, surface, borderColor,
              min: _guarMin, max: _guarMax),
      ],
    );
  }

  Widget _buildPriceCard(String titulo, String unidad, String emoji, double value,
      ValueChanged<double> onChanged, Color textColor, Color subtextColor, Color surface, Color borderColor,
      {String? note, double min = 10, double max = 400}) {
    final clampedValue = value.clamp(min, max);
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: borderColor)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Text(titulo, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('Bs ${clampedValue.round()}', style: const TextStyle(color: GardenColors.primary, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(width: 4),
            Text(unidad, style: TextStyle(color: subtextColor, fontSize: 12)),
          ]),
          const SizedBox(height: 10),
          Slider(
            min: min, max: max, divisions: (max - min).round().clamp(1, 200),
            value: clampedValue,
            activeColor: GardenColors.primary,
            onChanged: onChanged,
          ),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(note, style: TextStyle(color: subtextColor, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  // ── Step 7: Logo ───────────────────────────────────────────────────────────
  Widget _buildStep7(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Logo de la empresa', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('Sube el logo o una foto representativa de tu empresa. Esta es la imagen que verán los clientes.',
            style: TextStyle(color: subtextColor, fontSize: 14)),
        const SizedBox(height: 32),
        Center(
          child: GestureDetector(
            onTap: _pickLogo,
            child: Container(
              width: 160, height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: surface,
                border: Border.all(color: GardenColors.primary.withValues(alpha: 0.4), width: 2),
                image: _localLogo != null
                    ? DecorationImage(image: MemoryImage(_localLogo!.bytes), fit: BoxFit.cover)
                    : _logoUrl != null
                        ? DecorationImage(image: NetworkImage(_logoUrl!), fit: BoxFit.cover)
                        : null,
              ),
              child: _localLogo == null && _logoUrl == null
                  ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.add_a_photo_outlined, color: GardenColors.primary, size: 36),
                      const SizedBox(height: 8),
                      Text('Subir logo', style: TextStyle(color: GardenColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                    ])
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_localLogo != null || _logoUrl != null)
          Center(
            child: TextButton.icon(
              onPressed: _pickLogo,
              icon: const Icon(Icons.edit_outlined, size: 16, color: GardenColors.primary),
              label: const Text('Cambiar logo', style: TextStyle(color: GardenColors.primary)),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _companyNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    _bioCtrl.dispose();
    _addressCtrl.dispose();
    _streetCtrl.dispose();
    _numberCtrl.dispose();
    _apartmentCtrl.dispose();
    _condominioCtrl.dispose();
    _referenceCtrl.dispose();
    super.dispose();
  }
}
