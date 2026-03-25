import 'dart:convert';
import 'dart:typed_data';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';

class CaregiverProfileDataScreen extends StatefulWidget {
  const CaregiverProfileDataScreen({super.key});

  @override
  State<CaregiverProfileDataScreen> createState() => _CaregiverProfileDataScreenState();
}

class _CaregiverProfileDataScreenState extends State<CaregiverProfileDataScreen> {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _user;
  bool _isLoading = true;
  bool _isSaving = false;
  String _caregiverToken = '';
  int _completionPercentage = 0;

  // Controllers
  final _bioController = TextEditingController();
  final _bioDetailController = TextEditingController();
  final _addressController = TextEditingController();
  final _pricePerDayController = TextEditingController();
  final _pricePerWalk30Controller = TextEditingController();
  final _pricePerWalk60Controller = TextEditingController();
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
  List<String> _sizesAccepted = [];

  // Selecciones
  String _selectedZone = 'EQUIPETROL';
  List<String> _selectedServices = [];
  List<String> _selectedHomeTypes = [];
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

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api');

  @override
  void initState() {
    super.initState();
    _loadData();
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
        final profile = data['data'];
        final user = profile['user'];
        final details = profile['serviceDetails'] ?? {};
        final faq = details['faq'] ?? {};
        final availability = details['availability'] ?? {};
        final slots = availability['slots'] ?? {};

        setState(() {
          _profile = profile;
          _user = user;
          _bioController.text = profile['bio'] ?? '';
          _bioDetailController.text = profile['bioDetail'] ?? '';
          _addressController.text = profile['address'] ?? '';
          _pricePerDayController.text = (profile['pricePerDay'] ?? 0).toString();
          _pricePerWalk30Controller.text = (profile['pricePerWalk30'] ?? 0).toString();
          _pricePerWalk60Controller.text = (profile['pricePerWalk60'] ?? 0).toString();
          _includesController.text = faq['includes'] ?? '';
          _emergencyController.text = faq['emergency'] ?? '';
          _requirementsController.text = faq['requirements'] ?? '';
          _selectedZone = profile['zone'] ?? 'EQUIPETROL';
          _selectedServices = List<String>.from(profile['servicesOffered'] ?? []);
          _selectedHomeTypes = List<String>.from(profile['spaceType'] ?? []);
          _hasYard = profile['hasYard'] ?? false;
          _allowsLargePets = details['allowsLargePets'] ?? false;
          _allowsMultiplePets = details['allowsMultiplePets'] ?? false;
          _maxPets = details['maxPets'] ?? 1;
          _acceptedPetTypes = List<String>.from(details['acceptedPetTypes'] ?? []);
          _acceptedSizes = List<String>.from(details['acceptedSizes'] ?? []);
          _weekdays = availability['weekdays'] ?? true;
          _weekends = availability['weekends'] ?? false;
          _holidays = availability['holidays'] ?? false;
          _morningSlot = slots['morning'] ?? true;
          _afternoonSlot = slots['afternoon'] ?? true;
          _nightSlot = slots['night'] ?? false;
          _photos = List<String>.from(profile['photos'] ?? []);

          // Nuevos campos simplificados
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
          _sizesAccepted = (profile['sizesAccepted'] as List? ?? []).cast<String>();
        });
        _computeCompletion();
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
      if (_pricePerWalk30Controller.text != '0') score++;
    }

    if (_includesController.text.isNotEmpty) score++;
    if (_experienceYearsController.text.isNotEmpty && _experienceDescController.text.length >= 20) score++;
    
