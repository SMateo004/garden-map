import 'dart:convert';
import 'dart:typed_data';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../widgets/ai_write_assist.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/pin_gate.dart';
import '../../utils/garden_banks.dart';
import '../../services/auth_state.dart';
import '../../widgets/address_section.dart';
import '../../services/cities_service.dart';
import '../../widgets/garden_loading_indicator.dart';
import '../../widgets/phone_change_flow.dart';
import '../../design/garden_icons.dart';
import '../../design/garden_profile.dart';
import '../../utils/person_validators.dart';
import '../../design/garden_depth.dart';

class CaregiverEditProfileScreen extends StatefulWidget {
  const CaregiverEditProfileScreen({super.key});

  @override
  State<CaregiverEditProfileScreen> createState() => _CaregiverEditProfileScreenState();
}

class _CaregiverEditProfileScreenState extends State<CaregiverEditProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;
  String _caregiverToken = '';
  Uint8List? _newPhotoBytes;
  String? _newPhotoName;

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
  String? _gardenCityId;
  double? _addressLat;
  double? _addressLng;
  bool _isApartment = false;

  // Datos de cobro
  final _bankAccountController = TextEditingController();
  final _bankHolderController = TextEditingController();
  String _selectedBankName = '';
  String _selectedBankType = 'CUENTA_AHORRO';
  /// Datos de cobro tal como llegaron del servidor: solo se reenvían (y se
  /// pide el PIN) si el cuidador los cambió.
  String _savedBankSnapshot = '';
  String get _bankSnapshot => [
        _selectedBankName,
        _selectedBankType,
        _bankAccountController.text.trim(),
        _bankHolderController.text.trim(),
      ].join('|');

  // Modalidad de cobro (transferencia bancaria vs QR de transferencia) y QR de
  // cobro propio — mismo dato/endpoints que en la billetera (`/api/wallet`,
  // `/api/wallet/withdrawal-method`, `/api/wallet/withdrawal-qr`). Vive en
  // `User`, no en `CaregiverProfile`, por eso se carga aparte de `/caregiver/my-profile`.
  String _withdrawalMethod = 'BANK_TRANSFER';
  Map<String, dynamic>? _qrInfo;
  bool _uploadingQr = false;
  bool _switchingMethod = false;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  @override
  void initState() {
    super.initState();
    for (final c in [_bioController, _firstNameController, _lastNameController, _phoneController,
        _streetCtrl, _bankAccountController, _bankHolderController]) {
      c.addListener(_onFieldChanged);
    }
    _initData();
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  /// Lo que le falta al perfil, en el orden de la pantalla (mismo criterio
  /// que el registro: descripción de 50+, celular boliviano, dirección con
  /// mapa y datos de cobro válidos para la modalidad elegida).
  List<String> _missing() {
    final m = <String>[];
    final hasPhoto = _newPhotoBytes != null || ((_profile?['profilePhoto'] as String?)?.trim().isNotEmpty ?? false);
    if (!hasPhoto) m.add('Foto de perfil');
    if (_bioController.text.trim().length < 50) m.add('Descripción (50+ caracteres)');
    if (_firstNameController.text.trim().isEmpty) m.add('Nombre');
    if (_lastNameController.text.trim().isEmpty) m.add('Apellido');
    if (PersonValidators.boPhone(_phoneController.text) != null) m.add('Teléfono');
    if (_streetCtrl.text.trim().isEmpty) m.add('Calle');
    if (_addressZone == null) m.add('Zona');
    if (_addressLat == null || _addressLng == null) m.add('Ubicación en el mapa');
    final payoutOk = _withdrawalMethod == 'QR_TRANSFER'
        ? _qrInfo != null
        : _selectedBankName.isNotEmpty &&
            GardenBanks.validateAccount(_selectedBankType, _bankAccountController.text) == null &&
            GardenBanks.validateHolder(_bankHolderController.text) == null;
    if (!payoutOk) m.add('Datos de cobro');
    return m;
  }

  static const _kSobreTi = {'Foto de perfil', 'Descripción (50+ caracteres)'};
  static const _kPersonal = {'Nombre', 'Apellido', 'Teléfono'};
  static const _kUbicacion = {'Calle', 'Zona', 'Ubicación en el mapa'};
  static const _kCobro = {'Datos de cobro'};
  static const _kTotal = 9;

  static String _statusLabel(String? s) => switch (s) {
        'APPROVED' => 'Perfil aprobado',
        'PENDING_REVIEW' => 'En revisión',
        'REJECTED' => 'Rechazado: revisa lo que falta',
        'SUSPENDED' => 'Suspendido',
        'DRAFT' => 'Borrador',
        _ => 'Pendiente',
      };

  /// Foto editable (en modo edición) para el encabezado.
  Widget _editableAvatar(double size) {
    final firstName = _profile?['user']?['firstName'] as String? ?? _profile?['firstName'] as String? ?? 'C';
    return Stack(
      children: [
        _newPhotoBytes != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(size / 2),
                child: Image.memory(_newPhotoBytes!, width: size, height: size, fit: BoxFit.cover),
              )
            : GardenAvatar(
                imageUrl: _profile?['profilePhoto'] as String?,
                size: size,
                initials: firstName.isNotEmpty ? firstName[0] : 'C',
              ),
        if (_isEditing)
          Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
              onTap: _pickProfilePhoto,
              child: const GardenClay(size: 28, color: GardenColors.primary, interactive: false, child: GardenIcon(GIcon.foto, size: GIconSize.xs, color: Colors.white)),
            ),
          ),
      ],
    );
  }

  Widget _completionHeader() {
    final missing = _missing();
    final first = _firstNameController.text.trim();
    final last = _lastNameController.text.trim();
    return GardenProfileCompletion(
      avatar: _editableAvatar(76),
      name: '$first $last'.trim(),
      subtitle: _newPhotoBytes != null
          ? 'Foto nueva: se guarda al tocar Guardar cambios'
          : _statusLabel(_profile?['status'] as String?),
      done: _kTotal - missing.length,
      total: _kTotal,
      missing: missing,
    );
  }

  Future<void> _initData() async {
    final token = AuthState.token;
    // Antes: sin sesión se usaba un token de desarrollo escrito en el código
    // (de un usuario concreto). Sin sesión no hay nada que mostrar.
    if (token.isEmpty) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    setState(() => _caregiverToken = token);
    await Future.wait([_loadProfile(), _loadWithdrawalInfo()]);
  }

  /// Carga modalidad de cobro (BANK_TRANSFER/QR_TRANSFER) y el QR de cobro
  /// vigente desde `/api/wallet` — el mismo endpoint que usa la billetera, ya
  /// que ambos datos viven en `User`, no en `CaregiverProfile`.
  Future<void> _loadWithdrawalInfo() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/wallet'),
        headers: {'Authorization': 'Bearer $_caregiverToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true && mounted) {
        final walletData = data['data'] as Map<String, dynamic>;
        setState(() {
          _withdrawalMethod = walletData['withdrawalMethod'] as String? ?? 'BANK_TRANSFER';
          _qrInfo = walletData['qrInfo'] as Map<String, dynamic>?;
        });
      }
    } catch (e) {
      debugPrint('Error loading withdrawal info: $e');
    }
  }

  /// Cambia la modalidad de cobro preferida (transferencia bancaria vs QR de
  /// transferencia). Persiste de inmediato en el backend, igual que en la
  /// billetera — el backend valida cuál usar al procesar un retiro.
  Future<void> _setWithdrawalMethod(String method) async {
    if (_switchingMethod || _withdrawalMethod == method) return;
    final headers = await pinTokenHeaders(context,
        base: {'Authorization': 'Bearer $_caregiverToken', 'Content-Type': 'application/json'});
    if (headers == null || !mounted) return;
    setState(() => _switchingMethod = true);
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/wallet/withdrawal-method'),
        headers: headers,
        body: jsonEncode({'withdrawalMethod': method}),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true && mounted) {
        setState(() => _withdrawalMethod = method);
      } else if (mounted) {
        GardenErrorDialog.show(context, data['error']?['message'] ?? 'No se pudo cambiar la modalidad de cobro');
      }
    } catch (e) {
      if (mounted) {
        GardenErrorDialog.show(context, 'Error de conexión. Intenta de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _switchingMethod = false);
    }
  }

  /// Sube (o reemplaza) el QR de cobro propio del cuidador para la modalidad
  /// "QR de transferencia". El backend guarda historial (isCurrent) — ver
  /// comentario en el modelo WithdrawalQr del schema.
  Future<void> _pickAndUploadQr() async {
    if (_uploadingQr) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;

    if (!mounted) return;
    final pinHeaders = await pinTokenHeaders(context, base: {'Authorization': 'Bearer $_caregiverToken'});
    if (pinHeaders == null || !mounted) return;
    setState(() => _uploadingQr = true);
    try {
      final bytes = await picked.readAsBytes();
      final fileName = picked.name.isEmpty ? 'qr.jpg' : picked.name;
      final uri = Uri.parse('$_baseUrl/wallet/withdrawal-qr');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(pinHeaders);
      request.files.add(http.MultipartFile.fromBytes(
        'qrImage', bytes, filename: fileName,
        contentType: MediaType('image', 'jpeg'),
      ));
      final response = await http.Response.fromStream(await request.send());
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          _qrInfo = {'imageUrl': data['data']['imageUrl'], 'updatedAt': data['data']['updatedAt']};
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('QR de cobro actualizado'), backgroundColor: GardenColors.success),
        );
      } else {
        GardenErrorDialog.show(context, data['error']?['message'] ?? 'Error al subir el QR');
      }
    } catch (e) {
      if (mounted) {
        GardenErrorDialog.show(context, 'Error de conexión. Intenta de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _uploadingQr = false);
    }
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
          // bioDetail es el campo usado en Datos del Cuidador; bio es el legacy corto
          final bioDetail = (profile['bioDetail'] as String? ?? '').trim();
          final bioLegacy = (profile['bio'] as String? ?? '').trim();
          _bioController.text = bioDetail.isNotEmpty ? bioDetail : bioLegacy;

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
          _gardenCityId = profile['cityId'] as String?;
          _addressLat = (profile['addressLat'] as num?)?.toDouble();
          _addressLng = (profile['addressLng'] as num?)?.toDouble();
          _isApartment = (_apartmentCtrl.text).isNotEmpty;

          _selectedBankName = profile['bankName'] as String? ?? '';
          _selectedBankType = profile['bankType'] as String? ?? 'CUENTA_AHORRO';
          _bankAccountController.text = profile['bankAccount'] as String? ?? '';
_bankHolderController.text = profile['bankHolder'] as String? ?? '';
          _savedBankSnapshot = _bankSnapshot;
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

  Future<void> _saveProfile() async {
    // ── Validación de campos obligatorios ──
    final isVerifiedCheck = _profile?['identityVerificationStatus'] == 'VERIFIED';
    if (!isVerifiedCheck) {
      if (_firstNameController.text.trim().isEmpty) {
        GardenErrorDialog.show(context, 'El nombre es obligatorio');
        return;
      }
      if (_lastNameController.text.trim().isEmpty) {
        GardenErrorDialog.show(context, 'El apellido es obligatorio');
        return;
      }
    }
    if (_phoneController.text.trim().isEmpty) {
      GardenErrorDialog.show(context, 'El teléfono es obligatorio');
      return;
    }
    // Los datos de cobro se revisan ANTES de guardar nada: antes el perfil se
    // guardaba y recién después fallaba el banco, dejando el guardado a medias.
    if (_selectedBankName.isNotEmpty && _bankSnapshot != _savedBankSnapshot) {
      final bankError = GardenBanks.validateAccount(_selectedBankType, _bankAccountController.text) ??
          GardenBanks.validateHolder(_bankHolderController.text);
      if (bankError != null) {
        GardenErrorDialog.show(context, bankError);
        return;
      }
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
        'bioDetail': _bioController.text.trim(),
        'address': [_streetCtrl.text.trim(), _numberCtrl.text.trim()].where((s) => s.isNotEmpty).join(', '),
        if (_addressLat != null) 'addressLat': _addressLat,
        if (_addressLng != null) 'addressLng': _addressLng,
        // Siempre se mandan (vacíos incluidos): si se omitían, borrar la
        // referencia o dejar de vivir en un depto no se guardaba nunca.
        'addressStreet': _streetCtrl.text.trim(),
        'addressNumber': _numberCtrl.text.trim(),
        'addressApartment': _isApartment ? _apartmentCtrl.text.trim() : '',
        'addressCondominio': _isApartment ? _condominioCtrl.text.trim() : '',
        'addressReference': _referenceCtrl.text.trim(),
        if (_addressZone != null) 'addressZone': _addressZone,
        if (_gardenCityId != null) 'cityId': _gardenCityId,
      };
      if (_gardenCityId != null && _addressZone != null) {
        final zones = await CitiesService.getZones(_gardenCityId!);
        final match = zones.where((z) => z.key == _addressZone).firstOrNull;
        if (match != null) addressBody['zoneId'] = match.id;
      }

      final response = await http.patch(
        Uri.parse('$_baseUrl/caregiver/profile'),
        headers: {
          'Authorization': 'Bearer $_caregiverToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(addressBody),
      );

      final data = jsonDecode(response.body);
      if (data['success'] != true) {
        throw Exception(data['error']?['message'] ?? 'No se pudo guardar tu perfil. Intenta de nuevo.');
      }
      // Guardar también la info personal y datos de cobro
      await _saveUserInfo();
      await _saveBankInfo();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Perfil actualizado correctamente'),
          backgroundColor: GardenColors.success,
          duration: Duration(seconds: 2),
        ),
      );
      setState(() => _isEditing = false);
    } catch (e) {
      if (!mounted) return;
      GardenErrorDialog.show(
        context,
        e is Exception && e is! FormatException ? e.toString().replaceFirst('Exception: ', '') : 'Error de conexión. Intenta de nuevo.',
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Antes ignoraba la respuesta y tragaba los errores: si el banco no se
  /// guardaba (datos inválidos), el cuidador veía "guardado" igual.
  Future<void> _saveBankInfo() async {
    if (_selectedBankName.isEmpty || _bankSnapshot == _savedBankSnapshot) return;
    // Cambiar a dónde va el dinero exige el PIN verificado en el servidor.
    final headers = await pinTokenHeaders(context,
        base: {'Authorization': 'Bearer $_caregiverToken', 'Content-Type': 'application/json'});
    if (headers == null) {
      throw Exception('Tus datos de cobro no se guardaron: falta confirmar tu PIN.');
    }
    {
      final response = await http.patch(
        Uri.parse('$_baseUrl/caregiver/bank-info'),
        headers: headers,
        body: jsonEncode({
          'bankName': _selectedBankName,
          'bankAccount': GardenBanks.normalizeAccount(_selectedBankType, _bankAccountController.text),
          'bankHolder': _bankHolderController.text.trim(),
          'bankType': _selectedBankType,
        }),
      );
      final data = jsonDecode(response.body);
      if (data['success'] != true) {
        throw Exception(data['error']?['message'] ?? 'No se pudieron guardar tus datos de cobro');
      }
      _savedBankSnapshot = _bankSnapshot;
    }
  }

  Future<void> _saveUserInfo() async {
    final isVerified = _profile?['identityVerificationStatus'] == 'VERIFIED';
    final isPhoneVerified = _profile?['phoneVerified'] == true;

    final Map<String, dynamic> body = {
      // Teléfono ya verificado: no se reenvía, el backend lo rechaza con
      // 403 PHONE_LOCKED (solo se cambia por el chat de soporte).
      if (!isPhoneVerified) 'phone': _phoneController.text.trim(),
    };

    if (!isVerified) {
      body['firstName'] = _firstNameController.text.trim();
      body['lastName'] = _lastNameController.text.trim();
    }
    if (body.isEmpty) return;
    final response = await http.patch(
      Uri.parse('$_baseUrl/caregiver/user-info'),
      headers: {
        'Authorization': 'Bearer $_caregiverToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    final data = jsonDecode(response.body);
    if (data['success'] != true) {
      throw Exception(data['error']?['message'] ?? 'Error al actualizar tus datos personales');
    }
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

        if (kIsWeb) {
          return _buildWebScaffold(
            context, isDark, bg, surface, textColor, subtextColor, borderColor,
          );
        }

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: surface,
            elevation: 0,
            title: Text(
              'Editar perfil',
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            ),
            iconTheme: IconThemeData(color: textColor),
          ),
          bottomNavigationBar: _buildEditBarSimple(surface, borderColor, subtextColor),
          body: _isLoading
              ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Antes: foto suelta, secciones separadas por líneas y el estado
                      // del perfil al final. Ahora el avance arriba y cada sección
                      // dice si está completa.
                      _completionHeader(),
                      const SizedBox(height: 16),
                      Builder(builder: (_) {
                        final missing = _missing();
                        int n(Set<String> k) => missing.where(k.contains).length;
                        return Column(children: [
                          GardenFormSection(
                            icon: GIcon.editar,
                            title: 'Sobre ti',
                            hint: 'Lo primero que leen los dueños en tu perfil.',
                            missing: n(_kSobreTi),
                            children: [
                                // bioDetail (máx. 300): este campo se guarda en bio y en bioDetail a la vez.
                                if (_isEditing) AiWriteAssist(controller: _bioController, field: 'bioDetail', onApplied: () => setState(() {})),
                                // Sección 2 - Información básica
                                TextField(
                                  controller: _bioController,
                                  maxLines: 4,
                                  readOnly: !_isEditing,
                                  style: TextStyle(color: textColor),
                                  decoration: _inputDecoration('Cuéntanos sobre tu experiencia cuidando mascotas...', isDark),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          GardenFormSection(
                            icon: GIcon.ubicacion,
                            title: 'Ubicación',
                            hint: 'Define tu zona de servicio. Los dueños solo ven la zona, no tu calle.',
                            missing: n(_kUbicacion),
                            children: [
                                IgnorePointer(
                                  ignoring: !_isEditing,
                                  child: Theme(
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
                                      purposeText: 'Tu dirección define en qué zona ofreces servicios. Solo se muestra la zona (no la calle exacta) a los dueños.',
                                      onMapResult: (result) => setState(() {
                                        _addressLat = result.lat;
                                        _addressLng = result.lng;
                                      }),
                                      onApartmentToggle: (val) => setState(() => _isApartment = val),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          GardenFormSection(
                            icon: GIcon.perfil,
                            title: 'Datos personales',
                            missing: n(_kPersonal),
                            children: [
                              IgnorePointer(
                                ignoring: !_isEditing,
                                child: _buildPersonalInfoSection(textColor, subtextColor, isDark),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          GardenFormSection(
                            icon: GIcon.retiro,
                            title: 'Datos de cobro',
                            hint: 'A dónde enviamos tus ganancias cuando retiras.',
                            missing: n(_kCobro),
                            children: [
                              IgnorePointer(
                                ignoring: !_isEditing,
                                child: _buildBankSection(textColor, subtextColor, surface, borderColor, isDark, showHeader: false),
                              ),
                            ],
                          ),
                        ]);
                      }),
                      const SizedBox(height: 100),
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
  ) {
    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          // ── Top bar con botones ────────────────────────────────────────────
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
                  icon: GardenIcon(GIcon.atras, size: GIconSize.md, color: textColor),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Volver',
                ),
                const SizedBox(width: 4),
                Text('Editar perfil',
                  style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700)),
                const Spacer(),
                if (_isSaving)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: GardenLoadingIndicator(size: 20, color: GardenColors.primary),
                  )
                else if (_isEditing) ...[
                  TextButton(
                    onPressed: () { setState(() => _isEditing = false); _loadProfile(); },
                    style: TextButton.styleFrom(foregroundColor: subtextColor, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    child: const Text('Cancelar', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    onPressed: _saveProfile,
                    icon: const GardenIcon(GIcon.hecho, size: GIconSize.sm, inheritColor: true),
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
                    icon: const GardenIcon(GIcon.editar, size: GIconSize.sm, inheritColor: true),
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

          // ── Body — sin AbsorbPointer ───────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
                : SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 28, left: 24, right: 24, bottom: 100),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 940),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Profile header card ────────────────────────
                            _completionHeader(),
                            const SizedBox(height: 20),

                            // ── Two-column main content ────────────────────
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // LEFT — bio + address
                                  Expanded(
                                    flex: 52,
                                    child: Column(
                                      children: [
                                        _webCard(
                                          surface, borderColor, textColor,
                                          title: 'Sobre ti',
                                          badge: _missing().where(_kSobreTi.contains).isEmpty ? 'Completo' : 'Falta ${_missing().where(_kSobreTi.contains).length}',
                                          badgeColor: _missing().where(_kSobreTi.contains).isEmpty ? GardenColors.success : GardenColors.warning,
                                          icon: GIcon.editar,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('Descripción', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                                              const SizedBox(height: 8),
                                              TextField(
                                                controller: _bioController,
                                                maxLines: 4,
                                                readOnly: !_isEditing,
                                                style: TextStyle(color: textColor, fontSize: 13),
                                                decoration: _inputDecoration('Cuéntanos sobre tu experiencia cuidando mascotas...', isDark),
                                              ),
                                              if (_isEditing) AiWriteAssist(controller: _bioController, field: 'bioDetail', onApplied: () => setState(() {})),
                                            ],
                                          )),
                                        const SizedBox(height: 16),
                                        _webCard(
                                          surface, borderColor, textColor,
                                          title: 'Ubicación',
                                          badge: _missing().where(_kUbicacion.contains).isEmpty ? 'Completo' : 'Falta ${_missing().where(_kUbicacion.contains).length}',
                                          badgeColor: _missing().where(_kUbicacion.contains).isEmpty ? GardenColors.success : GardenColors.warning,
                                          icon: GIcon.ubicacion,
                                          child: IgnorePointer(
                                            ignoring: !_isEditing,
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
                                                purposeText: 'Tu dirección define en qué zona ofreces servicios. Solo se muestra la zona (no la calle exacta) a los dueños.',
                                                onMapResult: (result) => setState(() {
                                                  _addressLat = result.lat;
                                                  _addressLng = result.lng;
                                                }),
                                                onApartmentToggle: (val) => setState(() => _isApartment = val),
                                              ),
                                            ),
                                          )),
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
                                          badge: _missing().where(_kPersonal.contains).isEmpty ? 'Completo' : 'Falta ${_missing().where(_kPersonal.contains).length}',
                                          badgeColor: _missing().where(_kPersonal.contains).isEmpty ? GardenColors.success : GardenColors.warning,
                                          icon: GIcon.perfil,
                                          child: IgnorePointer(
                                            ignoring: !_isEditing,
                                            child: _buildPersonalInfoSection(textColor, subtextColor, isDark),
                                          )),
                                        const SizedBox(height: 16),
                                        _webCard(
                                          surface, borderColor, textColor,
                                          title: 'Datos de cobro',
                                          badge: _missing().where(_kCobro.contains).isEmpty ? 'Completo' : 'Falta ${_missing().where(_kCobro.contains).length}',
                                          badgeColor: _missing().where(_kCobro.contains).isEmpty ? GardenColors.success : GardenColors.warning,
                                          icon: GIcon.retiro,
                                          child: IgnorePointer(
                                            ignoring: !_isEditing,
                                            child: _buildBankSection(textColor, subtextColor, surface, borderColor, isDark, showHeader: false),
                                          )),
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

  Widget _buildEditBarSimple(Color surface, Color borderColor, Color subtextColor) {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: borderColor)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, -3))],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          if (_isSaving) ...[
            const GardenLoadingIndicator(size: 18, color: GardenColors.primary),
            const SizedBox(width: 12),
            Text('Guardando...', style: TextStyle(color: subtextColor, fontSize: 13)),
          ] else if (_isEditing) ...[
            TextButton(
              onPressed: () { setState(() => _isEditing = false); _loadProfile(); },
              style: TextButton.styleFrom(foregroundColor: subtextColor),
              child: const Text('Cancelar', style: TextStyle(fontSize: 14)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saveProfile,
                icon: const GardenIcon(GIcon.hecho, size: GIconSize.sm, inheritColor: true),
                label: const Text('Guardar cambios', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GardenColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ),
          ] else ...[
            Expanded(
              child: Text('Modo vista — información de tu perfil',
                style: TextStyle(color: subtextColor, fontSize: 13)),
            ),
            ElevatedButton.icon(
              onPressed: () => setState(() => _isEditing = true),
              icon: const GardenIcon(GIcon.editar, size: GIconSize.sm, inheritColor: true),
              label: const Text('Editar perfil', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: GardenColors.primary,
                foregroundColor: Colors.white,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _webCard(
    Color surface, Color borderColor, Color textColor, {
    required String title,
    required GIcon icon,
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
              GardenIcon(icon, size: GIconSize.xs, color: GardenColors.primary),
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
                    GardenIcon(GIcon.seguridad, size: GIconSize.xs, color: GardenColors.secondary),
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

        // ── Selector de modalidad: transferencia bancaria vs QR de transferencia ──
        // Mismo selector que en la billetera — persiste de inmediato, no
        // espera al botón "Guardar cambios" de esta pantalla.
        Row(
          children: [
            Expanded(
              child: _withdrawalMethodChip(
                'Transferencia bancaria', GIcon.retiro, 'BANK_TRANSFER',
                textColor, subtextColor, surfaceEl, borderColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _withdrawalMethodChip(
                'QR de transferencia', GIcon.pagarQr, 'QR_TRANSFER',
                textColor, subtextColor, surfaceEl, borderColor),
            ),
          ],
        ),
        const SizedBox(height: 14),

        if (_withdrawalMethod == 'QR_TRANSFER')
          _buildQrSection(textColor, subtextColor, surfaceEl, borderColor)
        else ...[
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
                  GardenIcon(_selectedBankName.isEmpty ? GIcon.retiro : (isWallet ? GIcon.billetera : GIcon.retiro), size: GIconSize.md, color: _selectedBankName.isEmpty ? subtextColor : GardenColors.primary),
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
                  GardenIcon(GIcon.desplegar, size: GIconSize.md, color: subtextColor),
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
      ],
    );
  }

  /// Chip seleccionable para elegir la modalidad de cobro (transferencia
  /// bancaria vs QR de transferencia) — mismo widget/estilo que en la billetera.
  Widget _withdrawalMethodChip(
    String label, GIcon icon, String method,
    Color textColor, Color subtextColor, Color surface, Color borderColor,
  ) {
    final isSelected = _withdrawalMethod == method;
    return GestureDetector(
      onTap: _switchingMethod ? null : () => _setWithdrawalMethod(method),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? GardenColors.primary.withValues(alpha: 0.1) : surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? GardenColors.primary : borderColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GardenIcon(icon, size: GIconSize.md, color: isSelected ? GardenColors.primary : subtextColor),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? GardenColors.primary : textColor,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sección "QR de transferencia": muestra el QR de cobro vigente (si hay
  /// uno) y permite subir/reemplazar uno nuevo — mismo widget/estilo que en
  /// la billetera. El cuidador sube su propio QR de cobro (el que genera su
  /// banco o billetera personal para recibir pagos).
  Widget _buildQrSection(Color textColor, Color subtextColor, Color surface, Color borderColor) {
    final qrInfo = _qrInfo;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: qrInfo != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.network(qrInfo['imageUrl'] as String, fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const GardenIcon(GIcon.sinImagen, size: GIconSize.lg, color: GardenColors.error)),
                  )
                : GardenIcon(GIcon.pagarQr, size: GIconSize.lg, color: subtextColor.withValues(alpha: 0.4)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  qrInfo != null ? 'QR de cobro cargado' : 'Sube tu QR de cobro',
                  style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  qrInfo != null
                      ? 'Es el que genera tu banco o billetera para recibir pagos. Puedes reemplazarlo cuando quieras.'
                      : 'Sube el QR de cobro que genera tu banco o billetera para recibir pagos.',
                  style: TextStyle(color: subtextColor, fontSize: 12),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _uploadingQr ? null : _pickAndUploadQr,
                  icon: _uploadingQr
                      ? const GardenLoadingIndicator(size: 14, color: GardenColors.primary)
                      : const GardenIcon(GIcon.subir, size: GIconSize.sm, inheritColor: true),
                  label: Text(_uploadingQr ? 'Subiendo...' : (qrInfo != null ? 'Reemplazar QR' : 'Subir QR')),
                  style: OutlinedButton.styleFrom(foregroundColor: GardenColors.primary, side: const BorderSide(color: GardenColors.primary)),
                ),
              ],
            ),
          ),
        ],
      ),
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
                  leading: GardenClay(size: 36, tint: isSelected ? GardenColors.primary.withValues(alpha: 0.15) : GardenColors.primary.withValues(alpha: 0.08), circle: false, radius: 10, interactive: false, child: GardenIcon(category == 'Bancos' ? GIcon.retiro : GIcon.billetera, size: GIconSize.sm, state: category == 'Bancos' ? GIconState.idle : GIconState.active, color: isSelected ? GardenColors.primary : subtextColor)),
                  title: Text(bank['name']!, style: TextStyle(
                    color: isSelected ? GardenColors.primary : textColor,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 14,
                  )),
                  subtitle: Text(GardenBanks.typeLabels[bank['type']] ?? '', style: TextStyle(color: subtextColor, fontSize: 11)),
                  trailing: isSelected ? const GardenIcon(GIcon.confirmado, size: GIconSize.md, state: GIconState.active, color: GardenColors.primary) : null,
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
                    prefixIcon: GardenIcon(GIcon.buscar, size: GIconSize.md, color: subtextColor),
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

  Widget _buildPersonalInfoSection(Color textColor, Color subtextColor, bool isDark) {
    bool isVerified = _profile?['identityVerificationStatus'] == 'VERIFIED';
    bool isPhoneVerified = _profile?['phoneVerified'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // El título lo pone la sección que la contiene; acá solo el sello.
        Row(
          children: [
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
                    GardenIcon(GIcon.protegido, size: GIconSize.xs, state: GIconState.active, color: GardenColors.success),
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
          enabled: !isPhoneVerified,
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          style: TextStyle(color: isPhoneVerified ? subtextColor : textColor),
          decoration: _inputDecoration('Teléfono (ej: 70012345)', isDark),
        ),
        if (isPhoneVerified) ...[
          const SizedBox(height: 4),
          Text(
            'Tu teléfono ya está verificado. Para cambiarlo, pídelo por el chat de soporte.',
            style: TextStyle(color: subtextColor, fontSize: 12, fontStyle: FontStyle.italic),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                final changed = await PhoneChangeFlow.promptAndRun(context, baseUrl: _baseUrl, token: _caregiverToken);
                if (changed != null && mounted) setState(() => _phoneController.text = changed);
              },
              icon: const GardenIcon(GIcon.repetir, size: GIconSize.sm),
              label: const Text('Cambiar número verificado'),
            ),
          ),
        ],
      ],
    );
  }
}
