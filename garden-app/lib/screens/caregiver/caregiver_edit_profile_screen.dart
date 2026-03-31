import 'dart:convert';
import 'dart:typed_data';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import '../../utils/garden_banks.dart';

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

  // Controladores de texto
  final _bioController = TextEditingController();
  final _addressController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();

  // Datos de cobro
  final _bankAccountController = TextEditingController();
  final _bankHolderController = TextEditingController();
  String _selectedBankName = '';
  String _selectedBankType = 'CUENTA_AHORRO';

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://garden-api-1ldd.onrender.com/api');

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    String token = prefs.getString('access_token') ?? '';
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
          _addressController.text = profile['address'] as String? ?? '';
          
          final user = profile['user'] as Map<String, dynamic>?;
          if (user != null) {
            _firstNameController.text = user['firstName'] as String? ?? '';
            _lastNameController.text = user['lastName'] as String? ?? '';
            _phoneController.text = user['phone'] as String? ?? '';
          }
          _selectedBankName = profile['bankName'] as String? ?? '';
          _selectedBankType = profile['bankType'] as String? ?? 'CUENTA_AHORRO';
          _bankAccountController.text = profile['bankAccount'] as String? ?? '';
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
      final response = await http.patch(
        Uri.parse('$_baseUrl/caregiver/profile'),
        headers: {
          'Authorization': 'Bearer $_caregiverToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'bio': _bioController.text.trim(),
          'address': _addressController.text.trim(),
        }),
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

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: surface,
            elevation: 0,
            title: Text('Editar perfil', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
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
                      const SizedBox(height: 16),
                      Text('Dirección', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _addressController,
                        style: TextStyle(color: textColor),
                        decoration: _inputDecoration('Calle, número, barrio...', isDark),
                      ),
                      const Divider(height: 32),

                      _buildPersonalInfoSection(textColor, subtextColor, isDark),
                      const Divider(height: 32),

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

  Widget _buildBankSection(Color textColor, Color subtextColor, Color surface, Color borderColor, bool isDark) {
    final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    final isWallet = GardenBanks.isDigitalWallet(_selectedBankName);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
      case 'DRAFT': color = Colors.grey; label = 'Borrador'; break;
      default: color = Colors.grey; label = status;
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
                  color: GardenColors.success.withOpacity(0.1),
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
