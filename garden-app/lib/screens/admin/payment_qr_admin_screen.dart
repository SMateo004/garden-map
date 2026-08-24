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

const double _kAmountRowHeight = 62.0;

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

  // ── QR por monto exacto (Bs 15-1000) ──────────────────────────────────────
  Map<int, String> _amountUrls = {};
  int _minAmount = 15;
  int _maxAmount = 1000;
  bool _isLoadingAmounts = true;
  int? _uploadingAmount;
  int? _deletingAmount;
  final TextEditingController _jumpController = TextEditingController();
  final ScrollController _amountScrollController = ScrollController();

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  @override
  void initState() {
    super.initState();
    _loadUrls();
    _loadAmountUrls();
  }

  @override
  void dispose() {
    _jumpController.dispose();
    _amountScrollController.dispose();
    super.dispose();
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

  Future<void> _loadAmountUrls() async {
    setState(() => _isLoadingAmounts = true);
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/admin/payment-qr-by-amount'),
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        final body = data['data'] as Map<String, dynamic>;
        final rawUrls = Map<String, dynamic>.from(body['urls'] as Map);
        setState(() {
          _minAmount = body['min'] as int? ?? 15;
          _maxAmount = body['max'] as int? ?? 1000;
          _amountUrls = rawUrls.map((k, v) => MapEntry(int.parse(k), v as String));
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingAmounts = false);
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
        GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _uploadingServiceType = null);
    }
  }

  Future<void> _pickAndUploadAmount(int amount) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;

    setState(() => _uploadingAmount = amount);
    try {
      final bytes = await picked.readAsBytes();
      final fileName = picked.name.isEmpty ? 'qr-bs$amount.jpg' : picked.name;
      final uri = Uri.parse('$_baseUrl/admin/payment-qr-by-amount/$amount');
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
        setState(() => _amountUrls[amount] = data['data']['url'] as String);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('QR de Bs $amount actualizado'), backgroundColor: GardenColors.success));
      } else {
        throw Exception(data['error']?['message'] ?? 'Error al subir el QR');
      }
    } catch (e) {
      if (mounted) {
        GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _uploadingAmount = null);
    }
  }

  Future<void> _deleteAmountQr(int amount) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Quitar este QR?'),
        content: Text('Bs $amount volverá a usar el QR genérico del tipo de servicio hasta que subas otro.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: GardenColors.error),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _deletingAmount = amount);
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/admin/payment-qr-by-amount/$amount'),
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (res.statusCode == 200 && data['success'] == true) {
        setState(() => _amountUrls.remove(amount));
      } else {
        throw Exception(data['error']?['message'] ?? 'Error al quitar el QR');
      }
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _deletingAmount = null);
    }
  }

  void _jumpToAmount() {
    final parsed = int.tryParse(_jumpController.text.trim());
    if (parsed == null) return;
    final clamped = parsed.clamp(_minAmount, _maxAmount);
    final index = clamped - _minAmount;
    if (!_amountScrollController.hasClients) return;
    final target = (index * _kAmountRowHeight).clamp(
      0.0,
      _amountScrollController.position.maxScrollExtent,
    );
    _amountScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
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
                              ? 'QR cargado — respaldo genérico si el monto exacto no tiene uno propio.'
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

          const SizedBox(height: 12),
          Divider(color: borderColor),
          const SizedBox(height: 20),

          Text('QR por monto exacto', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'Más preciso que el QR genérico: uno distinto para cada boliviano entre '
            'Bs $_minAmount y Bs $_maxAmount, con el monto ya "impreso" en el código. Si una '
            'reserva cae en un monto sin QR subido, se usa el QR genérico del servicio de arriba.',
            style: TextStyle(color: subtextColor, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),

          if (_isLoadingAmounts)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: GardenLoadingIndicator(color: GardenColors.primary)),
            )
          else ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: GardenColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_amountUrls.length} de ${_maxAmount - _minAmount + 1} montos con QR',
                    style: const TextStyle(color: GardenColors.primary, fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: _jumpController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: textColor, fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Ir a Bs...',
                      hintStyle: TextStyle(color: subtextColor, fontSize: 13),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
                    ),
                    onSubmitted: (_) => _jumpToAmount(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _jumpToAmount,
                  icon: const Icon(Icons.search_rounded),
                  color: GardenColors.primary,
                  tooltip: 'Ir al monto',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 480,
              decoration: BoxDecoration(
                color: surfaceEl,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: ListView.builder(
                controller: _amountScrollController,
                itemExtent: _kAmountRowHeight,
                itemCount: _maxAmount - _minAmount + 1,
                itemBuilder: (context, index) {
                  final amount = _minAmount + index;
                  final url = _amountUrls[amount];
                  final hasQr = url != null && url.isNotEmpty;
                  final isUploading = _uploadingAmount == amount;
                  final isDeleting = _deletingAmount == amount;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: borderColor.withValues(alpha: 0.5))),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: borderColor),
                          ),
                          child: hasQr
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(7),
                                  child: Image.network(url, fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, size: 16, color: GardenColors.error)),
                                )
                              : Icon(Icons.qr_code_2_rounded, color: subtextColor.withValues(alpha: 0.35), size: 18),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 64,
                          child: Text('Bs $amount', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                        ),
                        Expanded(
                          child: Text(
                            hasQr ? 'Cargado' : 'Sin QR',
                            style: TextStyle(
                              color: hasQr ? GardenColors.success : subtextColor.withValues(alpha: 0.6),
                              fontSize: 12.5,
                              fontWeight: hasQr ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (hasQr)
                          IconButton(
                            onPressed: isDeleting ? null : () => _deleteAmountQr(amount),
                            icon: isDeleting
                                ? const GardenLoadingIndicator(size: 14, color: GardenColors.error)
                                : const Icon(Icons.delete_outline_rounded, size: 18),
                            color: GardenColors.error,
                            tooltip: 'Quitar QR',
                            visualDensity: VisualDensity.compact,
                          ),
                        IconButton(
                          onPressed: isUploading ? null : () => _pickAndUploadAmount(amount),
                          icon: isUploading
                              ? const GardenLoadingIndicator(size: 14, color: GardenColors.primary)
                              : Icon(hasQr ? Icons.autorenew_rounded : Icons.upload_rounded, size: 18),
                          color: GardenColors.primary,
                          tooltip: hasQr ? 'Reemplazar' : 'Subir QR',
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
