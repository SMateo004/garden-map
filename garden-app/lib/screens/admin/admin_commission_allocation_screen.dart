import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../design/garden_icons.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/garden_loading_indicator.dart';

/// Admin > Comisiones > Distribución.
///
/// A dónde va cada boliviano de comisión de GARDEN: sueldos, mantenimiento, activos,
/// fondo de garantía (emergencias veterinarias hasta Bs 2.000 por caso), otros gastos
/// e inversores. El plan suma 100 % y se versiona en el backend: cambiarlo hoy no
/// reescribe lo ya asignado (ver commission-allocation.service.ts).
///
/// Los gastos reales de cada destino se registran aquí; disponible = asignado − gastado.
/// Es contabilidad de gestión: no mueve dinero de ninguna billetera.
class AdminCommissionAllocationScreen extends StatefulWidget {
  final String adminToken;
  const AdminCommissionAllocationScreen({super.key, required this.adminToken});

  @override
  State<AdminCommissionAllocationScreen> createState() => _AdminCommissionAllocationScreenState();
}

class _BucketStyle {
  final GIcon icon;
  final Color color;
  const _BucketStyle(this.icon, this.color);
}

const _bucketStyles = <String, _BucketStyle>{
  'SUELDOS': _BucketStyle(GIcon.equipo, GardenColors.primary),
  'MANTENIMIENTO': _BucketStyle(GIcon.herramientas, GardenColors.info),
  'ACTIVOS': _BucketStyle(GIcon.computadora, GardenColors.polygon),
  'FONDO_GARANTIA': _BucketStyle(GIcon.pagoProtegido, GardenColors.forest),
  'OTROS': _BucketStyle(GIcon.categoria, GardenColors.orange),
  'INVERSORES': _BucketStyle(GIcon.estadisticas, GardenColors.warning),
};

_BucketStyle _styleOf(String key) => _bucketStyles[key] ?? const _BucketStyle(GIcon.categoria, GardenColors.primary);

