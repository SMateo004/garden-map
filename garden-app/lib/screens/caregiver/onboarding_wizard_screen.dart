import 'dart:convert';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart' as image_picker_pkg;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';
import '../../theme/garden_theme.dart' show fixImageUrl, GardenColors, GardenButton, themeNotifier;
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
  /// When true, the user is a CLIENT converting to CAREGIVER. Step 0
  /// (personal data / registration) is skipped — the account already exists
  /// and the CaregiverProfile was created via init-caregiver-profile.
  final bool clientConversionMode;

  const OnboardingWizardScreen({
    super.key,
    this.initialEmail = '',
    this.initialPassword = '',
    this.resumeMode = false,
    this.clientConversionMode = false,
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
  ({Uint8List bytes, String name, String mimeType})? _localProfilePhoto;
  DateTime? _dateOfBirth;

  // Paso 2: Fotos del hogar
  List<String> _photoUrls = [];       // URLs confirmadas en el servidor
  List<({Uint8List bytes, String name, String mimeType})> _localPhotos = [];  // fotos en memoria, sin blob URLs
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

    // clientConversionMode: the account + empty CaregiverProfile already exist.
    // Pre-fill step 0 from existing user data, then jump to step 1.
    if (token.isNotEmpty && widget.clientConversionMode) {
      await _prefillFromExistingUser(token);
      await _tryPopulateCaregiverProfile(token);
      setState(() => _currentStep = 1);
      return;
    }

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

  /// Rellena los controladores del paso 0 con los datos del usuario ya registrado.
  /// Solo se usa en clientConversionMode.
  Future<void> _prefillFromExistingUser(String token) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/auth/me'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        final user = data['data'] as Map<String, dynamic>;
        setState(() {
          _firstNameController.text = user['firstName'] as String? ?? '';
          _lastNameController.text = user['lastName'] as String? ?? '';
          _emailController.text = user['email'] as String? ?? '';
          _phoneController.text = user['phone'] as String? ?? '';
          // Pre-fill address and bio from client profile data
          if ((user['address'] as String? ?? '').isNotEmpty) {
            _addressController.text = user['address'] as String;
          }
          if ((user['bio'] as String? ?? '').isNotEmpty) {
            _bioController.text = user['bio'] as String;
          }
          if (user['dateOfBirth'] != null) {
            try {
              _dateOfBirth = DateTime.parse(user['dateOfBirth'] as String);
            } catch (_) {}
          }
        });
      }
    } catch (_) {}
  }

  /// In clientConversionMode: tries to load existing CaregiverProfile data and
  /// pre-populate wizard state (services, zone, availability, photos, price, etc.).
  /// Does NOT change _currentStep — that is handled by _loadToken.
  Future<void> _tryPopulateCaregiverProfile(String token) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/caregiver/my-profile'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        _populateStateFromProfile(data['data'] as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  /// For returning users: load profile and jump to the first incomplete step (1-8).
  /// Reads a backend profile map and populates all wizard state variables so that
  /// resuming a session shows previously filled data instead of blank fields.
  void _populateStateFromProfile(Map<String, dynamic> profile) {
    final services = (profile['servicesOffered'] as List? ?? []).cast<String>();
    final hasHospedaje = services.contains('HOSPEDAJE');

    // Read availability from serviceAvailability (what the wizard saves in step 2)
    final svcAvail = profile['serviceAvailability'] as Map?;
    bool weekdays = false, weekends = false, holidays = false;
    final times = <String>[];
    if (svcAvail != null && svcAvail.isNotEmpty) {
      final firstVal = svcAvail.values.first as Map? ?? {};
      weekdays = firstVal['weekdays'] as bool? ?? false;
      weekends = firstVal['weekends'] as bool? ?? false;
      holidays = firstVal['holidays'] as bool? ?? false;
      times.addAll(List<String>.from(firstVal['times'] ?? []));
    }

    setState(() {
      // Step 1: Services & zone
      _servicesOffered
        ..clear()
        ..addAll(services);
      _selectedZone = profile['zone'] as String?;
      _homeType = profile['homeType'] as String?;
      _hasYard = profile['hasYard'] as bool? ?? false;

      // Step 2: Availability
      _weekdays = weekdays;
      _weekends = weekends;
      _holidays = holidays;
      _times
        ..clear()
        ..addAll(times);

      // Step 3: Photos — restore confirmed URLs (shown with green checkmark in grid)
      _photoUrls = List<String>.from(profile['photos'] ?? []);

      // Step 4: Price
      _precioFinal = hasHospedaje
          ? ((profile['pricePerDay'] ?? 0) as num).toDouble()
          : ((profile['pricePerWalk60'] ?? 0) as num).toDouble();

      // Step 5: Profile photo
      _profilePhotoUrl = profile['profilePhoto'] as String?;
    });
  }

  Future<void> _computeAndSetResumeStep(String token) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/caregiver/my-profile'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] != true) return;
      final profile = data['data'] as Map<String, dynamic>;

      // Pre-populate all wizard state variables from the saved profile
      _populateStateFromProfile(profile);

      // Step 1: Services & zone
      final zone = profile['zone'];
      final servicesOffered = (profile['servicesOffered'] as List?) ?? [];
      if (zone == null || servicesOffered.isEmpty) {
        setState(() => _currentStep = 1);
        return;
      }

      // Step 2: Availability
      final svcAvail = profile['serviceAvailability'] as Map?;
      if (svcAvail == null || svcAvail.isEmpty) {
        setState(() => _currentStep = 2);
        return;
      }

      // Step 3: Photos
      final photos = (profile['photos'] as List?) ?? [];
      final minPhotos = servicesOffered.contains('HOSPEDAJE') ? 4 : 2;
      if (photos.length < minPhotos) {
        setState(() => _currentStep = 3);
        return;
      }

      // Step 4: Price
      final priceDay = profile['pricePerDay'];
      final priceWalk = profile['pricePerWalk60'];
      final hasPrice = (priceDay != null && priceDay != 0) || (priceWalk != null && priceWalk != 0);
      if (!hasPrice) {
        setState(() => _currentStep = 4);
        return;
      }

      // Step 5: Profile photo
      if (profile['profilePhoto'] == null) {
        setState(() => _currentStep = 5);
        return;
      }

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

      final profileComplete = bio.length >= 10 &&
          bioDetail.length >= 3 &&
          experienceDesc.length >= 5 &&
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

      // All steps complete — attempt submit (handles already-approved case)
      await _completeWizard();
    } catch (_) {
      // If error, stay at step 0 (new registration)
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
        await prefs.remove('client_conversion_in_progress');
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
    // Step 0: en clientConversionMode el usuario ya está registrado, solo avanzar
    if (_currentStep == 0 && widget.clientConversionMode) {
      setState(() => _currentStep = 1);
      return;
    }

    // Step 0: Datos personales → register with minimal data
    if (_currentStep == 0) {
      if (!_validateCurrentStep()) return;
      await _registerMinimalAndAdvance();
      return;
    }

    // Step 1: Servicios y zona → PATCH profile
    if (_currentStep == 1) {
      if (!_validateCurrentStep()) return;
      setState(() => _isLoading = true);
      await _patchProfile({
        'zone': _selectedZone,
        'servicesOffered': _servicesOffered,
        if (_homeType != null) 'homeType': _homeType,
        'hasYard': _hasYard,
      });
      setState(() { _isLoading = false; _currentStep++; });
      return;
    }

    // Step 2: Disponibilidad → PATCH profile
    if (_currentStep == 2) {
      if (!_validateCurrentStep()) return;
      setState(() => _isLoading = true);
      final svcAvail = <String, dynamic>{};
      for (final svc in _servicesOffered) {
        svcAvail[svc] = {
          'weekdays': _weekdays,
          'weekends': _weekends,
          'holidays': _holidays,
          'times': _times,
          'lastMinute': false,
        };
      }
      await _patchProfile({
        'serviceAvailability': svcAvail, // used by _computeAndSetResumeStep on resume
        'serviceDetails': {              // synced by backend to defaultAvailabilitySchedule
          'availability': {
            'weekdays': _weekdays,
            'weekends': _weekends,
            'holidays': _holidays,
            'slots': {
              'morning':   _times.contains('MORNING'),
              'afternoon': _times.contains('AFTERNOON'),
              'night':     _times.contains('NIGHT'),
            },
          },
        },
      });
      setState(() { _isLoading = false; _currentStep++; });
      return;
    }

    // Step 3: Fotos del hogar → upload then PATCH
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
      setState(() => _isLoading = true);
      await _patchProfile({'photos': _photoUrls});
      setState(() { _isLoading = false; _currentStep++; });
      return;
    }

    // Step 4: Precio → PATCH profile
    if (_currentStep == 4) {
      if (!_validateCurrentStep()) return;
      setState(() => _isLoading = true);
      await _patchProfile({
        if (_servicesOffered.contains('HOSPEDAJE')) 'pricePerDay': _precioFinal.toInt(),
        if (_servicesOffered.contains('PASEO')) 'pricePerWalk60': _precioFinal.toInt(),
      });
      setState(() { _isLoading = false; _currentStep++; });
      return;
    }

    // Step 5: Foto de perfil → upload then PATCH profile
    if (_currentStep == 5) {
      if (!_validateCurrentStep()) return;
      setState(() => _isLoading = true);
      if (_localProfilePhoto != null && _profilePhotoUrl == null) {
        try {
          final uri = Uri.parse('$_baseUrl/upload/public-single-photo');
          final request = http.MultipartRequest('POST', uri);
          // bytes ya en memoria — sin blob URL
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
      await _patchProfile({
        if (_profilePhotoUrl != null) 'profilePhoto': _profilePhotoUrl,
      });
      setState(() { _isLoading = false; _currentStep++; });
      return;
    }

    // Steps 6-8 handled by embedded screens
  }

  /// Step 0 → 1: Register with minimal data, get token, advance.
  Future<void> _registerMinimalAndAdvance() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/caregiver/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
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
            'address': _addressController.text.trim(),
          },
        }),
      );

      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw Exception('El servidor no está disponible. Intenta de nuevo en unos segundos.');
      }

      if (response.statusCode == 201 && data['success'] == true) {
        final authService = AuthService();
        await authService.saveToken(data['data']['accessToken']);
        await authService.saveUserData(data['data']['user']);
        setState(() {
          _authToken = data['data']['accessToken'] as String? ?? _authToken;
          _currentStep = 1;
        });
      } else {
        if (data['errors'] != null) {
          final errors = (data['errors'] as List)
              .map((e) => '${e['field']}: ${e['message']}')
              .join('\n');
          throw Exception(errors);
        }
        throw Exception(
          data['error']?['message'] ?? data['message'] ?? 'Error al crear la cuenta',
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

  /// PATCH /caregiver/profile with partial data (silent on error — non-blocking).
  Future<void> _patchProfile(Map<String, dynamic> data) async {
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

  /// Step 6 → next: check backend to auto-skip steps 7/8 if already verified.
  Future<void> _afterStep6Save() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/caregiver/my-profile'),
        headers: {'Authorization': 'Bearer $_authToken'},
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final profile = data['data'] as Map<String, dynamic>? ?? {};

      final identityStatus = (profile['identityVerificationStatus'] as String? ?? '').toUpperCase();
      final identityDone = identityStatus == 'VERIFIED' || identityStatus == 'APPROVED';

      final emailVerified = profile['emailVerified'] == true ||
          (profile['user'] as Map?)?['emailVerified'] == true;

      if (identityDone && emailVerified) {
        await _completeWizard();
      } else if (identityDone) {
        setState(() => _currentStep = 8);
      } else {
        setState(() => _currentStep = 7);
      }
    } catch (_) {
      setState(() => _currentStep = 7);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Step 7 → next: only advance if identityVerificationStatus == VERIFIED,
  /// and auto-skip step 8 if email is already verified.
  Future<void> _onIdentityVerificationComplete() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/caregiver/my-profile'),
        headers: {'Authorization': 'Bearer $_authToken'},
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final profile = body['data'] as Map<String, dynamic>? ?? {};
      final status = (profile['identityVerificationStatus'] as String? ?? '').toUpperCase();

      if (status == 'VERIFIED' || status == 'APPROVED') {
        final emailVerified = profile['emailVerified'] == true ||
            (profile['user'] as Map?)?['emailVerified'] == true;
        if (emailVerified) {
          await _completeWizard();
        } else {
          setState(() => _currentStep = 8);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Debes completar y aprobar la verificación de identidad para continuar.'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 5),
          ));
        }
      }
    } catch (_) {
      // Network error — stay on step 7
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  Future<void> _pickAndUploadPhoto() async {
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
      setState(() {
        _localPhotos.add((bytes: bytes, name: name, mimeType: mimeType));
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error leyendo imagen: $e'), backgroundColor: Colors.red.shade700));
      }
    }
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
        // bytes ya están en memoria — sin blob URL, sin fetch
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


  // ── PASO 1: Datos personales ──────────────────────────────
  Widget _buildStep1() {
    final isDark = themeNotifier.isDark;
    final textColor    = isDark ? GardenColors.darkTextPrimary    : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary  : GardenColors.lightTextSecondary;
    final borderColor  = isDark ? GardenColors.darkBorder         : GardenColors.lightBorder;
    final surfaceEl    = isDark ? GardenColors.darkSurfaceElevated: GardenColors.lightSurfaceElevated;

    InputDecoration _field(String hint, IconData icon) => InputDecoration(
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

          // Nombre + Apellido
          Row(children: [
            Expanded(child: TextFormField(controller: _firstNameController, style: TextStyle(color: textColor),
                decoration: _field('Nombre', Icons.person_outlined))),
            const SizedBox(width: 12),
            Expanded(child: TextFormField(controller: _lastNameController, style: TextStyle(color: textColor),
                decoration: _field('Apellido', Icons.person_outline))),
          ]),
          const SizedBox(height: 16),

          TextFormField(controller: _emailController, keyboardType: TextInputType.emailAddress,
              style: TextStyle(color: textColor), decoration: _field('Correo electrónico', Icons.email_outlined)),
          const SizedBox(height: 16),

          TextFormField(controller: _passwordController, obscureText: true,
              style: TextStyle(color: textColor), decoration: _field('Contraseña (mínimo 8 caracteres)', Icons.lock_outlined)),
          const SizedBox(height: 16),

          TextFormField(controller: _phoneController, keyboardType: TextInputType.number,
              style: TextStyle(color: textColor), decoration: _field('Teléfono (ej: 76543210)', Icons.phone_outlined)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text('8 dígitos, empieza con 6 o 7', style: TextStyle(color: subtextColor, fontSize: 12)),
          ),
          const SizedBox(height: 16),

          TextFormField(controller: _addressController,
              style: TextStyle(color: textColor), decoration: _field('Dirección completa', Icons.home_work_outlined)),
          const SizedBox(height: 16),

          // Date of birth
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime(2000),
                firstDate: DateTime(1940),
                lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
                builder: (context, child) => Theme(
                  data: ThemeData.dark().copyWith(
                    colorScheme: const ColorScheme.dark(
                      primary: GardenColors.primary,
                      onPrimary: Colors.white,
                      surface: Color(0xFF1A2E10),
                      onSurface: Colors.white,
                    ),
                    dialogTheme: const DialogThemeData(backgroundColor: GardenColors.darkSurface),
                  ),
                  child: child!,
                ),
              );
              if (picked != null) setState(() => _dateOfBirth = picked);
            },
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: surfaceEl,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _dateOfBirth != null ? GardenColors.primary.withValues(alpha: 0.5) : borderColor),
              ),
              child: Row(children: [
                Icon(Icons.cake_outlined, color: subtextColor, size: 20),
                const SizedBox(width: 12),
                Text(
                  _dateOfBirth == null ? 'Fecha de nacimiento' : _formatDate(_dateOfBirth!),
                  style: TextStyle(color: _dateOfBirth == null ? subtextColor : textColor, fontSize: 14),
                ),
                const Spacer(),
                if (_dateOfBirth != null)
                  const Icon(Icons.check_circle_rounded, color: GardenColors.primary, size: 18),
              ]),
            ),
          ),
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

  // ── PASO 2 (index 2): Fotos adaptadas al servicio ────────
  Widget _buildStep2() {
    final isDark = themeNotifier.isDark;
    final textColor    = isDark ? GardenColors.darkTextPrimary    : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary  : GardenColors.lightTextSecondary;
    final borderColor  = isDark ? GardenColors.darkBorder         : GardenColors.lightBorder;
    final surfaceEl    = isDark ? GardenColors.darkSurfaceElevated: GardenColors.lightSurfaceElevated;

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
          Text(titulo, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: textColor, letterSpacing: -0.5)),
          const SizedBox(height: 4),
          Text(subtitulo, style: TextStyle(fontSize: 14, color: subtextColor)),
          const SizedBox(height: 16),

          // Barra de progreso de subida
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
              // Celda con foto ya subida al servidor (URL confirmada)
              if (index < _photoUrls.length) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(fixImageUrl(_photoUrls[index]), fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        decoration: const BoxDecoration(color: GardenColors.success, shape: BoxShape.circle),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(Icons.check, color: Colors.white, size: 14),
                      ),
                    ),
                    Positioned(
                      bottom: 8, right: 8,
                      child: GestureDetector(
                        onTap: () => setState(() => _photoUrls.removeAt(index)),
                        child: Container(
                          decoration: BoxDecoration(color: Colors.red.shade700, shape: BoxShape.circle),
                          padding: const EdgeInsets.all(4),
                          child: const Icon(Icons.close, color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                  ],
                );
              }

              // Celda con foto local pendiente de subir (bytes ya en memoria)
              final localIndex = index - _photoUrls.length;
              if (localIndex >= 0 && localIndex < _localPhotos.length) {
                final photo = _localPhotos[localIndex];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(photo.bytes, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        decoration: BoxDecoration(color: Colors.orange.shade700, shape: BoxShape.circle),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(Icons.cloud_upload_outlined, color: Colors.white, size: 14),
                      ),
                    ),
                    Positioned(
                      bottom: 8, right: 8,
                      child: GestureDetector(
                        onTap: () => setState(() => _localPhotos.removeAt(localIndex)),
                        child: Container(
                          decoration: BoxDecoration(color: Colors.red.shade700, shape: BoxShape.circle),
                          padding: const EdgeInsets.all(4),
                          child: const Icon(Icons.close, color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                  ],
                );
              }

              // Celda vacía — botón para añadir
              return GestureDetector(
                onTap: (_isLoading || _uploadingPhotos) ? null : _pickAndUploadPhoto,
                child: Container(
                  decoration: BoxDecoration(
                    color: surfaceEl,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: GardenColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_photo_alternate_outlined, color: GardenColors.primary, size: 40),
                      const SizedBox(height: 8),
                      Text('Añadir foto', style: TextStyle(color: subtextColor, fontSize: 12)),
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
              color: _localPhotos.isNotEmpty ? Colors.orange.shade400 : subtextColor,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ── PASO 3: Servicios y zona ──────────────────────────────
  Widget _buildStep3() {
    final isDark = themeNotifier.isDark;
    final textColor    = isDark ? GardenColors.darkTextPrimary    : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary  : GardenColors.lightTextSecondary;
    final borderColor  = isDark ? GardenColors.darkBorder         : GardenColors.lightBorder;
    final surfaceEl    = isDark ? GardenColors.darkSurfaceElevated: GardenColors.lightSurfaceElevated;

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
        onTap: () {
          setState(() {
            if (selected) { _servicesOffered.remove(service); } else { _servicesOffered.add(service); }
          });
          _loadPriceStats();
        },
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: selected ? GardenColors.primary.withValues(alpha: 0.12) : surfaceEl,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? GardenColors.primary : borderColor,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 36)),
              const SizedBox(height: 10),
              Text(label, style: TextStyle(
                color: selected ? GardenColors.primary : textColor,
                fontWeight: FontWeight.w700, fontSize: 15,
              )),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('¿Qué ofreces?', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: textColor, letterSpacing: -0.5)),
          const SizedBox(height: 6),
          Text('Selecciona los servicios que brindarás', style: TextStyle(fontSize: 14, color: subtextColor)),
          const SizedBox(height: 28),

          Text('Servicios', style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: serviceCard('HOSPEDAJE', '🏠', 'Hospedaje')),
            const SizedBox(width: 12),
            Expanded(child: serviceCard('PASEO', '🦮', 'Paseo')),
          ]),
          const SizedBox(height: 28),

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
            onChanged: (v) { setState(() => _selectedZone = v); _loadPriceStats(); },
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
        ],
      ),
    );
  }

  // ── PASO 4: Disponibilidad ────────────────────────────────
  Widget _buildStep4() {
    final isDark = themeNotifier.isDark;
    final textColor    = isDark ? GardenColors.darkTextPrimary    : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary  : GardenColors.lightTextSecondary;
    final borderColor  = isDark ? GardenColors.darkBorder         : GardenColors.lightBorder;
    final surfaceEl    = isDark ? GardenColors.darkSurfaceElevated: GardenColors.lightSurfaceElevated;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('¿Cuándo estás disponible?', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: textColor, letterSpacing: -0.5)),
          const SizedBox(height: 6),
          Text('Selecciona los días y horarios en que puedes cuidar mascotas', style: TextStyle(fontSize: 14, color: subtextColor)),
          const SizedBox(height: 28),

          Text('Días disponibles', style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          availSwitch('Días de semana', 'Lunes a Viernes', _weekdays, (v) => setState(() => _weekdays = v)),
          availSwitch('Fines de semana', 'Sábado y Domingo', _weekends, (v) => setState(() => _weekends = v)),
          availSwitch('Feriados', 'Días festivos nacionales', _holidays, (v) => setState(() => _holidays = v)),

          const SizedBox(height: 12),
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
        ],
      ),
    );
  }

  // ── PASO 5: Precio ────────────────────────────────────────
  Widget _buildStep5() {
    final isDark = themeNotifier.isDark;
    final textColor    = isDark ? GardenColors.darkTextPrimary   : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [GardenColors.primary, Color(0xFF4A5E28)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: GardenColors.primary.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: const Row(children: [
              Icon(Icons.auto_awesome, color: Colors.white, size: 40),
              SizedBox(width: 16),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Precio Dinámico Recomendado', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
                  SizedBox(height: 4),
                  Text('GARDEN analiza la demanda en tiempo real para sugerirte el mejor precio inicial según tu zona y experiencia.',
                      style: TextStyle(fontSize: 12, color: Colors.white70)),
                ],
              )),
            ]),
          ),
          const SizedBox(height: 20),
          Text('Basado en el mercado de tu zona', style: TextStyle(fontSize: 14, color: subtextColor)),
          const SizedBox(height: 20),
          PrecioOnboardingCard(
            zona: _selectedZone ?? 'EQUIPETROL',
            servicio: _servicesOffered.isNotEmpty ? _servicesOffered.first.toLowerCase() : 'paseo',
            experienciaMeses: 6,
            trustScore: 85,
            precioPromedioZona: (_priceStats?['avgPrice'] as num?)?.toDouble() ?? 90.0,
            precioMinZona: (_priceStats?['minPrice'] as num?)?.toDouble() ?? 50.0,
            precioMaxZona: (_priceStats?['maxPrice'] as num?)?.toDouble() ?? 290.0,
            agentesService: AgentesService(authToken: _authToken),
            onPrecioConfirmado: (precio) => setState(() => _precioFinal = precio),
          ),
          if (_precioFinal > 0) ...[
            const SizedBox(height: 16),
            Center(child: Text(
              'Precio seleccionado: Bs ${_precioFinal.toStringAsFixed(0)}',
              style: const TextStyle(color: GardenColors.primary, fontSize: 18, fontWeight: FontWeight.w800),
            )),
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
    final picked = await image_picker_pkg.ImagePicker()
        .pickImage(source: image_picker_pkg.ImageSource.gallery, imageQuality: 85);
    if (picked == null || !mounted) return;

    try {
      final bytes = await picked.readAsBytes();
      final name = picked.name.isEmpty
          ? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg'
          : picked.name;
      final mimeType = picked.mimeType ?? 'image/jpeg';
      setState(() {
        _profilePhotoUrl = null;
        _localProfilePhoto = (bytes: bytes, name: name, mimeType: mimeType);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error leyendo imagen: $e'), backgroundColor: Colors.red.shade700));
      }
    }
  }

  Widget _buildStep7() {
    final isDark = themeNotifier.isDark;
    final textColor    = isDark ? GardenColors.darkTextPrimary    : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary  : GardenColors.lightTextSecondary;
    final surfaceEl    = isDark ? GardenColors.darkSurfaceElevated: GardenColors.lightSurfaceElevated;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('Tu retrato final', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: textColor, letterSpacing: -0.5)),
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
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.camera_alt_outlined, size: 56, color: subtextColor),
                              const SizedBox(height: 10),
                              Text('Subir foto', style: TextStyle(color: subtextColor, fontWeight: FontWeight.w600, fontSize: 14)),
                            ],
                          )),
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
                Text('¡Excelente elección! Estás listo para empezar.',
                    style: TextStyle(color: GardenColors.success, fontSize: 14, fontWeight: FontWeight.w600)),
              ]),
            ),
        ],
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
        onSaveComplete: _afterStep6Save,
      );
    } else if (_currentStep == 7) {
      postRegStep = VerificationScreen(
        showAppBar: false,
        onComplete: _onIdentityVerificationComplete,
      );
    } else if (_currentStep == 8) {
      postRegStep = EmailVerificationScreen(
        showAppBar: false,
        onComplete: () { _completeWizard(); },
      );
    } else {
      postRegStep = const SizedBox.shrink();
    }

    final steps = [
      _buildStep1(),   // 0: Datos personales → register
      _buildStep3(),   // 1: Servicios y zona
      _buildStep4(),   // 2: Disponibilidad básica
      _buildStep2(),   // 3: Fotos del lugar
      _buildStep5(),   // 4: Precio
      _buildStep7(),   // 5: Foto de perfil
      postRegStep,     // 6: Perfil profesional
      postRegStep,     // 7: Verificación de identidad
      postRegStep,     // 8: Verificación de email
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
    ];

    // Steps 6-8 are embedded screens that manage their own "Continue" buttons.
    // The wizard hides the bottom nav bar for those steps.
    final bool showNavButtons = _currentStep <= 5;
    final bool isRegistrationStep = _currentStep == 0;

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

        return Theme(
          data: ThemeData(
            colorScheme: isDark
                ? ColorScheme.dark(
                    primary: GardenColors.primary,
                    secondary: GardenColors.primary,
                    surface: GardenColors.darkSurface,
                    onSurface: GardenColors.darkTextPrimary,
                    onPrimary: Colors.white,
                  )
                : const ColorScheme.light(
                    primary: GardenColors.primary,
                    secondary: GardenColors.primary,
                    surface: GardenColors.lightSurface,
                    onSurface: GardenColors.lightTextPrimary,
                    onPrimary: Colors.white,
                  ),
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
            listTileTheme: ListTileThemeData(
              textColor: textColor,
              iconColor: subtextColor,
              tileColor: surfaceEl,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            switchTheme: SwitchThemeData(
              thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? GardenColors.primary : subtextColor),
              trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? GardenColors.primary.withValues(alpha: 0.35) : borderColor),
            ),
            dropdownMenuTheme: DropdownMenuThemeData(
              textStyle: TextStyle(color: textColor),
            ),
          ),
          child: Scaffold(
            backgroundColor: bg,
            appBar: AppBar(
              title: const Text('Crear perfil de cuidador'),
              automaticallyImplyLeading: _currentStep < 5,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(
                  value: (_currentStep + 1) / 9,
                  backgroundColor: borderColor,
                  valueColor: const AlwaysStoppedAnimation<Color>(GardenColors.primary),
                  minHeight: 4,
                ),
              ),
            ),
            body: Column(
              children: [
                // Step indicator
                Container(
                  color: surface,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Paso ${_currentStep + 1} de 9',
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

                // Step content
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: KeyedSubtree(
                      key: ValueKey(_currentStep),
                      child: steps[_currentStep],
                    ),
                  ),
                ),

                // Navigation buttons — only for pre-registration steps (0-5)
                if (showNavButtons) ...[
                  Container(height: 1, color: borderColor),
                  Container(
                    color: surface,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: Row(
                      children: [
                        if (_currentStep > 0) ...[
                          SizedBox(
                            width: 110,
                            child: GardenButton(
                              label: 'Anterior',
                              outline: true,
                              height: 48,
                              onPressed: _prevStep,
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: GardenButton(
                            label: isRegistrationStep ? 'Crear mi cuenta' : 'Siguiente →',
                            loading: _isLoading,
                            height: 48,
                            onPressed: _isLoading ? () {} : _nextStep,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
