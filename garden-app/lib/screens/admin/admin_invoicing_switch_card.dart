import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../design/garden_icons.dart';
import '../../services/invoicing_state.dart';
import '../../theme/garden_theme.dart';

/// Interruptor de facturación con NIT — Admin > Comisiones y Admin > Finanzas.
///
/// Apagado (por defecto): antes de pagar, "Datos de facturación" aparece como "Pronto", la app
/// no pide NIT y el backend no lo guarda. Encenderlo solo tiene sentido cuando GARDEN ya emite
/// facturas electrónicas ante el SIN (PUT /admin/pricing/invoicing, con confirmación).
class AdminInvoicingSwitchCard extends StatefulWidget {
  final String adminToken;
  const AdminInvoicingSwitchCard({super.key, required this.adminToken});

  @override
  State<AdminInvoicingSwitchCard> createState() => _AdminInvoicingSwitchCardState();
}

class _AdminInvoicingSwitchCardState extends State<AdminInvoicingSwitchCard> {
  static const _baseUrl = String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  bool? _enabled;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${widget.adminToken}',
        'Content-Type': 'application/json',
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(Uri.parse('$_baseUrl/admin/pricing'), headers: _headers);
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() => _enabled = data['data']['invoicing']?['enabled'] == true);
      } else {
        setState(() => _error = 'No se pudo leer el estado de la facturación');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo leer el estado de la facturación');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _request(bool enable) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(enable ? 'Activar facturación con NIT' : 'Poner la facturación en "Pronto"'),
        content: Text(enable
            ? 'Antes de pagar, la app volverá a pedir NIT o Carnet y razón social, y se guardarán en '
                'cada reserva. Actívala solo cuando GARDEN ya emita facturas electrónicas ante el SIN.'
            : 'Los datos de facturación se verán desactivados con la etiqueta "Pronto" y la app dejará '
                'de pedir NIT antes de pagar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: GardenColors.primary, foregroundColor: Colors.white),
            child: Text(enable ? 'Activar' : 'Poner en "Pronto"'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _saving = true);
    try {
      final res = await http.put(
        Uri.parse('$_baseUrl/admin/pricing/invoicing'),
        headers: _headers,
        body: jsonEncode({'enabled': enable, 'confirm': true}),
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (data['success'] == true) {
        final enabled = data['data']['invoicing']?['enabled'] == true;
        setState(() => _enabled = enabled);
        InvoicingState.active.value = enabled;
        _toast(enabled ? 'Facturación con NIT activada.' : 'Facturación en "Pronto".');
      } else {
        _toast((data['error']?['message'] as String?) ?? 'No se pudo cambiar', error: true);
      }
    } catch (_) {
      _toast('No se pudo cambiar', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? GardenColors.error : GardenColors.success,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final enabled = _enabled == true;
    final accent = enabled ? GardenColors.successDark : GardenColors.warning;
    final status = enabled ? 'Activa — se pide NIT antes de pagar' : 'En "Pronto" — no se pide NIT';
    final detail = enabled
        ? 'El NIT o Carnet se guarda en cada reserva para emitir su factura.'
        : 'Antes de pagar, los datos de facturación se ven desactivados con la etiqueta "Pronto".';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GardenRadius.lg),
        border: Border.all(color: _loading ? borderColor : accent.withValues(alpha: 0.5)),
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
                    GardenIcon(enabled ? GIcon.recibo : GIcon.pausar, size: GIconSize.sm, color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Facturación con NIT',
                          style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                    Switch(value: enabled, onChanged: _saving ? null : (v) => _request(v)),
                  ]),
                  const SizedBox(height: 4),
                  Text(status, style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(detail, style: TextStyle(color: subtextColor, fontSize: 12)),
                ]),
    );
  }
}
