/// Pantalla de registro para CUIDADORES PROFESIONALES.
///
/// Flujo (8 pasos):
///   0 — Código de admin (se valida contra /api/auth/validate-professional-code)
///   1 — Datos personales (sin CI ni fecha de nacimiento)
///   2 — Servicios y zona
///   3 — Disponibilidad
///   4 — Fotos del lugar / de trabajo
///   5 — Precio
///   6 — Foto de perfil
///   7 — Perfil profesional detallado (embedded CaregiverProfileDataScreen)
///
/// Al completar el paso 7 llama a POST /api/auth/register-professional,
/// guarda el token y navega a /caregiver/home.

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart' as image_picker_pkg;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart' show fixImageUrl, GardenColors, GardenButton, themeNotifier;
import '../../services/auth_service.dart';
import '../../utils/input_formatters.dart';
import 'caregiver_profile_data_screen.dart';

class ProfessionalRegisterScreen extends StatefulWidget {
  const ProfessionalRegisterScreen({super.key});

  @override
  State<ProfessionalRegisterScreen> createState() => _ProfessionalRegisterScreenState();
}

class _ProfessionalRegisterScreenState extends State<ProfessionalRegisterScreen> {
  int _currentStep = 0;
  bool _isLoading = false;
  String _authToken = '';

  // Paso 0: Código de admin
  final _codeController = TextEditingController();
  bool _codeValid = false;

  // Paso 1: Datos personales
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bioController = TextEditingController();
  final _addressController = TextEditingController();

  // Paso 2: Servicios y zona
  final List<String> _servicesOffered = [];
  String? _selectedZone;
  String? _homeType;
  bool _hasYard = false;

  // Paso 3: Disponibilidad
  bool _weekdays = false;
  bool _weekends = false;
  bool _holidays = false;
  final List<String> _times = [];

  // Paso 4: Fotos
  List<String> _photoUrls = [];
  List<({Uint8List bytes, String name, String mimeType})> _localPhotos = [];
  bool _uploadingPhotos = false;

  // Paso 5: Precio
  double _precioHospedaje = 90.0;
  double _precioPaseo = 90.0;
  double _precioGuarderia = 90.0;

  // Paso 6: Foto de perfil
  String? _profilePhotoUrl;
  ({Uint8List bytes, String name, String mimeType})? _localProfilePhoto;

