import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';

class MyDataScreen extends StatefulWidget {
  const MyDataScreen({super.key});
  @override
  State<MyDataScreen> createState() => _MyDataScreenState();
}

class _MyDataScreenState extends State<MyDataScreen> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;
  String _token = '';

  late TextEditingController _firstCtrl;
  late TextEditingController _lastCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _cityCtrl;
  late TextEditingController _countryCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _bioCtrl;
  DateTime? _dateOfBirth;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://garden-api-1ldd.onrender.com/api');

  @override
  void initState() {
    super.initState();
    _firstCtrl = TextEditingController();
    _lastCtrl = TextEditingController();
    _emailCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _cityCtrl = TextEditingController();
    _countryCtrl = TextEditingController();
    _addressCtrl = TextEditingController();
    _bioCtrl = TextEditingController();
    _loadData();
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _cityCtrl.dispose();
    _countryCtrl.dispose();
    _addressCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('access_token') ?? '';
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/auth/me'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        final user = data['data'] as Map<String, dynamic>;
        setState(() {
          _userData = user;
          _firstCtrl.text = user['firstName'] as String? ?? '';
          _lastCtrl.text = user['lastName'] as String? ?? '';
          _emailCtrl.text = user['email'] as String? ?? '';
          _phoneCtrl.text = user['phone'] as String? ?? '';
          _cityCtrl.text = user['city'] as String? ?? '';
          _countryCtrl.text = user['country'] as String? ?? '';
          _addressCtrl.text = user['address'] as String? ?? '';
          _bioCtrl.text = user['bio'] as String? ?? '';
          final dob = user['dateOfBirth'] as String?;
          if (dob != null && dob.isNotEmpty) {
            try { _dateOfBirth = DateTime.parse(dob); } catch (_) {}
          }
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      final fileName = picked.name.isEmpty
          ? 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg'
          : picked.name;
      final uri = Uri.parse('$_baseUrl/upload/user-photo');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $_token';
      request.files.add(http.MultipartFile.fromBytes(
        'photo', bytes, filename: fileName,
        contentType: MediaType('image', 'jpeg'),
      ));
      final response = await http.Response.fromStream(await request.send());
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (response.statusCode == 200 && data['success'] == true) {
        setState(() => _userData = {...?_userData, 'profilePicture': data['data']['url']});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Foto actualizada'), backgroundColor: GardenColors.success));
      } else {
        throw Exception(data['message'] ?? 'Error al subir foto');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: GardenColors.error));
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _save() async {
    final fn = _firstCtrl.text.trim();
    final ln = _lastCtrl.text.trim();
    if (fn.isEmpty || ln.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nombre y apellido son requeridos')));
      return;
    }
    setState(() => _saving = true);
    try {
      final emailVerified = _userData?['emailVerified'] == true;
      final body = <String, dynamic>{
        'firstName': fn,
        'lastName': ln,
        'phone': _phoneCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'country': _countryCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
        if (_dateOfBirth != null) 'dateOfBirth': _dateOfBirth!.toIso8601String(),
        if (!emailVerified && _emailCtrl.text.trim().isNotEmpty) 'email': _emailCtrl.text.trim(),
      };
      final res = await http.patch(
        Uri.parse('$_baseUrl/auth/me'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Datos actualizados'), backgroundColor: GardenColors.success));
        Navigator.pop(context, true); // true = reload profile
      } else {
        throw Exception(data['error']?['message'] ?? 'Error al actualizar');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: GardenColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
        final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
        final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
        final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

        InputDecoration fieldDeco(String label, IconData icon) => InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: subtextColor, fontSize: 13),
          prefixIcon: Icon(icon, color: subtextColor, size: 20),
          filled: true, fillColor: surfaceEl,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        );

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            title: const Text('Mis Datos'),
            backgroundColor: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
            foregroundColor: textColor,
            elevation: 0,
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Photo section
                      Center(
                        child: Stack(
                          children: [
                            GestureDetector(
                              onTap: _uploadingPhoto ? null : _pickAndUploadPhoto,
                              child: Container(
                                width: 100, height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: GardenColors.primary.withValues(alpha: 0.4), width: 2),
                                ),
                                child: _uploadingPhoto
                                    ? const Padding(
                                        padding: EdgeInsets.all(30),
                                        child: CircularProgressIndicator(color: GardenColors.primary, strokeWidth: 2))
                                    : ClipOval(
                                        child: _userData?['profilePicture'] != null
                                            ? Image.network(
                                                fixImageUrl(_userData!['profilePicture'] as String),
                                                width: 100, height: 100, fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => _avatarFallback(textColor),
                                              )
                                            : _avatarFallback(textColor),
                                      ),
                              ),
                            ),
                            Positioned(
                              bottom: 0, right: 0,
                              child: GestureDetector(
                                onTap: _uploadingPhoto ? null : _pickAndUploadPhoto,
                                child: Container(
                                  width: 32, height: 32,
                                  decoration: const BoxDecoration(
                                    color: GardenColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text('Toca para cambiar foto',
                          style: TextStyle(color: subtextColor, fontSize: 12))),
                      const SizedBox(height: 32),

                      // Email
                      if (_userData?['email'] != null) ...[
                        Text('Correo electrónico', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        if (_userData?['emailVerified'] == true)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: surfaceEl.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: borderColor.withValues(alpha: 0.5)),
                            ),
                            child: Row(children: [
                              Icon(Icons.email_outlined, color: subtextColor, size: 20),
                              const SizedBox(width: 12),
                              Expanded(child: Text(_userData!['email'] as String,
                                style: TextStyle(color: subtextColor, fontSize: 14))),
                              const Icon(Icons.verified_outlined, color: GardenColors.success, size: 16),
                            ]),
                          )
                        else
                          TextField(
                            controller: _emailCtrl,
                            style: TextStyle(color: textColor),
                            keyboardType: TextInputType.emailAddress,
                            decoration: fieldDeco('Correo electrónico', Icons.email_outlined).copyWith(
                              suffixIcon: const Tooltip(
                                message: 'Correo no verificado',
                                child: Icon(Icons.warning_amber_rounded, color: GardenColors.warning, size: 18),
                              ),
                            ),
                          ),
                        const SizedBox(height: 20),
                      ],

                      // Name
                      Text('Nombre', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(child: TextField(controller: _firstCtrl,
                          style: TextStyle(color: textColor),
                          decoration: fieldDeco('Nombre *', Icons.person_outline))),
                        const SizedBox(width: 12),
                        Expanded(child: TextField(controller: _lastCtrl,
                          style: TextStyle(color: textColor),
                          decoration: fieldDeco('Apellido *', Icons.person_outlined))),
                      ]),
                      const SizedBox(height: 16),

                      // Phone
                      Text('Teléfono', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(controller: _phoneCtrl,
                        style: TextStyle(color: textColor),
                        keyboardType: TextInputType.phone,
                        decoration: fieldDeco('Número de teléfono', Icons.phone_outlined)),
                      const SizedBox(height: 16),

                      // City
                      Text('Ciudad', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(controller: _cityCtrl,
                        style: TextStyle(color: textColor),
                        decoration: fieldDeco('Tu ciudad', Icons.location_city_outlined)),
                      const SizedBox(height: 16),

                      // Country
                      Text('País', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(controller: _countryCtrl,
                        style: TextStyle(color: textColor),
                        decoration: fieldDeco('Tu país', Icons.public_outlined)),
                      const SizedBox(height: 16),

                      // Address
                      Text('Dirección', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(controller: _addressCtrl,
                        style: TextStyle(color: textColor),
                        decoration: fieldDeco('Tu dirección', Icons.home_work_outlined)),
                      const SizedBox(height: 16),

                      // Date of birth
                      Text('Fecha de nacimiento', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _dateOfBirth ?? DateTime(1995),
                            firstDate: DateTime(1940),
                            lastDate: DateTime.now().subtract(const Duration(days: 365 * 13)),
                          );
                          if (picked != null) setState(() => _dateOfBirth = picked);
                        },
                        child: Container(
                          height: 52,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: surfaceEl,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: borderColor),
                          ),
                          child: Row(children: [
                            Icon(Icons.cake_outlined, color: subtextColor, size: 20),
                            const SizedBox(width: 12),
                            Text(
                              _dateOfBirth == null
                                  ? 'Seleccionar fecha'
                                  : '${_dateOfBirth!.day.toString().padLeft(2, '0')}/${_dateOfBirth!.month.toString().padLeft(2, '0')}/${_dateOfBirth!.year}',
                              style: TextStyle(color: _dateOfBirth == null ? subtextColor : textColor, fontSize: 14),
                            ),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Bio
                      Text('Descripción', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _bioCtrl,
                        maxLines: 3,
                        maxLength: 300,
                        style: TextStyle(color: textColor, fontSize: 14),
                        decoration: fieldDeco('Una breve descripción de ti', Icons.description_outlined).copyWith(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                      const SizedBox(height: 16),

                      SizedBox(
                        width: double.infinity,
                        child: GardenButton(
                          label: _saving ? 'Guardando...' : 'Guardar cambios',
                          loading: _saving,
                          onPressed: _save,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _avatarFallback(Color textColor) {
    final initials = '${_firstCtrl.text.isNotEmpty ? _firstCtrl.text[0] : ''}${_lastCtrl.text.isNotEmpty ? _lastCtrl.text[0] : ''}'.toUpperCase();
    return Container(
      width: 100, height: 100,
      color: GardenColors.primary.withValues(alpha: 0.15),
      child: Center(child: Text(initials.isEmpty ? '?' : initials,
        style: const TextStyle(color: GardenColors.primary, fontSize: 32, fontWeight: FontWeight.bold))),
    );
  }
}