class _AdminCommissionAllocationScreenState extends State<AdminCommissionAllocationScreen> {
  static const _baseUrl = String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');
  static const _periods = {'month': 'Este mes', 'year': 'Este año', 'all': 'Todo'};

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${widget.adminToken}',
        'Content-Type': 'application/json',
      };

  bool _loading = true;
  bool _saving = false;
  String _period = 'month';
  Map<String, dynamic>? _data;

  final Map<String, TextEditingController> _pctCtl = {};
  final _noteCtl = TextEditingController();
  final _capCtl = TextEditingController();
  final _targetCtl = TextEditingController();
  final _simCtl = TextEditingController(text: '10000');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _pctCtl.values) {
      c.dispose();
    }
    _noteCtl.dispose();
    _capCtl.dispose();
    _targetCtl.dispose();
    _simCtl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _buckets =>
      ((_data?['buckets'] as List?) ?? const []).cast<Map<String, dynamic>>();

  String _num(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  String _bs(num v) {
    final neg = v < 0;
    final abs = v.abs();
    final parts = abs.toStringAsFixed(2).split('.');
    final int_ = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
    final dec = parts[1] == '00' ? '' : ',${parts[1]}';
    return '${neg ? '−' : ''}Bs $int_$dec';
  }

  double? _parse(String raw) => double.tryParse(raw.trim().replaceAll(',', '.'));

  /// Suma del plan en el formulario, en centésimas (evita errores de coma flotante).
  int get _sumCents {
    var total = 0;
    for (final c in _pctCtl.values) {
      total += ((_parse(c.text) ?? 0) * 100).round();
    }
    return total;
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? GardenColors.error : GardenColors.success,
    ));
  }

  void _apply(Map<String, dynamic> data) {
    _data = data;
    for (final b in _buckets) {
      final key = b['key'] as String;
      final ctl = _pctCtl.putIfAbsent(key, () => TextEditingController());
      ctl.text = _num(b['pct'] as num);
    }
    final fund = data['fund'] as Map<String, dynamic>;
    _capCtl.text = _num(fund['claimCapBs'] as num);
    _targetCtl.text = _num(fund['targetCases'] as num);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/admin/pricing/allocation').replace(queryParameters: {'period': _period}),
        headers: _headers,
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() => _apply(data['data'] as Map<String, dynamic>));
      } else {
        _toast('No se pudo cargar la distribución', error: true);
      }
    } catch (_) {
      _toast('No se pudo cargar la distribución', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _savePlan() async {
    final allocation = <String, double>{};
    for (final e in _pctCtl.entries) {
      final v = _parse(e.value.text);
      if (v == null || v < 0 || v > 100) {
        _toast('Cada porcentaje debe estar entre 0 y 100', error: true);
        return;
      }
      allocation[e.key] = v;
    }
    if (_sumCents != 10000) {
      _toast('El plan debe sumar 100 % (hoy suma ${_num(_sumCents / 100)} %)', error: true);
      return;
    }
    final cap = int.tryParse(_capCtl.text.trim());
    final target = int.tryParse(_targetCtl.text.trim());
    if (cap == null || cap < 100) {
      _toast('El tope por caso del fondo debe ser al menos Bs 100', error: true);
      return;
    }
    if (target == null || target < 1 || target > 100) {
      _toast('La meta del fondo debe ser de 1 a 100 casos', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await http.put(
        Uri.parse('$_baseUrl/admin/pricing/allocation'),
        headers: _headers,
        body: jsonEncode({
          'allocation': allocation,
          if (_noteCtl.text.trim().isNotEmpty) 'note': _noteCtl.text.trim(),
          'fundClaimCapBs': cap,
          'fundTargetCases': target,
        }),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        _noteCtl.clear();
        _toast('Plan guardado. Rige desde ahora; lo ya asignado no cambia.');
        await _load();
      } else {
        _toast((data['error']?['message'] as String?) ?? 'No se pudo guardar', error: true);
      }
    } catch (_) {
      _toast('No se pudo guardar', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openMovementDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _MovementDialog(buckets: _buckets),
    );
    if (result == null) return;
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/admin/pricing/allocation/movements'),
        headers: _headers,
        body: jsonEncode(result),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        _toast('Gasto registrado');
        await _load();
      } else {
        _toast((data['error']?['message'] as String?) ?? 'No se pudo registrar', error: true);
      }
    } catch (_) {
      _toast('No se pudo registrar', error: true);
    }
  }

  Future<void> _deleteMovement(Map<String, dynamic> m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anular gasto'),
        content: Text('“${m['description']}” por ${_bs(m['amount'] as num)}. '
            'Queda registrado en la auditoría.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Anular')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/admin/pricing/allocation/movements/${m['id']}'),
        headers: _headers,
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        _toast('Gasto anulado');
        await _load();
      } else {
        _toast('No se pudo anular', error: true);
      }
    } catch (_) {
      _toast('No se pudo anular', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    if (_loading && _data == null) {
      return const Center(child: GardenLoadingIndicator(color: GardenColors.primary));
    }
    if (_data == null) {
      return Center(
        child: TextButton(onPressed: _load, child: const Text('Reintentar')),
      );
    }

    final plan = _data!['plan'] as Map<String, dynamic>;
    final fund = _data!['fund'] as Map<String, dynamic>;
    final monthly = ((_data!['monthly'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final movements = ((_data!['movements'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final history = ((_data!['history'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final labelOf = {for (final b in _buckets) b['key'] as String: b['label'] as String};

    Widget card(List<Widget> children) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(GardenRadius.lg),
            border: Border.all(color: borderColor),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        );

    Widget title(String t, [String? sub]) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w800)),
            if (sub != null) ...[
              const SizedBox(height: 3),
              Text(sub, style: TextStyle(color: subtextColor, fontSize: 12)),
            ],
          ]),
        );

    final sumOk = _sumCents == 10000;
    final simAmount = _parse(_simCtl.text) ?? 0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Distribución de la comisión',
              style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'Cada boliviano de comisión cobrada (reservas completadas) se reparte entre estos destinos. '
            'Cambiar el plan rige desde ahora: lo ya asignado conserva el plan con el que se asignó.',
            style: TextStyle(color: subtextColor, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in _periods.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _period == e.key,
                onSelected: (_) {
                  setState(() => _period = e.key);
                  _load();
                },
              ),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _kpi('Comisión cobrada · ${_periods[_period]!.toLowerCase()}',
                _bs(_data!['commissionCollectedPeriod'] as num), GardenColors.primary, surface, borderColor, textColor, subtextColor),
            _kpi('Comisión cobrada · histórico', _bs(_data!['commissionCollectedAllTime'] as num),
                GardenColors.forest, surface, borderColor, textColor, subtextColor),
            _kpi('Fondo de garantía disponible', _bs(fund['available'] as num), GardenColors.forest, surface,
                borderColor, textColor, subtextColor),
          ]),
          const SizedBox(height: 16),

          // ── Plan ───────────────────────────────────────────────────────
          card([
            title('Plan de distribución',
                plan['isDefault'] == true
                    ? 'Plan sugerido (todavía no guardado). Ajústalo y guárdalo para empezar a registrarlo.'
                    : 'Vigente desde ${_date(plan['effectiveFrom'] as String)}${plan['note'] != null ? ' · ${plan['note']}' : ''}.'),
            _stackedBar({for (final e in _pctCtl.entries) e.key: _parse(e.value.text) ?? 0}, 12),
            const SizedBox(height: 14),
            for (final b in _buckets)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: _styleOf(b['key'] as String).color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(GardenRadius.sm),
                    ),
                    child: GardenIcon(_styleOf(b['key'] as String).icon,
                        size: GIconSize.sm, color: _styleOf(b['key'] as String).color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b['label'] as String,
                          style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13.5)),
                      Text(b['description'] as String, style: TextStyle(color: subtextColor, fontSize: 11.5)),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 86,
                    child: TextField(
                      controller: _pctCtl[b['key']],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(suffixText: '%', isDense: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ]),
              ),
            Row(children: [
              GardenIcon(sumOk ? GIcon.hecho : GIcon.advertencia,
                  size: GIconSize.sm, color: sumOk ? GardenColors.successDark : GardenColors.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  sumOk ? 'Suma 100 %' : 'Suma ${_num(_sumCents / 100)} % — debe sumar 100 %',
                  style: TextStyle(
                      color: sumOk ? GardenColors.successDark : GardenColors.error,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Text('Fondo de garantía', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(spacing: 14, runSpacing: 12, children: [
              SizedBox(
                width: 170,
                child: TextField(
                  controller: _capCtl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Tope por caso', prefixText: 'Bs ', isDense: true),
                ),
              ),
              SizedBox(
                width: 170,
                child: TextField(
                  controller: _targetCtl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Meta: casos cubiertos', isDense: true),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtl,
              maxLength: 300,
              decoration: const InputDecoration(
                  labelText: 'Motivo del cambio (opcional)', hintText: 'Ej. contratamos soporte', isDense: true),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: (_saving || !sumOk) ? null : _savePlan,
                style: ElevatedButton.styleFrom(backgroundColor: GardenColors.primary, foregroundColor: Colors.white),
                child: Text(_saving ? 'Guardando…' : 'Guardar plan'),
              ),
            ),
          ]),

          // ── Fondo de garantía ───────────────────────────────────────────
          card([
            title('Fondo de garantía',
                'Cubre emergencias veterinarias durante un servicio, hasta ${_bs(fund['claimCapBs'] as num)} por caso. '
                'Se alimenta con su % de la comisión y baja con cada caso pagado.'),
            Row(children: [
              Expanded(
                child: Text(_bs(fund['available'] as num),
                    style: TextStyle(
                        color: (fund['available'] as num) < 0 ? GardenColors.error : textColor,
                        fontSize: 22,
                        fontWeight: FontWeight.w900)),
              ),
              Text('${fund['casesCovered']} de ${fund['targetCases']} casos cubiertos',
                  style: TextStyle(color: subtextColor, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(GardenRadius.full),
              child: LinearProgressIndicator(
                value: ((fund['progressPct'] as num).toDouble() / 100).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: borderColor,
                color: GardenColors.forest,
              ),
            ),
            const SizedBox(height: 6),
            Text('Meta: ${_bs(fund['targetAmount'] as num)}',
                style: TextStyle(color: subtextColor, fontSize: 11.5)),
            if ((fund['casesCovered'] as num) < 1) ...[
              const SizedBox(height: 10),
              const Text(
                'Hoy el fondo no alcanza para cubrir un caso completo. Si ocurre una emergencia, '
                'la diferencia sale de otros destinos.',
                style: TextStyle(color: GardenColors.error, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ]),

          // ── Estado por destino ───────────────────────────────────────────
          card([
            title('Asignado, gastado y disponible',
                'Asignado y gastado: ${_periods[_period]!.toLowerCase()}. Disponible: acumulado histórico. '
                'Un disponible negativo significa que ese destino gastó más de lo que la comisión le dio.'),
            for (final b in _buckets) _bucketRow(b, textColor, subtextColor, borderColor),
          ]),

          // ── Simulador ─────────────────────────────────────────────────
          card([
            title('Simulador', 'Cuánto recibe cada destino con el plan del formulario (aunque no esté guardado).'),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _simCtl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Comisión del mes', prefixText: 'Bs ', isDense: true),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 12),
            for (final b in _buckets)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(
                    color: _styleOf(b['key'] as String).color, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(b['label'] as String, style: TextStyle(color: subtextColor, fontSize: 13))),
                  Text(_bs(simAmount * (_parse(_pctCtl[b['key']]?.text ?? '') ?? 0) / 100),
                      style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
              ),
          ]),

          // ── Últimos 6 meses ───────────────────────────────────────────
          card([
            title('Últimos 6 meses', 'Comisión de cada mes repartida con el plan que regía en ese momento.'),
            for (final m in monthly)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${m['month']}', style: TextStyle(color: subtextColor, fontSize: 12))),
                    Text(_bs(m['commission'] as num),
                        style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 12.5)),
                  ]),
                  const SizedBox(height: 4),
                  (m['commission'] as num) > 0
                      ? _stackedBar((m['allocated'] as Map).cast<String, num>(), 8)
                      : Container(height: 8, decoration: BoxDecoration(
                          color: borderColor, borderRadius: BorderRadius.circular(GardenRadius.full))),
                ]),
              ),
            Wrap(spacing: 12, runSpacing: 6, children: [
              for (final b in _buckets)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(
                    color: _styleOf(b['key'] as String).color, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text(b['label'] as String, style: TextStyle(color: subtextColor, fontSize: 11)),
                ]),
            ]),
          ]),

          // ── Gastos reales ───────────────────────────────────────────────
          card([
            Row(children: [
              Expanded(
                child: title('Gastos registrados',
                    'Sueldos pagados, servidores, casos del fondo, dividendos… Bajan el disponible de su destino.'),
              ),
              ElevatedButton.icon(
                onPressed: _openMovementDialog,
                icon: const GardenIcon(GIcon.agregar, size: GIconSize.sm, color: Colors.white),
                label: const Text('Registrar'),
                style: ElevatedButton.styleFrom(backgroundColor: GardenColors.primary, foregroundColor: Colors.white),
              ),
            ]),
            if (movements.isEmpty)
              Text('Todavía no hay gastos registrados.', style: TextStyle(color: subtextColor, fontSize: 13))
            else
              for (final m in movements)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(GardenRadius.md),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(children: [
                    GardenIcon(_styleOf(m['bucket'] as String).icon,
                        size: GIconSize.sm, color: _styleOf(m['bucket'] as String).color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m['description'] as String,
                            style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13)),
                        Text('${labelOf[m['bucket']] ?? m['bucket']} · ${_date(m['occurredAt'] as String)}',
                            style: TextStyle(color: subtextColor, fontSize: 11.5)),
                      ]),
                    ),
                    Text(_bs(m['amount'] as num),
                        style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 13.5)),
                    IconButton(
                      tooltip: 'Anular',
                      icon: const GardenIcon(GIcon.eliminar),
                      onPressed: () => _deleteMovement(m),
                    ),
                  ]),
                ),
          ]),

          // ── Historial del plan ───────────────────────────────────────────
          if (history.isNotEmpty)
            card([
              title('Historial del plan', 'Cada cambio queda como una versión nueva.'),
              for (final h in history)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Desde ${_date(h['effectiveFrom'] as String)}${h['note'] != null ? ' · ${h['note']}' : ''}',
                        style: TextStyle(color: textColor, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    _stackedBar((h['allocation'] as Map).cast<String, num>(), 6),
                    const SizedBox(height: 3),
                    Text(
                      [
                        for (final b in _buckets)
                          '${b['label']} ${_num(((h['allocation'] as Map)[b['key']] as num?) ?? 0)}%'
                      ].join(' · '),
                      style: TextStyle(color: subtextColor, fontSize: 11),
                    ),
                  ]),
                ),
            ]),
        ],
      ),
    );
  }

  String _date(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  Widget _stackedBar(Map<String, num> parts, double height) {
    final keys = _buckets.map((b) => b['key'] as String).where((k) => (parts[k] ?? 0) > 0).toList();
    if (keys.isEmpty) return SizedBox(height: height);
    return ClipRRect(
      borderRadius: BorderRadius.circular(GardenRadius.full),
      child: Row(children: [
        for (final k in keys)
          Flexible(
            flex: ((parts[k] ?? 0) * 100).round().clamp(1, 1 << 30),
            child: Container(height: height, color: _styleOf(k).color),
          ),
      ]),
    );
  }

  Widget _kpi(String label, String value, Color color, Color surface, Color borderColor, Color textColor,
      Color subtextColor) {
    return Container(
      constraints: const BoxConstraints(minWidth: 200),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GardenRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(color: subtextColor, fontSize: 11.5)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  Widget _bucketRow(Map<String, dynamic> b, Color textColor, Color subtextColor, Color borderColor) {
    final style = _styleOf(b['key'] as String);
    final available = b['available'] as num;
    Widget cell(String label, num v, {bool strong = false, Color? color}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(label, style: TextStyle(color: subtextColor, fontSize: 10.5)),
            Text(_bs(v),
                style: TextStyle(
                    color: color ?? textColor, fontSize: 12.5, fontWeight: strong ? FontWeight.w800 : FontWeight.w600)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: borderColor, width: 0.5))),
      child: Row(children: [
        GardenIcon(style.icon, size: GIconSize.sm, color: style.color),
        const SizedBox(width: 8),
        SizedBox(
          width: 118,
          child: Text('${b['label']} · ${_num(b['pct'] as num)}%',
              style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ),
        cell('Asignado', b['allocatedPeriod'] as num),
        cell('Gastado', b['spentPeriod'] as num),
        cell('Disponible', available, strong: true, color: available < 0 ? GardenColors.error : null),
      ]),
    );
  }
}

/// Registrar un gasto real de un destino.
class _MovementDialog extends StatefulWidget {
  final List<Map<String, dynamic>> buckets;
  const _MovementDialog({required this.buckets});

  @override
  State<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends State<_MovementDialog> {
  final _amountCtl = TextEditingController();
  final _descCtl = TextEditingController();
  final _bookingCtl = TextEditingController();
  late String _bucket = (widget.buckets.isNotEmpty ? widget.buckets.first['key'] as String : 'SUELDOS');
  DateTime _date = DateTime.now();
  bool _isAdjustment = false;
  String? _error;

  static final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);

  @override
  void dispose() {
    _amountCtl.dispose();
    _descCtl.dispose();
    _bookingCtl.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amountCtl.text.trim().replaceAll(',', '.'));
    if (amount == null || amount <= 0 || amount > 1000000) {
      setState(() => _error = 'Escribe un monto mayor a 0');
      return;
    }
    if (((amount * 100) - (amount * 100).round()).abs() > 1e-6) {
      setState(() => _error = 'Máximo 2 decimales');
      return;
    }
    if (_descCtl.text.trim().length < 3) {
      setState(() => _error = 'Describe el gasto');
      return;
    }
    final booking = _bookingCtl.text.trim();
    if (booking.isNotEmpty && !_uuid.hasMatch(booking)) {
      setState(() => _error = 'El ID de reserva no es válido');
      return;
    }
    Navigator.pop(context, {
      'bucket': _bucket,
      'amount': _isAdjustment ? -amount : amount,
      'description': _descCtl.text.trim(),
      'occurredAt': DateTime(_date.year, _date.month, _date.day, 12).toUtc().toIso8601String(),
      if (booking.isNotEmpty) 'bookingId': booking,
    });
  }

  @override
  Widget build(BuildContext context) {
    final isFund = _bucket == 'FONDO_GARANTIA';
    return AlertDialog(
      title: const Text('Registrar gasto'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            DropdownButtonFormField<String>(
              initialValue: _bucket,
              isDense: true,
              decoration: const InputDecoration(labelText: 'Destino', isDense: true),
              items: [
                for (final b in widget.buckets)
                  DropdownMenuItem(value: b['key'] as String, child: Text(b['label'] as String)),
              ],
              onChanged: (v) => setState(() => _bucket = v ?? _bucket),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amountCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto', prefixText: 'Bs ', isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descCtl,
              maxLength: 300,
              decoration: InputDecoration(
                labelText: 'Descripción',
                hintText: isFund ? 'Ej. emergencia veterinaria de Toby' : 'Ej. sueldo soporte octubre',
                isDense: true,
              ),
            ),
            if (isFund)
              TextField(
                controller: _bookingCtl,
                decoration: const InputDecoration(labelText: 'ID de la reserva (opcional)', isDense: true),
              ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: Text('Fecha: ${_date.day}/${_date.month}/${_date.year}')),
              TextButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
                child: const Text('Cambiar'),
              ),
            ]),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _isAdjustment,
              title: const Text('Es una devolución / ajuste a favor del destino'),
              onChanged: (v) => setState(() => _isAdjustment = v ?? false),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_error!, style: const TextStyle(color: GardenColors.error, fontSize: 12.5)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(backgroundColor: GardenColors.primary, foregroundColor: Colors.white),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
