import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';
import '../../widgets/extra_services_editor.dart';
import '../../widgets/garden_loading_indicator.dart';

class CaregiverProfileDataScreen extends StatefulWidget {
  /// When true, the screen hides its own AppBar/Scaffold and calls
  /// [onSaveComplete] instead of `Navigator.pop()` after a successful save.
  final bool embeddedMode;
  final VoidCallback? onSaveComplete;

  /// Optional pre-loaded profile data (e.g. passed from the setup flow).
  /// When provided, fields are filled immediately — no loading spinner — and
  /// the API is called in the background to refresh with the latest values.
  final Map<String, dynamic>? initialProfile;

  /// Services the caregiver selected during the wizard (e.g. ['HOSPEDAJE', 'PASEO']).
  /// Used to conditionally show the "Tu espacio" section only when the
  /// caregiver offers HOSPEDAJE or GUARDERIA.
  final List<String> servicesOffered;

  /// When true, adapts all labels and questions for a company (hotel/hostal/guardería)
  /// instead of an individual caregiver.
  final bool isCompany;

  /// When false, hides the caregiver/place photo upload sections.
  /// Set to false when embedded inside the onboarding wizard (photos were
  /// already uploaded in the dedicated photo step). True for standalone edit.
  final bool showPhotos;

  const CaregiverProfileDataScreen({
    super.key,
    this.embeddedMode = false,
    this.onSaveComplete,
    this.initialProfile,
    this.servicesOffered = const [],
    this.isCompany = false,
    this.showPhotos = true,
  });

  @override
  State<CaregiverProfileDataScreen> createState() => _CaregiverProfileDataScreenState();
}

