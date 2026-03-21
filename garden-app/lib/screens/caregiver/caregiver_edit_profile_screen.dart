import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:http_parser/http_parser.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import '../../main.dart';
import '../../theme/garden_theme.dart';

class CaregiverEditProfileScreen extends StatefulWidget {
  const CaregiverEditProfileScreen({Key? key}) : super(key: key);

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

  // Selecciones
  String _selectedZone = 'EQUIPETROL';
  List<String> _selectedServices = [];

  static const _zones = [
    'EQUIPETROL', 'URBARI', 'NORTE', 'SUR', 'CENTRO',
    'ESTE', 'OESTE', 'LAS_PALMAS', 'REMANSO',
  ];

  static const _zoneLabels = {
    'EQUIPETROL': 'Equipetrol',
    'URBARI': 'Urbari',
    'NORTE': 'Norte',
    'SUR': 'Sur',
    'CENTRO': 'Centro',
    'ESTE': 'Este',
    'OESTE': 'Oeste',
    'LAS_PALMAS': 'Las Palmas',
    'REMANSO': 'Remanso',
  };

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api');

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
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickProfilePhoto() async {
    final input = html.FileUploadInputElement();
    input.accept = 'image/*';
    input.click();
    await input.onChange.first;
    final file = input.files?.first;
    if (file == null) return;
    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    await reader.onLoad.first;
    final bytes = Uint8List.fromList(reader.result as List<int>);
    setState(() {
      _newPhotoBytes = bytes;
      _newPhotoName = file.name;
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

      // Guardar también la info personal
      await _saveUserInfo();

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Perfil actualizado correctamente'),
            backgroundColor: GardenColors.success,
          ),
        );
        Navigator.pop(context, true); // retorna true para indicar que hubo cambios
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
                        Center(
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

                      // Sección 6 - Estado
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

  Widget _serviceChip(String label, String value) {
    final isSelected = _selectedServices.contains(value);
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          if (selected) {
            _selectedServices.add(value);
          } else {
            _selectedServices.remove(value);
          }
        });
      },
      selectedColor: GardenColors.primary.withOpacity(0.2),
      checkmarkColor: GardenColors.primary,
      labelStyle: TextStyle(
        color: isSelected ? GardenColors.primary : Colors.grey,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: isSelected ? GardenColors.primary : Colors.grey.shade300),
      ),
    );
  }

  Widget _priceField(String label, TextEditingController controller, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: TextStyle(color: isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary),
          decoration: _inputDecoration('0.00', isDark).copyWith(
            prefixText: 'Bs ',
            prefixStyle: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.bold),
          ),
        ),
      ],
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
