import 'dart:convert';
import 'package:image_picker/image_picker.dart' as image_picker_pkg;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';
import '../../theme/garden_theme.dart' show fixImageUrl, GardenColors;
import '../../services/auth_service.dart';
import '../../services/agentes_service.dart';
import '../../widgets/precio_onboarding_card.dart';
import 'caregiver_profile_data_screen.dart';
import 'verification_screen.dart';
import 'email_verification_screen.dart';

class OnboardingWizardScreen extends StatefulWidget {
  final String initialEmail;
  final String initialPassword;
  /// When true, the wizard will query the backend on load to jump to the
  /// first incomplete post-registration step (6-9). Set to true when
  /// navigating from the home screen's "Continuar registro" button.
  final bool resumeMode;

  const OnboardingWizardScreen({
    super.key,
    this.initialEmail = '',
    this.initialPassword = '',
    this.resumeMode = false,
  });

  @override
  State<OnboardingWizardScreen> createState() => _OnboardingWizardScreenState();
}

class _OnboardingWizardScreenState extends State<OnboardingWizardScreen> {
  int _currentStep = 0;
  bool _isLoading = false;

  // Paso 1: Datos personales
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bioController = TextEditingController();
  final _addressController = TextEditingController();

  // Paso 6: Perfil Profesional
  final List<String> _sizesAccepted = [];
  final List<String> _animalTypes = ['DOGS'];
  int _experienceYears = 1;
  bool _ownPets = false;
  bool _acceptPuppies = false;
  bool _acceptSeniors = false;

  // Paso 5 (nueva pos): Foto de Perfil
  String? _profilePhotoUrl;
  XFile? _localProfilePhoto;
  DateTime? _dateOfBirth;

  // Paso 2: Fotos del hogar
  List<String> _photoUrls = [];       // URLs confirmadas en el servidor
  List<XFile> _localPhotos = [];      // fotos seleccionadas localmente, pendientes de subir
  bool _uploadingPhotos = false;

  // Paso 3: Tipo de servicio y zona
  final List<String> _servicesOffered = [];
  String? _selectedZone;
  String? _homeType;
  bool _hasYard = false;

  // Paso 4: Disponibilidad
  bool _weekdays = false;
  bool _weekends = false;
  bool _holidays = false;
  final List<String> _times = [];

