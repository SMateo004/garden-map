import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../design/garden_icons.dart';
import '../../services/taxes_state.dart';
import '../../theme/garden_theme.dart';

/// Interruptor de impuestos (IVA + IT) — Admin > Comisiones y Admin > Finanzas.
///
/// Es la ÚNICA condición para cobrar impuestos (no depende de la configuración del
/// servidor). Mientras está en pausa GARDEN cobra solo su comisión (que el cliente no ve) y
/// la app no menciona impuestos. Aprobarlos suma la tasa a las reservas nuevas; pausarlos
/// quita el impuesto de las reservas que todavía no se pagaron. Ambos cambios piden
/// confirmación explícita (PUT /admin/pricing/taxes).
class AdminTaxesSwitchCard extends StatefulWidget {
  final String adminToken;
  /// Se llama después de un cambio, para que la pantalla que lo contiene recargue.
  final VoidCallback? onChanged;
  const AdminTaxesSwitchCard({super.key, required this.adminToken, this.onChanged});

  @override
  State<AdminTaxesSwitchCard> createState() => _AdminTaxesSwitchCardState();
}

class _AdminTaxesSwitchCardState extends State<AdminTaxesSwitchCard> {
  static const _baseUrl = String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  Map<String, dynamic>? _taxes;
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
        setState(() => _taxes = (data['data']['taxes'] as Map).cast<String, dynamic>());
      } else {
        setState(() => _error = 'No se pudo leer el estado de los impuestos');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo leer el estado de los impuestos');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _pct(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  Future<void> _request(bool enable) async {
    final rate = _pct((_taxes?['configuredRatePct'] as num?) ?? 16);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(enable ? 'Aprobar cobro de impuestos' : 'Poner impuestos en pausa'),
        content: Text(enable
            ? 'Desde ahora las reservas NUEVAS sumarán $rate % de impuestos (IVA + IT) al total, '
                'y la app los mostrará en el detalle de pago. Las reservas ya creadas mantienen su precio.'
            : 'Se dejará de cobrar impuestos: las reservas nuevas cobrarán solo el precio del servicio '
                '(con la comisión de GARDEN incluida) y la app no mencionará impuestos. A las reservas '
                'que todavía no se pagaron se les quita el impuesto.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Rechazar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: GardenColors.primary, foregroundColor: Colors.white),
            child: Text(enable ? 'Aprobar' : 'Pausar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _saving = true);
    try {
      final res = await http.put(
        Uri.parse('$_baseUrl/admin/pricing/taxes'),
        headers: _headers,
        body: jsonEncode({'enabled': enable, 'confirm': true}),
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (data['success'] == true) {
        final taxes = (data['data']['taxes'] as Map).cast<String, dynamic>();
        final adjusted = (data['data']['unpaidBookingsAdjusted'] as Map?)?.cast<String, dynamic>();
        setState(() => _taxes = taxes);
        TaxesState.active.value = taxes['active'] == true;
        final n = (adjusted?['bookings'] as num?)?.toInt() ?? 0;
        _toast(enable
            ? 'Impuestos aprobados. Aplican a las reservas nuevas.'
            : n > 0
                ? 'Impuestos en pausa. Se quitó el impuesto de $n reserva${n == 1 ? '' : 's'} sin pagar.'
                : 'Impuestos en pausa.');
        widget.onChanged?.call();
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

    final taxes = _taxes;
    final enabled = taxes?['enabled'] == true;
    final active = taxes?['active'] == true;
    final rate = _pct((taxes?['configuredRatePct'] as num?) ?? 16);
    final accent = active ? GardenColors.successDark : GardenColors.warning;

    final status = active ? 'Activos — se cobra $rate % (IVA + IT)' : 'En pausa — pendiente de tu aprobación';
    final detail = active
        ? 'Las reservas nuevas suman $rate % al total y el cliente lo ve en el detalle de pago.'
        : 'No se cobran impuestos ni se mencionan en la app: GARDEN cobra solo su comisión. '
            'Al aprobar, las reservas nuevas sumarán $rate % (IVA + IT).';

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
                    GardenIcon(active ? GIcon.recibo : GIcon.pausar, size: GIconSize.sm, color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Impuestos (IVA + IT)',
                          style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                    Switch(
                      value: enabled,
                      onChanged: _saving ? null : (v) => _request(v),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(status, style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(detail, style: TextStyle(color: subtextColor, fontSize: 12)),
                ]),
    );
  }
}