class _CaregiverProfileDataScreenState extends State<CaregiverProfileDataScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;
  String _caregiverToken = '';
  int _completionPercentage = 0;

  // GlobalKeys for scroll-to-field on validation error
  final _keyAddress = GlobalKey();
  final _keyServicesPrices = GlobalKey();
  final _keySpaceType = GlobalKey();
  final _keyPetTypes = GlobalKey();
  final _keySizes = GlobalKey();
  final _keyPhotos = GlobalKey();
  final _keyPlacePhotos = GlobalKey();
  final _keyFaq = GlobalKey();
  final _keyExperience = GlobalKey();
  final _keyPolicies = GlobalKey();
  final _keyHandleAnxious = GlobalKey();
  final _keyEmergencyResponse = GlobalKey();

  // Controllers
  final _bioController = TextEditingController();
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

  // ── Chequeo de coherencia con IA ──────────────────────────────────────────
  // El texto de estos campos se muestra tal cual en el perfil comercial que
  // ve el cliente — con debounce mientras el cuidador escribe, se le avisa
  // si lo que puso no parece tener sentido (relleno de teclado, irrelevante,
  // etc.), sin bloquear el guardado (es un aviso, no un error duro).
  final Map<String, String?> _coherenceWarnings = {};
  final Map<String, Timer> _coherenceTimers = {};

  void _scheduleCoherenceCheck(String fieldKey, String label, String text) {
    _coherenceTimers[fieldKey]?.cancel();
    if (text.trim().length < 10) {
      if (_coherenceWarnings[fieldKey] != null) setState(() => _coherenceWarnings[fieldKey] = null);
      return;
    }
    _coherenceTimers[fieldKey] = Timer(const Duration(milliseconds: 900), () async {
      try {
        final res = await http.post(
          Uri.parse('$_baseUrl/caregiver/profile/check-text'),
          headers: {'Authorization': 'Bearer $_caregiverToken', 'Content-Type': 'application/json'},
          body: jsonEncode({'field': label, 'text': text}),
        );
        if (!mounted) return;
        final body = jsonDecode(res.body);
        if (body is Map && body['success'] == true) {
          final data = body['data'];
          final coherente = data?['coherente'] == true;
          setState(() => _coherenceWarnings[fieldKey] = coherente ? null : (data?['razon'] as String? ?? 'Este texto no parece coherente.'));
        }
      } catch (_) {
        // Silencioso — es un aviso opcional, nunca debe romper el formulario.
      }
    });
  }

  Widget _coherenceWarningText(String fieldKey) {
    final warning = _coherenceWarnings[fieldKey];
    if (warning == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 14, color: GardenColors.warning),
          const SizedBox(width: 6),
          Expanded(child: Text(warning, style: const TextStyle(color: GardenColors.warning, fontSize: 11.5))),
        ],
      ),
    );
  }

  bool _acceptAggressive = false;
  bool _acceptPuppies = false;
  bool _acceptSeniors = false;
  bool _requireMeetAndGreet = false;

  // Selecciones
  List<String> _selectedHomeTypes = [];

  // Chips: "Situaciones especiales" — opciones predefinidas
  static const _anxiousOptions = [
    'Técnicas de calma y paciencia',
    'Experiencia con ansiedad de separación',
    'Ambiente tranquilo y seguro',
    'Sigo indicaciones del dueño',
    'Consulto al veterinario si es necesario',
  ];
  static const _emergencyOptions = [
    'Contacto al veterinario inmediatamente',
    'Notifico al dueño al instante',
    'Conozco primeros auxilios para mascotas',
    'Tengo clínica veterinaria de confianza cercana',
    'Traslado de urgencia si es necesario',
  ];
  List<String> _selectedAnxiousOptions = [];
  List<String> _selectedEmergencyOptions = [];
  bool _hasYard = false;
  bool _allowsLargePets = false;
  bool _allowsMultiplePets = false;
  // Capacidad máxima de reservas simultáneas — configurable por tipo de
  // servicio (antes era un solo número [1,2,3] para los tres servicios, y
  // además se guardaba solo dentro de serviceDetails.maxPets, un JSON que el
  // backend nunca sincronizaba con la columna real usada al validar
  // capacidad — el límite configurado nunca se aplicaba de verdad).
  int _maxPetsPaseo = 1;
  int _maxPetsHospedaje = 1;
  int _maxPetsGuarderia = 1;
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

  // New photo fields (paso 4 model)
  List<String> _caregiverPhotoUrls = [];
  Map<String, List<String>> _placePhotoUrls = {};
  bool _uploadingCaregiverPhoto = false;
  bool _uploadingPlacePhoto = false;

  // Sección Documentos — identidad/CI ya se verifican al registrarse;
  // antecedentes penales es un filtro opcional, no bloquea el marketplace.
  String _identityVerificationStatus = 'PENDING';
  bool get _identityVerified => _identityVerificationStatus == 'VERIFIED';
  String _antecedentesStatus = 'PENDING'; // PENDING | EN_REVISION | LIMPIO | FLAGGED
  bool _uploadingAntecedentes = false;

  // Services from API (used when widget.servicesOffered is empty)
  List<String> _apiServicesOffered = [];

  static const _placeSections = [
    ('sala',         '🛋️ Sala / Área principal',  true),
    ('descanso',     '🛏️ Zona de descanso',        true),
    ('alimentacion', '🍽️ Área de alimentación',    true),
    ('jardin',       '🌿 Jardín / Patio',           false),
    ('juego',        '🎾 Área de juego',            false),
  ];

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

  /// true cuando el cuidador seleccionó 0 años de experiencia.
  /// Oculta todas las preguntas de follow-up de experiencia y situaciones especiales.
  bool get _isAmateur =>
      (int.tryParse(_experienceYearsController.text.replaceAll('+', '')) ?? -1) == 0;

  List<String> get _effectiveServices =>
      widget.servicesOffered.isNotEmpty ? widget.servicesOffered : _apiServicesOffered;

  bool get _needsSpaceSection =>
      _effectiveServices.contains('HOSPEDAJE') || _effectiveServices.contains('GUARDERIA');

  bool get _needsPlacePhotos => _needsSpaceSection;

  // ── Company-aware label helpers ──────────────────────────────────────────
  // widget.isCompany solo llega en true desde el wizard de registro de
  // empresa; en cualquier otra navegación (ej. Mi Perfil → Datos del
  // cuidador) hay que confiar en el valor real ya cargado desde el backend.
  bool _apiIsCompany = false;
  bool get _ic => widget.isCompany || _apiIsCompany;
  String get _lExpTitle       => _ic ? 'Historia de la empresa'         : 'Tu experiencia profesional';
  String get _lYearsLabel     => _ic ? 'Años de operación'              : 'Años cuidando mascotas';
  String get _lExpDesc        => _ic ? 'Describe los servicios de tu empresa' : 'Describe tu experiencia';
  String get _lExpDescHint    => _ic ? 'Historia, especialidades, certificaciones, etc.' : 'Animales cuidados, formación, etc.';
  String get _lWhyLabel       => _ic ? '¿Por qué eligieron el cuidado de mascotas?' : '¿Por qué eres cuidador?';
  String get _lWhyHint        => _ic ? 'La misión de la empresa'        : 'Tu motivación';
  String get _lDiffersLabel   => _ic ? '¿Qué diferencia a tu empresa?' : '¿Qué te diferencia?';
  String get _lDiffersHint    => _ic ? 'Valor diferencial del negocio'  : 'Lo que hace especial tu servicio';
  String get _lPoliciesTitle  => _ic ? 'Políticas de la empresa'        : 'Políticas de mascotas';
  String get _lSituTitle      => _ic ? 'Protocolos y situaciones especiales' : 'Situaciones especiales';
  String get _lAnxious        => _ic ? '¿Cómo manejan mascotas con necesidades especiales?' : '¿Cómo manejas mascotas ansiosas?';
  String get _lEmergency      => _ic ? '¿Cuáles son sus protocolos de emergencia?'          : '¿Cómo respondes ante emergencias?';

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
    _apiIsCompany = profile['isCompany'] as bool? ?? false;

    // Usar el porcentaje ya calculado por el backend (más preciso que el local)
    final onboardingPct = (profile['onboardingStatus'] as Map<String, dynamic>?)?['percentage'] as int?;
    if (onboardingPct != null) _completionPercentage = onboardingPct;

    final details = profile['serviceDetails'] ?? {};
    final faq = details['faq'] ?? {};
    final availability = details['availability'] ?? {};
    final slots = availability['slots'] ?? {};
    final defaultSchedule = profile['defaultAvailabilitySchedule'] ?? {};
    final paseoBlocks = defaultSchedule['paseoTimeBlocks'] ?? {};

    _bioController.text = profile['bio'] ?? '';
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
    _selectedHomeTypes = List<String>.from(profile['spaceType'] ?? []);
    _hasYard = profile['hasYard'] ?? false;
    _allowsLargePets = details['allowsLargePets'] ?? false;
    _allowsMultiplePets = details['allowsMultiplePets'] ?? false;
    // Top-level (columnas reales, no serviceDetails) — con fallback al
    // maxPets legacy de serviceDetails para perfiles guardados antes de
    // este cambio, para no resetear a 1 lo que el cuidador ya había puesto.
    final legacyMaxPets = (profile['maxPets'] as num?)?.toInt() ?? (details['maxPets'] as num?)?.toInt() ?? 1;
    _maxPetsPaseo = (profile['maxPetsPaseo'] as num?)?.toInt() ?? legacyMaxPets;
    // Hospedaje y Guardería comparten UN solo cupo combinado (no uno cada
    // uno) — se toma el mayor de los dos valores guardados como punto de
    // partida, para no achicar por accidente una capacidad que el cuidador
    // ya había configurado antes de este cambio.
    final combinedHospedajeGuarderia = [
      (profile['maxPetsHospedaje'] as num?)?.toInt() ?? legacyMaxPets,
      (profile['maxPetsGuarderia'] as num?)?.toInt() ?? legacyMaxPets,
    ].reduce((a, b) => a > b ? a : b);
    _maxPetsHospedaje = combinedHospedajeGuarderia;
    _maxPetsGuarderia = combinedHospedajeGuarderia;
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

    _apiServicesOffered = List<String>.from(profile['servicesOffered'] ?? []);
    _identityVerificationStatus = profile['identityVerificationStatus'] as String? ?? 'PENDING';
    _antecedentesStatus = profile['antecedentesStatus'] as String? ?? 'PENDING';
    _caregiverPhotoUrls = List<String>.from(profile['caregiverPhotos'] ?? []);
    final rawPlace = profile['placePhotos'];
    if (rawPlace is Map) {
      _placePhotoUrls = rawPlace.map((k, v) => MapEntry(k as String, List<String>.from(v ?? [])));
    } else {
      _placePhotoUrls = {};
    }

    _experienceYearsController.text = (profile['experienceYears'] ?? '').toString();
    if (_experienceYearsController.text == '5') _experienceYearsController.text = '5+';
    _experienceDescController.text = profile['experienceDescription'] as String? ?? '';
    _whyCaregiverController.text = profile['whyCaregiver'] as String? ?? '';
    _whatDiffersController.text = profile['whatDiffers'] as String? ?? '';
    _handleAnxiousController.text = profile['handleAnxious'] as String? ?? '';
    _emergencyResponseController.text = profile['emergencyResponse'] as String? ?? '';
    _acceptAggressive = profile['acceptAggressive'] as bool? ?? false;
    _acceptPuppies = profile['acceptPuppies'] as bool? ?? false;
    _acceptSeniors = profile['acceptSeniors'] as bool? ?? false;
    _requireMeetAndGreet = profile['requireMeetAndGreet'] as bool? ?? false;

    // Mapear texto guardado a chips predefinidas
    final anxiousText = profile['handleAnxious'] as String? ?? '';
    _selectedAnxiousOptions = _anxiousOptions
        .where((o) => anxiousText.contains(o))
        .toList();
    final emergencyText = profile['emergencyResponse'] as String? ?? '';
    _selectedEmergencyOptions = _emergencyOptions
        .where((o) => emergencyText.contains(o))
        .toList();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    _caregiverToken = AuthState.token;

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/caregiver/my-profile'),
        headers: {'Authorization': 'Bearer $_caregiverToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        // _applyProfile ya toma el % directo de onboardingStatus (fuente de
        // verdad del backend, recalculada en cada GET /my-profile) — no lo
        // pisamos con la estimación local para evitar el badge desincronizado.
        setState(() => _applyProfile(data['data']));
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
    _caregiverToken = AuthState.token;
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/caregiver/my-profile'),
        headers: {'Authorization': 'Bearer $_caregiverToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true && mounted) {
        setState(() => _applyProfile(data['data']));
      }
    } catch (e) {
      debugPrint('Background profile refresh error: $e');
    }
  }

  /// Este arreglo debe reflejar EXACTAMENTE los mismos 16 campos que
  /// calculatePercentage() en caregiver-profile-completion.helper.ts (backend),
  /// mismo orden, mismos umbrales — si difieren, el badge local puede mostrar
  /// 100% mientras el dashboard sigue "iluminado" (o viceversa).
  ///
  /// Recalculado en cada llamada (no cacheado) para que _isProfileComplete
  /// siempre esté al día — chips y fotos se seleccionan con setState() simple,
  /// sin pasar por _computeCompletion(), así que un valor cacheado quedaría
  /// desactualizado y el botón "Guardar y continuar" podría trabarse.
  List<bool> _completionFields() {
    final services = _effectiveServices;
    final offersPaseo     = services.contains('PASEO');
    final offersHospedaje = services.contains('HOSPEDAJE');
    final offersGuarderia = services.contains('GUARDERIA');
    final needsSpace      = offersHospedaje || offersGuarderia;

    // Precio según servicio
    final hasPaseoPrice     = !offersPaseo     || (double.tryParse(_pricePerWalk30Controller.text) ?? 0) > 0 || (double.tryParse(_pricePerWalk60Controller.text) ?? 0) > 0;
    final hasHospedajePrice = !offersHospedaje || (double.tryParse(_pricePerDayController.text) ?? 0) > 0;
    final hasGuarderiaPrice = !offersGuarderia || (double.tryParse(_pricePerGuarderiaController.text) ?? 0) > 0;

    // Fotos del lugar
    final hasPlacePhotos = !needsSpace || (['sala', 'descanso', 'alimentacion'].every((s) => (_placePhotoUrls[s]?.isNotEmpty ?? false)));

    // Fotos del cuidador
    final minPhotos = services.length == 1 && offersPaseo ? 2 : 4;
    final hasPhotos = _caregiverPhotoUrls.length >= minPhotos;

    // Experiencia
    final expYears = int.tryParse(_experienceYearsController.text.replaceAll('+', '')) ?? -1;

    return [
      services.isNotEmpty,
      hasPaseoPrice,
      hasHospedajePrice,
      hasGuarderiaPrice,
      hasPhotos,
      hasPlacePhotos,
      expYears >= 0,
      _isAmateur || _experienceDescController.text.trim().length >= 15,
      _whyCaregiverController.text.trim().length >= 3,
      _whatDiffersController.text.trim().length >= 3,
      _acceptedPetTypes.isNotEmpty,
      _acceptedSizes.isNotEmpty,
      true, // acceptAggressive (bool no-nullable en Dart, siempre "definido")
      true, // acceptPuppies
      true, // acceptSeniors
    ];
  }

  /// Misma lógica que _completionFields(), pero con una etiqueta legible
  /// por cada chequeo — para mostrarle al cuidador EXACTAMENTE qué falta,
  /// en vez de un solo número de porcentaje sin detalle. Las opciones que
  /// aparecen cambian según qué servicio(s) ofrece (un chequeo que no
  /// aplica al servicio actual directamente no se incluye en la lista).
  List<(String, bool)> _completionChecklist() {
    final services = _effectiveServices;
    final offersPaseo     = services.contains('PASEO');
    final offersHospedaje = services.contains('HOSPEDAJE');
    final offersGuarderia = services.contains('GUARDERIA');
    final needsSpace      = offersHospedaje || offersGuarderia;

    final hasPaseoPrice     = (double.tryParse(_pricePerWalk30Controller.text) ?? 0) > 0 || (double.tryParse(_pricePerWalk60Controller.text) ?? 0) > 0;
    final hasHospedajePrice = (double.tryParse(_pricePerDayController.text) ?? 0) > 0;
    final hasGuarderiaPrice = (double.tryParse(_pricePerGuarderiaController.text) ?? 0) > 0;
    final hasPlacePhotos = ['sala', 'descanso', 'alimentacion'].every((s) => (_placePhotoUrls[s]?.isNotEmpty ?? false));
    final minPhotos = services.length == 1 && offersPaseo ? 2 : 4;
    final hasPhotos = _caregiverPhotoUrls.length >= minPhotos;
    final expYears = int.tryParse(_experienceYearsController.text.replaceAll('+', '')) ?? -1;

    return [
      ('Al menos un servicio activo', services.isNotEmpty),
      if (offersPaseo) ('Precio de paseo', hasPaseoPrice),
      if (offersHospedaje) ('Precio de hospedaje', hasHospedajePrice),
      if (offersGuarderia) ('Precio de guardería', hasGuarderiaPrice),
      ('Fotos tuyas ($minPhotos mín.)', hasPhotos),
      if (needsSpace) ('Fotos del lugar (sala, descanso, alimentación)', hasPlacePhotos),
      ('Años de experiencia', expYears >= 0),
      if (!_isAmateur) ('Descripción de tu experiencia', _experienceDescController.text.trim().length >= 15),
      ('¿Por qué eres cuidador?', _whyCaregiverController.text.trim().length >= 3),
      ('¿Qué te diferencia?', _whatDiffersController.text.trim().length >= 3),
      ('Tipos de mascota que aceptas', _acceptedPetTypes.isNotEmpty),
      ('Tamaños que aceptas', _acceptedSizes.isNotEmpty),
    ];
  }

  void _showCompletionChecklist() {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final items = _completionChecklist();
    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Qué falta para completar tu perfil', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Las opciones cambian según los servicios que ofreces.', style: TextStyle(color: subtextColor, fontSize: 12)),
            const SizedBox(height: 16),
            ...items.map((item) {
              final (label, done) = item;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      size: 18, color: done ? GardenColors.success : subtextColor.withValues(alpha: 0.5)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(label, style: TextStyle(color: done ? textColor : subtextColor, fontSize: 13.5))),
                ]),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _computeCompletion() {
    final fields = _completionFields();
    final completed = fields.where((f) => f).length;
    setState(() => _completionPercentage = ((completed / fields.length) * 100).round().clamp(0, 100));
  }

  /// Fuente de verdad en tiempo real para habilitar/deshabilitar "Guardar y
  /// continuar" — a diferencia de _completionPercentage (cacheado), siempre
  /// refleja el estado actual sin depender de que algo haya disparado
  /// _computeCompletion() primero.
  bool get _isProfileComplete => _completionFields().every((f) => f);

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
    // ── Validación ───────────────────────────────────────────────────────────
    if (_acceptedPetTypes.isEmpty) {
      return _showValidationError('Selecciona al menos un tipo de mascota que aceptas', scrollTo: _keyPetTypes);
    }
    if (_acceptedSizes.isEmpty) {
      return _showValidationError('Selecciona al menos un tamaño de mascota aceptado', scrollTo: _keySizes);
    }

    // Servicios y precios — si un servicio está activo, su precio y demás
    // secciones que aparecen para él NO pueden guardarse vacías.
    final activeServices = _effectiveServices;
    if (activeServices.isEmpty) {
      return _showValidationError('Selecciona al menos un servicio que ofreces', scrollTo: _keyServicesPrices);
    }
    final offersPaseo = activeServices.contains('PASEO');
    final offersHospedaje = activeServices.contains('HOSPEDAJE');
    final offersGuarderia = activeServices.contains('GUARDERIA');
    final needsSpace = offersHospedaje || offersGuarderia;

    if (offersPaseo) {
      final w30 = double.tryParse(_pricePerWalk30Controller.text) ?? 0;
      final w60 = double.tryParse(_pricePerWalk60Controller.text) ?? 0;
      if (w30 <= 0 && w60 <= 0) {
        return _showValidationError('Configura al menos un precio de paseo (30 o 60 minutos)', scrollTo: _keyServicesPrices);
      }
    }
    if (offersHospedaje) {
      final dayPrice = double.tryParse(_pricePerDayController.text) ?? 0;
      if (dayPrice <= 0) {
        return _showValidationError('Configura el precio por noche de hospedaje', scrollTo: _keyServicesPrices);
      }
    }
    if (offersGuarderia) {
      final guarderiaPrice = double.tryParse(_pricePerGuarderiaController.text) ?? 0;
      if (guarderiaPrice <= 0) {
        return _showValidationError('Configura el precio por día de guardería', scrollTo: _keyServicesPrices);
      }
    }

    // Tu espacio — solo aparece (y solo se exige) si ofrece hospedaje o guardería
    if (needsSpace) {
      if (_selectedHomeTypes.isEmpty) {
        return _showValidationError('Selecciona el tipo de espacio donde recibes a las mascotas', scrollTo: _keySpaceType);
      }
      final missingPlaceSection = _placeSections
          .where((s) => s.$3) // solo las secciones requeridas: sala, descanso, alimentación
          .any((s) => (_placePhotoUrls[s.$1]?.isEmpty ?? true));
      if (missingPlaceSection) {
        return _showValidationError('Sube al menos una foto en cada sección requerida de "Fotos del espacio"', scrollTo: _keyPlacePhotos);
      }
    }

    // Fotos del cuidador — mínimo según servicios (2 si solo paseo, 4 en otro caso)
    if (widget.showPhotos) {
      final minPhotos = activeServices.length == 1 && offersPaseo ? 2 : 4;
      if (_caregiverPhotoUrls.length < minPhotos) {
        return _showValidationError('Sube al menos $minPhotos fotos tuyas en acción con mascotas', scrollTo: _keyPhotos);
      }
    }

    // FAQ
    if (_includesController.text.trim().length < 5) {
      return _showValidationError('Describe qué incluye tu servicio (sección Preguntas frecuentes)', scrollTo: _keyFaq);
    }
    if (_requirementsController.text.trim().length < 5) {
      return _showValidationError('Describe los requisitos de tu servicio (sección Preguntas frecuentes)', scrollTo: _keyFaq);
    }

    // Años de experiencia — requerido siempre
    final expYearsText = _experienceYearsController.text.trim().replaceAll('+', '');
    if (expYearsText.isEmpty || int.tryParse(expYearsText) == null) {
      return _showValidationError('Selecciona los años de experiencia', scrollTo: _keyExperience);
    }

    // Preguntas de follow-up: solo requeridas cuando NO es amateur (experienceYears >= 1)
    if (!_isAmateur) {
      if (_experienceDescController.text.trim().length < 15) {
        return _showValidationError('Describe tu experiencia con más detalle (mínimo 15 caracteres)', scrollTo: _keyExperience);
      }
      if (_whyCaregiverController.text.trim().length < 3) {
        return _showValidationError('Explica por qué eres cuidador', scrollTo: _keyExperience);
      }
      if (_whatDiffersController.text.trim().length < 3) {
        return _showValidationError('Explica qué te diferencia de otros cuidadores', scrollTo: _keyExperience);
      }
      if (_selectedAnxiousOptions.isEmpty) {
        return _showValidationError('Selecciona al menos una opción sobre mascotas ansiosas', scrollTo: _keyHandleAnxious);
      }
      if (_selectedEmergencyOptions.isEmpty) {
        return _showValidationError('Selecciona al menos una opción sobre emergencias', scrollTo: _keyEmergencyResponse);
      }
    }

    setState(() => _isSaving = true);
    try {
      String? hType;
      if (_selectedHomeTypes.contains('HOUSE')) {
        hType = 'HOUSE';
      } else if (_selectedHomeTypes.contains('APARTMENT')) {
        hType = 'APARTMENT';
      }

      final expYears = int.tryParse(expYearsText) ?? 0;

      // Precios según los servicios ofrecidos
      final pricePerDay = double.tryParse(_pricePerDayController.text);
      final pricePerWalk30 = double.tryParse(_pricePerWalk30Controller.text);
      final pricePerWalk60 = double.tryParse(_pricePerWalk60Controller.text);
      final pricePerGuarderia = double.tryParse(_pricePerGuarderiaController.text);

      final body = <String, dynamic>{
        'bio': _bioController.text.trim(),
        'homeType': hType,
        'spaceType': _selectedHomeTypes,
        'hasYard': _hasYard,
        'photos': _photos,
        'servicesOffered': _apiServicesOffered,
        'experienceYears': expYears,
        'acceptAggressive': _acceptAggressive,
        'acceptPuppies': _acceptPuppies,
        'acceptSeniors': _acceptSeniors,
        'requireMeetAndGreet': _requireMeetAndGreet,
        'sizesAccepted': _acceptedSizes,
        'animalTypes': _acceptedPetTypes,
        // Top-level, no dentro de serviceDetails — así el backend los guarda
        // en las columnas reales que usa la validación de capacidad al
        // crear una reserva (ver booking.service.ts assertPaseoAvailability/
        // assertHospedajeAvailability). Solo se manda el del servicio que
        // el cuidador realmente ofrece, para no pisar con "1" un servicio
        // que ni siquiera tiene habilitado.
        if (offersPaseo) 'maxPetsPaseo': _maxPetsPaseo,
        if (offersHospedaje) 'maxPetsHospedaje': _maxPetsHospedaje,
        if (offersGuarderia) 'maxPetsGuarderia': _maxPetsGuarderia,
        // Cada precio solo se envía si su servicio está realmente activo —
        // de lo contrario un precio pre-rellenado (ej. Guardería copiando el
        // precio de Paseo como sugerencia) podía guardarse en la BD aunque el
        // cuidador nunca hubiera habilitado ese servicio, y luego aparecer
        // ofrecido en el marketplace.
        if (offersHospedaje && pricePerDay != null && pricePerDay > 0) 'pricePerDay': pricePerDay,
        if (offersPaseo && pricePerWalk30 != null && pricePerWalk30 > 0) 'pricePerWalk30': pricePerWalk30,
        if (offersPaseo && pricePerWalk60 != null && pricePerWalk60 > 0) 'pricePerWalk60': pricePerWalk60,
        if (offersGuarderia && pricePerGuarderia != null && pricePerGuarderia > 0) 'pricePerGuarderia': pricePerGuarderia,
        'serviceDetails': {
          'allowsLargePets': _allowsLargePets,
          'allowsMultiplePets': _allowsMultiplePets,
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

      // whyCaregiver y whatDiffers — siempre se guardan
      body['whyCaregiver'] = _whyCaregiverController.text.trim();
      body['whatDiffers'] = _whatDiffersController.text.trim();
      // Se guarda explícitamente — antes nunca se enviaba, dejando el campo
      // en `false` en la BD para todo cuidador amateur y atascándolo en este
      // paso al reanudar el registro (el chequeo de reanudación asumía
      // isAmateur=false y exigía experienceDescription/whyCaregiver, que un
      // amateur nunca llena porque el formulario se los oculta).
      body['isAmateur'] = _isAmateur;
      // experienceDescription, handleAnxious, emergencyResponse — solo para no-amateurs
      if (!_isAmateur) {
        body['experienceDescription'] = _experienceDescController.text.trim();
        body['handleAnxious'] = _selectedAnxiousOptions.join(', ');
        body['emergencyResponse'] = _selectedEmergencyOptions.join(', ');
      }

      // En modo embedded (wizard), persistir T&C automáticamente — el usuario ya las aceptó al registrarse.
      if (widget.embeddedMode) {
        body['termsAccepted'] = true;
        body['privacyAccepted'] = true;
        body['verificationAccepted'] = true;
      }

      final response = await http.patch(
        Uri.parse('$_baseUrl/caregiver/profile'),
        headers: {
          'Authorization': 'Bearer $_caregiverToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (jsonDecode(response.body)['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cambios guardados correctamente'),
            backgroundColor: GardenColors.success,
            duration: Duration(seconds: 2),
          ),
        );
        // Recalcula desde el backend (fuente de verdad) en vez de confiar en la
        // estimación local, para que el badge refleje el % real tras guardar.
        await _refreshFromApi();
        setState(() => _isEditing = false);
        if (!mounted) return;
        if (widget.embeddedMode && widget.onSaveComplete != null) {
          widget.onSaveComplete!();
        }
        // In standalone mode: stay on screen in view mode instead of popping
      } else {
        final err = jsonDecode(response.body)['error']?['message'] ?? 'Error desconocido';
        throw Exception(err);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar: ${e.toString()}'), backgroundColor: GardenColors.error),
        );
      }
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

  Future<void> _addCaregiverPhoto() async {
    if (_caregiverPhotoUrls.length >= 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Máximo 6 fotos permitidas')));
      return;
    }
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: kIsWeb ? null : 85);
    if (picked == null) return;
    final bytes = Uint8List.fromList(await picked.readAsBytes());
    final fileName = picked.name.isEmpty ? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg' : picked.name;
    setState(() => _uploadingCaregiverPhoto = true);
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/caregiver/profile/caregiver-photo'));
      request.headers['Authorization'] = 'Bearer $_caregiverToken';
      request.files.add(http.MultipartFile.fromBytes('caregiverPhoto', bytes, filename: fileName, contentType: MediaType('image', 'jpeg')));
      final resp = await request.send();
      final data = jsonDecode(await resp.stream.bytesToString());
      if (!mounted) return;
      if (data['success'] == true) {
        setState(() => _caregiverPhotoUrls.add(data['data']['photoUrl'] as String));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['error']?['message'] ?? 'Error al subir foto'), backgroundColor: GardenColors.error));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: GardenColors.error));
    } finally {
      if (mounted) setState(() => _uploadingCaregiverPhoto = false);
    }
  }

  Future<void> _deleteCaregiverPhoto(int index) async {
    final url = _caregiverPhotoUrls[index];
    setState(() => _caregiverPhotoUrls.removeAt(index));
    try {
      await http.delete(
        Uri.parse('$_baseUrl/caregiver/profile/caregiver-photo'),
        headers: {'Authorization': 'Bearer $_caregiverToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'photoUrl': url}),
      );
    } catch (_) {}
  }

  // ── Documentos — antecedentes penales (FELCC/REJAP) ─────────────────────
  // Filtro opcional, no bloquea el marketplace. Un agente de IA revisa que
  // el documento sea legítimo y si muestra antecedentes explícitos — si los
  // hay, no se suspende solo: queda en revisión para que decida un admin.
  Future<void> _pickAndUploadAntecedentes() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildAntecedentesPickerSheet(ctx),
    );
    if (source == null) return;

    try {
      Uint8List? bytes;
      String filename;
      String mimeType;

      if (source == 'camera' || source == 'gallery') {
        final picked = await ImagePicker().pickImage(
          source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
          imageQuality: kIsWeb ? null : 85,
        );
        if (picked == null) return;
        bytes = Uint8List.fromList(await picked.readAsBytes());
        filename = picked.name.isEmpty ? 'antecedentes_${DateTime.now().millisecondsSinceEpoch}.jpg' : picked.name;
        mimeType = 'image/jpeg';
      } else {
        final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
        if (result == null || result.files.isEmpty || result.files.single.bytes == null) return;
        bytes = result.files.single.bytes;
        filename = result.files.single.name;
        mimeType = 'application/pdf';
      }

      if (!mounted) return;
      setState(() => _uploadingAntecedentes = true);
      final mediaParts = mimeType.split('/');
      final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/caregiver/profile/antecedentes'));
      request.headers['Authorization'] = 'Bearer $_caregiverToken';
      request.files.add(http.MultipartFile.fromBytes(
        'document', bytes!,
        filename: filename,
        contentType: MediaType(mediaParts[0], mediaParts[1]),
      ));
      final streamed = await request.send().timeout(const Duration(minutes: 2));
      final data = jsonDecode(await streamed.stream.bytesToString());
      if (!mounted) return;
      if (data['success'] == true) {
        setState(() => _antecedentesStatus = data['data']?['antecedentesStatus'] as String? ?? 'EN_REVISION');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Documento enviado. Lo estamos revisando.'), backgroundColor: GardenColors.success),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error']?['message'] ?? 'Error al subir el documento'), backgroundColor: GardenColors.error),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: GardenColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAntecedentes = false);
    }
  }

  Widget _buildAntecedentesPickerSheet(BuildContext ctx) {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      decoration: BoxDecoration(color: surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Subir documento', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined, color: GardenColors.primary),
            title: const Text('Tomar foto'),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: GardenColors.primary),
            title: const Text('Elegir de galería'),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined, color: GardenColors.primary),
            title: const Text('Subir PDF'),
            onTap: () => Navigator.pop(ctx, 'pdf'),
          ),
        ],
      ),
    );
  }

  void _showAntecedentesInfoDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cómo obtengo mi FELCC o REJAP?'),
        content: const SingleChildScrollView(
          child: Text(
            'Solo necesitas UNO de los dos documentos:\n\n'
            '• FELCC (Fuerza Especial de Lucha Contra el Crimen): solicítalo presencialmente en cualquier oficina de la FELCC con tu Cédula de Identidad.\n\n'
            '• REJAP (Registro Judicial de Antecedentes Penales): solicítalo en línea en rejap.organojudicial.gob.bo con tu CI, o presencialmente en las oficinas del Órgano Judicial.\n\n'
            'Ambos certifican si tienes o no antecedentes penales. Sube una foto clara o el PDF que te entreguen — no es obligatorio para aparecer en el marketplace, es un filtro adicional de confianza.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
        ],
      ),
    );
  }

  Widget _documentStatusRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool verified,
    required Color textColor,
    required Color subtextColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
      child: Row(
        children: [
          Icon(icon, color: subtextColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                Text(subtitle, style: TextStyle(color: subtextColor, fontSize: 12)),
              ],
            ),
          ),
          Icon(
            verified ? Icons.check_circle_rounded : Icons.hourglass_empty_rounded,
            color: verified ? GardenColors.success : subtextColor,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _antecedentesRow(Color textColor, Color subtextColor, Color borderColor) {
    final (statusIcon, statusColor, statusLabel) = switch (_antecedentesStatus) {
      'LIMPIO' => (Icons.check_circle_rounded, GardenColors.success, 'Verificado'),
      'EN_REVISION' => (Icons.hourglass_top_rounded, GardenColors.warning, 'En revisión'),
      'FLAGGED' => (Icons.flag_rounded, GardenColors.error, 'En revisión por un admin'),
      _ => (Icons.upload_file_outlined, subtextColor, 'Pendiente'),
    };
    final canUpload = _antecedentesStatus == 'PENDING';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.gavel_outlined, color: subtextColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Antecedentes penales', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                    Text('Filtro opcional — no es requisito para mostrarte en el marketplace', style: TextStyle(color: subtextColor, fontSize: 11.5)),
                  ],
                ),
              ),
              Icon(statusIcon, color: statusColor, size: 20),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: _showAntecedentesInfoDialog,
                icon: const Icon(Icons.info_outline_rounded, size: 16),
                label: const Text('¿Cómo lo obtengo?', style: TextStyle(fontSize: 12.5)),
              ),
              const Spacer(),
              if (canUpload)
                ElevatedButton(
                  onPressed: _uploadingAntecedentes ? null : _pickAndUploadAntecedentes,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GardenColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _uploadingAntecedentes
                      ? const GardenLoadingIndicator(size: 16, color: Colors.white)
                      : const Text('Subir documento', style: TextStyle(fontSize: 12.5)),
                )
              else
                Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentsSectionContent(Color textColor, Color subtextColor, Color borderColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _documentStatusRow(
          icon: Icons.badge_outlined,
          title: 'Identidad',
          subtitle: 'Verificada al registrarte',
          verified: _identityVerified,
          textColor: textColor, subtextColor: subtextColor, borderColor: borderColor,
        ),
        const SizedBox(height: 10),
        _documentStatusRow(
          icon: Icons.credit_card_outlined,
          title: 'Cédula de Identidad',
          subtitle: 'Verificada al registrarte',
          verified: _identityVerified,
          textColor: textColor, subtextColor: subtextColor, borderColor: borderColor,
        ),
        const SizedBox(height: 10),
        _antecedentesRow(textColor, subtextColor, borderColor),
      ],
    );
  }

  Future<void> _addPlacePhoto(String section) async {
    // Evita disparar subidas concurrentes (doble-tap o tocar otra sección
    // mientras una subida sigue en vuelo). El backend ya es atómico, pero
    // esto además evita gastar cuota/ancho de banda con subidas duplicadas.
    if (_uploadingPlacePhoto) return;
    final current = _placePhotoUrls[section] ?? [];
    if (current.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Máximo 3 fotos por sección')));
      return;
    }
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: kIsWeb ? null : 85);
    if (picked == null) return;
    final bytes = Uint8List.fromList(await picked.readAsBytes());
    final fileName = picked.name.isEmpty ? 'place_${DateTime.now().millisecondsSinceEpoch}.jpg' : picked.name;
    setState(() => _uploadingPlacePhoto = true);
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/caregiver/profile/place-photo'));
      request.headers['Authorization'] = 'Bearer $_caregiverToken';
      request.fields['section'] = section;
      request.files.add(http.MultipartFile.fromBytes('placePhoto', bytes, filename: fileName, contentType: MediaType('image', 'jpeg')));
      final resp = await request.send();
      final data = jsonDecode(await resp.stream.bytesToString());
      if (!mounted) return;
      if (data['success'] == true) {
        setState(() {
          _placePhotoUrls[section] = List<String>.from(_placePhotoUrls[section] ?? [])..add(data['data']['photoUrl'] as String);
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['error']?['message'] ?? 'Error al subir foto'), backgroundColor: GardenColors.error));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: GardenColors.error));
    } finally {
      if (mounted) setState(() => _uploadingPlacePhoto = false);
    }
  }

  Future<void> _deletePlacePhoto(String section, int index) async {
    final url = (_placePhotoUrls[section] ?? [])[index];
    setState(() {
      final updated = List<String>.from(_placePhotoUrls[section] ?? [])..removeAt(index);
      _placePhotoUrls[section] = updated;
    });
    try {
      await http.delete(
        Uri.parse('$_baseUrl/caregiver/profile/place-photo'),
        headers: {'Authorization': 'Bearer $_caregiverToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'section': section, 'photoUrl': url}),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      if (widget.embeddedMode) {
        return const Center(child: GardenLoadingIndicator(color: GardenColors.primary));
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Perfil profesional')),
        body: const Center(child: GardenLoadingIndicator(color: GardenColors.primary)),
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

    if (kIsWeb) {
      return _buildWebScaffold(context, isDark, textColor, subtextColor, surface, borderColor);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil profesional'),
        actions: [
          if (_isSaving)
            const Center(child: Padding(padding: EdgeInsets.only(right: 16), child: GardenLoadingIndicator(size: 20, color: GardenColors.primary)))
          else if (_isEditing) ...[
            TextButton(onPressed: () { setState(() => _isEditing = false); _loadData(); }, child: Text('Cancelar', style: TextStyle(color: textColor))),
            TextButton(onPressed: _saveAllData, child: const Text('Guardar', style: TextStyle(color: GardenColors.primary, fontWeight: FontWeight.bold, fontSize: 15))),
          ] else
            TextButton(onPressed: () => setState(() => _isEditing = true), child: const Text('Editar', style: TextStyle(color: GardenColors.primary, fontWeight: FontWeight.bold, fontSize: 15))),
        ],
      ),
      body: _buildBody(textColor, subtextColor, surface, borderColor, isDark),
    );
  }

  // ── WEB LAYOUT ────────────────────────────────────────────────────────────
  Widget _buildWebScaffold(
    BuildContext context,
    bool isDark,
    Color textColor,
    Color subtextColor,
    Color surface,
    Color borderColor,
  ) {
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          // ── Top bar con botones Editar / Guardar ──────────────────────────
          Container(
            height: 64,
            decoration: BoxDecoration(
              color: surface,
              border: Border(bottom: BorderSide(color: borderColor)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back_rounded, color: textColor, size: 20),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Volver',
                ),
                const SizedBox(width: 4),
                Text('Datos del cuidador',
                  style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700)),
                const Spacer(),
                // Badge de completitud (oculto al llegar a 100%)
                if (_completionPercentage < 100) ...[
                  GestureDetector(
                    onTap: _showCompletionChecklist,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: (_completionPercentage >= 80 ? GardenColors.success : GardenColors.warning).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$_completionPercentage%',
                        style: TextStyle(
                          color: _completionPercentage >= 80 ? GardenColors.success : GardenColors.warning,
                          fontSize: 11, fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                // Botones Editar / Guardar / Cancelar — siempre en el header
                if (_isSaving)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: GardenLoadingIndicator(size: 20, color: GardenColors.primary),
                  )
                else if (_isEditing) ...[
                  TextButton(
                    onPressed: () { setState(() => _isEditing = false); _loadData(); },
                    style: TextButton.styleFrom(foregroundColor: subtextColor, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    child: const Text('Cancelar', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    onPressed: _saveAllData,
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Guardar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GardenColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                ] else
                  ElevatedButton.icon(
                    onPressed: () => setState(() => _isEditing = true),
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text('Editar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GardenColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                const SizedBox(width: 8),
              ],
            ),
          ),

          // ── Scrollable two-column body — sin AbsorbPointer ─────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 24, left: 24, right: 24, bottom: 100),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── LEFT column ────────────────────────────────────────
                      Expanded(
                        flex: 55,
                        child: Column(
                          children: [
                            // Servicios y precios — redesignado con cards por servicio
                            _webSection(surface, borderColor, textColor,
                              title: 'Servicios y precios',
                              icon: Icons.sell_outlined,
                              child: _buildServicesPricesSection(surface, borderColor, textColor, subtextColor),
                            ),
                            const SizedBox(height: 14),

                            // Servicios extra — solo para cuentas EMPRESA
                            if (_ic) ...[
                              _webSection(surface, borderColor, textColor,
                                title: 'Servicios extra',
                                icon: Icons.add_business_outlined,
                                child: IgnorePointer(
                                  ignoring: !_isEditing,
                                  child: Opacity(
                                    opacity: _isEditing ? 1 : 0.6,
                                    child: ExtraServicesEditor(token: _caregiverToken, baseUrl: _baseUrl),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],

                            if (_needsSpaceSection) ...[
                              _webSection(surface, borderColor, textColor,
                                title: 'Tu espacio',
                                icon: Icons.home_outlined,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(key: _keySpaceType, height: 0),
                                    IgnorePointer(ignoring: !_isEditing, child: _buildHomeTypes(surface, borderColor)),
                                    IgnorePointer(ignoring: !_isEditing, child: _buildSwitchTile('¿Tiene jardín o patio?', _hasYard, (v) => setState(() => _hasYard = v))),
                                    IgnorePointer(ignoring: !_isEditing, child: _buildSwitchTile('¿Permite mascotas grandes?', _allowsLargePets, (v) => setState(() => _allowsLargePets = v))),
                                    IgnorePointer(ignoring: !_isEditing, child: _buildSwitchTile('¿Permite múltiples mascotas?', _allowsMultiplePets, (v) => setState(() => _allowsMultiplePets = v))),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],

                            if (widget.showPhotos) ...[
                              _webSection(surface, borderColor, textColor,
                                title: 'Fotos del cuidador en acción',
                                icon: Icons.photo_library_outlined,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(key: _keyPhotos, height: 0),
                                    Text(
                                      'Fotos tuyas con mascotas (mín. ${_effectiveServices.length == 1 && _effectiveServices.contains('PASEO') ? 2 : 4}, máx. 6)',
                                      style: TextStyle(color: subtextColor, fontSize: 12),
                                    ),
                                    const SizedBox(height: 12),
                                    if (_uploadingCaregiverPhoto)
                                      const Padding(padding: EdgeInsets.only(bottom: 8), child: LinearProgressIndicator(color: GardenColors.primary)),
                                    IgnorePointer(ignoring: !_isEditing, child: _buildCaregiverPhotoGrid(borderColor)),
                                  ],
                                ),
                              ),
                              if (_needsPlacePhotos) ...[
                                const SizedBox(height: 14),
                                _webSection(surface, borderColor, textColor,
                                  title: 'Fotos del espacio',
                                  icon: Icons.home_work_outlined,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(key: _keyPlacePhotos, height: 0),
                                      Text('Muestra el espacio donde cuidas a las mascotas',
                                        style: TextStyle(color: subtextColor, fontSize: 12)),
                                      const SizedBox(height: 12),
                                      if (_uploadingPlacePhoto)
                                        const Padding(padding: EdgeInsets.only(bottom: 8), child: LinearProgressIndicator(color: GardenColors.primary)),
                                      IgnorePointer(
                                        ignoring: !_isEditing,
                                        child: Column(
                                          children: [
                                            for (final (key, label, required) in _placeSections)
                                              _buildPlaceSectionBlock(key, label, required, borderColor, textColor, subtextColor),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(width: 16),

                      // ── RIGHT column ───────────────────────────────────────
                      Expanded(
                        flex: 45,
                        child: Column(
                          children: [
                            _webSection(surface, borderColor, textColor,
                              title: 'Mascotas que aceptas',
                              icon: Icons.pets_rounded,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(key: _keyPetTypes, height: 0),
                                  Text('Tipos de mascotas', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 8),
                                  IgnorePointer(
                                    ignoring: !_isEditing,
                                    child: Wrap(
                                      spacing: 8,
                                      children: _petTypes.map((t) => _filterChip(t, _petTypeLabels[t]!, _acceptedPetTypes, surface, borderColor)).toList(),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  SizedBox(key: _keySizes, height: 0),
                                  Text('Tamaños aceptados', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  IgnorePointer(
                                    ignoring: !_isEditing,
                                    child: Column(
                                      children: _petSizes.map((s) => _buildCheckTile(_petSizeLabels[s]!, _acceptedSizes.contains(s), (v) {
                                        setState(() { if (v!) { _acceptedSizes.add(s); } else { _acceptedSizes.remove(s); } });
                                      })).toList(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            _webSection(surface, borderColor, textColor,
                              title: 'Preguntas frecuentes',
                              icon: Icons.help_outline_rounded,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(key: _keyFaq, height: 0),
                                  Text('¿Qué incluye tu servicio?',
                                    style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  _viewOrInput(_includesController, 'Ej: Paseos diarios, fotos del recorrido, reportes de salud...',
                                    maxLines: 2, textColor: textColor, subtextColor: subtextColor, surface: surface, borderColor: borderColor),
                                  const SizedBox(height: 14),
                                  Text('¿Qué necesitas del dueño?',
                                    style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  _viewOrInput(_requirementsController, 'Ej: Correa, vacunas al día, bolsas para recoger...',
                                    maxLines: 2, textColor: textColor, subtextColor: subtextColor, surface: surface, borderColor: borderColor),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            _webSection(surface, borderColor, textColor,
                              title: _lExpTitle,
                              icon: Icons.workspace_premium_outlined,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(key: _keyExperience, height: 0),
                                  Text(_lYearsLabel, style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 8),
                                  IgnorePointer(
                                    ignoring: !_isEditing,
                                    child: Wrap(
                                      spacing: 8,
                                      children: ['0', '1', '2', '3', '4', '5+'].map((y) {
                                        final sel = _experienceYearsController.text == y;
                                        return GestureDetector(
                                          onTap: () => setState(() => _experienceYearsController.text = y),
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 150),
                                            margin: const EdgeInsets.only(bottom: 6),
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                            decoration: BoxDecoration(
                                              color: sel ? GardenColors.primary : surface,
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(color: sel ? GardenColors.primary : borderColor),
                                            ),
                                            child: Text(y, style: TextStyle(color: sel ? Colors.white : subtextColor, fontWeight: FontWeight.w600, fontSize: 13)),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                  if (_experienceYearsController.text.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    // Info para principiantes
                                    if (_isAmateur) ...[
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 12),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: GardenColors.primary.withValues(alpha: 0.07),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: GardenColors.primary.withValues(alpha: 0.3)),
                                        ),
                                        child: Row(children: [
                                          const Icon(Icons.info_outline_rounded, color: GardenColors.primary, size: 15),
                                          const SizedBox(width: 8),
                                          Expanded(child: Text(
                                            'Empezas como cuidador nuevo — completa los campos abajo para presentarte a los dueños.',
                                            style: TextStyle(color: textColor, fontSize: 12),
                                          )),
                                        ]),
                                      ),
                                    ] else ...[
                                      IgnorePointer(ignoring: !_isEditing, child: _sectionField(_lExpDesc, _experienceDescController, _lExpDescHint, maxLines: 3, coherenceKey: 'experienceDesc')),
                                      const SizedBox(height: 10),
                                    ],
                                    // whyCaregiver y whatDiffers — siempre visibles
                                    IgnorePointer(ignoring: !_isEditing, child: _sectionField(_lWhyLabel, _whyCaregiverController, _lWhyHint, maxLines: 2, coherenceKey: 'whyCaregiver')),
                                    const SizedBox(height: 10),
                                    IgnorePointer(ignoring: !_isEditing, child: _sectionField(_lDiffersLabel, _whatDiffersController, _lDiffersHint, maxLines: 2, coherenceKey: 'whatDiffers')),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            _webSection(surface, borderColor, textColor,
                              title: _lPoliciesTitle,
                              icon: Icons.policy_outlined,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(key: _keyPolicies, height: 0),
                                  IgnorePointer(ignoring: !_isEditing, child: _acceptSwitch('¿Aceptas mascotas agresivas?', _acceptAggressive, (v) => setState(() => _acceptAggressive = v), textColor, subtextColor, surface, borderColor)),
                                  const SizedBox(height: 8),
                                  IgnorePointer(ignoring: !_isEditing, child: _acceptSwitch('¿Aceptas cachorros?', _acceptPuppies, (v) => setState(() => _acceptPuppies = v), textColor, subtextColor, surface, borderColor)),
                                  const SizedBox(height: 8),
                                  IgnorePointer(ignoring: !_isEditing, child: _acceptSwitch('¿Aceptas mascotas mayores?', _acceptSeniors, (v) => setState(() => _acceptSeniors = v), textColor, subtextColor, surface, borderColor)),
                                  const SizedBox(height: 8),
                                  IgnorePointer(ignoring: !_isEditing, child: _acceptSwitch('¿Exiges Meet & Greet antes del primer servicio?', _requireMeetAndGreet, (v) => setState(() => _requireMeetAndGreet = v), textColor, subtextColor, surface, borderColor)),
                                  if (!_isAmateur && _experienceYearsController.text.isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    SizedBox(key: _keyHandleAnxious, height: 0),
                                    Text(_lAnxious, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 8),
                                    IgnorePointer(ignoring: !_isEditing, child: _buildChipsSection(_anxiousOptions, _selectedAnxiousOptions, surface, borderColor)),
                                    const SizedBox(height: 14),
                                    SizedBox(key: _keyEmergencyResponse, height: 0),
                                    Text(_lEmergency, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 8),
                                    IgnorePointer(ignoring: !_isEditing, child: _buildChipsSection(_emergencyOptions, _selectedEmergencyOptions, surface, borderColor)),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            _webSection(surface, borderColor, textColor,
                              title: 'Documentos',
                              icon: Icons.folder_shared_outlined,
                              child: _buildDocumentsSectionContent(textColor, subtextColor, borderColor),
                            ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── SERVICIOS Y PRECIOS — muestra los 3 servicios siempre ────────────────
  Widget _buildServicesPricesSection(Color surface, Color borderColor, Color textColor, Color subtextColor) {
    const allServices = ['PASEO', 'HOSPEDAJE', 'GUARDERIA'];
    const serviceData = {
      'PASEO':      ('🦮', 'Paseo de mascotas'),
      'HOSPEDAJE':  ('🏠', 'Hospedaje'),
      'GUARDERIA':  ('🐾', 'Guardería diurna'),
    };
    final List<(String, TextEditingController)> paseoRows = [
      ('Paseo de 30 minutos  (media hora)', _pricePerWalk30Controller),
      ('Paseo de 60 minutos  (una hora completa)', _pricePerWalk60Controller),
    ];
    final List<(String, TextEditingController)> hospedajeRows = [
      ('Precio por noche', _pricePerDayController),
    ];
    final List<(String, TextEditingController)> guarderiaRows = [
      ('Precio por día', _pricePerGuarderiaController),
    ];

    return Column(
      key: _keyServicesPrices,
      children: allServices.map((s) {
        final info = serviceData[s]!;
        final (emoji, name) = info;
        final isActive = _effectiveServices.contains(s);
        final rows = s == 'PASEO' ? paseoRows : s == 'HOSPEDAJE' ? hospedajeRows : guarderiaRows;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isActive
                ? GardenColors.primary.withValues(alpha: 0.04)
                : surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive
                  ? GardenColors.primary.withValues(alpha: 0.2)
                  : borderColor.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(children: [
                  Text(emoji, style: TextStyle(fontSize: 20, color: isActive ? null : Colors.grey)),
                  const SizedBox(width: 10),
                  Text(name, style: TextStyle(
                    color: isActive ? textColor : subtextColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  )),
                  const Spacer(),
                  if (_isEditing) ...[
                    // Toggle en modo edición
                    Transform.scale(
                      scale: 0.85,
                      child: Switch(
                        value: isActive,
                        activeColor: GardenColors.primary,
                        onChanged: (v) => setState(() {
                          if (v) {
                            _apiServicesOffered = [..._apiServicesOffered, s];
                          } else {
                            _apiServicesOffered = _apiServicesOffered.where((x) => x != s).toList();
                          }
                        }),
                      ),
                    ),
                  ] else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: (isActive ? GardenColors.success : subtextColor).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isActive ? 'Activo' : 'No ofrecido',
                        style: TextStyle(
                          color: isActive ? GardenColors.success : subtextColor,
                          fontSize: 11, fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ]),
              ),
              if (isActive) ...[
                Divider(height: 1, color: borderColor.withValues(alpha: 0.5)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    children: rows.map((row) {
                      final rowLabel = row.$1;
                      final rowCtrl  = row.$2;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              flex: 6,
                              child: Text(rowLabel, style: TextStyle(color: subtextColor, fontSize: 13, height: 1.3)),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 4,
                              child: _isEditing
                                ? _priceField(rowCtrl, borderColor, textColor)
                                : _priceReadOnly(rowCtrl.text, textColor, subtextColor),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ] else if (!isActive && _isEditing)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Text(
                    'Activa este servicio con el interruptor para configurar su precio.',
                    style: TextStyle(color: subtextColor, fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _priceField(TextEditingController controller, Color borderColor, Color textColor) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
        prefixText: 'Bs. ',
        prefixStyle: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w600, fontSize: 14),
      ),
      onChanged: (_) => _computeCompletion(),
    );
  }

  Widget _priceReadOnly(String rawValue, Color textColor, Color subtextColor) {
    final d = double.tryParse(rawValue) ?? 0;
    final display = d > 0 ? 'Bs. ${d % 1 == 0 ? d.toInt().toString() : d.toStringAsFixed(1)}' : 'Sin configurar';
    return Text(display, style: TextStyle(
      color: d > 0 ? textColor : subtextColor.withValues(alpha: 0.6),
      fontSize: 15,
      fontWeight: d > 0 ? FontWeight.w600 : FontWeight.normal,
    ));
  }

  // ── VIEW OR INPUT — muestra texto en modo vista, campo en modo edición ─────
  Widget _viewOrInput(TextEditingController ctrl, String hint, {
    int maxLines = 1, int? maxLength,
    required Color textColor, required Color subtextColor,
    required Color surface, required Color borderColor,
    String? coherenceKey,
  }) {
    if (_isEditing) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GardenInput(controller: ctrl, hint: hint, maxLines: maxLines, maxLength: maxLength, onChanged: (v) {
          setState(() {});
          if (coherenceKey != null) _scheduleCoherenceCheck(coherenceKey, hint, v);
        }),
        if (coherenceKey != null) _coherenceWarningText(coherenceKey),
      ]);
    }
    final text = ctrl.text.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor.withValues(alpha: 0.5)),
      ),
      child: Text(
        text.isEmpty ? hint : text,
        style: TextStyle(
          color: text.isEmpty ? subtextColor.withValues(alpha: 0.5) : textColor,
          fontSize: 14, height: 1.45,
        ),
        maxLines: maxLines > 1 ? maxLines : null,
        overflow: TextOverflow.visible,
      ),
    );
  }

  Widget _webSection(
    Color surface, Color borderColor, Color textColor, {
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: GardenColors.primary),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  // ── END WEB LAYOUT ───────────────────────────────────────────────────────

  Widget _buildBody(Color textColor, Color subtextColor, Color surface, Color borderColor, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Sección 1 — Banner (solo si incompleto)
          if (_completionPercentage < 100) ...[
            _buildCompletionBanner(),
            const SizedBox(height: 32),
          ],

            // Sección — Servicios y precios. Solo fuera del wizard de
            // onboarding (embeddedMode): ahí los servicios ofrecidos y
            // precios ya se definen en un paso dedicado del wizard, y este
            // widget se autogatea con _isEditing (que nunca se activa dentro
            // del wizard), así que mostrarlo ahí lo dejaría en solo-lectura.
            // Antes esta sección solo existía en la vista web
            // (_buildWebScaffold) — en la app real (iOS/Android) un
            // cuidador jamás podía cambiar su precio después del registro.
            if (!widget.embeddedMode) ...[
              _sectionTitle('Servicios y precios', textColor),
              _buildServicesPricesSection(surface, borderColor, textColor, subtextColor),
              const Divider(height: 48),
            ],

            SizedBox(key: _keyAddress, height: 0),
            const Divider(height: 48),

            // Sección — Tu espacio (solo para HOSPEDAJE o GUARDERIA)
            if (_needsSpaceSection) ...[
              SizedBox(key: _keySpaceType, height: 0),
              _sectionTitle('Tu espacio', textColor),
              IgnorePointer(ignoring: !widget.embeddedMode && !_isEditing, child: _buildHomeTypes(surface, borderColor)),
              const SizedBox(height: 16),
              IgnorePointer(ignoring: !widget.embeddedMode && !_isEditing, child: _buildSwitchTile('¿Tiene jardín o patio?', _hasYard, (v) => setState(() => _hasYard = v))),
              IgnorePointer(ignoring: !widget.embeddedMode && !_isEditing, child: _buildSwitchTile('¿Permite mascotas grandes?', _allowsLargePets, (v) => setState(() => _allowsLargePets = v))),
              IgnorePointer(ignoring: !widget.embeddedMode && !_isEditing, child: _buildSwitchTile('¿Permite múltiples mascotas?', _allowsMultiplePets, (v) => setState(() => _allowsMultiplePets = v))),
              const Divider(height: 48),
            ],

            // Máximo de reservas simultáneas. Tope de 3 para cuidadores
            // individuales (una empresa puede poner más — no tiene tope).
            // Hospedaje y Guardería NO son cupos independientes — comparten
            // un solo pool combinado, porque atenderlos a la vez ocupa a la
            // misma persona/espacio (ver combinedHospedajeGuarderiaMax en el
            // backend). Paseo es totalmente aparte, con su propio cupo.
            Text('Máximo de reservas simultáneas', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              _ic
                  ? 'Cuántas mascotas puedes atender al mismo tiempo. Hospedaje y Guardería comparten un mismo cupo (atenderlas juntas ocupa el mismo espacio); Paseo tiene el suyo aparte.'
                  : 'Cuántas mascotas puedes atender al mismo tiempo (máx. 3). Hospedaje y Guardería comparten un mismo cupo (atenderlas juntas ocupa el mismo espacio); Paseo tiene el suyo aparte.',
              style: TextStyle(color: subtextColor, fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 14),
            if (_effectiveServices.contains('PASEO'))
              _maxPetsStepper('Paseo', _maxPetsPaseo, (v) => setState(() => _maxPetsPaseo = v), textColor, subtextColor, surface, borderColor, maxCap: _ic ? null : 3),
            if (_effectiveServices.contains('HOSPEDAJE') || _effectiveServices.contains('GUARDERIA'))
              _maxPetsStepper(
                'Hospedaje + Guardería',
                _maxPetsHospedaje,
                (v) => setState(() {
                  _maxPetsHospedaje = v;
                  _maxPetsGuarderia = v;
                }),
                textColor, subtextColor, surface, borderColor,
                maxCap: _ic ? null : 3,
              ),
            const Divider(height: 48),

            // Sección 5 — Tipos de mascotas
            SizedBox(key: _keyPetTypes, height: 0),
            _sectionTitle('Mascotas que aceptas', textColor),
            IgnorePointer(
              ignoring: !widget.embeddedMode && !_isEditing,
              child: Wrap(
                spacing: 8,
                children: _petTypes.map((t) => _filterChip(t, _petTypeLabels[t]!, _acceptedPetTypes, surface, borderColor)).toList(),
              ),
            ),
            const Divider(height: 48),

            // Sección 7 — Tamaños
            SizedBox(key: _keySizes, height: 0),
            _sectionTitle('Tamaños aceptados', textColor),
            IgnorePointer(
              ignoring: !widget.embeddedMode && !_isEditing,
              child: Column(
                children: _petSizes.map((s) => _buildCheckTile(_petSizeLabels[s]!, _acceptedSizes.contains(s), (v) {
                  setState(() { if (v!) {
                    _acceptedSizes.add(s);
                  } else {
                    _acceptedSizes.remove(s);
                  } });
                })).toList(),
              ),
            ),
            const Divider(height: 48),

            // Sección — Fotos (oculta en modo wizard; ya se subieron en el Paso 2)
            if (widget.showPhotos) ...[
              SizedBox(key: _keyPhotos, height: 0),
              _sectionTitle('Fotos del cuidador', textColor),
              Text(
                'Sube fotos tuyas en acción con mascotas (mín. 2, máx. 6)',
                style: TextStyle(color: subtextColor, fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (_uploadingCaregiverPhoto)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(color: GardenColors.primary),
                ),
              IgnorePointer(
                ignoring: !widget.embeddedMode && !_isEditing,
                child: _buildCaregiverPhotoGrid(borderColor),
              ),

              if (_needsPlacePhotos) ...[
                const SizedBox(height: 28),
                _sectionTitle('Fotos del lugar', textColor),
                Text(
                  'Muestra el espacio donde se brindará el servicio',
                  style: TextStyle(color: subtextColor, fontSize: 13),
                ),
                const SizedBox(height: 12),
                if (_uploadingPlacePhoto)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(color: GardenColors.primary),
                  ),
                IgnorePointer(
                  ignoring: !widget.embeddedMode && !_isEditing,
                  child: Column(
                    children: [
                      for (final (key, label, required) in _placeSections)
                        _buildPlaceSectionBlock(key, label, required, borderColor, textColor, subtextColor),
                    ],
                  ),
                ),
              ],
              const Divider(height: 48),
            ],

            // Sección 8 — FAQ
            SizedBox(key: _keyFaq, height: 0),
            _sectionTitle('Preguntas frecuentes', textColor),
            IgnorePointer(
              ignoring: !widget.embeddedMode && !_isEditing,
              child: GardenInput(
                hint: '¿Qué incluye tu servicio?',
                controller: _includesController,
                enabled: widget.embeddedMode || _isEditing,
                maxLines: 2,
              ),
            ),
            const SizedBox(height: 12),
            const SizedBox(height: 12),
            IgnorePointer(
              ignoring: !widget.embeddedMode && !_isEditing,
              child: GardenInput(
                hint: '¿Qué necesitas del dueño antes del servicio?',
                controller: _requirementsController,
                enabled: widget.embeddedMode || _isEditing,
                maxLines: 2,
              ),
            ),

            const Divider(height: 48),

            // Sección — Experiencia profesional
            SizedBox(key: _keyExperience, height: 0),
            _sectionTitle(_lExpTitle, textColor),
            Text(_lYearsLabel, style: TextStyle(color: subtextColor, fontSize: 13)),
            const SizedBox(height: 8),
            IgnorePointer(
              ignoring: !widget.embeddedMode && !_isEditing,
              child: Wrap(
                spacing: 8,
                children: [
                  for (final years in ['0', '1', '2', '3', '4', '5+'])
                    GestureDetector(
                      onTap: () => setState(() => _experienceYearsController.text = years),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 4),
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
            ),

            // Follow-up: solo cuando experienceYears >= 1
            if (!_isAmateur && _experienceYearsController.text.isNotEmpty) ...[
              const SizedBox(height: 16),
              IgnorePointer(ignoring: !widget.embeddedMode && !_isEditing, child: _sectionField(_lExpDesc, _experienceDescController, _lExpDescHint, maxLines: 4, coherenceKey: 'experienceDesc')),
              const SizedBox(height: 16),
              IgnorePointer(ignoring: !widget.embeddedMode && !_isEditing, child: _sectionField(_lWhyLabel, _whyCaregiverController, _lWhyHint, maxLines: 3, coherenceKey: 'whyCaregiver')),
              const SizedBox(height: 16),
              IgnorePointer(ignoring: !widget.embeddedMode && !_isEditing, child: _sectionField(_lDiffersLabel, _whatDiffersController, _lDiffersHint, maxLines: 3, coherenceKey: 'whatDiffers')),
            ],

            if (_isAmateur && _experienceYearsController.text == '0') ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: GardenColors.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: GardenColors.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: GardenColors.primary, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '¡Sin problema! Puedes empezar como cuidador nuevo. Deberás completar los videos de capacitación antes de tu primer servicio.',
                        style: TextStyle(color: textColor, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const Divider(height: 48),

            // Políticas de mascotas — siempre visibles (No/Sí desde el inicio)
            SizedBox(key: _keyPolicies, height: 0),
            _sectionTitle(_lPoliciesTitle, textColor),
            IgnorePointer(ignoring: !widget.embeddedMode && !_isEditing, child: _acceptSwitch('¿Aceptas mascotas agresivas?', _acceptAggressive, (val) => setState(() => _acceptAggressive = val), textColor, subtextColor, surface, borderColor)),
            const SizedBox(height: 8),
            IgnorePointer(ignoring: !widget.embeddedMode && !_isEditing, child: _acceptSwitch('¿Aceptas cachorros?', _acceptPuppies, (val) => setState(() => _acceptPuppies = val), textColor, subtextColor, surface, borderColor)),
            const SizedBox(height: 8),
            IgnorePointer(ignoring: !widget.embeddedMode && !_isEditing, child: _acceptSwitch('¿Aceptas mascotas mayores?', _acceptSeniors, (val) => setState(() => _acceptSeniors = val), textColor, subtextColor, surface, borderColor)),
            const SizedBox(height: 8),
            IgnorePointer(ignoring: !widget.embeddedMode && !_isEditing, child: _acceptSwitch('¿Exiges Meet & Greet antes del primer servicio?', _requireMeetAndGreet, (val) => setState(() => _requireMeetAndGreet = val), textColor, subtextColor, surface, borderColor)),

            // Situaciones especiales — solo para no-amateurs
            if (!_isAmateur && _experienceYearsController.text.isNotEmpty) ...[
              const Divider(height: 48),
              _sectionTitle(_lSituTitle, textColor),
              SizedBox(key: _keyHandleAnxious, height: 0),
              Text(_lAnxious, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              IgnorePointer(ignoring: !widget.embeddedMode && !_isEditing, child: _buildChipsSection(_anxiousOptions, _selectedAnxiousOptions, surface, borderColor)),
              const SizedBox(height: 20),
              SizedBox(key: _keyEmergencyResponse, height: 0),
              Text(_lEmergency, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              IgnorePointer(ignoring: !widget.embeddedMode && !_isEditing, child: _buildChipsSection(_emergencyOptions, _selectedEmergencyOptions, surface, borderColor)),
            ],

            const Divider(height: 48),

            if (!widget.embeddedMode) ...[
              _sectionTitle('Documentos', textColor),
              _buildDocumentsSectionContent(textColor, subtextColor, borderColor),
              const Divider(height: 48),
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
                  onPressed: (_isSaving || !_isProfileComplete) ? null : _saveAllData,
                  child: _isSaving
                      ? const GardenLoadingIndicator(size: 24, color: Colors.white)
                      : const Text('Guardar y continuar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Al continuar aceptas los Términos de Servicio y Política de Privacidad de GARDEN',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: subtextColor, fontSize: 11),
                ),
              ),
            ],

            const SizedBox(height: 60),
          ],
        ),
    );
  }

  Widget _sectionField(String label, TextEditingController controller, String hint, {int maxLines = 1, String? coherenceKey}) {
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
          onChanged: (v) {
            _computeCompletion();
            if (coherenceKey != null) _scheduleCoherenceCheck(coherenceKey, label, v);
          },
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
        if (coherenceKey != null) _coherenceWarningText(coherenceKey),
      ],
    );
  }

  Widget _acceptSwitch(String label, bool value, Function(bool) onChanged, Color textColor, Color subtextColor, Color surface, Color borderColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: value ? GardenColors.primary.withValues(alpha: 0.06) : surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? GardenColors.primary.withValues(alpha: 0.35) : borderColor,
        ),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: textColor, fontSize: 14))),
          Text(
            value ? 'Sí' : 'No',
            style: TextStyle(
              color: value ? GardenColors.primary : subtextColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Switch(
            value: value,
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
          if (_completionPercentage < 100) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _showCompletionChecklist,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Ver qué falta', style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 14),
                ],
              ),
            ),
          ],
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

  /// Stepper numérico +/- para el máximo de reservas simultáneas de un
  /// servicio (o pool combinado de servicios) — mínimo 1, tope opcional
  /// (maxCap null = sin tope, para empresas).
  Widget _maxPetsStepper(
    String label,
    int value,
    ValueChanged<int> onChanged,
    Color textColor,
    Color subtextColor,
    Color surface,
    Color borderColor, {
    int? maxCap,
  }) {
    final enabled = widget.embeddedMode || _isEditing;
    final atCap = maxCap != null && value >= maxCap;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded),
              color: enabled && value > 1 ? GardenColors.primary : subtextColor.withValues(alpha: 0.3),
              onPressed: enabled && value > 1 ? () => onChanged(value - 1) : null,
            ),
            SizedBox(
              width: 32,
              child: Text('$value', textAlign: TextAlign.center,
                style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded),
              color: enabled && !atCap ? GardenColors.primary : subtextColor.withValues(alpha: 0.3),
              onPressed: enabled && !atCap ? () => onChanged(value + 1) : null,
            ),
          ],
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

  /// Chips de selección múltiple para "Situaciones especiales".
  Widget _buildChipsSection(List<String> options, List<String> selected, Color surface, Color border) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final isSel = selected.contains(opt);
        return GestureDetector(
          onTap: () => setState(() {
            if (isSel) {
              selected.remove(opt);
            } else {
              selected.add(opt);
            }
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSel ? GardenColors.primary.withValues(alpha: 0.12) : surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSel ? GardenColors.primary : border,
                width: isSel ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSel) ...[
                  const Icon(Icons.check_rounded, color: GardenColors.primary, size: 14),
                  const SizedBox(width: 4),
                ],
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 80),
                  child: Text(
                    opt,
                    softWrap: true,
                    style: TextStyle(
                      color: isSel ? GardenColors.primary : GardenColors.textSecondary,
                      fontSize: 13,
                      fontWeight: isSel ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCaregiverPhotoGrid(Color borderColor) {
    final count = _caregiverPhotoUrls.length;
    final showAdd = count < 6;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
      itemCount: showAdd ? count + 1 : count,
      itemBuilder: (context, index) {
        if (index == count && showAdd) {
          return GestureDetector(
            onTap: _addCaregiverPhoto,
            child: Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: GardenColors.primary.withValues(alpha: 0.4), style: BorderStyle.solid)),
              child: const Icon(Icons.add_a_photo_outlined, color: GardenColors.primary),
            ),
          );
        }
        return Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                image: DecorationImage(image: NetworkImage(_caregiverPhotoUrls[index]), fit: BoxFit.cover),
              ),
            ),
            Positioned(
              right: 5, top: 5,
              child: GestureDetector(
                onTap: () => _deleteCaregiverPhoto(index),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: Colors.white, size: 14),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlaceSectionBlock(String key, String label, bool required, Color borderColor, Color textColor, Color subtextColor) {
    final photos = _placePhotoUrls[key] ?? [];
    final canAdd = photos.length < 3;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Text(
                required ? 'obligatorio' : 'opcional',
                style: TextStyle(
                  color: required ? GardenColors.error : GardenColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < photos.length; i++)
                SizedBox(
                  width: 80, height: 80,
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          image: DecorationImage(image: NetworkImage(photos[i]), fit: BoxFit.cover),
                        ),
                      ),
                      Positioned(
                        right: 3, top: 3,
                        child: GestureDetector(
                          onTap: () => _deletePlacePhoto(key, i),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.close, color: Colors.white, size: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (canAdd)
                GestureDetector(
                  // Deshabilitado mientras hay una subida en curso (cualquier sección) —
                  // evita disparar subidas concurrentes por doble-tap o tocar otra sección.
                  onTap: _uploadingPlacePhoto ? null : () => _addPlacePhoto(key),
                  child: Opacity(
                    opacity: _uploadingPlacePhoto ? 0.4 : 1.0,
                    child: Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: required && photos.isEmpty ? GardenColors.error.withValues(alpha: 0.5) : borderColor),
                      ),
                      child: Icon(
                        Icons.add_photo_alternate_outlined,
                        color: required && photos.isEmpty ? GardenColors.error : GardenColors.primary,
                        size: 28,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
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

}

