import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';

class AdminIdentityReviewScreen extends StatefulWidget {
  final String sessionId;
  const AdminIdentityReviewScreen({super.key, required this.sessionId});

  @override
  State<AdminIdentityReviewScreen> createState() => _AdminIdentityReviewScreenState();
}

class _AdminIdentityReviewScreenState extends State<AdminIdentityReviewScreen> {
  Map<String, dynamic>? _session;
  bool _loading = true;
  String? _error;
  String _adminToken = '';
  int _selectedImageIndex = 0;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api');

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _adminToken = prefs.getString('access_token') ?? '';
    await _loadSession();
  }

  Future<void> _loadSession() async {
    setState(() { _loading = true; _error = null; });
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/admin/identity-reviews/${widget.sessionId}'),
        headers: {'Authorization': 'Bearer $_adminToken'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() { _session = data['data'] as Map<String, dynamic>; _loading = false; });
      } else {
        setState(() { _error = data['error']?['message'] ?? 'Error al cargar la sesión'; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _approve() async {
    final confirm = await _confirmDialog('Aprobar verificación', '¿Confirmas que la identidad es válida y auténtica?', GardenColors.success);
    if (confirm != true) return;
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/admin/verifications/${widget.sessionId}/approve'),
        headers: {'Authorization': 'Bearer $_adminToken'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Identidad aprobada'), backgroundColor: GardenColors.success));
          await _loadSession();
        }
      } else {
        throw Exception(data['error']?['message'] ?? 'Error');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: GardenColors.error));
    }
  }

  Future<void> _reject() async {
    final confirm = await _confirmDialog('Rechazar verificación', '¿Confirmas que la identidad NO es válida o detectas fraude?', GardenColors.error);
    if (confirm != true) return;
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/admin/verifications/${widget.sessionId}/reject'),
        headers: {'Authorization': 'Bearer $_adminToken'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Identidad rechazada'), backgroundColor: GardenColors.error));
          await _loadSession();
        }
      } else {
        throw Exception(data['error']?['message'] ?? 'Error');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: GardenColors.error));
    }
  }

  Future<bool?> _confirmDialog(String title, String message, Color color) => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: color),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Confirmar', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : const Color(0xFFF7F8FA);
    final surface = isDark ? GardenColors.darkSurface : Colors.white;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) => Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: surface,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: textColor),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Verificación de Identidad', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: GardenColors.primary)),
              if (_session != null)
                Text(_sessionId(), style: TextStyle(fontSize: 10, color: subtextColor, fontFamily: 'monospace')),
            ],
          ),
          actions: [
            if (_session != null && _canAct())
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _statusChip(_session!['status'] as String? ?? ''),
              ),
          ],
        ),
        body: _loading
          ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
          : _error != null
            ? _buildError()
            : _buildContent(surface, bg, textColor, subtextColor, borderColor),
      ),
    );
  }

  String _sessionId() {
    final id = _session?['id'] as String? ?? widget.sessionId;
    return id.length > 20 ? '${id.substring(0, 20)}…' : id;
  }

  bool _canAct() {
    final status = _session?['status'] as String? ?? '';
    return status == 'REVIEW' || status == 'PENDING';
  }

  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline_rounded, size: 48, color: GardenColors.error),
        const SizedBox(height: 16),
        Text(_error!, style: const TextStyle(color: GardenColors.error), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        ElevatedButton.icon(onPressed: _loadSession, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
      ]),
    ),
  );

  Widget _buildContent(Color surface, Color bg, Color textColor, Color subtextColor, Color borderColor) {
    final s = _session!;
    final user = s['user'] as Map<String, dynamic>? ?? {};
    final profile = (user['caregiverProfile'] as Map<String, dynamic>?) ?? {};
    final ocr = s['ocrData'] as Map<String, dynamic>?;
    final deviceDetails = s['deviceDetails'] as Map<String, dynamic>?;
    final locationData = s['locationData'] as Map<String, dynamic>?;
    final status = s['status'] as String? ?? '';

    // Collect all images
    final images = <_ImageItem>[];
    if (s['selfieUrlSigned'] != null) images.add(_ImageItem('Selfie', s['selfieUrlSigned'] as String, Icons.face_rounded, GardenColors.primary));
    if (s['ciFrontUrlSigned'] != null) images.add(_ImageItem('CI Anverso', s['ciFrontUrlSigned'] as String, Icons.credit_card_rounded, Colors.teal));
    if (s['ciBackUrlSigned'] != null) images.add(_ImageItem('CI Reverso', s['ciBackUrlSigned'] as String, Icons.credit_card_outlined, Colors.teal));
    if (s['faceCroppedSelfieUrlSigned'] != null) images.add(_ImageItem('Cara (selfie)', s['faceCroppedSelfieUrlSigned'] as String, Icons.face_retouching_natural_rounded, Colors.indigo));
    if (s['faceCroppedDocumentUrlSigned'] != null) images.add(_ImageItem('Cara (documento)', s['faceCroppedDocumentUrlSigned'] as String, Icons.face_retouching_natural_outlined, Colors.indigo));

    final livenessFrames = (s['livenessFrameUrlsSigned'] as List?)?.cast<String>() ?? [];
    for (var i = 0; i < livenessFrames.length; i++) {
      images.add(_ImageItem('Liveness ${i + 1}', livenessFrames[i], Icons.videocam_outlined, Colors.orange));
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // ── USER INFO ──
              _card(borderColor, surface, child: Row(children: [
                GardenAvatar(
                  imageUrl: user['profilePicture'] as String?,
                  size: 56,
                  initials: (user['firstName'] as String? ?? 'U')[0],
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim(),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: textColor)),
                  Text(user['email'] as String? ?? '—', style: TextStyle(color: subtextColor, fontSize: 12)),
                  if ((user['phone'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 2),
                    Row(children: [
                      const Icon(Icons.phone_rounded, size: 12, color: GardenColors.primary),
                      const SizedBox(width: 4),
                      Text(user['phone'] as String, style: const TextStyle(color: GardenColors.primary, fontSize: 12)),
                    ]),
                  ],
                  if ((profile['ciNumber'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 2),
                    Row(children: [
                      const Icon(Icons.badge_outlined, size: 12, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text('CI: ${profile['ciNumber']}', style: TextStyle(color: subtextColor, fontSize: 11)),
                    ]),
                  ],
                ])),
                _statusChip(status),
              ])),

              const SizedBox(height: 12),

              // ── SCORES ──
              _sectionTitle('SCORES DE VERIFICACIÓN', Icons.analytics_outlined),
              _card(borderColor, surface, child: Column(children: [
                _scoreBar('Similitud facial', _toNum(s['similarityScore'] ?? s['similarity']), subtextColor),
                _scoreBar('Liveness (vida real)', _toNum(s['livenessScore']), subtextColor),
                _scoreBar('Confianza documento', _toNum(s['documentConfidence']), subtextColor),
                _scoreBar('Score de identidad', _toNum(s['identityScore']), subtextColor),
                _scoreBar('Score facial', _toNum(s['faceScore']), subtextColor),
                _scoreBar('Score OCR', _toNum(s['ocrScore']), subtextColor),
                _scoreBar('Score documento', _toNum(s['docScore']), subtextColor),
                _scoreBar('Calidad', _toNum(s['qualityScore']), subtextColor),
                _scoreBar('Comportamiento', _toNum(s['behaviorScore']), subtextColor),
                _scoreBar('Confianza total (trust)', _toNum(s['trustScore']), subtextColor),
              ])),

              const SizedBox(height: 12),

              // ── PHOTOS ──
              if (images.isNotEmpty) ...[
                _sectionTitle('DOCUMENTOS Y FOTOS', Icons.photo_library_outlined),
                // Thumbnail selector
                SizedBox(
                  height: 60,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: images.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final img = images[i];
                      final selected = _selectedImageIndex == i;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedImageIndex = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: selected ? img.color.withValues(alpha: 0.15) : surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: selected ? img.color : borderColor, width: selected ? 2 : 1),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(img.icon, size: 14, color: selected ? img.color : subtextColor),
                            const SizedBox(width: 5),
                            Text(img.label, style: TextStyle(
                              fontSize: 11, fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                              color: selected ? img.color : subtextColor,
                            )),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                // Main image viewer
                _buildImageViewer(images[_selectedImageIndex.clamp(0, images.length - 1)], borderColor, surface, subtextColor),
                const SizedBox(height: 12),
              ],

              // ── OCR DATA ──
              if (ocr != null && ocr.isNotEmpty) ...[
                _sectionTitle('DATOS EXTRAÍDOS DEL CI (OCR)', Icons.document_scanner_outlined),
                _card(borderColor, surface, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: ocr.entries.where((e) => e.value != null).map((e) =>
                    _dataRow(e.key, e.value.toString(), textColor, subtextColor)
                  ).toList(),
                )),
                const SizedBox(height: 12),
              ],

              // ── DATES ──
              _sectionTitle('FECHAS Y REVISIÓN', Icons.schedule_outlined),
              _card(borderColor, surface, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (s['createdAt'] != null) _dataRow('Iniciada', _formatDate(s['createdAt'] as String), textColor, subtextColor),
                if (s['completedAt'] != null) _dataRow('Completada', _formatDate(s['completedAt'] as String), textColor, subtextColor),
                if (s['reviewedAt'] != null) _dataRow('Revisada', _formatDate(s['reviewedAt'] as String), textColor, subtextColor),
                if (s['reviewedBy'] != null) _dataRow('Revisada por', s['reviewedBy'] as String, textColor, subtextColor),
              ])),
              const SizedBox(height: 12),

              // ── SECURITY ──
              if (s['ipAddress'] != null || s['userAgent'] != null || deviceDetails != null || locationData != null) ...[
                _sectionTitle('SEGURIDAD Y DISPOSITIVO', Icons.security_outlined),
                _card(borderColor, surface, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (s['ipAddress'] != null) ...[
                    _dataRow('IP Address', s['ipAddress'] as String, textColor, subtextColor),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: s['ipAddress'] as String));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('IP copiada'), duration: Duration(seconds: 1)));
                      },
                      child: const Row(children: [
                        Icon(Icons.copy_rounded, size: 12, color: GardenColors.primary),
                        SizedBox(width: 4),
                        Text('Copiar IP', style: TextStyle(color: GardenColors.primary, fontSize: 11)),
                      ]),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (locationData != null) ...[
                    _dataRow('País', locationData['country'] as String? ?? '—', textColor, subtextColor),
                    if (locationData['city'] != null) _dataRow('Ciudad', locationData['city'] as String, textColor, subtextColor),
                    if (locationData['region'] != null) _dataRow('Región', locationData['region'] as String, textColor, subtextColor),
                    if (locationData['isp'] != null) _dataRow('ISP', locationData['isp'] as String, textColor, subtextColor),
                    const SizedBox(height: 4),
                  ],
                  if (s['userAgent'] != null) ...[
                    const Text('USER AGENT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                    const SizedBox(height: 4),
                    Text(s['userAgent'] as String, style: TextStyle(fontSize: 11, color: subtextColor, height: 1.4)),
                    const SizedBox(height: 8),
                  ],
                  if (deviceDetails != null) ...[
                    const Text('DISPOSITIVO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                    const SizedBox(height: 4),
                    ...deviceDetails.entries.where((e) => e.value != null).map((e) =>
                      _dataRow(e.key, e.value.toString(), textColor, subtextColor)
                    ),
                  ],
                  if (s['deviceFingerprint'] != null) ...[
                    const SizedBox(height: 4),
                    _dataRow('Device Fingerprint', (s['deviceFingerprint'] as String).length > 30
                      ? '${(s['deviceFingerprint'] as String).substring(0, 30)}…'
                      : s['deviceFingerprint'] as String, textColor, subtextColor),
                  ],
                ])),
                const SizedBox(height: 12),
              ],

              // ── SESSION ID ──
              _card(borderColor, surface, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('IDENTIFICADOR DE SESIÓN', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: Text(s['id'] as String? ?? '—',
                    style: TextStyle(fontSize: 11, color: subtextColor, fontFamily: 'monospace'))),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 16, color: GardenColors.primary),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: s['id'] as String? ?? ''));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ID copiado'), duration: Duration(seconds: 1)));
                    },
                    padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                  ),
                ]),
              ])),

              const SizedBox(height: 80), // Space for bottom bar
            ]),
          ),
        ),

        // ── BOTTOM ACTION BAR ──
        Container(
          color: surface,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          child: _canAct()
            ? Row(children: [
                Expanded(child: GardenButton(
                  label: 'Aprobar identidad',
                  icon: Icons.verified_rounded,
                  height: 48,
                  color: GardenColors.success,
                  onPressed: _approve,
                )),
                const SizedBox(width: 12),
                Expanded(child: GardenButton(
                  label: 'Rechazar',
                  icon: Icons.cancel_outlined,
                  height: 48,
                  color: GardenColors.error,
                  outline: true,
                  onPressed: _reject,
                )),
              ])
            : Row(children: [
                Expanded(child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _statusColor(status).withValues(alpha: 0.4)),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(_statusIcon(status), color: _statusColor(status), size: 20),
                    const SizedBox(width: 8),
                    Text(_statusLabel(status),
                      style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.bold, fontSize: 15)),
                  ]),
                )),
              ]),
        ),
      ],
    );
  }

  Widget _buildImageViewer(_ImageItem img, Color borderColor, Color surface, Color subtextColor) {
    return Container(
      height: 340,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.network(
                img.url,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const CircularProgressIndicator(color: GardenColors.primary),
                    const SizedBox(height: 8),
                    Text('Cargando imagen…', style: TextStyle(color: subtextColor, fontSize: 12)),
                  ]));
                },
                errorBuilder: (_, __, ___) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.broken_image_outlined, size: 48, color: subtextColor),
                  const SizedBox(height: 8),
                  Text('No se pudo cargar', style: TextStyle(color: subtextColor, fontSize: 12)),
                ])),
              ),
            ),
            Positioned(
              bottom: 10, left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: img.color.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(img.icon, size: 13, color: Colors.white),
                  const SizedBox(width: 5),
                  Text(img.label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(Color borderColor, Color surface, {required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: borderColor),
    ),
    child: child,
  );

  Widget _sectionTitle(String title, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Icon(icon, size: 14, color: GardenColors.primary),
      const SizedBox(width: 6),
      Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: GardenColors.primary, letterSpacing: 1)),
    ]),
  );

  Widget _dataRow(String label, String value, Color textColor, Color subtextColor) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 130,
        child: Text(label, style: TextStyle(fontSize: 11, color: subtextColor, fontWeight: FontWeight.w600)),
      ),
      Expanded(child: Text(value, style: TextStyle(fontSize: 12, color: textColor))),
    ]),
  );

  Widget _scoreBar(String label, num? score, Color subtextColor) {
    if (score == null) return const SizedBox.shrink();
    final pct = score.clamp(0, 100).toDouble();
    Color color;
    if (pct >= 80) {
      color = GardenColors.success;
    } else if (pct >= 60) color = GardenColors.warning;
    else color = GardenColors.error;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(fontSize: 12, color: subtextColor)),
          Text('${pct.toStringAsFixed(1)}%',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct / 100,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
      ]),
    );
  }

  Widget _statusChip(String status) {
    final color = _statusColor(status);
    final label = _statusLabel(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Color _statusColor(String s) => switch (s) {
    'VERIFIED' || 'APPROVED' => GardenColors.success,
    'REJECTED'               => GardenColors.error,
    'REVIEW'                 => GardenColors.warning,
    'PENDING'                => Colors.orange,
    _                        => Colors.grey,
  };

  String _statusLabel(String s) => switch (s) {
    'VERIFIED' || 'APPROVED' => 'Aprobada',
    'REJECTED'               => 'Rechazada',
    'REVIEW'                 => 'En revisión',
    'PENDING'                => 'Pendiente',
    _                        => s,
  };

  IconData _statusIcon(String s) => switch (s) {
    'VERIFIED' || 'APPROVED' => Icons.verified_rounded,
    'REJECTED'               => Icons.cancel_rounded,
    'REVIEW'                 => Icons.hourglass_top_rounded,
    _                        => Icons.info_outline_rounded,
  };

  num? _toNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return iso.substring(0, 10); }
  }
}

class _ImageItem {
  final String label;
  final String url;
  final IconData icon;
  final Color color;
  const _ImageItem(this.label, this.url, this.icon, this.color);
}
