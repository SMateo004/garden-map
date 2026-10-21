import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:http/http.dart' as http;
import '../../design/garden_icons.dart';
import '../../services/auth_state.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/garden_loading_indicator.dart';

const _baseUrl = String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

/// Quién paga la comisión de GARDEN en las reservas NUEVAS del cuidador/empresa:
/// el dueño (se suma a su precio, como siempre) o el propio cuidador (el dueño ve
/// su precio sin recargo y la comisión se descuenta de lo que cobra).
class CommissionPayerScreen extends StatefulWidget {
  const CommissionPayerScreen({super.key});

  @override
  State<CommissionPayerScreen> createState() => _CommissionPayerScreenState();
}

class _CommissionPayerScreenState extends State<CommissionPayerScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _payer = 'CLIENT';
  Map<String, num> _pct = const {};
  /// Hasta cuándo no se puede volver a cambiar (un cambio cada 24 h).
  DateTime? _nextChangeAt;

  bool get _locked => _nextChangeAt != null && _nextChangeAt!.isAfter(DateTime.now());

  Map<String, String> get _headers =>
      {'Authorization': 'Bearer ${AuthState.token}', 'Content-Type': 'application/json'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await http.get(Uri.parse('$_baseUrl/caregiver/commission-payer'), headers: _headers);
      final body = jsonDecode(res.body);
      if (!mounted) return;
      if (body['success'] == true) {
        final d = (body['data'] as Map).cast<String, dynamic>();
        setState(() {
          _payer = d['commissionPaidBy'] == 'CAREGIVER' ? 'CAREGIVER' : 'CLIENT';
          _pct = ((d['commissionPct'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, v as num));
          _nextChangeAt = DateTime.tryParse(d['nextChangeAt'] as String? ?? '')?.toLocal();
          _loading = false;
        });
      } else {
        setState(() { _error = body['error']?['message'] ?? 'No se pudo cargar'; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = 'Sin conexión. Intenta de nuevo.'; _loading = false; });
    }
  }

  Future<void> _choose(String payer) async {
    if (_saving || payer == _payer) return;
    if (_locked) {
      GardenErrorDialog.show(context, 'Podrás volver a cambiarlo ${_whenLabel(_nextChangeAt!)}.');
      return;
    }
    final mine = payer == 'CAREGIVER';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(mine ? '¿Pagar tú la comisión?' : '¿Que la pague el dueño?'),
        content: Text(mine
            ? 'Los dueños verán tu precio sin recargo y la comisión de Garden se descontará de lo que cobras. '
                'Vale para las reservas nuevas; las que ya tienes no cambian. Podrás volver a cambiarlo en 24 horas.'
            : 'La comisión volverá a sumarse al precio que ve el dueño. Vale para las reservas nuevas; '
                'las que ya tienes no cambian. Podrás volver a cambiarlo en 24 horas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    HapticFeedback.selectionClick();
    setState(() => _saving = true);
    try {
      final res = await http.put(Uri.parse('$_baseUrl/caregiver/commission-payer'),
          headers: _headers, body: jsonEncode({'commissionPaidBy': payer}));
      final body = jsonDecode(res.body);
      if (!mounted) return;
      if (body['success'] == true) {
        final d = (body['data'] as Map?)?.cast<String, dynamic>();
        setState(() {
          _payer = payer;
          _nextChangeAt = DateTime.tryParse(d?['nextChangeAt'] as String? ?? '')?.toLocal();
        });
        GardenSnackBar.success(context, 'Listo. Aplica a tus reservas nuevas.');
      } else {
        GardenErrorDialog.show(context, body['error']?['message'] ?? 'No se pudo guardar');
      }
    } catch (_) {
      if (mounted) GardenErrorDialog.show(context, 'Sin conexión. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// "mañana a las 14:05" / "hoy a las 21:30".
  String _whenLabel(DateTime d) {
    final now = DateTime.now();
    final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day).difference(today).inDays;
    if (day <= 0) return 'hoy a las $hm';
    if (day == 1) return 'mañana a las $hm';
    return 'el ${d.day}/${d.month} a las $hm';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    // Ejemplo con la comisión real del paseo (o la primera disponible).
    final pct = (_pct['PASEO'] ?? (_pct.values.isNotEmpty ? _pct.values.first : 10)).toDouble();
    final commissionOn100 = (100 * pct / 100).round();

    Widget option(String value, String title, String example) {
      final selected = _payer == value;
      return GestureDetector(
        onTap: _saving ? null : () => _choose(value),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(GardenRadius.xl),
            border: Border.all(color: selected ? GardenColors.primary : border, width: selected ? 2 : 1),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GardenIcon(selected ? GIcon.confirmado : GIcon.cancelado,
                state: selected ? GIconState.active : GIconState.idle,
                color: selected ? GardenColors.primary : sub),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(color: textColor, fontSize: 15.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(example, style: TextStyle(color: sub, fontSize: 13, height: 1.4)),
              ]),
            ),
          ]),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text('Comisión de Garden', style: TextStyle(color: textColor, fontWeight: FontWeight.w800)),
        iconTheme: IconThemeData(color: textColor),
      ),
      body: _loading
          ? const Center(child: GardenLoadingIndicator())
          : _error != null
              ? Center(child: TextButton(onPressed: _load, child: Text('$_error  Reintentar')))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    Text('¿Quién paga la comisión de tus reservas?',
                        style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text('Tu comisión es del ${pct.toStringAsFixed(pct % 1 == 0 ? 0 : 1)} %. '
                        'Ejemplo con un precio tuyo de Bs 100:',
                        style: TextStyle(color: sub, fontSize: 13.5)),
                    const SizedBox(height: 16),
                    option('CLIENT', 'La paga el dueño (como hasta ahora)',
                        'El dueño ve Bs ${100 + commissionOn100} y tú cobras Bs 100.'),
                    option('CAREGIVER', 'La pago yo',
                        'El dueño ve Bs 100 (tu precio, más barato para él) y tú cobras Bs ${100 - commissionOn100}.'),
                    const SizedBox(height: 8),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      GardenIcon(GIcon.info, size: GIconSize.sm, color: sub),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'El cambio vale para tus reservas nuevas. Las reservas que ya tienes mantienen la opción con la que se hicieron. '
                          '${_locked ? 'Podrás volver a cambiarlo ${_whenLabel(_nextChangeAt!)}.' : 'Puedes cambiarlo una vez cada 24 horas.'}',
                          style: TextStyle(color: sub, fontSize: 12.5, height: 1.4),
                        ),
                      ),
                    ]),
                    if (_saving) const Padding(padding: EdgeInsets.only(top: 16), child: Center(child: GardenLoadingIndicator())),
                  ],
                ),
    );
  }
}
