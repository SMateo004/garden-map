import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import '../legal/legal_screen.dart';

class CaregiverProfileDataScreen extends StatefulWidget {
  /// When true, the screen hides its own AppBar/Scaffold and calls
  /// [onSaveComplete] instead of `Navigator.pop()` after a successful save.
  final bool embeddedMode;
  final VoidCallback? onSaveComplete;

  /// Optional pre-loaded profile data (e.g. passed from the setup flow).
  /// When provided, fields are filled immediately — no loading spinner — and
  /// the API is called in the background to refresh with the latest values.
  final Map<String, dynamic>? initialProfile;

  const CaregiverProfileDataScreen({
    super.key,
    this.embeddedMode = false,
    this.onSaveComplete,
    this.initialProfile,
  });

  @override
  State<CaregiverProfileDataScreen> createState() => _CaregiverProfileDataScreenState();
}

class _CaregiverProfileDataScreenState extends State<CaregiverProfileDataScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _termsAccepted = false;
  bool _verificationAccepted = false;
  String _caregiverToken = '';
  int _completionPercentage = 0;

  // GlobalKeys for scroll-to-field on validation error
  final _keyBio = GlobalKey();
  final _keyBioDetail = GlobalKey();
  final _keyAddress = GlobalKey();
  final _keyServices = GlobalKey();
  final _keySpaceType = GlobalKey();
  final _keyPriceWalk = GlobalKey();
  final _keyPriceHospedaje = GlobalKey();
  final _keyPetTypes = GlobalKey();
  final _keySizes = GlobalKey();
  final _keyPhotos = GlobalKey();
  final _keyFaq = GlobalKey();
  final _keyExperience = GlobalKey();
  final _keyPolicies = GlobalKey();
  final _keyHandleAnxious = GlobalKey();
  final _keyEmergencyResponse = GlobalKey();
  final _keyTerms = GlobalKey();

  // Controllers
  final _bioController = TextEditingController();
  final _bioDetailController = TextEditingController();
  final _addressController = TextEditingController();
  final _pricePerDayController = TextEditingController();
  final _pricePerWalk30Controller = TextEditingController();
  final _pricePerWalk60Controller = TextEditingController();
  final _pricePerGuarderiaController = TextEditingController();
  final _includesController = TextEditingController();
  final _emergencyController = TextEditingController();
  final _requirementsController = TextEditingController();

  // Campos de experiencia y comportamiento
  final _experienceYearsController = TextEditingController();
  final _experienceDescController = TextEditingController();
  final _whyCaregiverController = TextEditingController();
  final _whatDiffersController = TextEditingController();
  final _handleAnxiousController = TextEditingController();
  final _emergencyResponseController = TextEditingController();
  bool? _acceptAggressive;
  bool? _acceptPuppies;
  bool? _acceptSeniors;

  // Selecciones
  String _selectedZone = 'EQUIPETROL';
  List<String> _selectedServices = [];
  List<String> _selectedHomeTypes = [];
  bool _offersWalk30 = false; // ¿Ofrece paseos de 30 min? (precio = mitad de 60 min)
  bool _hasYard = false;
  bool _allowsLargePets = false;
  bool _allowsMultiplePets = false;
  int _maxPets = 1;
  List<String> _acceptedPetTypes = [];
  List<String> _acceptedSizes = [];
  bool _weekdays = true;
  bool _weekends = false;
  bool _holidays = false;
  bool _morningSlot = true;
  bool _afternoonSlot = true;
  bool _nightSlot = false;
  List<String> _photos = [];
  final List<Uint8List?> _localPhotoData = [];

  static const _homeTypes = ['HOUSE', 'APARTMENT', 'FINCA', 'LOCAL'];
  static const _homeTypeLabels = {
    'HOUSE': '🏠 Casa',
    'APARTMENT': '🏢 Apartamento',
    'FINCA': '🌾 Finca',
    'LOCAL': '🏪 Local',
  };

  static const _petTypes = ['DOGS', 'CATS'];
  static const _petTypeLabels = {
    'DOGS': '🐶 Perros',
    'CATS': '🐱 Gatos',
  };

  static const _petSizes = ['SMALL', 'MEDIUM', 'LARGE', 'GIANT'];
  static const _petSizeLabels = {
    'SMALL': '🐾 Pequeño (<5kg)',
    'MEDIUM': '🐕 Mediano (5-20kg)',
    'LARGE': '🦮 Grande (20-40kg)',
    'GIANT': '🐘 Gigante (+40kg)',
  };

  static const _zones = ['EQUIPETROL', 'URBARI', 'NORTE', 'LAS_PALMAS', 'CENTRO_SAN_MARTIN', 'OTROS'];

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  @override
  void initState() {
    super.initState();
    if (widget.initialProfile != null) {
      // Pre-fill immediately from the parent-provided data (no spinner),
      // then silently refresh from the API in the background.
      _applyProfile(widget.initialProfile!);
      _isLoading = false;
      Future.microtask(_refreshFromApi);
    } else {
      _loadData();
    }
  }

  /// Reads the enabled flag from multiple possible sources in priority order:
  /// 1. slots value (bool from serviceDetails.availability.slots)
  /// 2. block object (Map with 'enabled' key, from defaultAvailabilitySchedule.paseoTimeBlocks.morning)
  /// 3. legacy bool (from old MANANA/TARDE/NOCHE format)
  bool _extractBlockEnabled(dynamic slotVal, dynamic blockObj, dynamic legacyBool, {required bool defaultValue}) {
    if (slotVal is bool) return slotVal;
    if (blockObj is Map) return blockObj['enabled'] as bool? ?? defaultValue;
    if (blockObj is bool) return blockObj;
    if (legacyBool is bool) return legacyBool;
    return defaultValue;
  }

  /// Populates all state variables from a profile map.
  /// Does NOT call setState — callers are responsible for wrapping in
  /// setState when appropriate (or calling directly in initState).
  void _applyProfile(Map<String, dynamic> profile) {
    final details = profile['serviceDetails'] ?? {};
    final faq = details['faq'] ?? {};
    final availability = details['availability'] ?? {};
    final slots = availability['slots'] ?? {};
    final defaultSchedule = profile['defaultAvailabilitySchedule'] ?? {};
    final paseoBlocks = defaultSchedule['paseoTimeBlocks'] ?? {};

    _bioController.text = profile['bio'] ?? '';
    _bioDetailController.text = profile['bioDetail'] ?? '';
    _addressController.text = profile['address'] ?? '';
    _pricePerDayController.text = (profile['pricePerDay'] ?? 0).toString();
    _pricePerWalk30Controller.text = (profile['pricePerWalk30'] ?? 0).toString();
    _pricePerWalk60Controller.text = (profile['pricePerWalk60'] ?? 0).toString();
    // Pre-rellena con precio de paseo/hora si no tiene precio de guardería configurado
    final savedGuarderia = profile['pricePerGuarderia'];
    _pricePerGuarderiaController.text = savedGuarderia != null && (savedGuarderia as num) > 0
        ? savedGuarderia.toString()
        : (profile['pricePerWalk60'] ?? 0).toString();
    _includesController.text = faq['includes'] ?? '';
    _emergencyController.text = faq['emergency'] ?? '';
    _requirementsController.text = faq['requirements'] ?? '';
    _selectedZone = profile['zone'] ?? 'EQUIPETROL';
    _selectedServices = List<String>.from(profile['servicesOffered'] ?? []);
    _selectedHomeTypes = List<String>.from(profile['spaceType'] ?? []);
    // offersWalk30: true si pricePerWalk30 > 0, o si la API lo devuelve explícitamente
    _offersWalk30 = (profile['offersWalk30'] as bool?) ??
        ((profile['pricePerWalk30'] as num?)?.toDouble() ?? 0) > 0;
    _hasYard = profile['hasYard'] ?? false;
    _allowsLargePets = details['allowsLargePets'] ?? false;
    _allowsMultiplePets = details['allowsMultiplePets'] ?? false;
    _maxPets = details['maxPets'] ?? 1;
    // Prioridad: campo animalTypes del DB (fuente de verdad para el marketplace)
    // Fallback: serviceDetails.acceptedPetTypes (legacy)
    final dbAnimalTypes = List<String>.from(profile['animalTypes'] ?? []);
    _acceptedPetTypes = dbAnimalTypes.isNotEmpty
        ? dbAnimalTypes
        : List<String>.from(details['acceptedPetTypes'] ?? []);
    _acceptedSizes = List<String>.from(details['acceptedSizes'] ?? []);
    _weekdays = availability['weekdays'] ?? defaultSchedule['weekdays'] ?? true;
    _weekends = availability['weekends'] ?? defaultSchedule['weekends'] ?? false;
    _holidays = availability['holidays'] ?? defaultSchedule['holidays'] ?? false;
    _morningSlot   = _extractBlockEnabled(slots['morning'],   paseoBlocks['morning'],   paseoBlocks['MANANA'],   defaultValue: true);
    _afternoonSlot = _extractBlockEnabled(slots['afternoon'], paseoBlocks['afternoon'], paseoBlocks['TARDE'],    defaultValue: true);
    _nightSlot     = _extractBlockEnabled(slots['night'],     paseoBlocks['night'],     paseoBlocks['NOCHE'],    defaultValue: false);
    _photos = List<String>.from(profile['photos'] ?? []);
    _localPhotoData
      ..clear()
      ..addAll(List.filled(_photos.length, null));

    _experienceYearsController.text = (profile['experienceYears'] ?? '').toString();
    if (_experienceYearsController.text == '5') _experienceYearsController.text = '5+';
    _experienceDescController.text = profile['experienceDescription'] as String? ?? '';
    _whyCaregiverController.text = profile['whyCaregiver'] as String? ?? '';
    _whatDiffersController.text = profile['whatDiffers'] as String? ?? '';
    _handleAnxiousController.text = profile['handleAnxious'] as String? ?? '';
    _emergencyResponseController.text = profile['emergencyResponse'] as String? ?? '';
    _acceptAggressive = profile['acceptAggressive'] as bool?;
    _acceptPuppies = profile['acceptPuppies'] as bool?;
    _acceptSeniors = profile['acceptSeniors'] as bool?;
    _termsAccepted = profile['termsAccepted'] == true;
    _verificationAccepted = profile['verificationAccepted'] == true;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _caregiverToken = prefs.getString('access_token') ?? '';

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/caregiver/my-profile'),
        headers: {'Authorization': 'Bearer $_caregiverToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _applyProfile(data['data']));
        _computeCompletion();
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Silently refreshes fields from the API without showing a loading spinner.
  /// Called in the background when [initialProfile] was provided.
  Future<void> _refreshFromApi() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    _caregiverToken = prefs.getString('access_token') ?? '';
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/caregiver/my-profile'),
        headers: {'Authorization': 'Bearer $_caregiverToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true && mounted) {
        setState(() => _applyProfile(data['data']));
        _computeCompletion();
      }
    } catch (e) {
      debugPrint('Background profile refresh error: $e');
    }
  }

  void _computeCompletion() {
    int score = 0;
    int total = 10;
    if (_bioController.text.isNotEmpty) score++;
    if (_bioDetailController.text.isNotEmpty) score++;
    if (_addressController.text.isNotEmpty) score++;
    if (_selectedServices.isNotEmpty) score++;
    if (_selectedHomeTypes.isNotEmpty) score++;
    if (_acceptedPetTypes.isNotEmpty) score++;
    if (_acceptedSizes.isNotEmpty) score++;
    if (_photos.isNotEmpty) {
      if (_selectedServices.contains('HOSPEDAJE')) {
        if (_photos.length >= 4) score++;
      } else {
        if (_photos.length >= 2) score++;
      }
    }
    
    if (_selectedServices.contains('HOSPEDAJE')) {
      if (_pricePerDayController.text != '0') score++;
      if (_selectedHomeTypes.isNotEmpty) score++;
    }
    
    if (_selectedServices.contains('PASEO')) {
      if (_pricePerWalk60Controller.text != '0') score++;
    }

    if (_includesController.text.isNotEmpty) score++;
    if (_experienceYearsController.text.isNotEmpty && _experienceDescController.text.length >= 20) score++;
    
    total = 11;
    setState(() => _completionPercentage = ((score / total) * 100).round());
  }

  void _showValidationError(String msg, {GlobalKey? scrollTo}) {
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
      backgroundColor: GardenColors.error,
      duration: const Duration(seconds: 5),
      action: scrollTo?.currentContext != null
          ? SnackBarAction(
              label: 'Ir al campo',
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
    setState(() => _isSaving = false);
  }

  Future<void> _saveAllData() async {
    // ── Validación completa de campos obligatorios ──
    if (_bioDetailController.text.trim().length < 10) {
      return _showValidationError('La descripción detallada debe tener al menos 10 caracteres', scrollTo: _keyBioDetail);
    }
    if (_selectedServices.isEmpty) {
      return _showValidationError('Selecciona al menos un servicio', scrollTo: _keyServices);
    }
    if (_selectedServices.contains('HOSPEDAJE') && _selectedHomeTypes.isEmpty) {
      return _showValidationError('Selecciona al menos un tipo de espacio para hospedaje', scrollTo: _keySpaceType);
    }
    if (_acceptedPetTypes.isEmpty) {
      return _showValidationError('Selecciona al menos un tipo de mascota que aceptas', scrollTo: _keyPetTypes);
    }
    if (_acceptedSizes.isEmpty) {
      return _showValidationError('Selecciona al menos un tamaño de mascota aceptado', scrollTo: _keySizes);
    }

    if (_selectedServices.contains('PASEO')) {
      if ((_pricePerWalk60Controller.text.trim().isEmpty) ||
          (double.tryParse(_pricePerWalk60Controller.text) ?? 0) <= 0) {
        return _showValidationError('Ingresa el precio del paseo (1 hora)', scrollTo: _keyPriceWalk);
      }
    }
    if (_selectedServices.contains('HOSPEDAJE')) {
      if ((_pricePerDayController.text.trim().isEmpty) ||
          (double.tryParse(_pricePerDayController.text) ?? 0) <= 0) {
        return _showValidationError('Ingresa el precio por noche del hospedaje', scrollTo: _keyPriceHospedaje);
      }
    }
    if (_selectedServices.contains('GUARDERIA')) {
      if ((_pricePerGuarderiaController.text.trim().isEmpty) ||
          (double.tryParse(_pricePerGuarderiaController.text) ?? 0) <= 0) {
        return _showValidationError('Ingresa el precio por hora de guardería');
      }
    }

    // FAQ
    if (_includesController.text.trim().length < 5) {
      return _showValidationError('Describe qué incluye tu servicio (sección Preguntas frecuentes)', scrollTo: _keyFaq);
    }
    if (_requirementsController.text.trim().length < 5) {
      return _showValidationError('Describe los requisitos de tu servicio (sección Preguntas frecuentes)', scrollTo: _keyFaq);
    }
    // Campos del perfil profesional
    final expYearsText = _experienceYearsController.text.trim().replaceAll('+', '');
    if (expYearsText.isEmpty || int.tryParse(expYearsText) == null) {
      return _showValidationError('Ingresa los años de experiencia', scrollTo: _keyExperience);
    }
    if (_experienceDescController.text.trim().length < 5) {
      return _showValidationError('Describe tu experiencia (mínimo 5 caracteres)', scrollTo: _keyExperience);
    }
    if (_whyCaregiverController.text.trim().length < 3) {
      return _showValidationError('Explica por qué eres cuidador', scrollTo: _keyExperience);
    }
    if (_whatDiffersController.text.trim().length < 3) {
      return _showValidationError('Explica qué te diferencia de otros cuidadores', scrollTo: _keyExperience);
    }
    if (_handleAnxiousController.text.trim().length < 3) {
      return _showValidationError('Describe cómo manejas mascotas ansiosas', scrollTo: _keyHandleAnxious);
    }
    if (_emergencyResponseController.text.trim().length < 3) {
      return _showValidationError('Describe cómo respondes a emergencias médicas', scrollTo: _keyEmergencyResponse);
    }
    if (_acceptAggressive == null) {
      return _showValidationError('Indica si aceptas mascotas agresivas (Sí/No)', scrollTo: _keyPolicies);
    }
    if (_acceptPuppies == null) {
      return _showValidationError('Indica si aceptas cachorros (Sí/No)', scrollTo: _keyPolicies);
    }
    if (_acceptSeniors == null) {
      return _showValidationError('Indica si aceptas mascotas mayores (Sí/No)', scrollTo: _keyPolicies);
    }

    if (widget.embeddedMode && !_termsAccepted) {
      return _showValidationError('Debes aceptar los Términos de Servicio y la Política de Privacidad para continuar', scrollTo: _keyTerms);
    }

    if (widget.embeddedMode && !_verificationAccepted) {
      return _showValidationError('Debes aceptar las condiciones de verificación de identidad para continuar', scrollTo: _keyTerms);
    }

    setState(() => _isSaving = true);
    try {
      // Mapping CASA/APARTAMENTO to Enum if only one selected
      String? hType;
      if (_selectedHomeTypes.contains('HOUSE')) {
        hType = 'HOUSE';
      } else if (_selectedHomeTypes.contains('APARTMENT')) { hType = 'APARTMENT'; }

      final body = {
        'bio': _bioController.text.trim(),
        'bioDetail': _bioDetailController.text.trim(),
        'zone': _selectedZone,
        'servicesOffered': _selectedServices,
        'pricePerDay': (double.tryParse(_pricePerDayController.text) ?? 0).round(),
        'pricePerWalk60': (double.tryParse(_pricePerWalk60Controller.text) ?? 0).round(),
        'offersWalk30': _offersWalk30,
        // pricePerWalk30 se calcula automáticamente: mitad del precio de 60 min
        'pricePerWalk30': _offersWalk30
            ? ((double.tryParse(_pricePerWalk60Controller.text) ?? 0) / 2).round()
            : 0,
        'pricePerGuarderia': (double.tryParse(_pricePerGuarderiaController.text) ?? 0),
        'homeType': hType,
        'spaceType': _selectedHomeTypes,
        'hasYard': _hasYard,
        'photos': _photos,
        'experienceYears': int.tryParse(_experienceYearsController.text.replaceAll('+', '')) ?? 0,
        'experienceDescription': _experienceDescController.text.trim(),
        'whyCaregiver': _whyCaregiverController.text.trim(),
        'whatDiffers': _whatDiffersController.text.trim(),
        'handleAnxious': _handleAnxiousController.text.trim(),
        'emergencyResponse': _emergencyResponseController.text.trim(),
        'acceptAggressive': _acceptAggressive ?? false,
        'acceptPuppies': _acceptPuppies ?? false,
        'acceptSeniors': _acceptSeniors ?? false,
        'sizesAccepted': _acceptedSizes,
        // Campo clave para el filtro del marketplace — debe coincidir con DB AnimalType enum
        'animalTypes': _acceptedPetTypes,
        'serviceDetails': {
          'allowsLargePets': _allowsLargePets,
          'allowsMultiplePets': _allowsMultiplePets,
          'maxPets': _maxPets,
          'acceptedPetTypes': _acceptedPetTypes,
          'acceptedSizes': _acceptedSizes,
          'availability': {
            'weekdays': _weekdays,
            'weekends': _weekends,
            'holidays': _holidays,
            'slots': {
              'morning': _morningSlot,
              'afternoon': _afternoonSlot,
              'night': _nightSlot,
            },
          },
          'faq': {
            'includes': _includesController.text.trim(),
            'requirements': _requirementsController.text.trim(),
            'emergency': _emergencyController.text.trim(),
          },
        },
      };

      final response = await http.patch(
        Uri.parse('$_baseUrl/caregiver/profile'),
        headers: {
          'Authorization': 'Bearer $_caregiverToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (jsonDecode(response.body)['success'] == true) {
        // If in embedded mode, persist T&C acceptance to the DB
        if (widget.embeddedMode) {
          await http.patch(
            Uri.parse('$_baseUrl/caregiver/profile'),
            headers: {
              'Authorization': 'Bearer $_caregiverToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'termsAccepted': true,
              'privacyAccepted': true,
              'verificationAccepted': true,
            }),
          );
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cambios guardados correctamente'), backgroundColor: GardenColors.success, duration: Duration(seconds: 2)),
        );
        _computeCompletion();
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        if (widget.embeddedMode && widget.onSaveComplete != null) {
          widget.onSaveComplete!();
        } else {
          Navigator.pop(context);
        }
      } else {
        final err = jsonDecode(response.body)['error']?['message'] ?? 'Error desconocido';
        throw Exception(err);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo guardar: ${e.toString()}'), backgroundColor: GardenColors.error));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _addPhoto() async {
    const maxPhotos = 6;
    if (_photos.length >= maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Máximo $maxPhotos fotos permitidas')));
      return;
    }

    // Skip imageQuality on web — canvas-based compression uses createObjectURL
    // which throws TypeError in Flutter web (CanvasKit).
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: kIsWeb ? null : 85,
    );
    if (picked == null) return;
    final bytes = Uint8List.fromList(await picked.readAsBytes());
    final fileName = picked.name.isEmpty ? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg' : picked.name;

    setState(() => _isSaving = true);
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/caregiver/profile/service-photo'));
      request.headers['Authorization'] = 'Bearer $_caregiverToken';
      request.files.add(http.MultipartFile.fromBytes(
        'servicePhoto',
        bytes,
        filename: fileName,
        contentType: MediaType('image', 'jpeg'),
      ));

      final response = await request.send();
      final respBody = await response.stream.bytesToString();
      final data = jsonDecode(respBody);

      if (!mounted) return;
      if (data['success'] == true) {
        setState(() {
          _photos.add(data['data']['photoUrl'] as String? ?? '');
          _localPhotoData.add(bytes);
        });
        _computeCompletion();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(data['error']?['message'] ?? data['message'] ?? 'Error al subir foto'),
          backgroundColor: GardenColors.error,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error al subir: $e'),
        backgroundColor: GardenColors.error,
      ));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _deletePhoto(int index) async {
    setState(() {
      _photos.removeAt(index);
      if (index < _localPhotoData.length) _localPhotoData.removeAt(index);
      _computeCompletion();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      if (widget.embeddedMode) {
        return const Center(child: CircularProgressIndicator(color: GardenColors.primary));
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Perfil profesional')),
        body: const Center(child: CircularProgressIndicator(color: GardenColors.primary)),
      );
    }

    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    if (widget.embeddedMode) {
      return _buildBody(textColor, subtextColor, surface, borderColor, isDark);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil profesional'),
        actions: [
          if (_isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 16),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: GardenColors.primary)),
              ),
            )
          else
            TextButton(
              onPressed: _saveAllData,
              child: const Text('Guardar', style: TextStyle(color: GardenColors.primary, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
        ],
      ),
      body: _buildBody(textColor, subtextColor, surface, borderColor, isDark),
    );
  }

  Widget _buildBody(Color textColor, Color subtextColor, Color surface, Color borderColor, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Sección 1 — Banner
          _buildCompletionBanner(),
            const SizedBox(height: 32),

            // Sección 2 — Sobre ti
            SizedBox(key: _keyBio, height: 0),
            _sectionTitle('Sobre ti como cuidador', textColor),
            SizedBox(key: _keyBioDetail, height: 0),
            GardenInput(
              hint: 'Biografía detallada: experiencia, método de cuidado, etc.',
              controller: _bioDetailController,
              maxLines: 6,
              maxLength: 300,
              onChanged: (_) => setState(() {}),
            ),
            const Divider(height: 48),

            SizedBox(key: _keyAddress, height: 0),
            const Divider(height: 48),

            if (_selectedServices.contains('HOSPEDAJE')) ...[
              // Sección 3 — Tu espacio
              SizedBox(key: _keySpaceType, height: 0),
              _sectionTitle('Tu espacio', textColor),
              _buildHomeTypes(surface, borderColor),
              const SizedBox(height: 16),
              _buildSwitchTile('¿Tiene jardín o patio?', _hasYard, (v) => setState(() => _hasYard = v)),
              _buildSwitchTile('¿Permite mascotas grandes?', _allowsLargePets, (v) => setState(() => _allowsLargePets = v)),
              _buildSwitchTile('¿Permite múltiples mascotas?', _allowsMultiplePets, (v) => setState(() => _allowsMultiplePets = v)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Máximo de mascotas simultáneas:', style: TextStyle(color: subtextColor, fontSize: 14)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: _maxPets > 1 ? () => setState(() => _maxPets--) : null),
                  Text('$_maxPets', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => setState(() => _maxPets++)),
                ],
              ),
              const Divider(height: 48),
            ],

            // Sección 4 — Servicios
            SizedBox(key: _keyServices, height: 0),
            _sectionTitle('Servicios que ofreces', textColor),
            _buildServiceChips(surface, borderColor),

            if (_selectedServices.contains('PASEO')) ...[
              const SizedBox(height: 24),
              SizedBox(key: _keyPriceWalk, height: 0),
              Row(children: [
                const Icon(Icons.directions_walk_rounded, color: GardenColors.primary, size: 18),
                const SizedBox(width: 8),
                Text('Precios de paseo', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: GardenColors.error.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                  child: const Text('Obligatorio', style: TextStyle(color: GardenColors.error, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Precio por paseo (1 hora)', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                GardenInput(hint: 'Ej: 60 (Bs)', controller: _pricePerWalk60Controller, keyboardType: TextInputType.number),
              ]),
              const SizedBox(height: 16),
              // Toggle paseos de 30 minutos
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _offersWalk30
                      ? GardenColors.primary.withValues(alpha: 0.07)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _offersWalk30
                        ? GardenColors.primary.withValues(alpha: 0.35)
                        : borderColor,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.timer_outlined, color: GardenColors.primary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ofrecer paseos de 30 min',
                              style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                          Text(
                            _offersWalk30
                                ? 'Precio: Bs ${((double.tryParse(_pricePerWalk60Controller.text) ?? 0) / 2).round()} (mitad de 1 hora)'
                                : 'El precio se calcula automáticamente como la mitad del paseo de 1 hora',
                            style: TextStyle(color: subtextColor, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _offersWalk30,
                      onChanged: (v) => setState(() => _offersWalk30 = v),
                      activeColor: GardenColors.primary,
                    ),
                  ],
                ),
              ),
            ],

            if (_selectedServices.contains('GUARDERIA')) ...[
              const SizedBox(height: 24),
              Row(children: [
                const Icon(Icons.home_work_rounded, color: GardenColors.primary, size: 18),
                const SizedBox(width: 8),
                Text('Precio de guardería', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Precio por hora de guardería', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Recomendado: igual al precio de paseo/hora', style: TextStyle(color: subtextColor, fontSize: 11)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: GardenInput(hint: 'Ej: 60 (Bs/hora)', controller: _pricePerGuarderiaController, keyboardType: TextInputType.number)),
                  const Expanded(child: SizedBox()),
                ]),
              ]),
            ],

            if (_selectedServices.contains('HOSPEDAJE')) ...[
              const SizedBox(height: 24),
              SizedBox(key: _keyPriceHospedaje, height: 0),
              Row(children: [
                const Icon(Icons.house_rounded, color: GardenColors.primary, size: 18),
                const SizedBox(width: 8),
                Text('Precio de hospedaje', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: GardenColors.error.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                  child: const Text('Obligatorio', style: TextStyle(color: GardenColors.error, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Precio por noche (la mascota duerme en tu casa)', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: GardenInput(hint: 'Ej: 120 (Bs)', controller: _pricePerDayController, keyboardType: TextInputType.number)),
                  const Expanded(child: SizedBox()),
                ]),
              ]),
            ],
            const SizedBox(height: 16),
            _buildZoneDropdown(surface, borderColor, textColor),
            const Divider(height: 48),

            // Sección 5 — Tipos de mascotas
            SizedBox(key: _keyPetTypes, height: 0),
            _sectionTitle('Mascotas que aceptas', textColor),
            Wrap(
              spacing: 8,
              children: _petTypes.map((t) => _filterChip(t, _petTypeLabels[t]!, _acceptedPetTypes, surface, borderColor)).toList(),
            ),
            const Divider(height: 48),

            // Sección 7 — Tamaños
            SizedBox(key: _keySizes, height: 0),
            _sectionTitle('Tamaños aceptados', textColor),
            Column(
              children: _petSizes.map((s) => _buildCheckTile(_petSizeLabels[s]!, _acceptedSizes.contains(s), (v) {
                setState(() { if (v!) {
                  _acceptedSizes.add(s);
                } else {
                  _acceptedSizes.remove(s);
                } });
              })).toList(),
            ),
            const Divider(height: 48),

            // Sección 8 — FAQ
            SizedBox(key: _keyFaq, height: 0),
            _sectionTitle('Preguntas frecuentes', textColor),
            GardenInput(hint: '¿Qué incluye tu servicio?', controller: _includesController, maxLines: 2),
            const SizedBox(height: 12),
            const SizedBox(height: 12),
            GardenInput(hint: '¿Qué necesitas del dueño antes del servicio?', controller: _requirementsController, maxLines: 2),

            const Divider(height: 48),

            // Sección EXTRA — Experiencia detallada
            SizedBox(key: _keyExperience, height: 0),
            _sectionTitle('Tu experiencia profesional', textColor),
            Text('Años cuidando mascotas', style: TextStyle(color: subtextColor, fontSize: 13)),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final years in ['0', '1', '2', '3', '4', '5+'])
                  GestureDetector(
                    onTap: () => setState(() => _experienceYearsController.text = years),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _experienceYearsController.text == years ? GardenColors.primary : surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _experienceYearsController.text == years ? GardenColors.primary : borderColor,
                        ),
                      ),
                      child: Text(years,
                        style: TextStyle(
                          color: _experienceYearsController.text == years ? Colors.white : subtextColor,
                          fontWeight: FontWeight.w600,
                        )),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _sectionField('Describe tu experiencia', _experienceDescController,
              'Cuéntanos sobre los animales que has cuidado, tu formación, etc.', maxLines: 4),
            const SizedBox(height: 16),
            _sectionField('¿Por qué eres cuidador?', _whyCaregiverController,
              'Tu motivación para cuidar mascotas', maxLines: 3),
            const SizedBox(height: 16),
            _sectionField('¿Qué te diferencia?', _whatDiffersController,
              'Lo que hace especial tu servicio', maxLines: 3),

            const Divider(height: 48),

            // Sección EXTRA — Mascotas que aceptas
            SizedBox(key: _keyPolicies, height: 0),
            _sectionTitle('Políticas de mascotas', textColor),
            _acceptSwitch('¿Aceptas mascotas agresivas?', _acceptAggressive, (val) => setState(() => _acceptAggressive = val), textColor, subtextColor, surface, borderColor),
            const SizedBox(height: 8),
            _acceptSwitch('¿Aceptas cachorros?', _acceptPuppies, (val) => setState(() => _acceptPuppies = val), textColor, subtextColor, surface, borderColor),
            const SizedBox(height: 8),
            _acceptSwitch('¿Aceptas mascotas mayores?', _acceptSeniors, (val) => setState(() => _acceptSeniors = val), textColor, subtextColor, surface, borderColor),

            const Divider(height: 48),

            // Sección EXTRA — Situaciones especiales
            _sectionTitle('Situaciones especiales', textColor),
            SizedBox(key: _keyHandleAnxious, height: 0),
            _sectionField('¿Cómo manejas mascotas ansiosas?', _handleAnxiousController,
              'Describe tu método para mascotas con ansiedad o estrés', maxLines: 3),
            const SizedBox(height: 16),
            SizedBox(key: _keyEmergencyResponse, height: 0),
            _sectionField('¿Cómo respondes ante emergencias?', _emergencyResponseController,
              'Protocolo ante una situación de emergencia veterinaria', maxLines: 3),

            const Divider(height: 48),

            if (widget.embeddedMode) ...[
              // T&C acceptance — only shown in embedded (wizard) mode
              SizedBox(key: _keyTerms, height: 0),
              _buildTermsSection(),
              const SizedBox(height: 24),
            ],

            if (widget.embeddedMode) ...[
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GardenColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: GardenColors.primary.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: _isSaving ? null : _saveAllData,
                  child: _isSaving
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Guardar y continuar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],

            const SizedBox(height: 60),
          ],
        ),
    );
  }

  Widget _sectionField(String label, TextEditingController controller, String hint, {int maxLines = 1}) {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: TextStyle(color: textColor),
          onChanged: (_) => _computeCompletion(),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: subtextColor, fontSize: 13),
            filled: true,
            fillColor: surfaceEl,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
      ],
    );
  }

  Widget _acceptSwitch(String label, bool? value, Function(bool) onChanged, Color textColor, Color subtextColor, Color surface, Color borderColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: textColor, fontSize: 14))),
          if (value == null)
            Text('Sin definir', style: TextStyle(color: subtextColor, fontSize: 12)),
          const SizedBox(width: 8),
          Switch(
            value: value ?? false,
            activeColor: GardenColors.primary,
            onChanged: (v) => onChanged(v),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Text(title, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildCompletionBanner() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _completionPercentage == 100
              ? [GardenColors.success, GardenColors.successDark]
              : [GardenColors.primary, GardenColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _completionPercentage == 100 ? '¡Perfil completo!' : 'Perfil profesional',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      _completionPercentage == 100
                          ? 'Tu perfil está listo para ser revisado'
                          : 'Completa todos los detalles para ser aprobado',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Text('$_completionPercentage%', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _completionPercentage / 100,
              backgroundColor: Colors.white.withValues(alpha: 0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTypes(Color surface, Color border) {
    return Wrap(
      spacing: 8,
      children: _homeTypes.map((t) => _filterChip(t, _homeTypeLabels[t]!, _selectedHomeTypes, surface, border)).toList(),
    );
  }

  Widget _buildServiceChips(Color surface, Color border) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ['PASEO', 'HOSPEDAJE', 'GUARDERIA'].map((s) {
        final label = s == 'PASEO' ? '🦮 Paseo' : s == 'GUARDERIA' ? '🏡 Guardería' : '🏠 Hospedaje';
        return _filterChip(s, label, _selectedServices, surface, border);
      }).toList(),
    );
  }

  Widget _filterChip(String value, String label, List<String> list, Color surface, Color border) {
    final isSelected = list.contains(value);
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        setState(() { if (val) {
          list.add(value);
        } else {
          list.remove(value);
        } });
      },
      selectedColor: GardenColors.primary.withValues(alpha: 0.2),
      checkmarkColor: GardenColors.primary,
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isSelected ? GardenColors.primary : border),
      ),
    );
  }

  Widget _slotChip(String label, bool value, Function(bool) onChanged, Color surface, Color border) {
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: value ? GardenColors.primary.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: value ? GardenColors.primary : border),
          ),
          child: Column(
            children: [
              Icon(label == 'Mañana' ? Icons.wb_sunny_outlined : label == 'Tarde' ? Icons.wb_cloudy_outlined : Icons.nights_stay_outlined,
                  color: value ? GardenColors.primary : GardenColors.textSecondary, size: 20),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: value ? GardenColors.primary : GardenColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile(String title, bool value, Function(bool) onChanged) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontSize: 14)),
      trailing: Switch(value: value, onChanged: onChanged, activeColor: GardenColors.primary),
    );
  }

  Widget _buildCheckTile(String title, bool value, Function(bool?) onChanged) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontSize: 14)),
      value: value,
      onChanged: onChanged,
      activeColor: GardenColors.primary,
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }

  Widget _buildPhotoGrid(Color borderColor) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
      itemCount: (_photos.length < 6) ? _photos.length + 1 : 6,
      itemBuilder: (context, index) {
        if (index == _photos.length && _photos.length < 6) {
          return GestureDetector(
            onTap: _addPhoto,
            child: Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor, style: BorderStyle.solid)),
              child: const Icon(Icons.add_a_photo_outlined, color: GardenColors.primary),
            ),
          );
        }
        final localBytes = index < _localPhotoData.length ? _localPhotoData[index] : null;
        return Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                image: DecorationImage(
                  image: localBytes != null
                      ? MemoryImage(localBytes) as ImageProvider
                      : NetworkImage(fixImageUrl(_photos[index])),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Positioned(
              right: 5, top: 5,
              child: GestureDetector(
                onTap: () => _deletePhoto(index),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildZoneDropdown(Color surface, Color borderColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedZone,
          isExpanded: true,
          dropdownColor: surface,
          items: _zones.map((z) => DropdownMenuItem(value: z, child: Text(z.replaceAll('_', ' '), style: TextStyle(color: textColor)))).toList(),
          onChanged: (val) { if (val != null) setState(() => _selectedZone = val); },
        ),
      ),
    );
  }

  Widget _buildTermsSection() {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _termsAccepted ? GardenColors.primary.withValues(alpha: 0.5) : borderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Términos y condiciones',
              style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Para continuar con el proceso de registro como cuidador, debes aceptar nuestros términos.',
              style: TextStyle(color: subtextColor, fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _termsAccepted,
            onChanged: (val) => setState(() => _termsAccepted = val ?? false),
            activeColor: GardenColors.primary,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'He leído y acepto los Términos de Servicio y la Política de Privacidad de GARDEN',
              style: TextStyle(fontSize: 13),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 56, bottom: 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsOfServiceScreen())),
                  child: const Text(
                    'Términos de Servicio',
                    style: TextStyle(color: GardenColors.primary, fontSize: 12, decoration: TextDecoration.underline),
                  ),
                ),
                Text('  •  ', style: TextStyle(color: subtextColor, fontSize: 12)),
                GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
                  child: const Text(
                    'Política de Privacidad',
                    style: TextStyle(color: GardenColors.primary, fontSize: 12, decoration: TextDecoration.underline),
                  ),
                ),
              ],
            ),
          ),
          CheckboxListTile(
            value: _verificationAccepted,
            onChanged: (val) => setState(() => _verificationAccepted = val ?? false),
            activeColor: GardenColors.primary,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'Acepto las condiciones de verificación de identidad de GARDEN',
              style: TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
