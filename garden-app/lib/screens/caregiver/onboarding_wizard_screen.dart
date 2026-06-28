import 'dart:convert';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart' as image_picker_pkg;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';
import '../../theme/garden_theme.dart' show fixImageUrl, GardenColors, GardenButton, themeNotifier;
import '../../services/auth_service.dart';

import 'caregiver_profile_data_screen.dart';
import 'verification_screen.dart';
import 'phone_verification_screen.dart';
import '../../services/auth_state.dart';
import '../../widgets/address_map_picker.dart';
import '../../widgets/address_section.dart';

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
  final _addressController = TextEditingController();

  // Dirección detallada
  final _addressStreetController = TextEditingController();
  final _addressNumberController = TextEditingController();
  final _addressApartmentController = TextEditingController();
  final _addressCondominioController = TextEditingController();
  final _addressReferenceController = TextEditingController();
  String? _addressZone;      // zona seleccionada del dropdown
  double? _addressLat;
  double? _addressLng;
  bool _isApartment = false;

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

  // Paso 4: Fotos
  // — Fotos del cuidador en acción (todos los servicios, mín 2, máx 6)
  List<String> _caregiverPhotoUrls = [];
  List<({Uint8List bytes, String name, String mimeType})> _localCaregiverPhotos = [];
  bool _uploadingCaregiverPhotos = false;
  // — Fotos del lugar por sección (solo HOSPEDAJE/GUARDERÍA)
  Map<String, List<String>> _placePhotoUrls = {};
  Map<String, List<({Uint8List bytes, String name, String mimeType})>> _localPlacePhotos = {};
  bool _uploadingPlacePhotos = false;
  // legacy — conservado para compatibilidad con _populateStateFromProfile
  List<String> _photoUrls = [];

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

  // Keys for step navigation on error
  final _keyStep0Name = GlobalKey();
  final _keyStep0Email = GlobalKey();
  final _keyStep0Password = GlobalKey();
  final _keyStep0Phone = GlobalKey();
  final _keyStep0Address = GlobalKey();
  final _keyStep0Dob = GlobalKey();
  final _keyStep1Services = GlobalKey();
  final _keyStep1Zone = GlobalKey();
  final _keyStep2Days = GlobalKey();
  final _keyStep2Times = GlobalKey();

  // Paso 5: Precio (uno por cada servicio)
  double _precioHospedaje = 90.0;  // pricePerDay (por noche)
  double _precioPaseo = 90.0;      // pricePerWalk60 (por hora)
  double _precioGuarderia = 90.0;        // pricePerGuarderia (por hora)
  bool  _guarderiaIncludeWalk = false;   // ¿La guardería incluye un paseo?
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
      // _addressZone viene del domicilio (Paso 0); _selectedZone es legado
      final zone = _addressZone ?? _selectedZone ?? 'EQUIPETROL';
      final url = '${const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api')}/caregivers/price-stats?zone=$zone&service=$service';
      final res = await http.get(Uri.parse(url));
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        setState(() => _priceStats = data['data'] as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  Future<void> _loadToken() async {
    String token = AuthState.token;

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
    defaultValue: 'https://api.gardenbo.com/api',
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

      // Step 4: Photos — restore confirmed URLs
      _photoUrls = List<String>.from(profile['photos'] ?? []); // legacy
      _caregiverPhotoUrls = List<String>.from(profile['caregiverPhotos'] ?? []);
      final rawPlace = profile['placePhotos'] as Map<String, dynamic>?;
      if (rawPlace != null) {
        _placePhotoUrls = rawPlace.map((k, v) => MapEntry(k, List<String>.from(v as List? ?? [])));
      }

      // Step 4: Price (separate for each service)
      final pDay  = ((profile['pricePerDay']       ?? 0) as num).toDouble();
      final pWalk = ((profile['pricePerWalk60']     ?? 0) as num).toDouble();
      final pGuar = ((profile['pricePerGuarderia']  ?? 0) as num).toDouble();
      _precioHospedaje       = pDay  > 0 ? pDay  : 90.0;
      _precioPaseo           = pWalk > 0 ? pWalk : 60.0;
      _precioGuarderia       = pGuar > 0 ? pGuar : 50.0;
      _guarderiaIncludeWalk  = profile['guarderiaIncludeWalk'] == true;

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

      // Rellenar teléfono desde el objeto user del perfil (necesario en paso 8)
      final userNode = profile['user'] as Map<String, dynamic>?;
      final savedPhone = (userNode?['phone'] as String? ?? '').trim();
      if (savedPhone.isNotEmpty && _phoneController.text.isEmpty) {
        setState(() => _phoneController.text = savedPhone);
      }

      // Step 1: Foto de perfil
      if (profile['profilePhoto'] == null) {
        setState(() => _currentStep = 1);
        return;
      }

      // Step 2: Servicios y zona
      final zone = profile['zone'];
      final servicesOffered = (profile['servicesOffered'] as List?) ?? [];
      if (zone == null || servicesOffered.isEmpty) {
        setState(() => _currentStep = 2);
        return;
      }

      // Step 3: Precio
      final priceDay  = profile['pricePerDay'];
      final priceWalk = profile['pricePerWalk60'];
      final priceGuar = profile['pricePerGuarderia'];
      final hasPrice  = (priceDay  != null && priceDay  != 0) ||
                        (priceWalk != null && priceWalk != 0) ||
                        (priceGuar != null && priceGuar != 0);
      if (!hasPrice) {
        setState(() => _currentStep = 3);
        return;
      }

      // Step 4: Disponibilidad
      final svcAvail = profile['serviceAvailability'] as Map?;
      if (svcAvail == null || svcAvail.isEmpty) {
        setState(() => _currentStep = 4);
        return;
      }

      // Step 5: Fotos (skipped for PASEO-only caregivers)
      final photos = (profile['caregiverPhotos'] as List?) ?? (profile['photos'] as List?) ?? [];
      final isPaseoOnly = servicesOffered.length == 1 && servicesOffered.contains('PASEO');
      final minPhotos = servicesOffered.contains('HOSPEDAJE') ? 4 : isPaseoOnly ? 0 : 2;
      if (photos.length < minPhotos) {
        setState(() => _currentStep = 5);
        return;
      }

      // Step 6: Professional profile (CaregiverProfileDataScreen)
      // termsAccepted se auto-guarda en true al completar el paso 6 en modo
      // embedded, lo usamos como señal definitiva de "paso 6 guardado".
      final termsAccepted = profile['termsAccepted'] == true;
      final bio = (profile['bio'] as String? ?? '').trim();
      final sizesAccepted = (profile['sizesAccepted'] as List?) ?? [];
      final animalTypes = (profile['animalTypes'] as List?) ?? [];
      final isAmateur = profile['isAmateur'] == true;

      // Para no-amateurs se exigen campos de experiencia mínimos.
      final experienceOk = isAmateur || (
        (profile['experienceDescription'] as String? ?? '').trim().length >= 3 &&
        (profile['whyCaregiver'] as String? ?? '').trim().length >= 3
      );

      final step6Complete = termsAccepted &&
          bio.length >= 10 &&
          sizesAccepted.isNotEmpty &&
          animalTypes.isNotEmpty &&
          experienceOk;

      if (!step6Complete) {
        setState(() => _currentStep = 6);
        return;
      }

      // Step 7: Verificación de identidad — requiere identityVerificationStatus VERIFIED
      final identityStatus = (profile['identityVerificationStatus'] as String? ?? '').toUpperCase();
      if (identityStatus != 'VERIFIED' && identityStatus != 'APPROVED') {
        setState(() => _currentStep = 7);
        return;
      }

      // Step 8: Verificación de teléfono — requiere phoneVerified true
      final phoneVerified = profile['phoneVerified'] == true;
      if (!phoneVerified) {
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
        body: jsonEncode({
          'termsAccepted': true,
          'privacyAccepted': true,
          'verificationAccepted': true,
        }),
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
    _addressController.dispose();
    _addressStreetController.dispose();
    _addressNumberController.dispose();
    _addressApartmentController.dispose();
    _addressCondominioController.dispose();
    _addressReferenceController.dispose();
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

  String _buildFullAddress() {
    final parts = <String>[
      if (_addressStreetController.text.trim().isNotEmpty) _addressStreetController.text.trim(),
      if (_addressNumberController.text.trim().isNotEmpty) 'N° ${_addressNumberController.text.trim()}',
      if (_isApartment && _addressApartmentController.text.trim().isNotEmpty)
        'Dpto. ${_addressApartmentController.text.trim()}',
      if (_isApartment && _addressCondominioController.text.trim().isNotEmpty)
        _addressCondominioController.text.trim(),
      if (_addressZone != null) _addressZone!,
      'Santa Cruz de la Sierra, Bolivia',
    ];
    return parts.join(', ');
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
      action: scrollTo?.currentContext != null
          ? SnackBarAction(
              label: 'Ver campo',
              textColor: Colors.white,
              onPressed: () {
                if (scrollTo?.currentContext != null) {
                  Scrollable.ensureVisible(
                    scrollTo!.currentContext!,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOut,
                  );
                }
              },
            )
          : null,
    ));
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        if (_firstNameController.text.trim().isEmpty) {
          _showStepError('Falta: Nombre', scrollTo: _keyStep0Name);
          return false;
        }
        if (_lastNameController.text.trim().isEmpty) {
          _showStepError('Falta: Apellido', scrollTo: _keyStep0Name);
          return false;
        }
        if (_emailController.text.trim().isEmpty) {
          _showStepError('Falta: Correo electrónico', scrollTo: _keyStep0Email);
          return false;
        }
        if (_passwordController.text.isEmpty) {
          _showStepError('Falta: Contraseña', scrollTo: _keyStep0Password);
          return false;
        }
        if (_phoneController.text.trim().isEmpty) {
          _showStepError('Falta: Número de teléfono', scrollTo: _keyStep0Phone);
          return false;
        }
        if (_addressStreetController.text.trim().isEmpty) {
          _showStepError('Falta: Calle de tu dirección', scrollTo: _keyStep0Address);
          return false;
        }
        if (_addressZone == null) {
          _showStepError('Selecciona tu zona / barrio', scrollTo: _keyStep0Address);
          return false;
        }
        if (_dateOfBirth == null) {
          _showStepError('Falta: Fecha de nacimiento', scrollTo: _keyStep0Dob);
          return false;
        }
        return true;
      case 1: // Foto de perfil
        if (_profilePhotoUrl == null && _localProfilePhoto == null) {
          _showStepError('Por favor, sube una foto de perfil para continuar');
          return false;
        }
        return true;
      case 2: // Servicios
        if (_servicesOffered.isEmpty) {
          _showStepError('Selecciona al menos un servicio', scrollTo: _keyStep1Services);
          return false;
        }
        if (_servicesOffered.contains('HOSPEDAJE') && _homeType == null) {
          _showStepError('Indica si tu espacio es Casa o Departamento', scrollTo: _keyStep1Services);
          return false;
        }
        return true;
      case 3: // Precio
        if (_servicesOffered.contains('HOSPEDAJE') && _precioHospedaje < 10) {
          _showStepError('El precio mínimo de Hospedaje es Bs 10');
          return false;
        }
        if (_servicesOffered.contains('PASEO') && _precioPaseo < 10) {
          _showStepError('El precio mínimo de Paseo es Bs 10');
          return false;
        }
        if (_servicesOffered.contains('GUARDERIA') && _precioGuarderia < 10) {
          _showStepError('El precio mínimo de Guardería es Bs 10');
          return false;
        }
        return true;
      case 4: // Disponibilidad
        if (!_weekdays && !_weekends && !_holidays) {
          _showStepError('Selecciona al menos un día disponible', scrollTo: _keyStep2Days);
          return false;
        }
        if (_times.isEmpty) {
          _showStepError('Selecciona al menos un horario', scrollTo: _keyStep2Times);
          return false;
        }
        return true;
      case 5: // Fotos del cuidador + lugar
        if (_caregiverPhotoUrls.length + _localCaregiverPhotos.length < 2) {
          _showStepError('Sube al menos 2 fotos tuyas en acción para continuar');
          return false;
        }
        final needsPlace = _servicesOffered.contains('HOSPEDAJE') || _servicesOffered.contains('GUARDERIA');
        if (needsPlace) {
          for (final sec in ['sala', 'descanso', 'alimentacion']) {
            final total = (_placePhotoUrls[sec]?.length ?? 0) + (_localPlacePhotos[sec]?.length ?? 0);
            if (total < 1) {
              final labels = {'sala': 'Sala / Área principal', 'descanso': 'Zona de descanso', 'alimentacion': 'Área de alimentación'};
              _showStepError('Agrega al menos 1 foto de: ${labels[sec]}');
              return false;
            }
          }
        }
        return true;
      default:
        return true; // Steps 6-8 handled by embedded screens
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

    // Step 1: Foto de perfil → upload then PATCH profile
    if (_currentStep == 1) {
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
      await _patchProfile({
        if (_profilePhotoUrl != null) 'profilePhoto': _profilePhotoUrl,
      });
      setState(() { _isLoading = false; _currentStep++; });
      return;
    }

    // Step 2: Servicios → PATCH profile (zona se toma del domicilio del Paso 0)
    if (_currentStep == 2) {
      if (!_validateCurrentStep()) return;
      setState(() => _isLoading = true);
      await _patchProfile({
        'zone': _addressZone ?? _selectedZone,
        'servicesOffered': _servicesOffered,
        if (_homeType != null) 'homeType': _homeType,
        'hasYard': _hasYard,
      });
      // Actualizar price stats con la zona real antes de mostrar el paso de precio
      _loadPriceStats();
      setState(() { _isLoading = false; _currentStep++; });
      return;
    }

    // Step 3: Precio → PATCH profile (justo después de servicios, flujo natural)
    if (_currentStep == 3) {
      if (!_validateCurrentStep()) return;
      setState(() => _isLoading = true);
      await _patchProfile({
        if (_servicesOffered.contains('HOSPEDAJE')) 'pricePerDay': _precioHospedaje.toInt(),
        if (_servicesOffered.contains('PASEO')) 'pricePerWalk60': _precioPaseo.toInt(),
        if (_servicesOffered.contains('GUARDERIA')) 'pricePerGuarderia': _precioGuarderia.toInt(),
        if (_servicesOffered.contains('GUARDERIA')) 'guarderiaIncludeWalk': _guarderiaIncludeWalk,
      });
      setState(() { _isLoading = false; _currentStep++; });
      return;
    }

    // Step 4: Disponibilidad → PATCH profile
    if (_currentStep == 4) {
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
        'serviceAvailability': svcAvail,
        'serviceDetails': {
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

    // Step 5: Fotos del cuidador + lugar
    if (_currentStep == 5) {
      if (!_validateCurrentStep()) return;
      setState(() => _isLoading = true);
      try {
        if (_localCaregiverPhotos.isNotEmpty) await _uploadPendingCaregiverPhotos();
        if (_localPlacePhotos.values.any((l) => l.isNotEmpty)) await _uploadPendingPlacePhotos();
        await _patchProfile({
          'caregiverPhotos': _caregiverPhotoUrls,
          if (_placePhotoUrls.isNotEmpty) 'placePhotos': _placePhotoUrls,
        });
      } catch (_) {
        setState(() => _isLoading = false);
        return;
      }
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
            'address': _buildFullAddress(),
            if (_addressLat != null) 'addressLat': _addressLat,
            if (_addressLng != null) 'addressLng': _addressLng,
            if (_addressStreetController.text.trim().isNotEmpty)
              'addressStreet': _addressStreetController.text.trim(),
            if (_addressNumberController.text.trim().isNotEmpty)
              'addressNumber': _addressNumberController.text.trim(),
            if (_isApartment && _addressApartmentController.text.trim().isNotEmpty)
              'addressApartment': _addressApartmentController.text.trim(),
            if (_isApartment && _addressCondominioController.text.trim().isNotEmpty)
              'addressCondominio': _addressCondominioController.text.trim(),
            if (_addressReferenceController.text.trim().isNotEmpty)
              'addressReference': _addressReferenceController.text.trim(),
            if (_addressZone != null) 'addressZone': _addressZone,
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

      final phoneVerified = profile['phoneVerified'] == true;

      if (!identityDone) {
        setState(() => _currentStep = 7);
      } else if (!phoneVerified) {
        setState(() => _currentStep = 8);
      } else {
        await _completeWizard();
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
        final phoneVerified = profile['phoneVerified'] == true;
        if (!phoneVerified) {
          setState(() => _currentStep = 8);
        } else {
          await _completeWizard();
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

  /// Step 8 complete: phone verified, finish wizard.
  Future<void> _onPhoneVerificationComplete() async {
    await _completeWizard();
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  static const _apiUrl = String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  /// Agrega foto al buffer local del cuidador (máx 6)
  Future<void> _pickCaregiverPhoto() async {
    if (_caregiverPhotoUrls.length + _localCaregiverPhotos.length >= 6) return;
    final picked = await image_picker_pkg.ImagePicker()
        .pickImage(source: image_picker_pkg.ImageSource.gallery, imageQuality: 85);
    if (picked == null || !mounted) return;
    try {
      final bytes = await picked.readAsBytes();
      final name = picked.name.isEmpty ? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg' : picked.name;
      setState(() => _localCaregiverPhotos.add((bytes: bytes, name: name, mimeType: picked.mimeType ?? 'image/jpeg')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.shade700));
    }
  }

  /// Sube fotos del cuidador pendientes al backend (una a una)
  Future<void> _uploadPendingCaregiverPhotos() async {
    setState(() => _uploadingCaregiverPhotos = true);
    final token = AuthState.token;
    final newUrls = <String>[];
    try {
      for (final photo in List.from(_localCaregiverPhotos)) {
        final request = http.MultipartRequest('POST', Uri.parse('$_apiUrl/caregiver/profile/caregiver-photo'));
        request.headers['Authorization'] = 'Bearer $token';
        String mime = photo.mimeType;
        if (mime == 'image/jpg' || mime.isEmpty) mime = 'image/jpeg';
        request.files.add(http.MultipartFile.fromBytes('caregiverPhoto', photo.bytes, filename: photo.name, contentType: MediaType.parse(mime)));
        final res = await http.Response.fromStream(await request.send());
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['success'] == true) {
          newUrls.add(data['data']['photoUrl'] as String);
        } else {
          throw Exception(data['error']?['message'] ?? 'Error al subir foto');
        }
      }
      setState(() { _caregiverPhotoUrls.addAll(newUrls); _localCaregiverPhotos.clear(); });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error subiendo foto: $e'), backgroundColor: Colors.red.shade700));
      rethrow;
    } finally {
      if (mounted) setState(() => _uploadingCaregiverPhotos = false);
    }
  }

  /// Agrega foto al buffer local de una sección del lugar (máx 3)
  Future<void> _pickPlacePhoto(String section) async {
    final current = (_placePhotoUrls[section]?.length ?? 0) + (_localPlacePhotos[section]?.length ?? 0);
    if (current >= 3) return;
    final picked = await image_picker_pkg.ImagePicker()
        .pickImage(source: image_picker_pkg.ImageSource.gallery, imageQuality: 85);
    if (picked == null || !mounted) return;
    try {
      final bytes = await picked.readAsBytes();
      final name = picked.name.isEmpty ? 'place_${DateTime.now().millisecondsSinceEpoch}.jpg' : picked.name;
      setState(() {
        _localPlacePhotos[section] = [...(_localPlacePhotos[section] ?? []), (bytes: bytes, name: name, mimeType: picked.mimeType ?? 'image/jpeg')];
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.shade700));
    }
  }

  /// Sube todas las fotos de lugar pendientes al backend
  Future<void> _uploadPendingPlacePhotos() async {
    setState(() => _uploadingPlacePhotos = true);
    final token = AuthState.token;
    try {
      for (final entry in _localPlacePhotos.entries) {
        final section = entry.key;
        final newUrls = <String>[];
        for (final photo in List.from(entry.value)) {
          final request = http.MultipartRequest('POST', Uri.parse('$_apiUrl/caregiver/profile/place-photo'));
          request.headers['Authorization'] = 'Bearer $token';
          request.fields['section'] = section;
          String mime = photo.mimeType;
          if (mime == 'image/jpg' || mime.isEmpty) mime = 'image/jpeg';
          request.files.add(http.MultipartFile.fromBytes('placePhoto', photo.bytes, filename: photo.name, contentType: MediaType.parse(mime)));
          final res = await http.Response.fromStream(await request.send());
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          if (data['success'] == true) {
            newUrls.add(data['data']['photoUrl'] as String);
          } else {
            throw Exception(data['error']?['message'] ?? 'Error al subir foto de sección');
          }
        }
        setState(() {
          _placePhotoUrls[section] = [...(_placePhotoUrls[section] ?? []), ...newUrls];
          _localPlacePhotos[section] = [];
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error subiendo foto: $e'), backgroundColor: Colors.red.shade700));
      rethrow;
    } finally {
      if (mounted) setState(() => _uploadingPlacePhotos = false);
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
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
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
          SizedBox(key: _keyStep0Name, height: 0),
          Row(children: [
            Expanded(child: TextFormField(controller: _firstNameController, style: TextStyle(color: textColor),
                decoration: _field('Nombre', Icons.person_outlined))),
            const SizedBox(width: 12),
            Expanded(child: TextFormField(controller: _lastNameController, style: TextStyle(color: textColor),
                decoration: _field('Apellido', Icons.person_outline))),
          ]),
          const SizedBox(height: 16),

          SizedBox(key: _keyStep0Email, height: 0),
          TextFormField(controller: _emailController, keyboardType: TextInputType.emailAddress,
              style: TextStyle(color: textColor), decoration: _field('Correo electrónico', Icons.email_outlined)),
          const SizedBox(height: 16),

          SizedBox(key: _keyStep0Password, height: 0),
          TextFormField(controller: _passwordController, obscureText: true,
              style: TextStyle(color: textColor), decoration: _field('Contraseña (mínimo 8 caracteres)', Icons.lock_outlined)),
          const SizedBox(height: 16),

          SizedBox(key: _keyStep0Phone, height: 0),
          TextFormField(controller: _phoneController, keyboardType: TextInputType.number,
              style: TextStyle(color: textColor), decoration: _field('Teléfono (ej: 76543210)', Icons.phone_outlined)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text('8 dígitos, empieza con 6 o 7', style: TextStyle(color: subtextColor, fontSize: 12)),
          ),
          const SizedBox(height: 16),

          // ── Dirección ────────────────────────────────────────────
          SizedBox(key: _keyStep0Address, height: 0),
          AddressSection(
            isDark: isDark,
            textColor: textColor,
            subtextColor: subtextColor,
            borderColor: borderColor,
            surfaceEl: surfaceEl,
            streetController: _addressStreetController,
            numberController: _addressNumberController,
            apartmentController: _addressApartmentController,
            condominioController: _addressCondominioController,
            referenceController: _addressReferenceController,
            selectedZone: _addressZone,
            onZoneChanged: (val) => setState(() => _addressZone = val),
            addressLat: _addressLat,
            addressLng: _addressLng,
            isApartment: _isApartment,
            purposeText: 'Tu dirección es privada. Solo se comparte con dueños de mascotas que aceptes atender.',
            onMapResult: (result) => setState(() {
              _addressLat = result.lat;
              _addressLng = result.lng;
            }),
            onApartmentToggle: (val) => setState(() => _isApartment = val),
          ),
          const SizedBox(height: 16),

          // Date of birth
          SizedBox(key: _keyStep0Dob, height: 0),
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
    final surface      = isDark ? GardenColors.darkSurface        : GardenColors.lightSurface;

    final needsPlace = _servicesOffered.contains('HOSPEDAJE') || _servicesOffered.contains('GUARDERIA');
    final totalCaregiver = _caregiverPhotoUrls.length + _localCaregiverPhotos.length;

    // Secciones del lugar con metadata
    final placeSections = [
      (key: 'sala',         emoji: '🛋️',  label: 'Sala / Área principal',   required: true),
      (key: 'descanso',     emoji: '🛏️',  label: 'Zona de descanso',         required: true),
      (key: 'alimentacion', emoji: '🍽️',  label: 'Área de alimentación',     required: true),
      (key: 'jardin',       emoji: '🌿',  label: 'Jardín / Patio',           required: false),
      (key: 'juego',        emoji: '🎾',  label: 'Área de juego',            required: false),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Header ────────────────────────────────────────────────
          Text('Tus fotos', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: textColor, letterSpacing: -0.5)),
          const SizedBox(height: 6),
          Text(
            'Los dueños de mascotas quieren conocerte. Muéstrate en acción — estas fotos son lo primero que verán en tu perfil.',
            style: TextStyle(fontSize: 14, color: subtextColor, height: 1.5),
          ),

          const SizedBox(height: 24),

          // ── Sección: Fotos del cuidador ───────────────────────────
          _buildPhotoSectionHeader(
            emoji: '📸',
            title: 'Fotos tuyas en acción',
            subtitle: 'Paseando, jugando, cuidando mascotas — muéstrate como cuidador (mínimo 2, máximo 6)',
            isRequired: true,
            textColor: textColor,
            subtextColor: subtextColor,
          ),
          const SizedBox(height: 12),

          if (_uploadingCaregiverPhotos) _buildUploadingBar(borderColor),

          _buildPhotoGrid(
            uploaded: _caregiverPhotoUrls,
            local: _localCaregiverPhotos,
            maxPhotos: 6,
            onAdd: _uploadingCaregiverPhotos || _isLoading ? null : _pickCaregiverPhoto,
            onRemoveUploaded: (url) => setState(() => _caregiverPhotoUrls.remove(url)),
            onRemoveLocal: (i) => setState(() => _localCaregiverPhotos.removeAt(i)),
            surfaceEl: surfaceEl,
            subtextColor: subtextColor,
          ),
          const SizedBox(height: 6),
          _buildPhotoCount(totalCaregiver, 6, 2, _localCaregiverPhotos.isNotEmpty, subtextColor),

          if (needsPlace) ...[
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 20),

            // ── Sección: Fotos del hogar ──────────────────────────
            _buildPhotoSectionHeader(
              emoji: '🏠',
              title: 'Fotos de tu espacio',
              subtitle: 'Muestra los lugares donde estarán las mascotas. Mínimo 1 foto por sección obligatoria.',
              isRequired: true,
              textColor: textColor,
              subtextColor: subtextColor,
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: GardenColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: GardenColors.primary.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline, color: GardenColors.primary, size: 15),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  'Estas fotos se mostrarán al final de tu perfil, organizadas por sección.',
                  style: TextStyle(fontSize: 12, color: subtextColor, height: 1.4),
                )),
              ]),
            ),
            const SizedBox(height: 20),

            if (_uploadingPlacePhotos) _buildUploadingBar(borderColor),

            ...placeSections.map((sec) {
              final uploaded = _placePhotoUrls[sec.key] ?? [];
              final local = _localPlacePhotos[sec.key] ?? [];
              final total = uploaded.length + local.length;
              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header de sección
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                        child: Row(children: [
                          Text(sec.emoji, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Text(sec.label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
                              if (sec.required) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: GardenColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                                  child: const Text('Obligatorio', style: TextStyle(fontSize: 10, color: GardenColors.primary, fontWeight: FontWeight.w600)),
                                ),
                              ] else ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(20)),
                                  child: Text('Opcional', style: TextStyle(fontSize: 10, color: subtextColor)),
                                ),
                              ],
                            ]),
                            const SizedBox(height: 2),
                            Text('$total / 3 fotos', style: TextStyle(fontSize: 11, color: subtextColor)),
                          ])),
                        ]),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: _buildPlaceSectionGrid(
                          section: sec.key,
                          uploaded: uploaded,
                          local: local,
                          surfaceEl: surfaceEl,
                          subtextColor: subtextColor,
                          borderColor: borderColor,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildPhotoSectionHeader({
    required String emoji, required String title, required String subtitle,
    required bool isRequired, required Color textColor, required Color subtextColor,
  }) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(emoji, style: const TextStyle(fontSize: 22)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textColor)),
          if (isRequired) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: GardenColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: const Text('Obligatorio', style: TextStyle(fontSize: 11, color: GardenColors.primary, fontWeight: FontWeight.w600)),
            ),
          ],
        ]),
        const SizedBox(height: 3),
        Text(subtitle, style: TextStyle(fontSize: 12, color: subtextColor, height: 1.4)),
      ])),
    ]);
  }

  Widget _buildUploadingBar(Color borderColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(children: [
        const Text('Subiendo fotos...', style: TextStyle(color: GardenColors.primary, fontSize: 12)),
        const SizedBox(height: 4),
        LinearProgressIndicator(backgroundColor: borderColor, valueColor: const AlwaysStoppedAnimation<Color>(GardenColors.primary)),
      ]),
    );
  }

  Widget _buildPhotoCount(int total, int max, int min, bool hasPending, Color subtextColor) {
    return Text(
      '$total/$max fotos · Mínimo $min${hasPending ? " · pendientes de subir" : ""}',
      style: TextStyle(color: hasPending ? Colors.orange.shade400 : subtextColor, fontSize: 12),
    );
  }

  Widget _buildPhotoGrid({
    required List<String> uploaded,
    required List<({Uint8List bytes, String name, String mimeType})> local,
    required int maxPhotos,
    required VoidCallback? onAdd,
    required void Function(String url) onRemoveUploaded,
    required void Function(int i) onRemoveLocal,
    required Color surfaceEl,
    required Color subtextColor,
  }) {
    return GridView.count(
      crossAxisCount: 3,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1,
      children: [
        ...uploaded.asMap().entries.map((e) => _photoCell(
          child: Image.network(fixImageUrl(e.value), fit: BoxFit.cover),
          badge: const Icon(Icons.check, color: Colors.white, size: 12),
          badgeColor: GardenColors.success,
          onRemove: () => onRemoveUploaded(e.value),
        )),
        ...local.asMap().entries.map((e) => _photoCell(
          child: Image.memory(e.value.bytes, fit: BoxFit.cover),
          badge: const Icon(Icons.cloud_upload_outlined, color: Colors.white, size: 12),
          badgeColor: Colors.orange.shade700,
          onRemove: () => onRemoveLocal(e.key),
        )),
        if (uploaded.length + local.length < maxPhotos)
          GestureDetector(
            onTap: onAdd,
            child: Container(
              decoration: BoxDecoration(
                color: surfaceEl,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: GardenColors.primary.withValues(alpha: 0.3)),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.add_photo_alternate_outlined, color: GardenColors.primary, size: 28),
                const SizedBox(height: 4),
                Text('Añadir', style: TextStyle(color: subtextColor, fontSize: 10)),
              ]),
            ),
          ),
      ],
    );
  }

  Widget _buildPlaceSectionGrid({
    required String section,
    required List<String> uploaded,
    required List<({Uint8List bytes, String name, String mimeType})> local,
    required Color surfaceEl,
    required Color subtextColor,
    required Color borderColor,
  }) {
    return Row(children: [
      ...uploaded.asMap().entries.map((e) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: SizedBox(width: 72, height: 72, child: _photoCell(
          child: Image.network(fixImageUrl(e.value), fit: BoxFit.cover),
          badge: const Icon(Icons.check, color: Colors.white, size: 11),
          badgeColor: GardenColors.success,
          onRemove: () => setState(() => _placePhotoUrls[section]?.remove(e.value)),
        )),
      )),
      ...local.asMap().entries.map((e) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: SizedBox(width: 72, height: 72, child: _photoCell(
          child: Image.memory(e.value.bytes, fit: BoxFit.cover),
          badge: const Icon(Icons.cloud_upload_outlined, color: Colors.white, size: 11),
          badgeColor: Colors.orange.shade700,
          onRemove: () => setState(() { final l = _localPlacePhotos[section]; l?.removeAt(e.key); }),
        )),
      )),
      if (uploaded.length + local.length < 3)
        SizedBox(width: 72, height: 72, child: GestureDetector(
          onTap: _uploadingPlacePhotos || _isLoading ? null : () => _pickPlacePhoto(section),
          child: Container(
            decoration: BoxDecoration(
              color: surfaceEl,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: GardenColors.primary.withValues(alpha: 0.3)),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.add_a_photo_outlined, color: GardenColors.primary, size: 22),
              const SizedBox(height: 3),
              Text('Foto', style: TextStyle(color: subtextColor, fontSize: 9)),
            ]),
          ),
        )),
    ]);
  }

  Widget _photoCell({required Widget child, required Widget badge, required Color badgeColor, required VoidCallback onRemove}) {
    return Stack(fit: StackFit.expand, children: [
      ClipRRect(borderRadius: BorderRadius.circular(10), child: child),
      Positioned(top: 4, left: 4, child: Container(
        decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
        padding: const EdgeInsets.all(3),
        child: badge,
      )),
      Positioned(top: 4, right: 4, child: GestureDetector(
        onTap: onRemove,
        child: Container(
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
          padding: const EdgeInsets.all(3),
          child: const Icon(Icons.close, color: Colors.white, size: 11),
        ),
      )),
    ]);
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
          decoration: BoxDecoration(
            color: selected ? GardenColors.primary.withValues(alpha: 0.1) : surfaceEl,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? GardenColors.primary : borderColor,
              width: selected ? 2 : 1,
            ),
            boxShadow: selected ? [
              BoxShadow(color: GardenColors.primary.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 3)),
            ] : [],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 30)),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? GardenColors.primary : textColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              if (selected) ...[
                const SizedBox(height: 6),
                Container(
                  width: 20, height: 20,
                  decoration: const BoxDecoration(color: GardenColors.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, size: 13, color: Colors.white),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('¿Qué ofreces?', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: textColor, letterSpacing: -0.5)),
          const SizedBox(height: 6),
          Text('Selecciona los servicios que brindarás', style: TextStyle(fontSize: 14, color: subtextColor, height: 1.4)),
          const SizedBox(height: 28),

          SizedBox(key: _keyStep1Services, height: 0),
          Text('SERVICIOS', style: TextStyle(color: subtextColor, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: serviceCard('HOSPEDAJE', '🏠', 'Hospedaje')),
            const SizedBox(width: 12),
            Expanded(child: serviceCard('PASEO', '🦮', 'Paseo')),
            const SizedBox(width: 12),
            Expanded(child: serviceCard('GUARDERIA', '🏡', 'Guardería')),
          ]),
          const SizedBox(height: 28),

          if (_servicesOffered.contains('HOSPEDAJE')) ...[
            const SizedBox(height: 4),
            Text('TU HOGAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: subtextColor, letterSpacing: 1.2)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _homeType = 'HOUSE'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    decoration: BoxDecoration(
                      color: _homeType == 'HOUSE' ? GardenColors.primary : surfaceEl,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _homeType == 'HOUSE' ? GardenColors.primary : borderColor),
                    ),
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Casa 🏡', style: TextStyle(
                        color: _homeType == 'HOUSE' ? Colors.white : textColor,
                        fontWeight: _homeType == 'HOUSE' ? FontWeight.bold : FontWeight.normal,
                        fontSize: 14,
                      )),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _homeType = 'APARTMENT'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    decoration: BoxDecoration(
                      color: _homeType == 'APARTMENT' ? GardenColors.primary : surfaceEl,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _homeType == 'APARTMENT' ? GardenColors.primary : borderColor),
                    ),
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Departamento 🏢', style: TextStyle(
                        color: _homeType == 'APARTMENT' ? Colors.white : textColor,
                        fontWeight: _homeType == 'APARTMENT' ? FontWeight.bold : FontWeight.normal,
                        fontSize: 14,
                      )),
                    ),
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
          title: Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text(subtitle, style: TextStyle(color: subtextColor, fontSize: 12)),
          value: value,
          activeColor: GardenColors.primary,
          onChanged: onChanged,
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('¿Cuándo estás disponible?', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: textColor, letterSpacing: -0.5)),
          const SizedBox(height: 6),
          Text('Selecciona los días y horarios en que puedes cuidar mascotas', style: TextStyle(fontSize: 14, color: subtextColor)),
          const SizedBox(height: 28),

          SizedBox(key: _keyStep2Days, height: 0),
          Text('DÍAS DISPONIBLES', style: TextStyle(color: subtextColor, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          const SizedBox(height: 12),
          availSwitch('Días de semana', 'Lunes a Viernes', _weekdays, (v) => setState(() => _weekdays = v)),
          availSwitch('Fines de semana', 'Sábado y Domingo', _weekends, (v) => setState(() => _weekends = v)),
          availSwitch('Feriados', 'Días festivos nacionales', _holidays, (v) => setState(() => _holidays = v)),

          const SizedBox(height: 12),
          SizedBox(key: _keyStep2Times, height: 0),
          Text('HORARIOS', style: TextStyle(color: subtextColor, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── PASO 5: Precio ────────────────────────────────────────
  Widget _buildPriceCard({
    required String titulo,
    required String unidad,
    required String emoji,
    required double value,
    required ValueChanged<double> onChanged,
    String? infoNote,
  }) {
    final isDark = themeNotifier.isDark;
    // Fondo oscuro intencional en ambos modos (hace que el precio grande resalte)
    // Light: forest green profundo. Dark: bosque aún más oscuro.
    final cardBg = isDark ? GardenColors.darkSurface : GardenColors.forest;

    const double sliderMin = 10.0;
    const double sliderMax = 400.0;
    final double sv = value.clamp(sliderMin, sliderMax);
    final double ratio = (sv - sliderMin) / (sliderMax - sliderMin);
    final String posicion = ratio < 0.25 ? 'ECONÓMICO' : ratio < 0.6 ? 'ESTÁNDAR' : 'PREMIUM';
    // Colores de posición usando el sistema de colores de Garden
    final Color posicionColor = posicion == 'ECONÓMICO'
        ? GardenColors.info
        : posicion == 'PREMIUM' ? GardenColors.warning : GardenColors.accent;
    final Color posicionText = posicion == 'PREMIUM'
        ? GardenColors.darkBackground
        : posicion == 'ECONÓMICO' ? Colors.white : GardenColors.darkBackground;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [BoxShadow(color: GardenColors.forest.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 8),
          Text(titulo, style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
        ]),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Text('Bs ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white60)),
            Text(sv.toStringAsFixed(0), style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: Colors.white, height: 1.0, letterSpacing: -1)),
          ],
        ),
        const SizedBox(height: 4),
        Text(unidad, style: const TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 0.3)),
        if (infoNote != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Text(infoNote, style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.4), textAlign: TextAlign.center),
          ),
        ],
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(color: posicionColor, borderRadius: BorderRadius.circular(20)),
          child: Text(posicion, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: posicionText, letterSpacing: 0.5)),
        ),
        const SizedBox(height: 14),
        SliderTheme(
          data: const SliderThemeData(
            trackHeight: 5,
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10),
            overlayShape: RoundSliderOverlayShape(overlayRadius: 18),
          ),
          child: Slider(
            value: sv, min: sliderMin, max: sliderMax, divisions: 78,
            activeColor: GardenColors.lime, inactiveColor: Colors.white.withValues(alpha: 0.18), thumbColor: Colors.white,
            label: 'Bs ${sv.toStringAsFixed(0)}',
            onChanged: onChanged,
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Bs 10', style: TextStyle(color: Colors.white38, fontSize: 11)),
          const Text('Bs 400', style: TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
      ]),
    );
  }

  Widget _buildStep5() {
    final isDark = themeNotifier.isDark;
    final textColor    = isDark ? GardenColors.darkTextPrimary   : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    final offersHospedaje = _servicesOffered.contains('HOSPEDAJE');
    final offersPaseo     = _servicesOffered.contains('PASEO');
    final offersGuarderia = _servicesOffered.contains('GUARDERIA');
    final serviceCount    = [offersHospedaje, offersPaseo, offersGuarderia].where((b) => b).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text('Tus tarifas', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: textColor, letterSpacing: -0.5)),
          const SizedBox(height: 6),
          Text(
            serviceCount > 1
                ? 'Fija un precio para cada servicio que ofreces. Puedes ajustarlos cuando quieras.'
                : 'Fija tu tarifa. Puedes ajustarla cuando quieras.',
            style: TextStyle(fontSize: 14, color: subtextColor, height: 1.5),
          ),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.info_outline, color: GardenColors.primary, size: 14),
            const SizedBox(width: 6),
            Expanded(child: Text('Precio mínimo: Bs 10', style: TextStyle(fontSize: 12, color: subtextColor))),
          ]),
          const SizedBox(height: 24),

          if (offersHospedaje) ...[
            _buildPriceCard(titulo: 'Hospedaje', unidad: '/ noche', emoji: '🏠', value: _precioHospedaje, onChanged: (v) => setState(() => _precioHospedaje = v)),
            const SizedBox(height: 20),
          ],
          if (offersPaseo) ...[
            _buildPriceCard(
              titulo: 'Paseo',
              unidad: '/ 1 hora',
              emoji: '🦮',
              value: _precioPaseo,
              onChanged: (v) => setState(() => _precioPaseo = v),
              infoNote: '30 min = Bs ${(_precioPaseo / 2).toStringAsFixed(0)} · Este precio aparecerá en tu perfil',
            ),
            const SizedBox(height: 20),
          ],
          if (offersGuarderia) ...[
            _buildPriceCard(titulo: 'Guardería', unidad: '/ hora', emoji: '🏡', value: _precioGuarderia, onChanged: (v) => setState(() => _precioGuarderia = v)),
            const SizedBox(height: 12),
            // Toggle: ¿La guardería incluye paseo?
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _guarderiaIncludeWalk
                    ? GardenColors.forest.withValues(alpha: 0.07)
                    : (isDark ? GardenColors.darkSurface : GardenColors.lightSurface),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _guarderiaIncludeWalk
                      ? GardenColors.forest.withValues(alpha: 0.35)
                      : (isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
                ),
              ),
              child: Row(
                children: [
                  const Text('🦮', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Incluye paseo',
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Activa si tu guardería incluye un paseo durante el día. Se mostrará en tu perfil.',
                          style: TextStyle(color: subtextColor, fontSize: 12, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: _guarderiaIncludeWalk,
                    onChanged: (v) => setState(() => _guarderiaIncludeWalk = v),
                    activeColor: GardenColors.forest,
                  ),
                ],
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
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
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

            const Text('Máximo de mascotas simultáneas', style: TextStyle(color: kTextSecondary)),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [1, 2, 3].map((n) {
                final selected = _maxPets == n;
                return GestureDetector(
                  onTap: () => setState(() => _maxPets = n),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: selected ? kPrimaryColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: selected ? kPrimaryColor : Colors.grey.shade400, width: selected ? 2 : 1),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$n', style: TextStyle(color: selected ? Colors.white : Colors.grey.shade700, fontSize: 26, fontWeight: FontWeight.w800)),
                        Text(n == 1 ? 'mascota' : 'mascotas', style: TextStyle(color: selected ? Colors.white70 : Colors.grey.shade500, fontSize: 10)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
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
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('Tu foto de perfil', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: textColor, letterSpacing: -0.5)),
          const SizedBox(height: 10),
          Text(
            'Es lo primero que verán los dueños de mascotas. Sube una foto clara, sonriendo — idealmente con una mascota.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: subtextColor, height: 1.5),
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
        servicesOffered: _servicesOffered,
        showPhotos: false, // fotos ya subidas en Paso 2
      );
    } else if (_currentStep == 7) {
      postRegStep = VerificationScreen(
        showAppBar: false,
        onComplete: _onIdentityVerificationComplete,
      );
    } else if (_currentStep == 8) {
      postRegStep = PhoneVerificationScreen(
        showAppBar: false,
        phoneNumber: _phoneController.text.trim(),
        onComplete: _onPhoneVerificationComplete,
        onChangePhone: (newPhone) async {
          // Actualiza el teléfono en el perfil y recarga el paso para enviar nuevo OTP
          _phoneController.text = newPhone;
          await _patchProfile({'phone': newPhone});
          if (mounted) setState(() {}); // rebuild para que PhoneVerificationScreen reciba nuevo número
        },
      );
    } else {
      postRegStep = const SizedBox.shrink();
    }

    final steps = [
      _buildStep1(),   // 0: Datos personales → register
      _buildStep7(),   // 1: Foto de perfil (primera impresión, involucra al cuidador)
      _buildStep3(),   // 2: Servicios y zona
      _buildStep5(),   // 3: Precio (flujo natural: ofrezco X → cobro Y)
      _buildStep4(),   // 4: Disponibilidad básica
      _buildStep2(),   // 5: Fotos del lugar/acción
      postRegStep,     // 6: Perfil profesional
      postRegStep,     // 7: Verificación de identidad
      postRegStep,     // 8: Verificación de teléfono
    ];

    final stepTitles = [
      'Datos básicos',
      'Foto de perfil',
      'Servicios',
      'Precio',
      'Disponibilidad',
      'Fotos',
      'Perfil profesional',
      'Verificación ID',
      'Verificar Teléfono',
    ];

    // Steps 6-9 are embedded screens that manage their own "Continue" buttons.
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
            appBar: kIsWeb ? null : AppBar(
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
                // ── Web top bar (replaces AppBar on web) ──────────────────
                if (kIsWeb) ...[
                  Container(
                    decoration: BoxDecoration(
                      color: surface,
                      border: Border(bottom: BorderSide(color: borderColor)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: Column(
                          children: [
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                if (_currentStep > 0)
                                  IconButton(
                                    icon: Icon(Icons.arrow_back_rounded, color: textColor, size: 18),
                                    onPressed: _prevStep,
                                    tooltip: 'Paso anterior',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  ),
                                if (_currentStep > 0) const SizedBox(width: 8),
                                Text(
                                  'Crear perfil de cuidador',
                                  style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700),
                                ),
                                const Spacer(),
                                Text(
                                  'Paso ${_currentStep + 1} de 9',
                                  style: TextStyle(color: subtextColor, fontSize: 12),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: GardenColors.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    stepTitles[_currentStep],
                                    style: const TextStyle(color: GardenColors.primary, fontSize: 11, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: (_currentStep + 1) / 9,
                                backgroundColor: borderColor,
                                valueColor: const AlwaysStoppedAnimation<Color>(GardenColors.primary),
                                minHeight: 3,
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],

                // ── Mobile step indicator ─────────────────────────────────
                if (!kIsWeb) ...[
                  Container(
                    color: surface,
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  stepTitles[_currentStep],
                                  style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  'Paso ${_currentStep + 1} de 9',
                                  style: TextStyle(color: subtextColor, fontSize: 11),
                                ),
                              ],
                            ),
                            // Dots: 9 pasos, llenos los completados
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(9, (i) {
                                final done   = i < _currentStep;
                                final active = i == _currentStep;
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: const EdgeInsets.symmetric(horizontal: 2),
                                  width:  active ? 18 : 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: done || active
                                        ? GardenColors.primary
                                        : borderColor,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                );
                              }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: (_currentStep + 1) / 9,
                            backgroundColor: borderColor,
                            valueColor: const AlwaysStoppedAnimation<Color>(GardenColors.primary),
                            minHeight: 3,
                          ),
                        ),
                        const SizedBox(height: 1),
                      ],
                    ),
                  ),
                  Container(height: 1, color: borderColor),
                ],

                // Step content
                Expanded(
                  child: kIsWeb
                      ? Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 640),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: KeyedSubtree(
                                key: ValueKey(_currentStep),
                                child: steps[_currentStep],
                              ),
                            ),
                          ),
                        )
                      : AnimatedSwitcher(
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
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: kIsWeb ? 640 : double.infinity),
                        child: Row(
                          children: [
                            if (_currentStep > 0 && !kIsWeb) ...[
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
