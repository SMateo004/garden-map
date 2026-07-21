import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';

/// Paso obligatorio para dueños de mascota recién registrados/logueados sin
/// foto de perfil (registro normal, o Google cuando no entregó foto).
/// Bloqueo total: sin botón de "omitir", sin back — hasta subir una foto
/// real no se puede continuar a [nextRoute].
class UploadProfilePhotoScreen extends StatefulWidget {
  final String nextRoute;
  const UploadProfilePhotoScreen({super.key, required this.nextRoute});

  @override
  State<UploadProfilePhotoScreen> createState() => _UploadProfilePhotoScreenState();
}

class _UploadProfilePhotoScreenState extends State<UploadProfilePhotoScreen> {
  bool _uploading = false;
  String? _error;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  Future<void> _pickAndUpload() async {
    HapticFeedback.lightImpact();
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;

    setState(() { _uploading = true; _error = null; });
    try {
      final bytes = await picked.readAsBytes();
      final fileName = picked.name.isEmpty
          ? 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg'
          : picked.name;
      final uri = Uri.parse('$_baseUrl/upload/user-photo');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer ${AuthState.token}';
      request.files.add(http.MultipartFile.fromBytes(
        'photo', bytes, filename: fileName,
        contentType: MediaType('image', 'jpeg'),
      ));
      final response = await http.Response.fromStream(await request.send());
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (response.statusCode == 200 && data['success'] == true) {
        context.go(widget.nextRoute);
      } else {
        throw Exception((data['error'] as Map<String, dynamic>?)?['message'] ?? data['message'] ?? 'Error al subir foto');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 120, height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: GardenColors.primary.withValues(alpha: 0.08),
                      border: Border.all(color: GardenColors.primary.withValues(alpha: 0.4), width: 2),
                    ),
                    child: const Icon(Icons.add_a_photo_outlined, color: GardenColors.primary, size: 44),
                  ),
                  const SizedBox(height: 28),
                  Text('Sube tu foto de perfil', textAlign: TextAlign.center,
                      style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Text(
                    'Los cuidadores necesitan saber a quién le confían tu mascota. '
                    'Una foto real de tu rostro es obligatoria para poder usar GARDEN.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: subtextColor, fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: GardenSpacing.lg, vertical: GardenSpacing.md),
                      decoration: BoxDecoration(
                        color: GardenColors.error.withValues(alpha: 0.08),
                        borderRadius: GardenRadius.md_,
                        border: Border.all(color: GardenColors.error.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: GardenColors.error, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_error!,
                                style: const TextStyle(color: GardenColors.error, fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: GardenButton(
                      label: _uploading ? 'Subiendo...' : 'Elegir foto',
                      loading: _uploading,
                      onPressed: _uploading ? null : _pickAndUpload,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