    total = 11;
    setState(() => _completionPercentage = ((score / total) * 100).round());
  }

  Future<void> _saveAllData() async {
    setState(() => _isSaving = true);
    try {
      // Mapping CASA/APARTAMENTO to Enum if only one selected
      String? hType;
      if (_selectedHomeTypes.contains('HOUSE')) {
        hType = 'HOUSE';
      } else if (_selectedHomeTypes.contains('APARTMENT')) hType = 'APARTMENT';

      final body = {
        'bio': _bioController.text.trim(),
        'bioDetail': _bioDetailController.text.trim(),
        'zone': _selectedZone,
        'servicesOffered': _selectedServices,
        'pricePerDay': (double.tryParse(_pricePerDayController.text) ?? 0).round(),
        'pricePerWalk30': (double.tryParse(_pricePerWalk30Controller.text) ?? 0).round(),
        'pricePerWalk60': (double.tryParse(_pricePerWalk60Controller.text) ?? 0).round(),
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
        'sizesAccepted': _sizesAccepted,
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
          },
        },
        'experienceYears': int.tryParse(_experienceYearsController.text) ?? 0,
        'experienceDescription': _experienceDescController.text.trim(),
        'whyCaregiver': _whyCaregiverController.text.trim(),
        'whatDiffers': _whatDiffersController.text.trim(),
        'handleAnxious': _handleAnxiousController.text.trim(),
        'emergencyResponse': _emergencyResponseController.text.trim(),
        'acceptAggressive': _acceptAggressive ?? false,
        'acceptPuppies': _acceptPuppies ?? false,
        'acceptSeniors': _acceptSeniors ?? false,
        'sizesAccepted': _sizesAccepted,
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cambios guardados correctamente'), backgroundColor: GardenColors.success),
        );
        _computeCompletion();
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Máximo $maxPhotos fotos permitidas')));
      return;
    }

    final input = html.FileUploadInputElement()..accept = 'image/*';
    input.click();
    await input.onChange.first;
    if (input.files == null || input.files!.isEmpty) return;

    final file = input.files!.first;
    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    await reader.onLoad.first;
    final bytes = Uint8List.fromList(reader.result as List<int>);

    setState(() => _isSaving = true);
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/caregiver/profile/service-photo'));
      request.headers['Authorization'] = 'Bearer $_caregiverToken';
      request.files.add(http.MultipartFile.fromBytes(
        'servicePhoto',
        bytes,
        filename: file.name,
        contentType: MediaType('image', 'jpeg'),
      ));

      final response = await request.send();
      final respBody = await response.stream.bytesToString();
      final data = jsonDecode(respBody);

      if (data['success'] == true) {
        setState(() => _photos.add(data['data']['photoUrl']));
        _computeCompletion();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al subir: $e')));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _deletePhoto(int index) async {
    setState(() {
      _photos.removeAt(index);
      _computeCompletion();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
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

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil profesional')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Sección 1 — Banner
            _buildCompletionBanner(),
            const SizedBox(height: 32),

            // Sección 2 — Sobre ti
            _sectionTitle('Sobre ti como cuidador', textColor),
            GardenInput(
              hint: 'Resumen corto (bio)',
              controller: _bioController,
              maxLength: 500,
              maxLines: 2,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            GardenInput(
              hint: 'Biografía detallada: experiencia, método de cuidado, etc.',
              controller: _bioDetailController,
              maxLines: 6,
              maxLength: 300,
              onChanged: (_) => setState(() {}),
            ),
            const Divider(height: 48),

            const Divider(height: 48),

            if (_selectedServices.contains('HOSPEDAJE')) ...[
              // Sección 3 — Tu espacio
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
            _sectionTitle('Servicios y precios', textColor),
            _buildServiceChips(surface, borderColor),
            if (_selectedServices.contains('PASEO')) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: GardenInput(hint: 'Precio 30 min (Bs)', controller: _pricePerWalk30Controller, keyboardType: TextInputType.number)),
                  const SizedBox(width: 12),
                  Expanded(child: GardenInput(hint: 'Precio 60 min (Bs)', controller: _pricePerWalk60Controller, keyboardType: TextInputType.number)),
                ],
              ),
            ],
            if (_selectedServices.contains('HOSPEDAJE')) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: GardenInput(hint: 'Precio por noche (Bs)', controller: _pricePerDayController, keyboardType: TextInputType.number)),
                  const SizedBox(width: 12),
                  const Expanded(child: SizedBox()), // Placeholder
                ],
              ),
            ],
            const SizedBox(height: 16),
            _buildZoneDropdown(surface, borderColor, textColor),
            const Divider(height: 48),

            // Sección 5 — Disponibilidad
            _sectionTitle('Disponibilidad general', textColor),
            _buildSwitchTile('Lunes a Viernes', _weekdays, (v) => setState(() => _weekdays = v)),
            _buildSwitchTile('Sábados y Domingos', _weekends, (v) => setState(() => _weekends = v)),
            _buildSwitchTile('Feriados', _holidays, (v) => setState(() => _holidays = v)),
            const SizedBox(height: 16),
            Row(
              children: [
                _slotChip('Mañana', _morningSlot, (v) => setState(() => _morningSlot = v), surface, borderColor),
                const SizedBox(width: 8),
                _slotChip('Tarde', _afternoonSlot, (v) => setState(() => _afternoonSlot = v), surface, borderColor),
                const SizedBox(width: 8),
                _slotChip('Noche', _nightSlot, (v) => setState(() => _nightSlot = v), surface, borderColor),
              ],
            ),
            const Divider(height: 48),

            // Sección 6 — Tipos de mascotas
            _sectionTitle('Mascotas que aceptas', textColor),
            Wrap(
              spacing: 8,
              children: _petTypes.map((t) => _filterChip(t, _petTypeLabels[t]!, _acceptedPetTypes, surface, borderColor)).toList(),
            ),
            const Divider(height: 48),

            // Sección 7 — Tamaños
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

            // Sección 8 — Fotos
            _sectionTitle('Fotos de tu servicio', textColor),
            _buildPhotoGrid(borderColor),
            const SizedBox(height: 8),
            if (_selectedServices.contains('HOSPEDAJE')) 
              const Text('Requerido: 4 a 6 fotos de tu espacio y mascotas', style: TextStyle(color: GardenColors.primary, fontSize: 12, fontWeight: FontWeight.bold))
            else
              const Text('Requerido: Al menos 2 fotos para el servicio de paseo', style: TextStyle(color: GardenColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
            const Divider(height: 48),

            // Sección 9 — FAQ
            _sectionTitle('Preguntas frecuentes', textColor),
            GardenInput(hint: '¿Qué incluye tu servicio?', controller: _includesController, maxLines: 2),
            const SizedBox(height: 12),
            const SizedBox(height: 12),
            GardenInput(hint: '¿Qué necesitas del dueño antes del servicio?', controller: _requirementsController, maxLines: 2),

            const Divider(height: 48),

            // Sección EXTRA — Experiencia detallada
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
            _sectionTitle('Políticas de mascotas', textColor),
            _acceptSwitch('¿Aceptas mascotas agresivas?', _acceptAggressive, (val) => setState(() => _acceptAggressive = val), textColor, subtextColor, surface, borderColor),
            const SizedBox(height: 8),
            _acceptSwitch('¿Aceptas cachorros?', _acceptPuppies, (val) => setState(() => _acceptPuppies = val), textColor, subtextColor, surface, borderColor),
            const SizedBox(height: 8),
            _acceptSwitch('¿Aceptas mascotas mayores?', _acceptSeniors, (val) => setState(() => _acceptSeniors = val), textColor, subtextColor, surface, borderColor),

            const Divider(height: 48),

            // Sección EXTRA — Situaciones especiales
            _sectionTitle('Situaciones especiales', textColor),
            _sectionField('¿Cómo manejas mascotas ansiosas?', _handleAnxiousController,
              'Describe tu método para mascotas con ansiedad o estrés', maxLines: 3),
            const SizedBox(height: 16),
            _sectionField('¿Cómo respondes ante emergencias?', _emergencyResponseController,
              'Protocolo ante una situación de emergencia veterinaria', maxLines: 3),

            const Divider(height: 48),

            const SizedBox(height: 20),
            GardenButton(
              label: _isSaving ? 'Guardando...' : 'Guardar cambios',
              loading: _isSaving,
              icon: Icons.check_circle_outline,
              onPressed: _saveAllData,
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Future<void> _submitProfile() async {
    // Primero guardar cambios
    await _saveAllData();
    
    setState(() => _isSaving = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/caregiver/submit'),
        headers: {
          'Authorization': 'Bearer $_caregiverToken',
          'Content-Type': 'application/json',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        await _loadData();
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: themeNotifier.isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.elasticOut,
                    builder: (_, value, __) => Transform.scale(
                      scale: value,
                      child: Container(
                        width: 80, height: 80,
                        decoration: BoxDecoration(
                          color: GardenColors.success.withOpacity(0.1),
                          shape: BoxShape.circle,
                          border: Border.all(color: GardenColors.success, width: 2),
                        ),
                        child: const Icon(Icons.check_rounded, color: GardenColors.success, size: 44),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('¡Perfil aprobado!',
                    style: TextStyle(
                      color: themeNotifier.isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary,
                      fontSize: 22, fontWeight: FontWeight.w800,
                    )),
                  const SizedBox(height: 8),
                  Text(
                    'Ya apareces en el marketplace. Los dueños de mascotas pueden encontrarte y reservar contigo.',
                    style: TextStyle(color: themeNotifier.isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary, fontSize: 14, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  GardenButton(
                    label: 'Ver mi perfil público',
                    icon: Icons.visibility_outlined,
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.push('/caregiver/${_profile!['id']}');
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        final errorMsg = data['error']?['message'] ?? 'Error al enviar';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: GardenColors.error, duration: const Duration(seconds: 5)),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: GardenColors.error),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
              ? [GardenColors.success, const Color(0xFF1A9954)]
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
              backgroundColor: Colors.white.withOpacity(0.3),
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
      children: ['PASEO', 'HOSPEDAJE'].map((s) {
        final label = s == 'PASEO' ? '🦮 Paseo' : '🏠 Hospedaje';
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
      selectedColor: GardenColors.primary.withOpacity(0.2),
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
            color: value ? GardenColors.primary.withOpacity(0.1) : Colors.transparent,
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
        return Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                image: DecorationImage(image: NetworkImage(_photos[index]), fit: BoxFit.cover),
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
}
