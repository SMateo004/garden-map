import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/garden_theme.dart';
import '../../services/caregiver_crm_service.dart';
import '../../utils/web_file_picker.dart';
import '../../widgets/garden_loading_indicator.dart';

const Map<String, String> _kEventEmoji = {
  'FEEDING': '🍽️', 'WALK': '🚶', 'MEDICATION': '💊', 'BATH': '🛁',
  'NOTE': '📝', 'PHOTO': '📷', 'INCIDENT': '⚠️', 'INCIDENT_RESOLVED': '✅',
};
const Map<String, String> _kEventLabel = {
  'FEEDING': 'Alimentación', 'WALK': 'Paseo interno', 'MEDICATION': 'Medicación', 'BATH': 'Baño',
  'NOTE': 'Nota', 'PHOTO': 'Foto', 'INCIDENT': 'Incidente', 'INCIDENT_RESOLVED': 'Incidente resuelto',
};

/// Detalle de una visita walk-in EN CURSO: bitácora de cuidado (alimentación,
/// paseo, medicación, baño, notas), fotos e incidentes — cada uno dispara (o
/// no) un email al dueño de la mascota según su tipo (ver
/// caregiver-crm.service.ts addVisitEvent). También permite asignar espacio
/// físico y hacer check-out con el monto cobrado.
class WalkInVisitDetailScreen extends StatefulWidget {
  final CaregiverCrmService service;
  final String visitId;
  const WalkInVisitDetailScreen({super.key, required this.service, required this.visitId});

  @override
  State<WalkInVisitDetailScreen> createState() => _WalkInVisitDetailScreenState();
}

class _WalkInVisitDetailScreenState extends State<WalkInVisitDetailScreen> {
  bool _isLoading = true;
  bool _busy = false;
  Map<String, dynamic>? _visit;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final visit = await widget.service.getVisit(widget.visitId);
      if (mounted) setState(() => _visit = visit);
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _elapsed(DateTime since) {
    final diff = DateTime.now().difference(since);
    if (diff.inHours >= 24) return '${diff.inDays}d ${diff.inHours % 24}h';
    if (diff.inHours >= 1) return '${diff.inHours}h ${diff.inMinutes % 60}m';
    return '${diff.inMinutes}m';
  }

  Future<({Uint8List bytes, String name})?> _pickImageBytes() async {
    if (kIsWeb) return pickImageFromWebInput();
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    final name = picked.name.isEmpty ? 'visit_${DateTime.now().millisecondsSinceEpoch}.jpg' : picked.name;
    return (bytes: bytes, name: name);
  }