  static const _baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://api.gardenbo.com/api',
  );

  // Keys for step navigation on error
  final _keyStep1Name = GlobalKey();
  final _keyStep1Email = GlobalKey();
  final _keyStep1Password = GlobalKey();
  final _keyStep1Phone = GlobalKey();
  final _keyStep2Services = GlobalKey();
  final _keyStep2Zone = GlobalKey();
  final _keyStep3Days = GlobalKey();
  final _keyStep3Times = GlobalKey();

  @override
  void dispose() {
    _codeController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _showStepError(String msg, {GlobalKey? scrollTo}) {
    if (scrollTo?.currentContext != null) {
      Scrollable.ensureVisible(
        scrollTo!.currentContext!,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.1,
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red.shade700,
      duration: const Duration(seconds: 5),
    ));
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        if (_codeController.text.trim().isEmpty) {
          _showStepError('Ingresa el código de registro profesional');
          return false;
        }
        if (!_codeValid) {
          _showStepError('El código ingresado no es válido');
          return false;
        }
        return true;
      case 1:
        if (_firstNameController.text.trim().isEmpty) {
          _showStepError('Falta: Nombre', scrollTo: _keyStep1Name);
          return false;
        }
        if (_lastNameController.text.trim().isEmpty) {
          _showStepError('Falta: Apellido', scrollTo: _keyStep1Name);
          return false;
        }
        if (_emailController.text.trim().isEmpty) {
          _showStepError('Falta: Correo electrónico', scrollTo: _keyStep1Email);
          return false;
        }
        if (_passwordController.text.isEmpty) {
          _showStepError('Falta: Contraseña', scrollTo: _keyStep1Password);
          return false;
        }
        if (_phoneController.text.trim().isEmpty) {
          _showStepError('Falta: Número de teléfono', scrollTo: _keyStep1Phone);
          return false;
        }
        if (_bioController.text.trim().length < 50) {
          _showStepError('La descripción debe tener al menos 50 caracteres');
          return false;
        }
        return true;
      case 2:
        if (_servicesOffered.isEmpty) {
          _showStepError('Selecciona al menos un servicio', scrollTo: _keyStep2Services);
          return false;
        }
        if (_selectedZone == null) {
          _showStepError('Selecciona tu zona en Santa Cruz', scrollTo: _keyStep2Zone);
          return false;
        }
        return true;
      case 3:
        if (!_weekdays && !_weekends && !_holidays) {
          _showStepError('Selecciona al menos un día disponible', scrollTo: _keyStep3Days);
          return false;
        }
        if (_times.isEmpty) {
          _showStepError('Selecciona al menos un horario', scrollTo: _keyStep3Times);
          return false;
        }
        return true;
      case 4:
        final minFotos = _servicesOffered.contains('HOSPEDAJE') ? 4 : 2;
        if (_photoUrls.length < minFotos) {
          _showStepError('Sube al menos $minFotos fotos para continuar');
          return false;
        }
        return true;
      case 5:
        if (_servicesOffered.contains('HOSPEDAJE') && _precioHospedaje <= 0) {
          _showStepError('Por favor, selecciona un precio para Hospedaje');
          return false;
        }
        if (_servicesOffered.contains('PASEO') && _precioPaseo <= 0) {
          _showStepError('Por favor, selecciona un precio para Paseo');
          return false;
        }
        if (_servicesOffered.contains('GUARDERIA') && _precioGuarderia <= 0) {
          _showStepError('Por favor, selecciona un precio para Guardería');
          return false;
        }
        return true;
      case 6:
        if (_profilePhotoUrl == null && _localProfilePhoto == null) {
          _showStepError('Por favor, sube una foto de perfil profesional');
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  // ── Paso 0 → 1: Validate code ──────────────────────────────────────────────

  Future<void> _validateAndAdvance() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      _showStepError('Ingresa el código de registro profesional');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/validate-professional-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': code}),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        setState(() { _codeValid = true; _currentStep = 1; });
      } else {
        final msg = data['error']?['message'] as String? ?? 'Código inválido';
        _showStepError(msg);
      }
    } catch (e) {
      _showStepError('Error de conexión. Verifica tu internet.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── PATCH profile helper (used for intermediate steps after registration) ───

  Future<void> _patchProfile(Map<String, dynamic> data) async {
    if (_authToken.isEmpty) return;
    try {
      await http.patch(
        Uri.parse('$_baseUrl/caregiver/profile'),
        headers: {
          'Authorization': 'Bearer $_authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(data),
      );
    } catch (_) {}
  }

  // ── Upload photos helper ────────────────────────────────────────────────────

  Future<void> _uploadAllPhotos() async {
    if (_localPhotos.isEmpty) return;
    setState(() => _uploadingPhotos = true);
    try {
      final uri = Uri.parse('$_baseUrl/upload/registration-photos');
      final request = http.MultipartRequest('POST', uri);
      for (final photo in _localPhotos) {
        final bytes = photo.bytes;
        final fileName = photo.name.isEmpty
            ? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg'
            : photo.name;
        String mimeType = photo.mimeType;
        if (mimeType == 'image/jpg' || mimeType.isEmpty) mimeType = 'image/jpeg';
        if (fileName.toLowerCase().endsWith('.jpg')) mimeType = 'image/jpeg';
        if (fileName.toLowerCase().endsWith('.png')) mimeType = 'image/png';
        request.files.add(http.MultipartFile.fromBytes(
          'photos', bytes, filename: fileName, contentType: MediaType.parse(mimeType),
        ));
      }
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        final raw = data['data']['urls'];
        final urls = raw is List ? raw.cast<String>() : [raw.toString()];
        setState(() { _photoUrls = urls; _localPhotos = []; });
      } else {
        throw Exception(data['message'] ?? data['error']?['message'] ?? 'Error al subir fotos');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: Colors.red.shade700,
        ));
      }
      rethrow;
    } finally {
      if (mounted) setState(() => _uploadingPhotos = false);
    }
  }

  // ── Final registration (called after step 7 — CaregiverProfileDataScreen) ──

  Future<void> _registerProfessional() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/register-professional'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': _codeController.text.trim(),
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
          'firstName': _firstNameController.text.trim(),
          'lastName': _lastNameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'bio': _bioController.text.trim(),
          if (_addressController.text.trim().isNotEmpty) 'address': _addressController.text.trim(),
          if (_selectedZone != null) 'zone': _selectedZone,
          'services': _servicesOffered,
          if (_servicesOffered.contains('HOSPEDAJE')) 'pricePerDay': _precioHospedaje.toInt(),
          if (_servicesOffered.contains('PASEO')) 'pricePerWalk60': _precioPaseo.toInt(),
          if (_servicesOffered.contains('GUARDERIA')) 'pricePerGuarderia': _precioGuarderia.toInt(),
          'photos': _photoUrls,
          if (_profilePhotoUrl != null) 'profilePhoto': _profilePhotoUrl,
        }),
      );

      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw Exception('El servidor no está disponible. Intenta de nuevo.');
      }

      if ((response.statusCode == 200 || response.statusCode == 201) && data['success'] == true) {
        final authService = AuthService();
        await authService.saveToken(data['data']['accessToken']);
        await authService.saveUserData(data['data']['user']);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('caregiver_setup_complete', true);
        // Save token for patching steps after registration
        setState(() => _authToken = data['data']['accessToken'] as String? ?? '');
        if (!mounted) return;
        context.go('/caregiver/home');
      } else {
        final msg = data['error']?['message'] ?? data['message'] ?? 'Error al crear la cuenta';
        throw Exception(msg);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Error'),
          ]),
          content: SingleChildScrollView(
            child: Text(e.toString().replaceFirst('Exception: ', ''), style: const TextStyle(fontSize: 14)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _nextStep() async {
    // Step 0: Validate code
    if (_currentStep == 0) {
      await _validateAndAdvance();
      return;
    }

    // Step 1: Personal data — validate only (no backend call yet)
    if (_currentStep == 1) {
      if (!_validateCurrentStep()) return;
      setState(() => _currentStep++);
      return;
    }

    // Step 2: Services & zone
    if (_currentStep == 2) {
      if (!_validateCurrentStep()) return;
      setState(() => _currentStep++);
      return;
    }

    // Step 3: Availability
    if (_currentStep == 3) {
      if (!_validateCurrentStep()) return;
      setState(() => _currentStep++);
      return;
    }

    // Step 4: Photos — upload then advance
    if (_currentStep == 4) {
      final minFotos = _servicesOffered.contains('HOSPEDAJE') ? 4 : 2;
      final total = _localPhotos.length + _photoUrls.length;
      if (total == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sube al menos $minFotos fotos para continuar')),
        );
        return;
      }
      if (_localPhotos.isNotEmpty) {
        try { await _uploadAllPhotos(); } catch (_) { return; }
      }
      if (_photoUrls.length < minFotos) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Necesitas al menos $minFotos fotos')),
        );
        return;
      }
      setState(() => _currentStep++);
      return;
    }

    // Step 5: Price
    if (_currentStep == 5) {
      if (!_validateCurrentStep()) return;
      setState(() => _currentStep++);
      return;
    }

    // Step 6: Profile photo — upload then advance
    if (_currentStep == 6) {
      if (!_validateCurrentStep()) return;
      setState(() => _isLoading = true);
      if (_localProfilePhoto != null && _profilePhotoUrl == null) {
        try {
          final uri = Uri.parse('$_baseUrl/upload/public-single-photo');
          final request = http.MultipartRequest('POST', uri);
          final bytes = _localProfilePhoto!.bytes;
          String mimeType = _localProfilePhoto!.mimeType;
          if (mimeType == 'image/jpg' || mimeType.isEmpty) mimeType = 'image/jpeg';
          request.files.add(
            http.MultipartFile.fromBytes(
              'photo',
              bytes,
              filename: _localProfilePhoto!.name.isEmpty ? 'profile.jpg' : _localProfilePhoto!.name,
              contentType: MediaType.parse(mimeType),
            ),
          );
          final streamed = await request.send();
          final response = await http.Response.fromStream(streamed);
          final data = jsonDecode(response.body);
          if (response.statusCode == 200 && data['success'] == true) {
            _profilePhotoUrl = data['data']['url'].toString();
          } else {
            throw Exception('Error subiendo foto de perfil');
          }
        } catch (e) {
          setState(() => _isLoading = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error foto perfil: $e'), backgroundColor: Colors.red.shade700),
            );
          }
          return;
        }
      }
      setState(() { _isLoading = false; _currentStep++; });
      return;
    }

    // Step 7: handled by CaregiverProfileDataScreen
  }

  void _prevStep() {
    if (_currentStep > 0) setState(() => _currentStep--);
  }

  Future<void> _pickPhoto() async {
    final isHospedaje = _servicesOffered.contains('HOSPEDAJE');
    final maxFotos = isHospedaje ? 6 : 4;
    if (_localPhotos.length + _photoUrls.length >= maxFotos) return;
    final picked = await image_picker_pkg.ImagePicker()
        .pickImage(source: image_picker_pkg.ImageSource.gallery, imageQuality: 85);
    if (picked == null || !mounted) return;
    try {
      final bytes = await picked.readAsBytes();
      final name = picked.name.isEmpty
          ? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg'
          : picked.name;
      final mimeType = picked.mimeType ?? 'image/jpeg';
      setState(() { _localPhotos.add((bytes: bytes, name: name, mimeType: mimeType)); });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error leyendo imagen: $e'), backgroundColor: Colors.red.shade700));
      }
    }
  }

  Future<void> _pickProfilePhoto() async {
    final picked = await image_picker_pkg.ImagePicker()
        .pickImage(source: image_picker_pkg.ImageSource.gallery, imageQuality: 85);
    if (picked == null || !mounted) return;
    try {
      final bytes = await picked.readAsBytes();
      final name = picked.name.isEmpty
          ? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg'
          : picked.name;
      final mimeType = picked.mimeType ?? 'image/jpeg';
      setState(() { _profilePhotoUrl = null; _localProfilePhoto = (bytes: bytes, name: name, mimeType: mimeType); });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error leyendo imagen: $e'), backgroundColor: Colors.red.shade700));
      }
    }
  }

  // ── Build steps ─────────────────────────────────────────────────────────────

  Widget _buildStep0(Color textColor, Color subtextColor, Color surfaceEl, Color borderColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [GardenColors.primary, Color(0xFF4A5E28)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(children: [
              Text('🌿', style: TextStyle(fontSize: 32)),
              SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Registro Profesional', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                SizedBox(height: 4),
                Text('Acceso exclusivo para cuidadores certificados de GARDEN.',
                    style: TextStyle(fontSize: 12, color: Colors.white70)),
              ])),
            ]),
          ),
          const SizedBox(height: 32),
          Text('Código de acceso',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: textColor, letterSpacing: -0.5)),
          const SizedBox(height: 8),
          Text('Ingresa el código de registro profesional proporcionado por el equipo GARDEN.',
              style: TextStyle(fontSize: 14, color: subtextColor)),
          const SizedBox(height: 28),
          TextFormField(
            controller: _codeController,
            style: TextStyle(color: textColor, letterSpacing: 2, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: 'Código de registro',
              prefixIcon: Icon(Icons.vpn_key_outlined, color: subtextColor, size: 20),
              suffixIcon: _codeValid
                  ? const Icon(Icons.check_circle_rounded, color: GardenColors.success, size: 20)
                  : null,
            ),
            onChanged: (_) {
              if (_codeValid) setState(() => _codeValid = false);
            },
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: GardenColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: GardenColors.primary.withValues(alpha: 0.25)),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline_rounded, color: GardenColors.primary, size: 18),
              SizedBox(width: 10),
              Expanded(child: Text(
                'Este registro es para cuidadores profesionales verificados. No necesitarás subir documentos de identidad.',
                style: TextStyle(color: GardenColors.primary, fontSize: 12, height: 1.4),
              )),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1(Color textColor, Color subtextColor, Color borderColor, Color surfaceEl) {
    InputDecoration field(String hint, IconData icon) => InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: subtextColor, size: 20),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cuéntanos sobre ti',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: textColor, letterSpacing: -0.5)),
          const SizedBox(height: 6),
          Text('Esta información aparecerá en tu perfil de cuidador',
              style: TextStyle(fontSize: 14, color: subtextColor)),
          const SizedBox(height: 28),

          SizedBox(key: _keyStep1Name, height: 0),
          Row(children: [
            Expanded(child: TextFormField(controller: _firstNameController, style: TextStyle(color: textColor),
                inputFormatters: [noDigitsFormatter],
                decoration: field('Nombre', Icons.person_outlined))),
            const SizedBox(width: 12),
            Expanded(child: TextFormField(controller: _lastNameController, style: TextStyle(color: textColor),
                inputFormatters: [noDigitsFormatter],
                decoration: field('Apellido', Icons.person_outline))),
          ]),
          const SizedBox(height: 16),

          SizedBox(key: _keyStep1Email, height: 0),
          TextFormField(controller: _emailController, keyboardType: TextInputType.emailAddress,
              style: TextStyle(color: textColor), decoration: field('Correo electrónico', Icons.email_outlined)),
          const SizedBox(height: 16),

          SizedBox(key: _keyStep1Password, height: 0),
          TextFormField(controller: _passwordController, obscureText: true,
              style: TextStyle(color: textColor), decoration: field('Contraseña (mínimo 8 caracteres)', Icons.lock_outlined)),
          const SizedBox(height: 16),

          SizedBox(key: _keyStep1Phone, height: 0),
          TextFormField(controller: _phoneController, keyboardType: TextInputType.number,
              style: TextStyle(color: textColor), decoration: field('Teléfono (ej: 76543210)', Icons.phone_outlined)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text('8 dígitos, empieza con 6 o 7', style: TextStyle(color: subtextColor, fontSize: 12)),
          ),
          const SizedBox(height: 16),

          TextFormField(controller: _addressController,
              style: TextStyle(color: textColor), decoration: field('Dirección (opcional)', Icons.home_work_outlined)),
          const SizedBox(height: 16),

          TextFormField(
            controller: _bioController,
            maxLines: 4,
            maxLength: 500,
            style: TextStyle(color: textColor, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Describe tu experiencia con animales (mínimo 50 caracteres)',
              prefixIcon: Padding(
                padding: const EdgeInsets.only(bottom: 60),
                child: Icon(Icons.description_outlined, color: subtextColor, size: 20),
              ),
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2(Color textColor, Color subtextColor, Color borderColor, Color surfaceEl) {
    const zoneLabels = {
      'EQUIPETROL': 'Equipetrol',
      'URBARI': 'Urbari',
      'NORTE': 'Norte',
      'LAS_PALMAS': 'Las Palmas',
      'CENTRO_SAN_MARTIN': 'Centro/San Martín',
      'OTROS': 'Otros',
    };

    Widget serviceCard(String service, String emoji, String label) {
      final selected = _servicesOffered.contains(service);
      return GestureDetector(
        onTap: () => setState(() {
          if (selected) { _servicesOffered.remove(service); } else { _servicesOffered.add(service); }
        }),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: selected ? GardenColors.primary.withValues(alpha: 0.12) : surfaceEl,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? GardenColors.primary : borderColor, width: selected ? 2 : 1),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(emoji, style: const TextStyle(fontSize: 36)),
            const SizedBox(height: 10),
            Text(label, style: TextStyle(
              color: selected ? GardenColors.primary : textColor,
              fontWeight: FontWeight.w700, fontSize: 15,
            )),
          ]),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('¿Qué ofreces?', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: textColor, letterSpacing: -0.5)),
        const SizedBox(height: 6),
        Text('Selecciona los servicios que brindarás', style: TextStyle(fontSize: 14, color: subtextColor)),
        const SizedBox(height: 28),

        SizedBox(key: _keyStep2Services, height: 0),
        Text('Servicios', style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: serviceCard('HOSPEDAJE', '🏠', 'Hospedaje')),
          const SizedBox(width: 12),
          Expanded(child: serviceCard('PASEO', '🦮', 'Paseo')),
          const SizedBox(width: 12),
          Expanded(child: serviceCard('GUARDERIA', '🏡', 'Guardería')),
        ]),
        const SizedBox(height: 28),

        SizedBox(key: _keyStep2Zone, height: 0),
        Text('Zona en Santa Cruz', style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _selectedZone,
          dropdownColor: surfaceEl,
          style: TextStyle(color: textColor, fontSize: 14),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.location_on_outlined, color: subtextColor, size: 20),
          ),
          hint: Text('Selecciona tu zona', style: TextStyle(color: subtextColor)),
          items: zoneLabels.entries.map((e) => DropdownMenuItem(
            value: e.key,
            child: Text(e.value, style: TextStyle(color: textColor)),
          )).toList(),
          onChanged: (v) => setState(() => _selectedZone = v),
        ),

        if (_servicesOffered.contains('HOSPEDAJE')) ...[
          const SizedBox(height: 28),
          Text('Tu hogar', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textColor)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _homeType = 'HOUSE'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: _homeType == 'HOUSE' ? GardenColors.primary : surfaceEl,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _homeType == 'HOUSE' ? GardenColors.primary : borderColor),
                  ),
                  alignment: Alignment.center,
                  child: Text('Casa 🏡', style: TextStyle(
                    color: _homeType == 'HOUSE' ? Colors.white : textColor,
                    fontWeight: _homeType == 'HOUSE' ? FontWeight.bold : FontWeight.normal,
                  )),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _homeType = 'APARTMENT'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: _homeType == 'APARTMENT' ? GardenColors.primary : surfaceEl,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _homeType == 'APARTMENT' ? GardenColors.primary : borderColor),
                  ),
                  alignment: Alignment.center,
                  child: Text('Departamento 🏢', style: TextStyle(
                    color: _homeType == 'APARTMENT' ? Colors.white : textColor,
                    fontWeight: _homeType == 'APARTMENT' ? FontWeight.bold : FontWeight.normal,
                  )),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          SwitchListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Text('¿Tienes patio?', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
            value: _hasYard,
            onChanged: (val) => setState(() => _hasYard = val),
            activeColor: GardenColors.primary,
          ),
        ],
      ]),
    );
  }

  Widget _buildStep3(Color textColor, Color subtextColor, Color borderColor, Color surfaceEl) {
    Widget availSwitch(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: surfaceEl, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
        child: SwitchListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 15)),
          subtitle: Text(subtitle, style: TextStyle(color: subtextColor, fontSize: 12)),
          value: value,
          activeColor: GardenColors.primary,
          onChanged: onChanged,
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('¿Cuándo estás disponible?', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: textColor, letterSpacing: -0.5)),
        const SizedBox(height: 6),
        Text('Selecciona los días y horarios en que puedes cuidar mascotas', style: TextStyle(fontSize: 14, color: subtextColor)),
        const SizedBox(height: 28),

        SizedBox(key: _keyStep3Days, height: 0),
        Text('Días disponibles', style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        availSwitch('Días de semana', 'Lunes a Viernes', _weekdays, (v) => setState(() => _weekdays = v)),
        availSwitch('Fines de semana', 'Sábado y Domingo', _weekends, (v) => setState(() => _weekends = v)),
        availSwitch('Feriados', 'Días festivos nacionales', _holidays, (v) => setState(() => _holidays = v)),

        const SizedBox(height: 12),
        SizedBox(key: _keyStep3Times, height: 0),
        Text('Horarios', style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: [
            {'label': 'Mañana ☀️', 'value': 'MORNING'},
            {'label': 'Tarde 🌤️', 'value': 'AFTERNOON'},
            {'label': 'Noche 🌙', 'value': 'NIGHT'},
          ].map((item) {
            final val = item['value']!;
            final selected = _times.contains(val);
            return FilterChip(
              label: Text(item['label']!, style: TextStyle(
                color: selected ? GardenColors.primary : subtextColor,
                fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
              )),
              selected: selected,
              onSelected: (s) => setState(() { if (s) { _times.add(val); } else { _times.remove(val); } }),
              backgroundColor: surfaceEl,
              selectedColor: GardenColors.primary.withValues(alpha: 0.14),
              checkmarkColor: GardenColors.primary,
              side: BorderSide(color: selected ? GardenColors.primary.withValues(alpha: 0.5) : borderColor),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            );
          }).toList(),
        ),
      ]),
    );
  }

  Widget _buildStep4(Color textColor, Color subtextColor, Color borderColor, Color surfaceEl) {
    final isHospedaje = _servicesOffered.contains('HOSPEDAJE');
    final titulo = isHospedaje ? 'Fotos de tu espacio' : 'Fotos tuyas como cuidador';
    final subtitulo = isHospedaje
        ? 'Los dueños quieren ver dónde estará su mascota (mínimo 4 fotos)'
        : 'Muéstrate con mascotas o en actividades de paseo (mínimo 2 fotos)';
    final minFotos = isHospedaje ? 4 : 2;
    final maxFotos = isHospedaje ? 6 : 4;
    final total = _photoUrls.length + _localPhotos.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titulo, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: textColor, letterSpacing: -0.5)),
        const SizedBox(height: 4),
        Text(subtitulo, style: TextStyle(fontSize: 14, color: subtextColor)),
        const SizedBox(height: 16),

        if (_uploadingPhotos) ...[
          Text('Subiendo fotos...', style: TextStyle(color: GardenColors.primary, fontSize: 12)),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            backgroundColor: borderColor,
            valueColor: const AlwaysStoppedAnimation<Color>(GardenColors.primary),
          ),
          const SizedBox(height: 16),
        ],

        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: List.generate(maxFotos, (index) {
            if (index < _photoUrls.length) {
              return Stack(fit: StackFit.expand, children: [
                ClipRRect(borderRadius: BorderRadius.circular(12),
                    child: Image.network(fixImageUrl(_photoUrls[index]), fit: BoxFit.cover)),
                Positioned(top: 8, right: 8,
                    child: Container(decoration: const BoxDecoration(color: GardenColors.success, shape: BoxShape.circle),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(Icons.check, color: Colors.white, size: 14))),
                Positioned(bottom: 8, right: 8,
                    child: GestureDetector(
                      onTap: () => setState(() => _photoUrls.removeAt(index)),
                      child: Container(decoration: BoxDecoration(color: Colors.red.shade700, shape: BoxShape.circle),
                          padding: const EdgeInsets.all(4),
                          child: const Icon(Icons.close, color: Colors.white, size: 14)),
                    )),
              ]);
            }
            final localIndex = index - _photoUrls.length;
            if (localIndex >= 0 && localIndex < _localPhotos.length) {
              final photo = _localPhotos[localIndex];
              return Stack(fit: StackFit.expand, children: [
                ClipRRect(borderRadius: BorderRadius.circular(12),
                    child: Image.memory(photo.bytes, fit: BoxFit.cover)),
                Positioned(top: 8, right: 8,
                    child: Container(decoration: BoxDecoration(color: Colors.orange.shade700, shape: BoxShape.circle),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(Icons.cloud_upload_outlined, color: Colors.white, size: 14))),
                Positioned(bottom: 8, right: 8,
                    child: GestureDetector(
                      onTap: () => setState(() => _localPhotos.removeAt(localIndex)),
                      child: Container(decoration: BoxDecoration(color: Colors.red.shade700, shape: BoxShape.circle),
                          padding: const EdgeInsets.all(4),
                          child: const Icon(Icons.close, color: Colors.white, size: 14)),
                    )),
              ]);
            }
            return GestureDetector(
              onTap: (_isLoading || _uploadingPhotos) ? null : _pickPhoto,
              child: Container(
                decoration: BoxDecoration(
                  color: surfaceEl,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: GardenColors.primary.withValues(alpha: 0.3)),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.add_photo_alternate_outlined, color: GardenColors.primary, size: 40),
                  const SizedBox(height: 8),
                  Text('Añadir foto', style: TextStyle(color: subtextColor, fontSize: 12)),
                ]),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        Text(
          '$total/$maxFotos fotos · Mínimo $minFotos${_localPhotos.isNotEmpty ? " (${_localPhotos.length} pendientes de subir)" : ""}',
          style: TextStyle(
            color: _localPhotos.isNotEmpty ? Colors.orange.shade400 : subtextColor,
            fontSize: 12,
          ),
        ),
      ]),
    );
  }

  Widget _buildPriceCard({
    required String titulo, required String unidad, required String emoji,
    required double value, required ValueChanged<double> onChanged,
  }) {
    const double sliderMin = 50.0;
    const double sliderMax = 290.0;
    final double sv = value.clamp(sliderMin, sliderMax);
    final double ratio = (sv - sliderMin) / (sliderMax - sliderMin);
    final String posicion = ratio < 0.33 ? 'ECONÓMICO' : ratio < 0.66 ? 'ESTÁNDAR' : 'PREMIUM';
    final Color posicionColor = posicion == 'ECONÓMICO'
        ? const Color(0xFF2196F3) : posicion == 'PREMIUM' ? const Color(0xFFFFD700) : const Color(0xFF4CAF50);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: GardenColors.primary.withValues(alpha: 0.4)),
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 8),
          Text(titulo, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic, children: [
          const Text('Bs ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70)),
          Text(sv.toStringAsFixed(0), style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold, color: Colors.white)),
        ]),
        Text(unidad, style: const TextStyle(color: Colors.white60, fontSize: 13)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(color: posicionColor, borderRadius: BorderRadius.circular(20)),
          child: Text(posicion, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
              color: posicion == 'PREMIUM' ? Colors.black : Colors.white)),
        ),
        const SizedBox(height: 20),
        Slider(
          value: sv, min: sliderMin, max: sliderMax, divisions: 48,
          activeColor: GardenColors.primary, inactiveColor: Colors.white24, thumbColor: Colors.white,
          label: 'Bs ${sv.toStringAsFixed(0)}',
          onChanged: onChanged,
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Bs 50', style: TextStyle(color: Colors.white54, fontSize: 11)),
          const Text('Bs 290', style: TextStyle(color: Colors.white54, fontSize: 11)),
        ]),
      ]),
    );
  }

  Widget _buildStep5() {
    final offersHospedaje = _servicesOffered.contains('HOSPEDAJE');
    final offersPaseo = _servicesOffered.contains('PASEO');
    final offersGuarderia = _servicesOffered.contains('GUARDERIA');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [GardenColors.primary, Color(0xFF4A5E28)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(children: [
            Icon(Icons.payments_outlined, color: Colors.white, size: 36),
            SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Elige tus precios', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
              SizedBox(height: 4),
              Text('Ajusta la barra para fijar tu tarifa. Puedes cambiarlo después.',
                  style: TextStyle(fontSize: 12, color: Colors.white70)),
            ])),
          ]),
        ),
        const SizedBox(height: 24),
        if (offersHospedaje) ...[
          _buildPriceCard(titulo: 'Hospedaje', unidad: '/ noche', emoji: '🏠',
              value: _precioHospedaje, onChanged: (v) => setState(() => _precioHospedaje = v)),
          if (offersPaseo || offersGuarderia) const SizedBox(height: 20),
        ],
        if (offersPaseo) ...[
          _buildPriceCard(titulo: 'Paseo', unidad: '/ 1 hora', emoji: '🦮',
              value: _precioPaseo, onChanged: (v) => setState(() => _precioPaseo = v)),
          if (offersGuarderia) const SizedBox(height: 20),
        ],
        if (offersGuarderia)
          _buildPriceCard(titulo: 'Guardería', unidad: '/ hora', emoji: '🏡',
              value: _precioGuarderia, onChanged: (v) => setState(() => _precioGuarderia = v)),
      ]),
    );
  }

  Widget _buildStep6(Color textColor, Color subtextColor, Color surfaceEl) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Text('Tu retrato final',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: textColor, letterSpacing: -0.5)),
        const SizedBox(height: 10),
        Text(
          'Sube una foto tuya clara, sonriendo e idealmente con una mascota. Esta será la cara visible de tu negocio en GARDEN.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: subtextColor),
        ),
        const SizedBox(height: 40),
        GestureDetector(
          onTap: _pickProfilePhoto,
          child: Container(
            width: 200, height: 200,
            decoration: BoxDecoration(
              color: surfaceEl,
              shape: BoxShape.circle,
              border: Border.all(color: GardenColors.primary, width: 3),
              boxShadow: [BoxShadow(color: GardenColors.primary.withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 4)],
            ),
            child: ClipOval(
              child: _localProfilePhoto != null
                  ? Image.memory(_localProfilePhoto!.bytes, fit: BoxFit.cover)
                  : (_profilePhotoUrl != null
                      ? Image.network(fixImageUrl(_profilePhotoUrl!), fit: BoxFit.cover)
                      : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.camera_alt_outlined, size: 56, color: subtextColor),
                          const SizedBox(height: 10),
                          Text('Subir foto', style: TextStyle(color: subtextColor, fontWeight: FontWeight.w600, fontSize: 14)),
                        ])),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Toca para seleccionar foto', style: TextStyle(color: subtextColor, fontSize: 12)),
        const SizedBox(height: 24),
        if (_localProfilePhoto != null || _profilePhotoUrl != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: GardenColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: GardenColors.success.withValues(alpha: 0.3)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle_rounded, color: GardenColors.success, size: 20),
              SizedBox(width: 8),
              Text('¡Excelente elección! Estás listo para continuar.',
                  style: TextStyle(color: GardenColors.success, fontSize: 14, fontWeight: FontWeight.w600)),
            ]),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final bg          = isDark ? GardenColors.darkBackground       : GardenColors.lightBackground;
        final surface     = isDark ? GardenColors.darkSurface          : GardenColors.lightSurface;
        final surfaceEl   = isDark ? GardenColors.darkSurfaceElevated  : GardenColors.lightSurfaceElevated;
        final textColor   = isDark ? GardenColors.darkTextPrimary      : GardenColors.lightTextPrimary;
        final subtextColor= isDark ? GardenColors.darkTextSecondary    : GardenColors.lightTextSecondary;
        final borderColor = isDark ? GardenColors.darkBorder           : GardenColors.lightBorder;

        // Step 7: CaregiverProfileDataScreen handles its own UI and "save" button.
        // After save it calls _registerProfessional.
        if (_currentStep == 7) {
          return Theme(
            data: ThemeData(
              colorScheme: isDark
                  ? ColorScheme.dark(primary: GardenColors.primary, secondary: GardenColors.primary,
                      surface: GardenColors.darkSurface, onSurface: GardenColors.darkTextPrimary, onPrimary: Colors.white)
                  : const ColorScheme.light(primary: GardenColors.primary, secondary: GardenColors.primary,
                      surface: GardenColors.lightSurface, onSurface: GardenColors.lightTextPrimary, onPrimary: Colors.white),
              scaffoldBackgroundColor: bg,
            ),
            child: CaregiverProfileDataScreen(
              embeddedMode: true,
              onSaveComplete: () async {
                // After profile data saved, create the account
                await _registerProfessional();
              },
            ),
          );
        }

        final stepTitles = [
          'Código de acceso',
          'Datos básicos',
          'Servicios',
          'Disponibilidad',
          'Fotos',
          'Precio',
          'Tu retrato',
          'Perfil profesional',
        ];

        Widget stepContent;
        switch (_currentStep) {
          case 0: stepContent = _buildStep0(textColor, subtextColor, surfaceEl, borderColor); break;
          case 1: stepContent = _buildStep1(textColor, subtextColor, borderColor, surfaceEl); break;
          case 2: stepContent = _buildStep2(textColor, subtextColor, borderColor, surfaceEl); break;
          case 3: stepContent = _buildStep3(textColor, subtextColor, borderColor, surfaceEl); break;
          case 4: stepContent = _buildStep4(textColor, subtextColor, borderColor, surfaceEl); break;
          case 5: stepContent = _buildStep5(); break;
          case 6: stepContent = _buildStep6(textColor, subtextColor, surfaceEl); break;
          default: stepContent = const SizedBox.shrink();
        }

        final totalSteps = 8;
        final isRegistrationStep = _currentStep == 0;
        final buttonLabel = _currentStep == 0 ? 'Verificar código' :
            _currentStep == 6 ? 'Continuar →' : 'Siguiente →';

        return Theme(
          data: ThemeData(
            colorScheme: isDark
                ? ColorScheme.dark(primary: GardenColors.primary, secondary: GardenColors.primary,
                    surface: GardenColors.darkSurface, onSurface: GardenColors.darkTextPrimary, onPrimary: Colors.white)
                : const ColorScheme.light(primary: GardenColors.primary, secondary: GardenColors.primary,
                    surface: GardenColors.lightSurface, onSurface: GardenColors.lightTextPrimary, onPrimary: Colors.white),
            scaffoldBackgroundColor: bg,
            appBarTheme: AppBarTheme(
              backgroundColor: surface,
              foregroundColor: textColor,
              elevation: 0,
              iconTheme: IconThemeData(color: textColor),
              titleTextStyle: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: surfaceEl,
              hintStyle: TextStyle(color: subtextColor),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
            ),
            switchTheme: SwitchThemeData(
              thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? GardenColors.primary : subtextColor),
              trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? GardenColors.primary.withValues(alpha: 0.35) : borderColor),
            ),
          ),
          child: Scaffold(
            backgroundColor: bg,
            appBar: kIsWeb ? null : AppBar(
              title: const Text('Registro Profesional'),
              automaticallyImplyLeading: _currentStep > 0,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(
                  value: (_currentStep + 1) / totalSteps,
                  backgroundColor: borderColor,
                  valueColor: const AlwaysStoppedAnimation<Color>(GardenColors.primary),
                  minHeight: 4,
                ),
              ),
            ),
            body: Column(
              children: [
                // Web top bar
                if (kIsWeb)
                  Container(
                    decoration: BoxDecoration(color: surface, border: Border(bottom: BorderSide(color: borderColor))),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 620),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: Column(children: [
                            Row(children: [
                              if (_currentStep > 0)
                                GestureDetector(
                                  onTap: _prevStep,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
                                    child: Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: subtextColor),
                                  ),
                                )
                              else
                                const SizedBox(width: 26),
                              const SizedBox(width: 8),
                              Text('Registro Profesional', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w700)),
                              const Spacer(),
                              Text('Paso ${_currentStep + 1} de $totalSteps', style: TextStyle(color: subtextColor, fontSize: 11)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: GardenColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                                child: Text(stepTitles[_currentStep], style: const TextStyle(color: GardenColors.primary, fontSize: 10, fontWeight: FontWeight.w700)),
                              ),
                            ]),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: (_currentStep + 1) / totalSteps,
                                backgroundColor: borderColor,
                                valueColor: const AlwaysStoppedAnimation<Color>(GardenColors.primary),
                                minHeight: 3,
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),

                // Mobile step indicator
                if (!kIsWeb) ...[
                  Container(
                    color: surface,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Paso ${_currentStep + 1} de $totalSteps',
                            style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w500)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: GardenColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: GardenColors.primary.withValues(alpha: 0.3)),
                          ),
                          child: Text(stepTitles[_currentStep],
                              style: const TextStyle(color: GardenColors.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                  Container(height: 1, color: borderColor),
                ],

                Expanded(
                  child: kIsWeb
                      ? Center(child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 620),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: KeyedSubtree(key: ValueKey(_currentStep), child: stepContent),
                          ),
                        ))
                      : AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: KeyedSubtree(key: ValueKey(_currentStep), child: stepContent),
                        ),
                ),

                Container(height: 1, color: borderColor),
                Container(
                  color: surface,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: kIsWeb ? 620 : double.infinity),
                      child: Row(
                        children: [
                          if (_currentStep > 0 && !kIsWeb) ...[
                            SizedBox(
                              width: 110,
                              child: GardenButton(label: 'Anterior', outline: true, height: 48, onPressed: _prevStep),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: GardenButton(
                              label: buttonLabel,
                              loading: _isLoading,
                              height: kIsWeb ? 44 : 48,
                              onPressed: _isLoading ? () {} : _nextStep,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).padding.bottom),
              ],
            ),
          ),
        );
      },
    );
  }
}