  // Paso 5: Precio
  double _precioFinal = 0;
  String _authToken = '';
  Map<String, dynamic>? _priceStats;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail;
    _passwordController.text = widget.initialPassword;
    _loadToken();
    _loadPriceStats();
  }

  Future<void> _loadPriceStats() async {
    try {
      final service = _servicesOffered.isNotEmpty ? _servicesOffered.first : 'PASEO';
      final zone = _selectedZone ?? 'EQUIPETROL';
      final url = '${const String.fromEnvironment('API_URL', defaultValue: 'https://garden-api-1ldd.onrender.com/api')}/caregivers/price-stats?zone=$zone&service=$service';
      final res = await http.get(Uri.parse(url));
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        setState(() => _priceStats = data['data'] as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    String token = prefs.getString('access_token') ?? '';

    if (token.isEmpty) {
      token = const String.fromEnvironment('TEST_JWT', defaultValue: '');
    }

    setState(() => _authToken = token);

    // Only compute resume step when explicitly navigating back from home screen.
    // This prevents overriding the user's manual step navigation mid-wizard.
    if (token.isNotEmpty && widget.resumeMode) {
      await _computeAndSetResumeStep(token);
    }
  }

  static const _baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://garden-api-1ldd.onrender.com/api',
  );

  /// For returning users: load profile and jump to the first incomplete step (6-9).
  Future<void> _computeAndSetResumeStep(String token) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/caregiver/my-profile'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] != true) return;
      final profile = data['data'] as Map<String, dynamic>;

      // Step 6: Professional profile (CaregiverProfileDataScreen)
      final bio = (profile['bio'] as String? ?? '').trim();
      final bioDetail = (profile['bioDetail'] as String? ?? '').trim();
      final experienceDesc = (profile['experienceDescription'] as String? ?? '').trim();
      final whyCaregiver = (profile['whyCaregiver'] as String? ?? '').trim();
      final whatDiffers = (profile['whatDiffers'] as String? ?? '').trim();
      final handleAnxious = (profile['handleAnxious'] as String? ?? '').trim();
      final emergencyResponse = (profile['emergencyResponse'] as String? ?? '').trim();
      final sizesAccepted = (profile['sizesAccepted'] as List?) ?? [];
      final animalTypes = (profile['animalTypes'] as List?) ?? [];

      final profileComplete = bio.length >= 45 &&
          bioDetail.length >= 3 &&
          experienceDesc.length >= 15 &&
          whyCaregiver.length >= 3 &&
          whatDiffers.length >= 3 &&
          handleAnxious.isNotEmpty &&
          emergencyResponse.isNotEmpty &&
          sizesAccepted.isNotEmpty &&
          animalTypes.isNotEmpty;

      if (!profileComplete) {
        setState(() => _currentStep = 6);
        return;
      }

      // Step 7: Verificación de identidad — requiere identityVerificationStatus VERIFIED
      final identityStatus = (profile['identityVerificationStatus'] as String? ?? '').toUpperCase();
      if (identityStatus != 'VERIFIED' && identityStatus != 'APPROVED') {
        setState(() => _currentStep = 7);
        return;
      }

      // Step 8: Verificación de email — requiere emailVerified true
      final emailVerified = profile['emailVerified'] == true;
      final userEmailVerified = (profile['user'] as Map<String, dynamic>?)?['emailVerified'] == true;
      if (!emailVerified && !userEmailVerified) {
        setState(() => _currentStep = 8);
        return;
      }

      // Step 9: Availability — check if any availability has been configured
      final availSet = profile['availabilityConfigured'] == true ||
          profile['hasServiceAvailability'] == true;
      if (!availSet) {
        setState(() => _currentStep = 9);
        return;
      }

      // All steps complete — put user on step 9 so they can confirm and submit
      setState(() => _currentStep = 9);
    } catch (_) {
      // If error, stay at step 0 (new registration)
    }
  }

  void _advanceStep() {
    if (_currentStep >= 9) {
      _completeWizard();
    } else {
      setState(() => _currentStep++);
    }
  }

  Future<void> _completeWizard() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/caregiver/submit'),
        headers: {
          'Authorization': 'Bearer $_authToken',
          'Content-Type': 'application/json',
        },
      );

      // Guard against HTML error pages (502/503 from server)
      Map<String, dynamic> body = {};
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        // Server returned non-JSON (e.g. HTML 502 page) — treat as server error
        setState(() => _isLoading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('El servidor no está disponible (${response.statusCode}). Intenta de nuevo en unos segundos.'),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }

      if (response.statusCode == 200 && body['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('caregiver_setup_complete', true);
        if (!mounted) return;
        context.go('/caregiver/home');
      } else {
        setState(() => _isLoading = false);
        final errorMsg = body['error']?['message'] ?? body['message'] ?? 'No se pudo completar el registro';
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 8),
          ),
        );
        // Do NOT auto-redirect — user stays on current step and sees the error.
        // They can manually go back to the indicated step.
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sin conexión al servidor. Verifica tu internet e intenta de nuevo.'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    _addressController.dispose();
    _whyCaregiverController.dispose();
    _whatDiffersController.dispose();
    _handleAnxiousController.dispose();
    _emergencyResponseController.dispose();
    _breedsWhyController.dispose();
    _typicalDayController.dispose();
    _bioDetailController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        if (_firstNameController.text.trim().isEmpty ||
            _lastNameController.text.trim().isEmpty ||
            _emailController.text.trim().isEmpty ||
            _passwordController.text.isEmpty ||
            _phoneController.text.trim().isEmpty ||
            _addressController.text.trim().isEmpty ||
            _dateOfBirth == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Completa todos los campos requeridos')),
          );
          return false;
        }
        if (_bioController.text.trim().length < 50) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('La descripción debe tener al menos 50 caracteres')),
          );
          return false;
        }
        return true;
      case 1:
        if (_servicesOffered.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Selecciona al menos un servicio')),
          );
          return false;
        }
        if (_selectedZone == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Selecciona tu zona en Santa Cruz')),
          );
          return false;
        }
        return true;
      case 2:
        if (!_weekdays && !_weekends && !_holidays) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Selecciona al menos un día disponible')),
          );
          return false;
        }
        if (_times.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Selecciona al menos un horario')),
          );
          return false;
        }
        return true;
      case 3:
        final minFotos = _servicesOffered.contains('HOSPEDAJE') ? 4 : 2;
        if (_photoUrls.length < minFotos) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Sube al menos $minFotos fotos para continuar')),
          );
          return false;
        }
        return true;
      case 4:
        if (_precioFinal <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Por favor, selecciona o acepta un precio razonable')),
          );
          return false;
        }
        return true;
      case 5: // Foto de perfil (retrato) — triggers registration
        if (_profilePhotoUrl == null && _localProfilePhoto == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Por favor, sube una foto de perfil profesional')),
          );
          return false;
        }
        return true;
      default:
        return true; // Steps 6-9 handled by embedded screens
    }
  }

  Future<void> _nextStep() async {
    // Paso de fotos (index 3): subir antes de validar
    if (_currentStep == 3) {
      final minFotos = _servicesOffered.contains('HOSPEDAJE') ? 4 : 2;
      final total = _localPhotos.length + _photoUrls.length;
      if (total == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sube al menos $minFotos fotos para continuar')),
        );
        return;
      }
      if (_localPhotos.isNotEmpty) {
        try {
          await _uploadAllPhotos();
        } catch (_) {
          return;
        }
      }
      if (_photoUrls.length < minFotos) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Necesitas al menos $minFotos fotos')),
        );
        return;
      }
      setState(() => _currentStep++);
      return;
    }

    // Paso de foto de perfil (index 5): validar y crear cuenta
    if (_currentStep == 5) {
      if (!_validateCurrentStep()) return;
      await _submitWizard(); // creates account, then advances to step 6
      return;
    }

    if (!_validateCurrentStep()) return;
    if (_currentStep < 9) {
      setState(() => _currentStep++);
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    // Usar image_picker para seleccionar fotos (compatible con web y móvil)
    final isHospedaje = _servicesOffered.contains('HOSPEDAJE');
    final maxFotos = isHospedaje ? 6 : 4;
    if (_localPhotos.length + _photoUrls.length >= maxFotos) return;

    final picked = await image_picker_pkg.ImagePicker().pickImage(
      source: image_picker_pkg.ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _localPhotos.add(XFile.fromData(
        Uint8List.fromList(bytes),
        name: picked.name.isEmpty ? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg' : picked.name,
        mimeType: 'image/jpeg',
      ));
    });
  }

  Future<void> _uploadAllPhotos() async {
    if (_localPhotos.isEmpty) return;
    setState(() => _uploadingPhotos = true);
    try {
      final uri = Uri.parse(
        '${const String.fromEnvironment('API_URL', defaultValue: 'https://garden-api-1ldd.onrender.com/api')}/upload/registration-photos',
      );
      final request = http.MultipartRequest('POST', uri);
      for (final photo in _localPhotos) {
        final bytes = await photo.readAsBytes();
        final fileName = photo.name.isEmpty
            ? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg'
            : photo.name;

        // Normalizar el mimeType para que el backend lo acepte
        String mimeType = photo.mimeType ?? '';
        if (mimeType == 'image/jpg' || mimeType.isEmpty) {
          mimeType = 'image/jpeg';
        }
        // Forzar jpeg si el nombre termina en .jpg
        if (fileName.toLowerCase().endsWith('.jpg')) {
          mimeType = 'image/jpeg';
        }
        if (fileName.toLowerCase().endsWith('.png')) {
          mimeType = 'image/png';
        }

        request.files.add(
          http.MultipartFile.fromBytes(
            'photos',
            bytes,
            filename: fileName,
            contentType: MediaType.parse(mimeType),
          ),
        );
      }
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        final raw = data['data']['urls'];
        final urls = raw is List ? raw.cast<String>() : [raw.toString()];
        setState(() {
          _photoUrls = urls;
          _localPhotos = [];
        });
      } else {
        // ignore: avoid_print
        print('ERROR UPLOAD BODY: ${response.body}');
        throw Exception(data['message'] ?? data['error']?['message'] ?? 'Error al subir fotos: ${response.body}');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      rethrow;
    } finally {
      if (mounted) setState(() => _uploadingPhotos = false);
    }
  }


  Future<void> _submitWizard() async {
    if (!_validateCurrentStep()) return;
    setState(() => _isLoading = true);
    
    // Si hay foto de perfil local, subirla primero
    if (_localProfilePhoto != null && _profilePhotoUrl == null) {
      try {
        final uri = Uri.parse('${const String.fromEnvironment('API_URL', defaultValue: 'https://garden-api-1ldd.onrender.com/api')}/upload/public-single-photo');
        final request = http.MultipartRequest('POST', uri);
        final bytes = await _localProfilePhoto!.readAsBytes();
        
        String mimeType = _localProfilePhoto!.mimeType ?? '';
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
          final raw = data['data']['url'];
          _profilePhotoUrl = raw.toString();
        } else {
          throw Exception('Error subiendo foto perfil');
        }
      } catch (e) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error foto perfil: $e')));
        return;
      }
    }

    try {
      final availabilityItem = {

        'weekdays': _weekdays,
        'weekends': _weekends,
        'holidays': _holidays,
        'times': _times, // ['MORNING', 'AFTERNOON', 'NIGHT']
        'lastMinute': false,
      };

      final serviceAvailability = <String, dynamic>{};
      if (_servicesOffered.contains('HOSPEDAJE')) {
        serviceAvailability['HOSPEDAJE'] = availabilityItem;
      }
      if (_servicesOffered.contains('PASEO')) {
        serviceAvailability['PASEO'] = availabilityItem;
      }

      // Construir el body completo
      final body = {
        'user': {
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
          'firstName': _firstNameController.text.trim(),
          'lastName': _lastNameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'dateOfBirth': _dateOfBirth!.toIso8601String(),
          'country': 'Bolivia',
          'city': 'Santa Cruz de la Sierra',
          'isOver18': true,
        },
        'profile': {
          'bio': _bioController.text.trim(),
          'zone': _selectedZone,
          'servicesOffered': _servicesOffered,
          'photos': _photoUrls,
          'serviceAvailability': serviceAvailability,
          if (_servicesOffered.contains('HOSPEDAJE'))
            'pricePerDay': _precioFinal.toInt(),
          if (_servicesOffered.contains('PASEO'))
            'pricePerWalk60': _precioFinal.toInt(),
          if (_homeType != null) 'homeType': _homeType,
          'hasYard': _hasYard,
          'address': _addressController.text.trim(),
          'sizesAccepted': _sizesAccepted,
          'animalTypes': _animalTypes,
          'experienceYears': _experienceYears,
          'ownPets': _ownPets,
          'acceptPuppies': _acceptPuppies,
          'acceptSeniors': _acceptSeniors,
                    if (_profilePhotoUrl != null) 'profilePhoto': _profilePhotoUrl,
          'caredOthers': _caredOthers,
          if (_whyCaregiverController.text.trim().length >= 5)
            'whyCaregiver': _whyCaregiverController.text.trim(),
          if (_whatDiffersController.text.trim().length >= 5)
            'whatDiffers': _whatDiffersController.text.trim(),
          if (_handleAnxiousController.text.trim().length >= 5)
            'handleAnxious': _handleAnxiousController.text.trim(),
          if (_emergencyResponseController.text.trim().length >= 5)
            'emergencyResponse': _emergencyResponseController.text.trim(),
          'acceptAggressive': _acceptAggressive,
          'hasChildren': _hasChildren,
          'petsSleep': 'INSIDE',
          'hoursAlone': _hoursAlone,
          'workFromHome': _workFromHome,
          'maxPets': _maxPets,
          'oftenOut': _oftenOut,
          if (_typicalDayController.text.trim().length >= 5)
            'typicalDay': _typicalDayController.text.trim(),
          if (_bioDetailController.text.trim().length >= 5)
            'bioDetail': _bioDetailController.text.trim(),
        },
      };

      final response = await http.post(
        Uri.parse(
          '${const String.fromEnvironment('API_URL', defaultValue: 'https://garden-api-1ldd.onrender.com/api')}/auth/caregiver/register',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201 && data['success'] == true) {
        // Save token and user data
        final authService = AuthService();
        await authService.saveToken(data['data']['accessToken']);
        await authService.saveUserData(data['data']['user']);

        // Update local token so post-registration steps can use the API
        setState(() => _authToken = data['data']['accessToken'] as String? ?? _authToken);

        if (!mounted) return;

        // Seamlessly advance to step 6 (Professional Profile)
        setState(() => _currentStep = 6);

      } else {
        // Manejo de errores de validación
        if (data['errors'] != null) {
          final errors = (data['errors'] as List)
              .map((e) => '${e['field']}: ${e['message']}')
              .join('\n');
          throw Exception(errors);
        }
        throw Exception(
          data['error']?['message'] ?? data['message'] ?? 'Error al crear perfil',
        );
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Error al registrarse'),
          ]),
          content: SingleChildScrollView(
            child: Text(msg, style: const TextStyle(fontSize: 14)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── PASO 1: Datos personales ──────────────────────────────
  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cuéntanos sobre ti',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: GardenColors.lightTextPrimary),
          ),
          const SizedBox(height: 4),
          const Text(
            'Esta información aparecerá en tu perfil',
            style: TextStyle(fontSize: 14, color: kTextSecondary),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _firstNameController,
            decoration: const InputDecoration(
              hintText: 'Nombre',
              prefixIcon: Icon(Icons.person_outlined, color: kTextSecondary),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _lastNameController,
            decoration: const InputDecoration(
              hintText: 'Apellido',
              prefixIcon: Icon(Icons.person_outlined, color: kTextSecondary),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              hintText: 'Correo electrónico',
              prefixIcon: Icon(Icons.email_outlined, color: kTextSecondary),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              hintText: 'Contraseña (mínimo 8 caracteres)',
              prefixIcon: Icon(Icons.lock_outlined, color: kTextSecondary),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: 'Teléfono (ej: 76543210)',
              prefixIcon: Icon(Icons.phone_outlined, color: kTextSecondary),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _addressController,
            decoration: const InputDecoration(
              hintText: 'Dirección completa',
              prefixIcon: Icon(Icons.home_work_outlined, color: kTextSecondary),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            tileColor: GardenColors.lightSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: GardenColors.lightBorder),
            ),
            leading: const Icon(Icons.cake_outlined, color: kTextSecondary),
            title: Text(
              _dateOfBirth == null ? 'Fecha de nacimiento' : _formatDate(_dateOfBirth!),
              style: TextStyle(
                color: _dateOfBirth == null ? GardenColors.lightTextHint : GardenColors.lightTextPrimary,
              ),
            ),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime(2000),
                firstDate: DateTime(1940),
                lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
                builder: (context, child) {
                  return Theme(
                    data: ThemeData.dark().copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: kPrimaryColor,
                        onPrimary: Colors.white,
                        surface: Color(0xFF1A2E10),
                        onSurface: Colors.white,
                      ),
                      dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF162610)),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null) setState(() => _dateOfBirth = picked);
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _bioController,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(
              hintText: 'Describe tu experiencia con animales (mínimo 50 caracteres)',
              prefixIcon: Padding(
                padding: EdgeInsets.only(bottom: 64),
                child: Icon(Icons.description_outlined, color: kTextSecondary),
              ),
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  // ── PASO 2 (index 2): Fotos adaptadas al servicio ────────
  Widget _buildStep2() {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: GardenColors.lightTextPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            subtitulo,
            style: const TextStyle(fontSize: 14, color: kTextSecondary),
          ),
          const SizedBox(height: 16),

          // Barra de progreso de subida
          if (_uploadingPhotos) ...
            [
              const Text(
                'Subiendo fotos...',
                style: TextStyle(color: kPrimaryColor, fontSize: 12),
              ),
              const SizedBox(height: 6),
              const LinearProgressIndicator(
                backgroundColor: kSurfaceColor,
                valueColor: AlwaysStoppedAnimation<Color>(kPrimaryColor),
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
              // Celda con foto ya subida al servidor (URL confirmada)
              if (index < _photoUrls.length) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        fixImageUrl(_photoUrls[index]),
                        fit: BoxFit.cover,
                      ),
                    ),
                    // Check verde: foto subida con éxito
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(Icons.check, color: Colors.white, size: 14),
                      ),
                    ),
                    // Botón de eliminar
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => setState(() => _photoUrls.removeAt(index)),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.red.shade700,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(4),
                          child: const Icon(Icons.close, color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                  ],
                );
              }

              // Celda con foto local pendiente de subir
              final localIndex = index - _photoUrls.length;
              if (localIndex >= 0 && localIndex < _localPhotos.length) {
                return FutureBuilder<Uint8List>(
                  future: _localPhotos[localIndex].readAsBytes(),
                  builder: (ctx, snap) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: snap.hasData
                              ? Image.memory(snap.data!, fit: BoxFit.cover)
                              : Container(color: kSurfaceColor),
                        ),
                        // Ícono de nube: pendiente de subir
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.orange.shade700,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(4),
                            child: const Icon(Icons.cloud_upload_outlined, color: Colors.white, size: 14),
                          ),
                        ),
                        // Botón de eliminar local
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: () => setState(() => _localPhotos.removeAt(localIndex)),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.red.shade700,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(4),
                              child: const Icon(Icons.close, color: Colors.white, size: 14),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              }

              // Celda vacía — botón para añadir
              return GestureDetector(
                onTap: (_isLoading || _uploadingPhotos) ? null : _pickAndUploadPhoto,
                child: Container(
                  decoration: BoxDecoration(
                    color: kSurfaceColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kPrimaryColor.withOpacity(0.3)),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        color: kPrimaryColor,
                        size: 40,
                      ),
                      SizedBox(height: 8),
                      Text('Añadir foto', style: TextStyle(color: kTextSecondary, fontSize: 12)),
                    ],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          Text(
            '$total/$maxFotos fotos · Mínimo $minFotos${_localPhotos.isNotEmpty ? " (${_localPhotos.length} pendientes de subir)" : ""}',
            style: TextStyle(
              color: _localPhotos.isNotEmpty ? Colors.orange.shade400 : kTextSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ── PASO 3: Servicios y zona ──────────────────────────────
  Widget _buildStep3() {
    const zoneLabels = {
      'EQUIPETROL': 'Equipetrol',
      'URBARI': 'Urbari',
      'NORTE': 'Norte',
      'LAS_PALMAS': 'Las Palmas',
      'CENTRO_SAN_MARTIN': 'Centro/San Martín',
      'OTROS': 'Otros',
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '¿Qué ofreces?',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: GardenColors.lightTextPrimary),
          ),
          const SizedBox(height: 24),

          // Servicios
          const Text('Servicios', style: TextStyle(color: kTextSecondary, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_servicesOffered.contains('HOSPEDAJE')) {
                        _servicesOffered.remove('HOSPEDAJE');
                      } else {
                        _servicesOffered.add('HOSPEDAJE');
                      }
                    });
                    _loadPriceStats();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: kSurfaceColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _servicesOffered.contains('HOSPEDAJE')
                            ? kPrimaryColor
                            : kSurfaceColor,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        const Text('🏠', style: TextStyle(fontSize: 32)),
                        const SizedBox(height: 8),
                        Text(
                          'Hospedaje',
                          style: TextStyle(
                            color: _servicesOffered.contains('HOSPEDAJE') ? kPrimaryColor : GardenColors.lightTextPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_servicesOffered.contains('PASEO')) {
                        _servicesOffered.remove('PASEO');
                      } else {
                        _servicesOffered.add('PASEO');
                      }
                    });
                    _loadPriceStats();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: kSurfaceColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _servicesOffered.contains('PASEO')
                            ? kPrimaryColor
                            : kSurfaceColor,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        const Text('🦮', style: TextStyle(fontSize: 32)),
                        const SizedBox(height: 8),
                        Text(
                          'Paseo',
                          style: TextStyle(
                            color: _servicesOffered.contains('PASEO') ? kPrimaryColor : GardenColors.lightTextPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Zona
          const Text('Zona en Santa Cruz', style: TextStyle(color: kTextSecondary, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedZone,
            dropdownColor: kSurfaceColor,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.location_on_outlined, color: kTextSecondary),
            ),
            hint: const Text('Selecciona tu zona', style: TextStyle(color: kTextSecondary)),
            items: zoneLabels.entries.map((e) => DropdownMenuItem(
              value: e.key,
              child: Text(e.value, style: const TextStyle(color: GardenColors.lightTextPrimary)),
            )).toList(),
            onChanged: (v) {
              setState(() => _selectedZone = v);
              _loadPriceStats();
            },
          ),

          // Solo mostrar opciones de hogar si ofrece HOSPEDAJE
          if (_servicesOffered.contains('HOSPEDAJE')) ...[
            const SizedBox(height: 24),
            const Text(
              'Tu hogar',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: GardenColors.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _homeType = 'HOUSE'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _homeType == 'HOUSE' ? kPrimaryColor : kSurfaceColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _homeType == 'HOUSE'
                              ? kPrimaryColor
                              : Colors.white.withOpacity(0.1),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Casa 🏡',
                        style: TextStyle(
                          color: _homeType == 'HOUSE' ? Colors.white : kTextSecondary,
                          fontWeight: _homeType == 'HOUSE'
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
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
                        color: _homeType == 'APARTMENT' ? kPrimaryColor : kSurfaceColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _homeType == 'APARTMENT'
                              ? kPrimaryColor
                              : Colors.white.withOpacity(0.1),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Departamento 🏢',
                        style: TextStyle(
                          color: _homeType == 'APARTMENT' ? Colors.white : kTextSecondary,
                          fontWeight: _homeType == 'APARTMENT'
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              tileColor: GardenColors.lightSurface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: const Text('¿Tienes patio?', style: TextStyle(color: GardenColors.lightTextPrimary)),
              value: _hasYard,
              onChanged: (val) => setState(() => _hasYard = val),
              activeColor: kPrimaryColor,
            ),
          ],
        ],
      ),
    );
  }

  // ── PASO 4: Disponibilidad ────────────────────────────────
  Widget _buildStep4() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '¿Cuándo estás disponible?',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: GardenColors.lightTextPrimary),
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            tileColor: GardenColors.lightSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text('Días de semana', style: TextStyle(color: GardenColors.lightTextPrimary)),
            subtitle: const Text('Lunes a Viernes', style: TextStyle(color: kTextSecondary, fontSize: 12)),
            value: _weekdays,
            activeColor: kPrimaryColor,
            onChanged: (v) => setState(() => _weekdays = v),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            tileColor: GardenColors.lightSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text('Fines de semana', style: TextStyle(color: GardenColors.lightTextPrimary)),
            subtitle: const Text('Sábado y Domingo', style: TextStyle(color: kTextSecondary, fontSize: 12)),
            value: _weekends,
            activeColor: kPrimaryColor,
            onChanged: (v) => setState(() => _weekends = v),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            tileColor: GardenColors.lightSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text('Feriados', style: TextStyle(color: GardenColors.lightTextPrimary)),
            subtitle: const Text('Días festivos nacionales', style: TextStyle(color: kTextSecondary, fontSize: 12)),
            value: _holidays,
            activeColor: kPrimaryColor,
            onChanged: (v) => setState(() => _holidays = v),
          ),
          const SizedBox(height: 24),
          const Text('Horarios', style: TextStyle(color: kTextSecondary, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              {'label': 'Mañana ☀️', 'value': 'MORNING'},
              {'label': 'Tarde 🌤️', 'value': 'AFTERNOON'},
              {'label': 'Noche 🌙', 'value': 'NIGHT'},
            ].map((item) {
              final val = item['value']!;
              return FilterChip(
                label: Text(item['label']!),
                selected: _times.contains(val),
                onSelected: (selected) => setState(() {
                  if (selected) {
                    _times.add(val);
                  } else {
                    _times.remove(val);
                  }
                }),
                backgroundColor: kSurfaceColor,
                selectedColor: GardenColors.primary.withValues(alpha: 0.18),
                labelStyle: TextStyle(
                  color: _times.contains(val) ? GardenColors.primary : kTextSecondary,
                  fontWeight: _times.contains(val) ? FontWeight.bold : FontWeight.normal,
                ),
                checkmarkColor: GardenColors.primary,
                side: BorderSide(
                  color: _times.contains(val)
                      ? GardenColors.primary.withValues(alpha: 0.4)
                      : GardenColors.darkBorder,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── PASO 5: Precio ────────────────────────────────────────
  Widget _buildStep5() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [kPrimaryColor, Color(0xFF1B5E20)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: kPrimaryColor.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
              ]
            ),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.white, size: 40),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Precio Dinámico Recomendado',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'GARDEN analiza la demanda en tiempo real para sugerirte el mejor precio inicial según tu zona y experiencia.',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ]
                  )
                )
              ]
            )
          ),
          const SizedBox(height: 24),
          const SizedBox(height: 4),
          const Text(
            'Basado en el mercado de tu zona',
            style: TextStyle(fontSize: 14, color: kTextSecondary),
          ),
          const SizedBox(height: 24),
          PrecioOnboardingCard(
            zona: _selectedZone ?? 'EQUIPETROL',
            servicio: _servicesOffered.isNotEmpty ? _servicesOffered.first.toLowerCase() : 'paseo',
            experienciaMeses: 6,
            trustScore: 85,
            precioPromedioZona: (_priceStats?['avgPrice'] as num?)?.toDouble() ?? 90.0,
            precioMinZona: (_priceStats?['minPrice'] as num?)?.toDouble() ?? 50.0,
            precioMaxZona: (_priceStats?['maxPrice'] as num?)?.toDouble() ?? 180.0,
            agentesService: AgentesService(authToken: _authToken),
            onPrecioConfirmado: (precio) => setState(() => _precioFinal = precio),
          ),
          if (_precioFinal > 0) ...[
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Precio seleccionado: Bs ${_precioFinal.toStringAsFixed(0)}',
                style: const TextStyle(
                  color: kPrimaryColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }



  // ── Paso 6 (Perfil profesional) is now handled by CaregiverProfileDataScreen ──
  // These fields remain for the registration body (sent with defaults):
  bool _caredOthers = false;
  bool _acceptAggressive = false;
  bool _hasChildren = false;
  int _hoursAlone = 0;
  bool _workFromHome = true;
  int _maxPets = 1;
  bool _oftenOut = false;

  // Keeping these controllers so dispose() doesn't crash (they may be referenced):
  final _whyCaregiverController = TextEditingController();
  final _whatDiffersController = TextEditingController();
  final _handleAnxiousController = TextEditingController();
  final _emergencyResponseController = TextEditingController();
  final _typicalDayController = TextEditingController();
  final _bioDetailController = TextEditingController();
  final _breedsWhyController = TextEditingController();

  // Dead code kept for reference — replaced by CaregiverProfileDataScreen
  // ignore: unused_element
  Widget _buildStep6Deprecated() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Perfil Profesional Avanzado', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 4),
          const Text('Completa todos los detalles para que tu perfil sea 100% visible a los dueños.', style: TextStyle(fontSize: 14, color: kTextSecondary)),
          const SizedBox(height: 24),
          
          const Text('Experiencia y mascotas', style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          
          const Text('Mascotas que aceptas', style: TextStyle(color: kTextSecondary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['DOGS', 'CATS'].map((type) {
              final isSelected = _animalTypes.contains(type);
              return ChoiceChip(
                label: Text(type == 'DOGS' ? '🐶 Perros' : '🐱 Gatos'),
                selected: isSelected,
                selectedColor: kPrimaryColor,
                backgroundColor: kSurfaceColor,
                labelStyle: TextStyle(color: isSelected ? Colors.white : kTextSecondary),
                onSelected: (selected) {
                  setState(() { if (selected) {
                    _animalTypes.add(type);
                  } else {
                    _animalTypes.remove(type);
                  } });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          
          const Text('Años de experiencia con mascotas', style: TextStyle(color: kTextSecondary)),
          Slider(
            value: _experienceYears.toDouble(), min: 0, max: 10, divisions: 10,
            label: '\${_experienceYears} años', activeColor: kPrimaryColor,
            onChanged: (val) => setState(() => _experienceYears = val.toInt()),
          ),
          const Center(child: Text('\${_experienceYears} años de experiencia', style: TextStyle(color: Colors.white, fontSize: 16))),
          const SizedBox(height: 16),
          
          const Text('Tamaños aceptados', style: TextStyle(color: kTextSecondary)),
          Wrap(
            spacing: 8,
            children: ['SMALL', 'MEDIUM', 'LARGE', 'GIANT'].map((size) {
              final isSelected = _sizesAccepted.contains(size);
              final label = size == 'SMALL' ? 'Pequeño' : size == 'MEDIUM' ? 'Mediano' : size == 'LARGE' ? 'Grande' : 'Gigante';
              return ChoiceChip(
                label: Text(label), selected: isSelected, selectedColor: kPrimaryColor, backgroundColor: kSurfaceColor,
                labelStyle: TextStyle(color: isSelected ? Colors.white : kTextSecondary),
                onSelected: (selected) {
                  setState(() { if (selected) {
                    _sizesAccepted.add(size);
                  } else {
                    _sizesAccepted.remove(size);
                  } });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          SwitchListTile(tileColor: GardenColors.lightSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), title: const Text('¿He cuidado mascotas de otras personas?', style: TextStyle(color: GardenColors.lightTextPrimary, fontSize: 14)), value: _caredOthers, activeColor: kPrimaryColor, onChanged: (v) => setState(() => _caredOthers = v)),
          const SizedBox(height: 8),
          SwitchListTile(tileColor: GardenColors.lightSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), title: const Text('¿Tienes mascotas propias?', style: TextStyle(color: GardenColors.lightTextPrimary, fontSize: 14)), value: _ownPets, activeColor: kPrimaryColor, onChanged: (v) => setState(() => _ownPets = v)),
          const SizedBox(height: 8),
          SwitchListTile(tileColor: GardenColors.lightSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), title: const Text('¿Aceptas cachorros?', style: TextStyle(color: GardenColors.lightTextPrimary, fontSize: 14)), value: _acceptPuppies, activeColor: kPrimaryColor, onChanged: (v) => setState(() => _acceptPuppies = v)),
          const SizedBox(height: 8),
          SwitchListTile(tileColor: GardenColors.lightSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), title: const Text('¿Aceptas mascotas senior?', style: TextStyle(color: GardenColors.lightTextPrimary, fontSize: 14)), value: _acceptSeniors, activeColor: kPrimaryColor, onChanged: (v) => setState(() => _acceptSeniors = v)),
          const SizedBox(height: 8),
          SwitchListTile(tileColor: GardenColors.lightSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), title: const Text('¿Aceptas mascotas agresivas?', style: TextStyle(color: GardenColors.lightTextPrimary, fontSize: 14)), value: _acceptAggressive, activeColor: kPrimaryColor, onChanged: (v) => setState(() => _acceptAggressive = v)),
          const SizedBox(height: 24),
          if (_servicesOffered.contains('HOSPEDAJE') || _servicesOffered.contains('GUARDERIA')) ...[
            const Text('Condiciones y Entorno (Alojamiento)', style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SwitchListTile(tileColor: GardenColors.lightSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), title: const Text('¿Tienes niños en casa?', style: TextStyle(color: GardenColors.lightTextPrimary, fontSize: 14)), value: _hasChildren, activeColor: kPrimaryColor, onChanged: (v) => setState(() => _hasChildren = v)),
            const SizedBox(height: 8),
            SwitchListTile(tileColor: GardenColors.lightSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), title: const Text('¿Trabajas desde casa?', style: TextStyle(color: GardenColors.lightTextPrimary, fontSize: 14)), value: _workFromHome, activeColor: kPrimaryColor, onChanged: (v) => setState(() => _workFromHome = v)),
            const SizedBox(height: 8),
            SwitchListTile(tileColor: GardenColors.lightSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), title: const Text('¿Sales a menudo?', style: TextStyle(color: GardenColors.lightTextPrimary, fontSize: 14)), value: _oftenOut, activeColor: kPrimaryColor, onChanged: (v) => setState(() => _oftenOut = v)),
            const SizedBox(height: 16),
            
            const Text('Horas que las mascotas estarán solas', style: TextStyle(color: kTextSecondary)),
            Slider(value: _hoursAlone.toDouble(), min: 0, max: 24, divisions: 24, label: '$_hoursAlone hrs', activeColor: kPrimaryColor, onChanged: (val) => setState(() => _hoursAlone = val.toInt())),
            const SizedBox(height: 16),

            const Text('Máximo de mascotas permitidas a la vez', style: TextStyle(color: kTextSecondary)),
            Slider(value: _maxPets.toDouble(), min: 1, max: 10, divisions: 9, label: '$_maxPets mascotas', activeColor: kPrimaryColor, onChanged: (val) => setState(() => _maxPets = val.toInt())),
            const SizedBox(height: 24),
          ],

          const Text('Sobre ti y tu método', style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextFormField(controller: _bioDetailController, maxLines: 4, decoration: const InputDecoration(hintText: 'Biografía detallada: tu experiencia, método de cuidado, formaciones...', prefixIcon: Padding(padding: EdgeInsets.only(bottom: 64), child: Icon(Icons.person_pin, color: kTextSecondary)), alignLabelWithHint: true)),
          const SizedBox(height: 8),
          TextFormField(controller: _whyCaregiverController, maxLines: 2, decoration: const InputDecoration(hintText: '¿Por qué quieres ser cuidador?', prefixIcon: Icon(Icons.help_outline, color: kTextSecondary))),
          const SizedBox(height: 8),
          TextFormField(controller: _whatDiffersController, maxLines: 2, decoration: const InputDecoration(hintText: '¿Qué te diferencia de otros?', prefixIcon: Icon(Icons.star_outline, color: kTextSecondary))),
          const SizedBox(height: 8),
          TextFormField(controller: _handleAnxiousController, maxLines: 2, decoration: const InputDecoration(hintText: '¿Cómo manejas ansiedad?', prefixIcon: Icon(Icons.pets, color: kTextSecondary))),
          const SizedBox(height: 8),
          TextFormField(controller: _emergencyResponseController, maxLines: 2, decoration: const InputDecoration(hintText: '¿Qué harías en emergencia?', prefixIcon: Icon(Icons.warning_amber_rounded, color: kTextSecondary))),
          const SizedBox(height: 8),
          TextFormField(controller: _typicalDayController, maxLines: 2, decoration: const InputDecoration(hintText: 'Describe un día típico', prefixIcon: Icon(Icons.calendar_today, color: kTextSecondary))),
          const SizedBox(height: 24),
        ]
      )
    );
  }


  // ── PASO 7: Foto de Perfil ────────────────────────────────
  Future<void> _pickProfilePhoto() async {
    final picked = await image_picker_pkg.ImagePicker().pickImage(
      source: image_picker_pkg.ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _profilePhotoUrl = null;
      _localProfilePhoto = XFile.fromData(
        Uint8List.fromList(bytes),
        name: picked.name.isEmpty ? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg' : picked.name,
        mimeType: 'image/jpeg',
      );
    });
  }

  Widget _buildStep7() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text('Tu retrato final', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: GardenColors.lightTextPrimary)),
          const SizedBox(height: 12),
          const Text(
            'Sube una foto tuya clara, sonriendo e idealmente con una mascota. Esta será la cara visible de tu negocio en GARDEN.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: kTextSecondary)
          ),
          const SizedBox(height: 48),
          
          GestureDetector(
            onTap: _pickProfilePhoto,
            child: Container(
              width: 200, height: 200,
              decoration: BoxDecoration(
                color: kSurfaceColor,
                shape: BoxShape.circle,
                border: Border.all(color: kPrimaryColor, width: 4),
                boxShadow: [BoxShadow(color: kPrimaryColor.withOpacity(0.4), blurRadius: 20, spreadRadius: 5)],
              ),
              child: ClipOval(
                child: _localProfilePhoto != null
                  ? FutureBuilder<Uint8List>(
                      future: _localProfilePhoto!.readAsBytes(),
                      builder: (c, s) => s.hasData ? Image.memory(s.data!, fit: BoxFit.cover) : const CircularProgressIndicator()
                    )
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_outlined, size: 60, color: kTextSecondary),
                        SizedBox(height: 8),
                        Text('Subir foto', style: TextStyle(color: kTextSecondary, fontWeight: FontWeight.bold))
                      ]
                    )
              )
            )
          ),
          const SizedBox(height: 48),
          if (_localProfilePhoto != null)
            const Text('¡Excelente elección! Estás listo para empezar.', style: TextStyle(color: Colors.greenAccent, fontSize: 16, fontWeight: FontWeight.bold))
        ]
      )
    );
  }

  // ── PASO 10: Disponibilidad detallada ─────────────────────────────────────
  bool _availWeekdays = true;
  bool _availWeekends = false;
  bool _availHolidays = false;
  bool _availMorning = true;
  bool _availAfternoon = true;
  bool _availNight = false;
  bool _savingAvailability = false;

  Future<void> _saveAvailabilityAndFinish() async {
    setState(() => _savingAvailability = true);
    try {
      await http.patch(
        Uri.parse('$_baseUrl/caregiver/availability'),
        headers: {
          'Authorization': 'Bearer $_authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'defaultSchedule': {
            'weekdays': _availWeekdays,
            'weekends': _availWeekends,
            'holidays': _availHolidays,
            'times': [
              if (_availMorning) 'MORNING',
              if (_availAfternoon) 'AFTERNOON',
              if (_availNight) 'NIGHT',
            ],
          },
        }),
      );
    } catch (_) {}
    if (mounted) setState(() => _savingAvailability = false);
    _completeWizard();
  }

  Widget _buildStepAvailability() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Configura tu disponibilidad',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 6),
          const Text(
            'Dinos cuándo puedes atender mascotas. Los dueños solo podrán reservarte en los días y horarios que actives.',
            style: TextStyle(fontSize: 14, color: kTextSecondary),
          ),
          const SizedBox(height: 28),

          const Text('Días disponibles', style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),
          _availDayTile(
            icon: Icons.work_outline_rounded,
            title: 'Días de semana',
            subtitle: 'Lunes a Viernes',
            value: _availWeekdays,
            onChanged: (v) => setState(() => _availWeekdays = v),
          ),
          const SizedBox(height: 10),
          _availDayTile(
            icon: Icons.weekend_outlined,
            title: 'Fines de semana',
            subtitle: 'Sábado y Domingo',
            value: _availWeekends,
            onChanged: (v) => setState(() => _availWeekends = v),
          ),
          const SizedBox(height: 10),
          _availDayTile(
            icon: Icons.event_outlined,
            title: 'Feriados',
            subtitle: 'Días festivos nacionales',
            value: _availHolidays,
            onChanged: (v) => setState(() => _availHolidays = v),
          ),

          const SizedBox(height: 28),
          const Text('Horarios de atención', style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _availTimeChip('Mañana', '6am–12pm', Icons.wb_sunny_outlined, _availMorning, (v) => setState(() => _availMorning = v))),
              const SizedBox(width: 10),
              Expanded(child: _availTimeChip('Tarde', '12pm–7pm', Icons.wb_cloudy_outlined, _availAfternoon, (v) => setState(() => _availAfternoon = v))),
              const SizedBox(width: 10),
              Expanded(child: _availTimeChip('Noche', '7pm–10pm', Icons.nights_stay_outlined, _availNight, (v) => setState(() => _availNight = v))),
            ],
          ),

          const SizedBox(height: 36),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kPrimaryColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kPrimaryColor.withOpacity(0.25)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: kPrimaryColor, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Podrás ajustar días específicos en cualquier momento desde tu panel de disponibilidad.',
                    style: TextStyle(color: kTextSecondary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: _savingAvailability ? null : _saveAvailabilityAndFinish,
              child: _savingAvailability
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Finalizar y entrar a GARDEN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _availDayTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: value ? kPrimaryColor.withOpacity(0.4) : Colors.transparent, width: 1.5),
      ),
      child: SwitchListTile(
        secondary: Icon(icon, color: value ? kPrimaryColor : kTextSecondary, size: 22),
        title: Text(title, style: TextStyle(color: Colors.white, fontWeight: value ? FontWeight.w600 : FontWeight.normal)),
        subtitle: Text(subtitle, style: const TextStyle(color: kTextSecondary, fontSize: 12)),
        value: value,
        activeColor: kPrimaryColor,
        onChanged: onChanged,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _availTimeChip(String label, String hours, IconData icon, bool selected, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!selected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? kPrimaryColor.withOpacity(0.15) : kSurfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? kPrimaryColor : GardenColors.darkBorder, width: 1.5),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? kPrimaryColor : kTextSecondary, size: 22),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(color: selected ? Colors.white : kTextSecondary, fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 2),
            Text(hours, style: const TextStyle(color: kTextSecondary, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ─── Steps 6-9 are post-registration embedded screens ───────────────────
    // They manage their own navigation via callbacks; wizard provides only
    // the progress header above them.
    final Widget postRegStep;
    if (_currentStep == 6) {
      postRegStep = CaregiverProfileDataScreen(
        embeddedMode: true,
        onSaveComplete: _advanceStep,
      );
    } else if (_currentStep == 7) {
      postRegStep = VerificationScreen(
        showAppBar: false,
        onComplete: _advanceStep,
      );
    } else if (_currentStep == 8) {
      postRegStep = EmailVerificationScreen(
        showAppBar: false,
        onComplete: _advanceStep,
      );
    } else if (_currentStep == 9) {
      postRegStep = _buildStepAvailability();
    } else {
      postRegStep = const SizedBox.shrink();
    }

    final steps = [
      _buildStep1(),   // 0: Datos personales
      _buildStep3(),   // 1: Servicios y zona
      _buildStep4(),   // 2: Disponibilidad básica
      _buildStep2(),   // 3: Fotos del lugar
      _buildStep5(),   // 4: Precio
      _buildStep7(),   // 5: Foto de perfil → triggers registration
      postRegStep,     // 6: Perfil profesional
      postRegStep,     // 7: Verificación de identidad
      postRegStep,     // 8: Verificación de email
      postRegStep,     // 9: Disponibilidad
    ];

    final stepTitles = [
      'Datos básicos',
      'Servicios',
      'Disponibilidad',
      'Fotos del lugar',
      'Precio',
      'Tu retrato',
      'Perfil profesional',
      'Verificación ID',
      'Verificación Email',
      'Tu agenda',
    ];

    // Steps 6-9 are embedded screens that manage their own "Continue" buttons.
    // The wizard hides the bottom nav bar for those steps.
    final bool showNavButtons = _currentStep <= 5;
    final bool isRegistrationStep = _currentStep == 5;

    return Theme(
      data: ThemeData(
        colorScheme: const ColorScheme.light(
          primary: kPrimaryColor,
          secondary: kPrimaryColor,
          surface: GardenColors.lightSurface,
          onSurface: GardenColors.lightTextPrimary,
          onPrimary: Colors.white,
        ),
        scaffoldBackgroundColor: GardenColors.lightBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: GardenColors.lightSurface,
          foregroundColor: GardenColors.lightTextPrimary,
          elevation: 0,
          iconTheme: IconThemeData(color: GardenColors.lightTextPrimary),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: GardenColors.lightSurfaceElevated,
          hintStyle: const TextStyle(color: GardenColors.lightTextHint),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: GardenColors.lightBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: GardenColors.lightBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kPrimaryColor, width: 2),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimaryColor,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: kPrimaryColor,
            side: const BorderSide(color: kPrimaryColor),
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        dropdownMenuTheme: const DropdownMenuThemeData(
          textStyle: TextStyle(color: GardenColors.lightTextPrimary),
        ),
        listTileTheme: const ListTileThemeData(
          textColor: GardenColors.lightTextPrimary,
          iconColor: GardenColors.lightTextSecondary,
        ),
      ),
      child: Scaffold(
      backgroundColor: GardenColors.lightBackground,
      appBar: AppBar(
        title: const Text('Crear perfil de cuidador'),
        // Show back arrow only for pre-registration steps (0-4)
        automaticallyImplyLeading: _currentStep < 5,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6),
          child: LinearProgressIndicator(
            value: (_currentStep + 1) / 10,
            backgroundColor: kSurfaceColor,
            valueColor: const AlwaysStoppedAnimation<Color>(kPrimaryColor),
            minHeight: 6,
          ),
        ),
      ),
      body: Column(
        children: [
          // Step indicator
          Container(
            color: kSurfaceColor,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Paso ${_currentStep + 1} de 10',
                  style: const TextStyle(color: kTextSecondary, fontSize: 12),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: kPrimaryColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    stepTitles[_currentStep],
                    style: const TextStyle(color: kPrimaryColor, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          // Step content
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: KeyedSubtree(
                key: ValueKey(_currentStep),
                child: steps[_currentStep],
              ),
            ),
          ),

          // Navigation buttons — only for pre-registration steps (0-5)
          if (showNavButtons)
            Container(
              color: kSurfaceColor,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _currentStep == 0 ? null : _prevStep,
                      child: const Text('Anterior'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _nextStep,
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(isRegistrationStep ? 'Crear mi cuenta' : 'Siguiente'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    )); // closes Scaffold + Theme
  }
}