  Future<void> _addEvent(String type, {bool requirePhoto = false, bool requireNote = false}) async {
    final noteCtrl = TextEditingController();
    String? photoUrl;
    bool uploading = false;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = themeNotifier.isDark;
          final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
          final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
          final surface = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
          final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

          Future<void> pickPhoto() async {
            final img = await _pickImageBytes();
            if (img == null) return;
            setSheetState(() => uploading = true);
            try {
              final url = await widget.service.uploadPetPhoto(img.bytes, img.name);
              setSheetState(() {
                photoUrl = url;
                uploading = false;
              });
            } catch (e) {
              setSheetState(() => uploading = false);
              if (ctx.mounted) GardenSnackBar.error(ctx, e.toString().replaceFirst('Exception: ', ''));
            }
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_kEventEmoji[type]} ${_kEventLabel[type]}', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w800)),
                  if (type == 'PHOTO')
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Se le avisa al dueño por email si dejó su correo.', style: TextStyle(color: subtextColor, fontSize: 12)),
                    ),
                  if (type == 'INCIDENT')
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Se notifica al dueño (tono tranquilo) y queda registrado para el equipo Garden.', style: TextStyle(color: GardenColors.warning, fontSize: 12)),
                    ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: noteCtrl,
                    style: TextStyle(color: textColor),
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: requireNote ? 'Describí qué pasó *' : 'Nota (opcional)',
                      hintStyle: TextStyle(color: subtextColor, fontSize: 13),
                      filled: true,
                      fillColor: surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                    ),
                  ),
                  if (type == 'PHOTO' || type == 'INCIDENT') ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: uploading ? null : pickPhoto,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: GardenColors.primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: GardenColors.primary.withValues(alpha: 0.3)),
                        ),
                        child: uploading
                            ? const Padding(padding: EdgeInsets.all(24), child: GardenLoadingIndicator(color: GardenColors.primary))
                            : photoUrl != null
                                ? ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(fixImageUrl(photoUrl!), fit: BoxFit.cover))
                                : const Icon(Icons.add_a_photo_outlined, color: GardenColors.primary, size: 26),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: GardenButton(
                      label: 'Registrar',
                      onPressed: () {
                        if (requirePhoto && photoUrl == null) {
                          GardenSnackBar.warning(ctx, 'Agregá una foto');
                          return;
                        }
                        if (requireNote && noteCtrl.text.trim().isEmpty) {
                          GardenSnackBar.warning(ctx, 'Describí qué pasó');
                          return;
                        }
                        Navigator.pop(ctx, true);
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.service.addVisitEvent(widget.visitId, type: type, note: noteCtrl.text.trim(), photoUrl: photoUrl);
      if (mounted) GardenSnackBar.success(context, 'Registrado');
      await _load();
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editSpace() async {
    final ctrl = TextEditingController(text: _visit?['spaceLabel'] as String? ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Espacio asignado'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'Ej: Jaula 4')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (saved != true) return;
    try {
      await widget.service.updateVisit(widget.visitId, {'spaceLabel': ctrl.text.trim()});
      await _load();
    } catch (e) {
      if (mounted) GardenSnackBar.error(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _checkOut() async {
    final amountCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Check-out'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('¿Cuánto cobraste en efectivo? (opcional — solo para tu registro, no pasa por Garden)'),
            const SizedBox(height: 10),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(hintText: 'Bs 0.00'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar check-out')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final amount = double.tryParse(amountCtrl.text.trim());
      await widget.service.checkOut(widget.visitId, amountCollected: amount);
      if (mounted) {
        GardenSnackBar.success(context, 'Check-out registrado');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
        final surface = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
        final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
        final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

        final v = _visit;
        final pet = v?['walkInPet'] as Map<String, dynamic>?;
        final client = pet?['walkInClient'] as Map<String, dynamic>?;
        final events = (v?['events'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final reversedEvents = events.reversed.toList();

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            elevation: 0,
            iconTheme: IconThemeData(color: textColor),
            title: Text(pet?['name'] as String? ?? 'Visita', style: TextStyle(color: textColor, fontWeight: FontWeight.w800)),
          ),
          floatingActionButton: v == null
              ? null
              : FloatingActionButton.extended(
                  onPressed: _busy ? null : _checkOut,
                  backgroundColor: GardenColors.error,
                  icon: const Icon(Icons.logout_rounded, color: Colors.white),
                  label: const Text('Check-out', style: TextStyle(color: Colors.white)),
                ),
          body: _isLoading
              ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
              : v == null
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: borderColor)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${client?['name'] ?? '—'}', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text('${v['serviceType']} · hace ${_elapsed(DateTime.parse(v['checkedInAt'] as String))}', style: TextStyle(color: subtextColor, fontSize: 12.5)),
                              const SizedBox(height: 10),
                              InkWell(
                                onTap: _editSpace,
                                child: Row(children: [
                                  const Icon(Icons.meeting_room_outlined, size: 16, color: GardenColors.primary),
                                  const SizedBox(width: 6),
                                  Text(
                                    (v['spaceLabel'] as String?)?.isNotEmpty == true ? v['spaceLabel'] as String : 'Asignar espacio (ej. Jaula 4)',
                                    style: const TextStyle(color: GardenColors.primary, fontSize: 12.5, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.edit_outlined, size: 13, color: GardenColors.primary),
                                ]),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text('Bitácora', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final t in ['FEEDING', 'WALK', 'MEDICATION', 'BATH', 'NOTE', 'PHOTO', 'INCIDENT'])
                              OutlinedButton(
                                onPressed: _busy ? null : () => _addEvent(t, requirePhoto: t == 'PHOTO', requireNote: t == 'INCIDENT'),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: t == 'INCIDENT' ? GardenColors.warning : borderColor),
                                  foregroundColor: t == 'INCIDENT' ? GardenColors.warning : textColor,
                                ),
                                child: Text('${_kEventEmoji[t]} ${_kEventLabel[t]}'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (reversedEvents.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text('Todavía no hay registros en esta visita.', style: TextStyle(color: subtextColor, fontSize: 13)),
                          )
                        else
                          for (final e in reversedEvents)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: e['type'] == 'INCIDENT' ? GardenColors.warning.withValues(alpha: 0.4) : borderColor),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_kEventEmoji[e['type']] ?? '📝', style: const TextStyle(fontSize: 20)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          Text(_kEventLabel[e['type']] ?? e['type'] as String, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w700)),
                                          const SizedBox(width: 8),
                                          Text(_fmtTime(e['at'] as String), style: TextStyle(color: subtextColor, fontSize: 11)),
                                        ]),
                                        if ((e['note'] as String?)?.isNotEmpty == true) ...[
                                          const SizedBox(height: 3),
                                          Text(e['note'] as String, style: TextStyle(color: textColor, fontSize: 12.5)),
                                        ],
                                        if ((e['photoUrl'] as String?)?.isNotEmpty == true) ...[
                                          const SizedBox(height: 6),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.network(fixImageUrl(e['photoUrl'] as String), width: 90, height: 90, fit: BoxFit.cover),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                      ],
                    ),
        );
      },
    );
  }

  String _fmtTime(String iso) {
    final d = DateTime.parse(iso).toLocal();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
