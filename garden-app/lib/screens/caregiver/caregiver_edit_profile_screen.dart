import 'dart:convert';
import 'dart:typed_data';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';
import '../../utils/garden_banks.dart';
import '../../services/auth_state.dart';
import '../../widgets/address_section.dart';
import '../../widgets/address_map_picker.dart';

class CaregiverEditProfileScreen extends StatefulWidget {
  const CaregiverEditProfileScreen({super.key});

  @override
  State<CaregiverEditProfileScreen> createState() => _CaregiverEditProfileScreenState();
}

class _CaregiverEditProfileScreenState extends State<CaregiverEditProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  bool _isSaving = false;
  String _caregiverToken = '';
  Uint8List? _newPhotoBytes;
  String? _newPhotoName;

  // Walker photos (PASEO-only caregivers)
  List<String> _walkerPhotos = [];
  bool _uploadingWalkerPhoto = false;
  List<String> _servicesOffered = [];

  // Controladores de texto
  final _bioController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();

  // Dirección detallada
  final _streetCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  final _apartmentCtrl = TextEditingController();
  final _condominioCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  String? _addressZone;
  double? _addressLat;
  double? _addressLng;
  bool _isApartment = false;

  // Datos de cobro
  final _bankAccountController = TextEditingController();
  final _bankHolderController = TextEditingController();
  String _selectedBankName = '';
  String _selectedBankType = 'CUENTA_AHORRO';

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    String token = AuthState.token;
    if (token.isEmpty) {
      // Fallback a token de dev si no hay sesión
      token = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiJjOWViOGU0NS1hZTIwLTQyYTYtOGI5NC0wNmYzYTBiOTE4YjciLCJyb2xlIjoiQ0FSRUdJVkVSIiwiaWQiOiJjOWViOGU0NS1hZTIwLTQyYTYtOGI5NC0wNmYzYTBiOTE4YjciLCJpYXQiOjE3NDI0MjI3MTYsImV4cCI6MTc0NTAxNDcxNn0.8mIu-oA7N_R2xWj4J5_vC_REj78Vp2LMTM7R_g_J8-w';
    }
    setState(() => _caregiverToken = token);
    await _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/caregiver/my-profile'),
        headers: {'Authorization': 'Bearer $_caregiverToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final profile = data['data'] as Map<String, dynamic>;
        setState(() {
          _profile = profile;
          _bioController.text = profile['bio'] as String? ?? '';

          final user = profile['user'] as Map<String, dynamic>?;
          if (user != null) {
            _firstNameController.text = user['firstName'] as String? ?? '';
            _lastNameController.text = user['lastName'] as String? ?? '';
            _phoneController.text = user['phone'] as String? ?? '';
          }

          // Dirección detallada
          _streetCtrl.text = profile['addressStreet'] as String? ?? '';
          _numberCtrl.text = profile['addressNumber'] as String? ?? '';
          _apartmentCtrl.text = profile['addressApartment'] as String? ?? '';
          _condominioCtrl.text = profile['addressCondominio'] as String? ?? '';
          _referenceCtrl.text = profile['addressReference'] as String? ?? '';
          _addressZone = profile['addressZone'] as String?;
          _addressLat = (profile['addressLat'] as num?)?.toDouble();
          _addressLng = (profile['addressLng'] as num?)?.toDouble();
          _isApartment = (_apartmentCtrl.text).isNotEmpty;

          _selectedBankName = profile['bankName'] as String? ?? '';
          _selectedBankType = profile['bankType'] as String? ?? 'CUENTA_AHORRO';
          _bankAccountController.text = profile['bankAccount'] as String? ?? '';
          _walkerPhotos = (profile['walkerPhotos'] as List?)?.cast<String>() ?? [];
          _servicesOffered = (profile['servicesOffered'] as List?)?.cast<String>() ?? [];
          _bankHolderController.text = profile['bankHolder'] as String? ?? '';
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickProfilePhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _newPhotoBytes = bytes;
      _newPhotoName = picked.name.isEmpty ? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg' : picked.name;
    });
  }

  Future<String?> _uploadProfilePhoto() async {
    if (_newPhotoBytes == null) return null;
    try {
      final uri = Uri.parse('$_baseUrl/caregiver/profile/photo');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $_caregiverToken';
      String mimeType = 'image/jpeg';
      if (_newPhotoName?.endsWith('.png') == true) mimeType = 'image/png';
      request.files.add(http.MultipartFile.fromBytes(
        'photo',
        _newPhotoBytes!,
        filename: _newPhotoName ?? 'profile.jpg',
        contentType: MediaType.parse(mimeType),
      ));
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        return data['data']['photoUrl'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('Error uploading photo: $e');
      return null;
    }
  }

  Future<void> _pickAndUploadWalkerPhoto() async {
    if (_walkerPhotos.length >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Máximo 4 fotos permitidas')));
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1200);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => _uploadingWalkerPhoto = true);
    try {
      final uri = Uri.parse('$_baseUrl/caregiver/profile/walker-photo');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $_caregiverToken';
      String mimeType = picked.name.endsWith('.png') ? 'image/png' : 'image/jpeg';
      request.files.add(http.MultipartFile.fromBytes(
        'walkerPhoto', bytes,
        filename: picked.name,
        contentType: MediaType.parse(mimeType),
      ));
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _walkerPhotos.add(data['data']['photoUrl'] as String));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['error']?['message'] ?? 'Error al subir foto'), backgroundColor: GardenColors.error));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: GardenColors.error));
    } finally {
      if (mounted) setState(() => _uploadingWalkerPhoto = false);
    }
  }

  Future<void> _deleteWalkerPhoto(String photoUrl) async {
    try {
      await http.delete(
        Uri.parse('$_baseUrl/caregiver/profile/walker-photo'),
        headers: {'Authorization': 'Bearer $_caregiverToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'photoUrl': photoUrl}),
      );
      setState(() => _walkerPhotos.remove(photoUrl));
    } catch (_) {}
  }

  Future<void> _saveProfile() async {
    // ── Validación de campos obligatorios ──
    final isVerifiedCheck = _profile?['identityVerificationStatus'] == 'VERIFIED';
    if (!isVerifiedCheck) {
      if (_firstNameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El nombre es obligatorio'), backgroundColor: GardenColors.error));
        return;
      }
      if (_lastNameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El apellido es obligatorio'), backgroundColor: GardenColors.error));
        return;
      }
    }
    if (_phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El teléfono es obligatorio'), backgroundColor: GardenColors.error));
      return;
    }

    setState(() => _isSaving = true);
    try {
      // Subir foto primero si hay una nueva
      if (_newPhotoBytes != null) {
        await _uploadProfilePhoto();
      }
      // Luego guardar el resto del perfil
      final addressBody = <String, dynamic>{
        'bio': _bioController.text.trim(),
        'address': [_streetCtrl.text.trim(), _numberCtrl.text.trim()].where((s) => s.isNotEmpty).join(', '),
        if (_addressLat != null) 'addressLat': _addressLat,
        if (_addressLng != null) 'addressLng': _addressLng,
        if (_streetCtrl.text.trim().isNotEmpty) 'addressStreet': _streetCtrl.text.trim(),
        if (_numberCtrl.text.trim().isNotEmpty) 'addressNumber': _numberCtrl.text.trim(),
        if (_isApartment && _apartmentCtrl.text.trim().isNotEmpty) 'addressApartment': _apartmentCtrl.text.trim(),
        if (_isApartment && _condominioCtrl.text.trim().isNotEmpty) 'addressCondominio': _condominioCtrl.text.trim(),
        if (_referenceCtrl.text.trim().isNotEmpty) 'addressReference': _referenceCtrl.text.trim(),
        if (_addressZone != null) 'addressZone': _addressZone,
      };

      final response = await http.patch(
        Uri.parse('$_baseUrl/caregiver/profile'),
        headers: {
          'Authorization': 'Bearer $_caregiverToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(addressBody),
      );

      // Guardar también la info personal y datos de cobro
      await _saveUserInfo();
      await _saveBankInfo();

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Perfil actualizado correctamente'),
            backgroundColor: GardenColors.success,
            duration: Duration(seconds: 2),
          ),
        );
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        Navigator.pop(context, true);
      } else {
        throw Exception(data['error']?['message'] ?? 'Error al guardar');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: GardenColors.error),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveBankInfo() async {
    if (_selectedBankName.isEmpty) return;
    try {
      await http.patch(
        Uri.parse('$_baseUrl/caregiver/bank-info'),
        headers: {'Authorization': 'Bearer $_caregiverToken', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'bankName': _selectedBankName,
          'bankAccount': _bankAccountController.text.trim(),
          'bankHolder': _bankHolderController.text.trim(),
          'bankType': _selectedBankType,
        }),
      );
    } catch (e) {
      debugPrint('Error saving bank info: $e');
    }
  }

  Future<void> _saveUserInfo() async {
    final isVerified = _profile?['identityVerificationStatus'] == 'VERIFIED';
    
    final Map<String, dynamic> body = {
      'phone': _phoneController.text.trim(),
    };

    if (!isVerified) {
      body['firstName'] = _firstNameController.text.trim();
      body['lastName'] = _lastNameController.text.trim();
    }
    await http.patch(
      Uri.parse('$_baseUrl/caregiver/user-info'),
      headers: {
        'Authorization': 'Bearer $_caregiverToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
        final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
        final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
        final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

        final isPaseoOnly = _servicesOffered.length == 1 && _servicesOffered.contains('PASEO');
        final needsWalkerPhotos = isPaseoOnly && _walkerPhotos.isEmpty;

        if (kIsWeb) {
          return _buildWebScaffold(
            context, isDark, bg, surface, textColor, subtextColor, borderColor,
            isPaseoOnly, needsWalkerPhotos,
          );
        }

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: surface,
            elevation: 0,
            title: Text(
              needsWalkerPhotos ? 'Completar perfil' : 'Editar perfil',
              style: TextStyle(color: needsWalkerPhotos ? GardenColors.primary : textColor, fontWeight: FontWeight.bold),
            ),
            iconTheme: IconThemeData(color: textColor),
            actions: [
              if (_isSaving)
                const Center(child: Padding(padding: EdgeInsets.only(right: 16.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: GardenColors.primary))))
              else
                TextButton(
                  onPressed: _saveProfile,
                  child: const Text('Guardar', style: TextStyle(color: GardenColors.primary, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sección 1 - Foto
                      Center(
                        child: Stack(
                          children: [
                            _newPhotoBytes != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(50),
                                  child: Image.memory(_newPhotoBytes!, width: 100, height: 100, fit: BoxFit.cover),
                                )
                              : GardenAvatar(
                                  imageUrl: _profile?['profilePhoto'] as String?,
                                  size: 100,
                                  initials: (_profile?['firstName'] as String? ?? 'C')[0],
                                ),
                            Positioned(
                              bottom: 0, right: 0,
                              child: GestureDetector(
                                onTap: _pickProfilePhoto,
                                child: Container(
                                  width: 32, height: 32,
                                  decoration: const BoxDecoration(
                                    color: GardenColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_newPhotoBytes != null)
                        const Center(
                          child: Text('Nueva foto seleccionada',
                            style: TextStyle(color: GardenColors.success, fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      const Divider(height: 32),

                      // Sección 2 - Información básica
                      Text('Sobre ti', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _bioController,
                        maxLines: 4,
                        style: TextStyle(color: textColor),
                        decoration: _inputDecoration('Cuéntanos sobre tu experiencia cuidando mascotas...', isDark),
                      ),
                      const Divider(height: 32),

                      // Sección 3 - Dirección detallada
                      Text('Ubicación', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(
                        'Tu dirección es usada para mostrar tu zona de servicio y calcular distancias.',
                        style: TextStyle(color: subtextColor, fontSize: 12),
                      ),
                      const SizedBox(height: 14),
                      Theme(
                        data: Theme.of(context).copyWith(
                          inputDecorationTheme: InputDecorationTheme(
                            filled: true,
                            fillColor: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary, width: 2)),
                            hintStyle: TextStyle(color: isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                        child: AddressSection(
                          isDark: isDark,
                          textColor: textColor,
                          subtextColor: subtextColor,
                          borderColor: borderColor,
                          surfaceEl: isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated,
                          streetController: _streetCtrl,
                          numberController: _numberCtrl,
                          apartmentController: _apartmentCtrl,
                          condominioController: _condominioCtrl,
                          referenceController: _referenceCtrl,
                          selectedZone: _addressZone,
                          onZoneChanged: (val) => setState(() => _addressZone = val),
                          addressLat: _addressLat,
                          addressLng: _addressLng,
                          isApartment: _isApartment,
                          purposeText: 'Tu dirección define en qué zona ofreces servicios. Solo se muestra la zona (no la calle exacta) a los dueños.',
                          onMapResult: (result) => setState(() {
                            _addressLat = result.lat;
                            _addressLng = result.lng;
                          }),
                          onApartmentToggle: (val) => setState(() => _isApartment = val),
                        ),
                      ),
                      const Divider(height: 32),

                      _buildPersonalInfoSection(textColor, subtextColor, isDark),
                      const Divider(height: 32),

                      // Sección — Fotos de paseador (solo PASEO-only)
                      if (isPaseoOnly) ...[
                        _buildWalkerPhotosSection(textColor, subtextColor, borderColor, isDark, needsWalkerPhotos),
                        const Divider(height: 32),
                      ],

                      // Sección — Datos de cobro
                      _buildBankSection(textColor, subtextColor, surface, borderColor, isDark),
                      const Divider(height: 32),

                      // Sección — Estado
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Estado del perfil', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                          _statusBadge(_profile?['status'] ?? ''),
                        ],
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
        );
      },
    );
  }

  // ── WEB LAYOUT ──────────────────────────────────────────────────────────────
  Widget _buildWebScaffold(
    BuildContext context,
    bool isDark,
    Color bg,
    Color surface,
    Color textColor,
    Color subtextColor,
    Color borderColor,
    bool isPaseoOnly,
    bool needsWalkerPhotos,
  ) {
    final firstName = _profile?['user']?['firstName'] as String? ?? _profile?['firstName'] as String? ?? 'Cuidador';
    final lastName  = _profile?['user']?['lastName']  as String? ?? _profile?['lastName']  as String? ?? '';

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          // ── Top bar ────────────────────────────────────────────────────────
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: surface,
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back_rounded, color: textColor, size: 20),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Volver',
                ),
                const SizedBox(width: 8),
                Text(
                  needsWalkerPhotos ? 'Completar perfil' : 'Editar perfil',
                  style: TextStyle(
                    color: needsWalkerPhotos ? GardenColors.primary : textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (_isSaving)
                  const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: GardenColors.primary),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _saveProfile,
                    icon: const Icon(Icons.save_rounded, size: 15),
                    label: const Text('Guardar cambios', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GardenColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
              ],
            ),
          ),

          // ── Body ───────────────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 940),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Profile header card ────────────────────────
                            _buildWebProfileHeaderCard(
                              surface, borderColor, textColor, subtextColor, isDark,
                              firstName, lastName,
                            ),
                            const SizedBox(height: 20),

                            // ── Two-column main content ────────────────────
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // LEFT — bio + address + walker photos
                                  Expanded(
                                    flex: 52,
                                    child: Column(
                                      children: [
                                        _webCard(
                                          surface, borderColor, textColor,
                                          title: 'Sobre ti',
                                          icon: Icons.edit_note_rounded,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('Descripción', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                                              const SizedBox(height: 8),
                                              TextField(
                                                controller: _bioController,
                                                maxLines: 4,
                                                style: TextStyle(color: textColor, fontSize: 13),
                                                decoration: _inputDecoration('Cuéntanos sobre tu experiencia cuidando mascotas...', isDark),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        _webCard(
                                          surface, borderColor, textColor,
                                          title: 'Ubicación',
                                          icon: Icons.location_on_outlined,
                                          child: Theme(
                                            data: Theme.of(context).copyWith(
                                              inputDecorationTheme: InputDecorationTheme(
                                                filled: true,
                                                fillColor: isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated,
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder)),
                                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder)),
                                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary, width: 2)),
                                                hintStyle: TextStyle(color: isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              ),
                                            ),
                                            child: AddressSection(
                                              isDark: isDark,
                                              textColor: textColor,
                                              subtextColor: subtextColor,
                                              borderColor: borderColor,
                                              surfaceEl: isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated,
                                              streetController: _streetCtrl,
                                              numberController: _numberCtrl,
                                              apartmentController: _apartmentCtrl,
                                              condominioController: _condominioCtrl,
                                              referenceController: _referenceCtrl,
                                              selectedZone: _addressZone,
                                              onZoneChanged: (val) => setState(() => _addressZone = val),
                                              addressLat: _addressLat,
                                              addressLng: _addressLng,
                                              isApartment: _isApartment,
                                              purposeText: 'Tu dirección define en qué zona ofreces servicios. Solo se muestra la zona (no la calle exacta) a los dueños.',
                                              onMapResult: (result) => setState(() {
                                                _addressLat = result.lat;
                                                _addressLng = result.lng;
                                              }),
                                              onApartmentToggle: (val) => setState(() => _isApartment = val),
                                            ),
                                          ),
                                        ),
                                        if (isPaseoOnly) ...[
                                          const SizedBox(height: 16),
                                          _webCard(
                                            surface, borderColor, textColor,
                                            title: 'Fotos como cuidador',
                                            icon: Icons.photo_library_rounded,
                                            badge: needsWalkerPhotos ? 'Incompleto' : null,
                                            badgeColor: GardenColors.warning,
                                            child: _buildWalkerPhotosSection(
                                              textColor, subtextColor, borderColor, isDark, needsWalkerPhotos,
                                              showHeader: false,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),

                                  // RIGHT — personal info + bank + status
                                  Expanded(
                                    flex: 48,
                                    child: Column(
                                      children: [
                                        _webCard(
                                          surface, borderColor, textColor,
                                          title: 'Información personal',
                                          icon: Icons.person_outline_rounded,
                                          child: _buildPersonalInfoSection(textColor, subtextColor, isDark),
                                        ),
                                        const SizedBox(height: 16),
                                        _webCard(
                                          surface, borderColor, textColor,
                                          title: 'Datos de cobro',
                                          icon: Icons.account_balance_rounded,
                                          child: _buildBankSection(textColor, subtextColor, surface, borderColor, isDark, showHeader: false),
                                        ),
                                        const SizedBox(height: 16),
                                        _webCard(
                                          surface, borderColor, textColor,
                                          title: 'Estado del perfil',
                                          icon: Icons.verified_outlined,
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text('Estado actual', style: TextStyle(color: subtextColor, fontSize: 13)),
                                              _statusBadge(_profile?['status'] ?? ''),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),
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

  Widget _buildWebProfileHeaderCard(
    Color surface, Color borderColor, Color textColor, Color subtextColor,
    bool isDark, String firstName, String lastName,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          // Avatar with camera overlay
          Stack(
            children: [
              _newPhotoBytes != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(36),
                      child: Image.memory(_newPhotoBytes!, width: 72, height: 72, fit: BoxFit.cover),
                    )
                  : GardenAvatar(
                      imageUrl: _profile?['profilePhoto'] as String?,
                      size: 72,
                      initials: firstName.isNotEmpty ? firstName[0] : 'C',
                    ),
              Positioned(
                bottom: 0, right: 0,
                child: GestureDetector(
                  onTap: _pickProfilePhoto,
                  child: Container(
                    width: 24, height: 24,
                    decoration: const BoxDecoration(color: GardenColors.primary, shape: BoxShape.circle),
                    child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 13),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$firstName $lastName'.trim(),
                  style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                if (_newPhotoBytes != null)
                  const Text(
                    'Nueva foto seleccionada — se guardará al presionar "Guardar cambios"',
                    style: TextStyle(color: GardenColors.success, fontSize: 11),
                  )
                else
                  Text(
                    'Haz clic en la cámara para cambiar tu foto de perfil',
                    style: TextStyle(color: subtextColor, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _webCard(
    Color surface, Color borderColor, Color textColor, {
    required String title,
    required IconData icon,
    required Widget child,
    String? badge,
    Color? badgeColor,
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
              Icon(icon, size: 15, color: GardenColors.primary),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w700)),
              if (badge != null) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (badgeColor ?? GardenColors.warning).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(color: badgeColor ?? GardenColors.warning, fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
  // ── END WEB LAYOUT ─────────────────────────────────────────────────────────

  Widget _buildWalkerPhotosSection(Color textColor, Color subtextColor, Color borderColor, bool isDark, bool needsCompletion, {bool showHeader = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader) ...[
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Fotos tuyas como cuidador', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text('Fotos contigo con mascotas o en actividades de paseo (mín. 2)', style: TextStyle(color: subtextColor, fontSize: 12)),
                  ],
                ),
              ),
              if (needsCompletion)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: GardenColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: const Text('Incompleto', style: TextStyle(color: GardenColors.warning, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
          itemCount: _walkerPhotos.length < 4 ? _walkerPhotos.length + 1 : 4,
          itemBuilder: (context, index) {
            if (index == _walkerPhotos.length) {
              return GestureDetector(
                onTap: _uploadingWalkerPhoto ? null : _pickAndUploadWalkerPhoto,
                child: Container(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: borderColor)),
                  child: _uploadingWalkerPhoto && index == _walkerPhotos.length
                      ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: GardenColors.primary)))
                      : const Icon(Icons.add_a_photo_outlined, color: GardenColors.primary),
                ),
              );
            }
            return Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(_walkerPhotos[index], fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                ),
                Positioned(
                  right: 4, top: 4,
                  child: GestureDetector(
                    onTap: () => _deleteWalkerPhoto(_walkerPhotos[index]),
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
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint, bool isDark) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary),
      filled: true,
      fillColor: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: GardenColors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  Widget _buildBankSection(Color textColor, Color subtextColor, Color surface, Color borderColor, bool isDark, {bool showHeader = true}) {
    final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    final isWallet = GardenBanks.isDigitalWallet(_selectedBankName);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader) ...[
          Row(
            children: [
              Text('Datos de cobro', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: GardenColors.secondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, color: GardenColors.secondary, size: 12),
                    SizedBox(width: 4),
                    Text('Solo visible para ti', style: TextStyle(color: GardenColors.secondary, fontSize: 10, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Cuenta donde recibirás tus pagos. No es visible para los dueños.', style: TextStyle(color: subtextColor, fontSize: 12)),
          const SizedBox(height: 16),
        ] else ...[
          // On web the header is shown in the _webCard title; show only the subtitle
          Text('Cuenta donde recibirás tus pagos.', style: TextStyle(color: subtextColor, fontSize: 12)),
          const SizedBox(height: 12),
        ],

        // Selector banco/billetera
        GestureDetector(
          onTap: () => _showBankPickerSheet(context, isDark),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: surfaceEl,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _selectedBankName.isEmpty ? borderColor : GardenColors.primary.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(
                  _selectedBankName.isEmpty ? Icons.account_balance_rounded : (isWallet ? Icons.account_balance_wallet_rounded : Icons.account_balance_rounded),
                  color: _selectedBankName.isEmpty ? subtextColor : GardenColors.primary, size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _selectedBankName.isEmpty
                      ? Text('Selecciona banco o billetera', style: TextStyle(color: subtextColor, fontSize: 14))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_selectedBankName, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14)),
                            Text(GardenBanks.typeLabels[_selectedBankType] ?? _selectedBankType, style: TextStyle(color: subtextColor, fontSize: 11)),
                          ],
                        ),
                ),
                Icon(Icons.keyboard_arrow_down_rounded, color: subtextColor, size: 20),
              ],
            ),
          ),
        ),

        if (_selectedBankName.isNotEmpty) ...[
          const SizedBox(height: 10),
          // Tipo de cuenta (solo bancos tradicionales)
          if (!isWallet)
            Row(
              children: [
                _accountTypeChip('Cuenta de ahorro', 'CUENTA_AHORRO', textColor, subtextColor),
                const SizedBox(width: 10),
                _accountTypeChip('Cuenta corriente', 'CUENTA_CORRIENTE', textColor, subtextColor),
              ],
            ),
          if (!isWallet) const SizedBox(height: 10),
          TextField(
            controller: _bankAccountController,
            keyboardType: TextInputType.number,
            style: TextStyle(color: textColor),
            decoration: _inputDecoration(isWallet ? 'Número de teléfono (ej: 70012345)' : 'Número de cuenta bancaria', isDark),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _bankHolderController,
            style: TextStyle(color: textColor),
            decoration: _inputDecoration('Nombre completo del titular', isDark),
          ),
        ],
      ],
    );
  }

  Widget _accountTypeChip(String label, String value, Color textColor, Color subtextColor) {
    final isSelected = _selectedBankType == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedBankType = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? GardenColors.primary.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? GardenColors.primary : subtextColor.withValues(alpha: 0.3)),
          ),
          child: Center(
            child: Text(label, style: TextStyle(
              color: isSelected ? GardenColors.primary : subtextColor,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 12,
            )),
          ),
        ),
      ),
    );
  }

  void _showBankPickerSheet(BuildContext parentCtx, bool isDark) {
    final searchController = TextEditingController();

    showModalBottomSheet(
      context: parentCtx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setPickerSheet) {
          final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
          final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
          final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
          final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;

          final query = searchController.text.toLowerCase();
          final filtered = query.isEmpty
              ? GardenBanks.all
              : GardenBanks.all.where((b) => b['name']!.toLowerCase().contains(query)).toList();

          final items = <Widget>[];
          for (final category in ['Bancos', 'Billeteras digitales']) {
            final catBanks = filtered.where((b) => b['category'] == category).toList();
            if (catBanks.isEmpty) continue;
            items.add(Padding(
              padding: const EdgeInsets.only(left: 4, top: 12, bottom: 6),
              child: Text(category.toUpperCase(), style: TextStyle(color: subtextColor, fontWeight: FontWeight.w700, fontSize: 10, letterSpacing: 1)),
            ));
            for (final bank in catBanks) {
              final isSelected = bank['name'] == _selectedBankName;
              items.add(Material(
                color: Colors.transparent,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: isSelected ? GardenColors.primary.withValues(alpha: 0.15) : GardenColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      category == 'Bancos' ? Icons.account_balance_rounded : Icons.account_balance_wallet_rounded,
                      color: isSelected ? GardenColors.primary : subtextColor, size: 18,
                    ),
                  ),
                  title: Text(bank['name']!, style: TextStyle(
                    color: isSelected ? GardenColors.primary : textColor,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 14,
                  )),
                  subtitle: Text(GardenBanks.typeLabels[bank['type']] ?? '', style: TextStyle(color: subtextColor, fontSize: 11)),
                  trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: GardenColors.primary, size: 20) : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _selectedBankName = bank['name']!;
                      _selectedBankType = bank['type']!;
                    });
                  },
                ),
              ));
            }
          }

          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.78,
            child: GlassBox(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Text('Banco o billetera', style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 14),
                TextField(
                  controller: searchController,
                  style: TextStyle(color: textColor),
                  onChanged: (_) => setPickerSheet(() {}),
                  decoration: InputDecoration(
                    hintText: 'Buscar...',
                    hintStyle: TextStyle(color: subtextColor),
                    prefixIcon: Icon(Icons.search_rounded, color: subtextColor, size: 20),
                    filled: true, fillColor: surfaceEl,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(child: ListView(padding: EdgeInsets.zero, children: items)),
              ],
            ),
          ));
        },
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color color;
    String label;
    switch (status) {
      case 'APPROVED': color = GardenColors.success; label = 'Aprobado'; break;
      case 'PENDING_REVIEW': color = GardenColors.warning; label = 'Pendiente'; break;
      case 'REJECTED': color = GardenColors.error; label = 'Rechazado'; break;
      case 'DRAFT': color = GardenColors.textHint; label = 'Borrador'; break;
      case 'SUSPENDED': color = GardenColors.error; label = 'Suspendido'; break;
      default: color = GardenColors.textHint; label = 'Pendiente';
    }
    return GardenBadge(text: label, color: color, fontSize: 12);
  }

  Widget _buildPersonalInfoSection(Color textColor, Color subtextColor, bool isDark) {
    bool isVerified = _profile?['identityVerificationStatus'] == 'VERIFIED';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Información personal',
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            if (isVerified)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: GardenColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.verified_user, color: GardenColors.success, size: 14),
                    SizedBox(width: 4),
                    Text('Verificada y bloqueada',
                      style: TextStyle(color: GardenColors.success, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
          ],
        ),
        if (isVerified) ...[
          const SizedBox(height: 8),
          Text(
            'Tu identidad ha sido verificada. Estos datos ya no pueden ser modificados para garantizar la seguridad de la plataforma.',
            style: TextStyle(color: subtextColor, fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                enabled: !isVerified,
                controller: _firstNameController,
                style: TextStyle(color: isVerified ? subtextColor : textColor),
                decoration: _inputDecoration('Nombre', isDark),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                enabled: !isVerified,
                controller: _lastNameController,
                style: TextStyle(color: isVerified ? subtextColor : textColor),
                decoration: _inputDecoration('Apellido', isDark),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          enabled: true,
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          style: TextStyle(color: textColor),
          decoration: _inputDecoration('Teléfono (ej: 70012345)', isDark),
        ),
      ],
    );
  }
}
