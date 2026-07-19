import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/garden_loading_indicator.dart';

/// Los 3 tipos de servicio que aceptan un QR de pago provisional propio
/// (mientras SIP_ENABLED=false) — deben coincidir con el enum ServiceType
/// del backend (prisma/schema.prisma).
const _serviceTypes = [
  ('PASEO', 'Paseo', Icons.directions_walk_rounded),
  ('HOSPEDAJE', 'Hospedaje', Icons.home_rounded),
  ('GUARDERIA', 'Guardería', Icons.pets_rounded),
];

class PaymentQrAdminScreen extends StatefulWidget {
  final String adminToken;
  const PaymentQrAdminScreen({super.key, required this.adminToken});

  @override
  State<PaymentQrAdminScreen> createState() => _PaymentQrAdminScreenState();
}

class _PaymentQrAdminScreenState extends State<PaymentQrAdminScreen> {
  Map<String, String?> _urls = {};
  bool _isLoading = true;
  String? _uploadingServiceType;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  @override
  void initState() {
    super.initState();
    _loadUrls();
  }

  Future<void> _loadUrls() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/admin/payment-qr'),
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        setState(() => _urls = Map<String, String?>.from(data['data'] as Map));
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _pickAndUpload(String serviceType) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;

    setState(() => _uploadingServiceType = serviceType);
    try {
      final bytes = await picked.readAsBytes();
      final fileName = picked.name.isEmpty ? 'qr-$serviceType.jpg' : picked.name;
      final uri = Uri.parse('$_baseUrl/admin/payment-qr/$serviceType');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer ${widget.adminToken}';
      request.files.add(http.MultipartFile.fromBytes(
        'qr', bytes, filename: fileName,
        contentType: MediaType('image', 'jpeg'),
      ));
      final response = await http.Response.fromStream(await request.send());
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (response.statusCode == 200 && data['success'] == true) {
        setState(() => _urls[serviceType] = data['data']['url'] as String?);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('QR actualizado'), backgroundColor: GardenColors.success));
      } else {
        throw Exception(data['error']?['message'] ?? 'Error al subir el QR');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: GardenColors.error));
      }
    } finally {
      if (mounted) setState(() => _uploadingServiceType = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    if (_isLoading) {
      return const Center(child: GardenLoadingIndicator(color: GardenColors.primary));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('QR de pago provisional', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'Estas imágenes se muestran a los clientes mientras el sistema bancario SIP '
            'esté desactivado (SIP_ENABLED=false). Son QR reales que tú administras (ej. de tu '
            'cuenta bancaria), pero NO conectados al banco — nadie confirma el pago automáticamente. '
            'Una vez SIP_ENABLED=true, estas imágenes dejan de usarse por completo.',
            style: TextStyle(color: subtextColor, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 24),
          for (final (serviceType, label, icon) in _serviceTypes) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surfaceEl,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 90, height: 90,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor),
                    ),
                    child: _urls[serviceType] != null && _urls[serviceType]!.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: Image.network(_urls[serviceType]!, fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: GardenColors.error)),
                          )
                        : Icon(Icons.qr_code_2_rounded, color: subtextColor.withValues(alpha: 0.4), size: 36),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(icon, color: GardenColors.primary, size: 18),
                          const SizedBox(width: 6),
                          Text(label, style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700)),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          _urls[serviceType] != null && _urls[serviceType]!.isNotEmpty
                              ? 'QR cargado — los clientes lo ven al reservar este servicio.'
                              : 'Sin QR — los clientes verán un código genérico hasta que subas uno.',
                          style: TextStyle(color: subtextColor, fontSize: 12.5),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _uploadingServiceType == serviceType ? null : () => _pickAndUpload(serviceType),
                          icon: _uploadingServiceType == serviceType
                              ? const GardenLoadingIndicator(size: 14, color: GardenColors.primary)
                              : const Icon(Icons.upload_rounded, size: 16),
                          label: Text(_uploadingServiceType == serviceType
                              ? 'Subiendo...'
                              : (_urls[serviceType] != null && _urls[serviceType]!.isNotEmpty ? 'Reemplazar QR' : 'Subir QR')),
                          style: OutlinedButton.styleFrom(foregroundColor: GardenColors.primary, side: const BorderSide(color: GardenColors.primary)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}
