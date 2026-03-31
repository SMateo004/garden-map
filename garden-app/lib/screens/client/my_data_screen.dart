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
  late TextEditingController _phoneCtrl;
  late TextEditingController _cityCtrl;
  late TextEditingController _countryCtrl;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://garden-api-1ldd.onrender.com/api');

  @override
  void initState() {
    super.initState();
    _firstCtrl = TextEditingController();
    _lastCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _cityCtrl = TextEditingController();
    _countryCtrl = TextEditingController();
    _loadData();
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _phoneCtrl.dispose();
    _cityCtrl.dispose();
    _countryCtrl.dispose();
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
          _phoneCtrl.text = user['phone'] as String? ?? '';
          _cityCtrl.text = user['city'] as String? ?? '';
          _countryCtrl.text = user['country'] as String? ?? '';
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final fileName = picked.name.isEmpty ? 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg' : picked.name;

    setState(() => _uploadingPhoto = true);
    try {
      final uri = Uri.parse('$_baseUrl/upload/user-photo');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $_token';
      request.files.add(http.MultipartFile.fromBytes(
        'photo', bytes, filename: fileName,
        contentType: MediaType('image', 'jpeg'),
      ));
      final response = await http.Response.fromStream(await request.send());
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          _userData = {...?_userData, 'profilePicture': data['data']['url']};
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Foto actualizada'), backgroundColor: GardenColors.success));
        }
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
      final body = <String, dynamic>{
        'firstName': fn,
        'lastName': ln,
        'phone': _phoneCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'country': _countryCtrl.text.trim(),
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

                      // Email (read-only)
                      if (_userData?['email'] != null) ...[
                        Text('Correo electrónico', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
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
                            if (_userData?['emailVerified'] == true)
                              const Icon(Icons.verified_outlined, color: GardenColors.success, size: 16),
                          ]),
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
                      const SizedBox(height: 32),

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
