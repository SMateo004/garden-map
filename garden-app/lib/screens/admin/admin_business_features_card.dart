import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../design/garden_icons.dart';
import '../../theme/garden_theme.dart';

/// Funciones del negocio — Admin > Cuidadores > detalle.
///
/// La recepción (clientes que llegan sin la app), el equipo y sus permisos NO vienen
/// activos: el negocio los solicita y SOLO el admin los enciende o apaga, uno por uno
/// (GET/PUT /admin/caregivers/:id/features). El servidor solo devuelve las funciones que
/// aplican a ese tipo de cuenta; si no aplica ninguna (cuidador individual), la tarjeta
/// no se muestra.
class AdminBusinessFeaturesCard extends StatefulWidget {
  final String caregiverProfileId;
  final String adminToken;
  final String baseUrl;
  const AdminBusinessFeaturesCard({
    super.key,
    required this.caregiverProfileId,
    required this.adminToken,
    required this.baseUrl,
  });

  @override
  State<AdminBusinessFeaturesCard> createState() => _AdminBusinessFeaturesCardState();
}

class _AdminBusinessFeaturesCardState extends State<AdminBusinessFeaturesCard> {
  List<Map<String, dynamic>> _features = [];
  bool _loading = true;
  String? _saving;
  String? _error;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${widget.adminToken}',
        'Content-Type': 'application/json',
      };

  Uri get _url => Uri.parse('${widget.baseUrl}/admin/caregivers/${widget.caregiverProfileId}/features');

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _apply(Map<String, dynamic> data) {
    _features = ((data['features'] as List?) ?? const []).cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(_url, headers: _headers);
      final body = jsonDecode(res.body);
      if (!mounted) return;
      if (body['success'] == true) {
        setState(() => _apply((body['data'] as Map).cast<String, dynamic>()));
      } else {
        setState(() => _error = 'No se pudieron leer las funciones del negocio');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudieron leer las funciones del negocio');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _set(Map<String, dynamic> feature, bool enable) async {
    final label = feature['label'] as String? ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(enable ? 'Habilitar "$label"' : 'Deshabilitar "$label"'),
        content: Text(enable
            ? 'Este negocio podrá usar "$label" desde ahora. Hazlo solo si el negocio lo solicitó.'
            : 'El negocio y su equipo dejarán de ver "$label" de inmediato. Los datos que ya cargaron no se borran.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: GardenColors.primary, foregroundColor: Colors.white),
            child: Text(enable ? 'Habilitar' : 'Deshabilitar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final key = feature['key'] as String;
    setState(() => _saving = key);
    try {
      final res = await http.put(_url, headers: _headers, body: jsonEncode({'features': {key: enable}}));
      final body = jsonDecode(res.body);
      if (!mounted) return;
      if (body['success'] == true) {
        setState(() => _apply((body['data'] as Map).cast<String, dynamic>()));
      } else {
        _toast((body['error']?['message'] as String?) ?? 'No se pudo cambiar');
      }
    } catch (_) {
      _toast('No se pudo cambiar');
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: GardenColors.error));
  }

  String? _labelOf(String? key) {
    for (final f in _features) {
      if (f['key'] == key) return f['label'] as String?;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading && _error == null && _features.isEmpty) return const SizedBox.shrink();

    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GardenRadius.lg),
        border: Border.all(color: borderColor),
      ),
      child: _loading
          ? const LinearProgressIndicator()
          : _error != null
              ? Row(children: [
                  Expanded(child: Text(_error!, style: TextStyle(color: subtextColor, fontSize: 13))),
                  TextButton(onPressed: _load, child: const Text('Reintentar')),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    GardenIcon(GIcon.ajustes, size: GIconSize.sm, color: subtextColor),
                    const SizedBox(width: 8),
                    Text('Funciones del negocio',
                        style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 4),
                  Text('Solo se habilitan si el negocio las solicita.',
                      style: TextStyle(color: subtextColor, fontSize: 12)),
                  const SizedBox(height: 6),
                  for (final f in _features) _row(f, textColor, subtextColor),
                ]),
    );
  }

  Widget _row(Map<String, dynamic> f, Color textColor, Color subtextColor) {
    final enabled = f['enabled'] == true;
    final effective = f['effective'] == true;
    final requires = _labelOf(f['requires'] as String?);
    final waiting = enabled && !effective && requires != null;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f['label'] as String? ?? '',
                style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(f['description'] as String? ?? '', style: TextStyle(color: subtextColor, fontSize: 11.5)),
            if (waiting)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('Sin efecto hasta habilitar "$requires".',
                    style: const TextStyle(color: GardenColors.warning, fontSize: 11.5, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
        Switch(
          value: enabled,
          onChanged: _saving != null ? null : (v) => _set(f, v),
        ),
      ]),
    );
  }
}
