import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';
import '../../widgets/garden_loading_indicator.dart';

/// Panel de analítica de producto: cómo usa la gente la app y cómo le va al
/// negocio, por día / semana / mes / año. Todo sale de
/// `GET /admin/analytics/summary` (ver analytics.service.ts): lo de uso viene
/// de sesiones y eventos anónimos; lo de negocio, de las reservas reales.
class AdminAnalyticsScreen extends StatefulWidget {
  final String adminToken;
  const AdminAnalyticsScreen({super.key, required this.adminToken});

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  static const _ranges = [('7d', '7 días'), ('30d', '30 días'), ('90d', '90 días'), ('365d', '1 año')];
  static const _dows = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];
  static const _labels = {
    'PASEO': 'Paseo', 'GUARDERIA': 'Guardería', 'HOSPEDAJE': 'Hospedaje',
    'MORNING': 'Mañana', 'AFTERNOON': 'Tarde', 'NIGHT': 'Noche',
    'SMALL': 'Pequeño', 'MEDIUM': 'Mediano', 'LARGE': 'Grande', 'GIANT': 'Gigante',
    'CLIENT': 'Dueños', 'CAREGIVER': 'Cuidadores', 'GUEST': 'Invitados', 'ADMIN': 'Admin',
    'android': 'Android', 'ios': 'iOS', 'web': 'Web',
    'CLIMA': 'Clima', 'EMERGENCIA_PERSONAL': 'Emergencia personal', 'CAMBIO_DE_PLANES': 'Cambio de planes',
    'PROBLEMA_CON_MASCOTA_O_CUIDADOR': 'Problema con mascota/cuidador', 'OTRO': 'Otro',
    'SIN_MOTIVO': 'Sin motivo', 'SIN_ZONA': 'Sin zona',
  };

  String _range = '30d';
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _d;

  String get _base => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await http.get(
        Uri.parse('$_base/admin/analytics/summary?range=$_range'),
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      ).timeout(const Duration(seconds: 40));
      final body = jsonDecode(r.body);
      if (r.statusCode != 200 || body['success'] != true) throw Exception('Error ${r.statusCode}');
      if (mounted) setState(() { _d = body['data'] as Map<String, dynamic>; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'No se pudo cargar la analítica ($e)'; _loading = false; });
    }
  }

  // ── helpers ──────────────────────────────────────────────────────────
  String _lbl(String k) => _labels[k] ?? k;
  num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;
  List<Map<String, dynamic>> _list(dynamic v) => List<Map<String, dynamic>>.from((v as List?) ?? const []);
  String _fmt(num v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}k' : (v % 1 == 0 ? '${v.toInt()}' : v.toStringAsFixed(1));
  String _bs(num v) => 'Bs ${_fmt(v)}';
  String _dur(num sec) {
    final s = sec.round();
    if (s < 60) return '${s}s';
    return '${s ~/ 60}m ${(s % 60).toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final card = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Row(children: [
          Expanded(
            child: Wrap(spacing: 8, children: [
              for (final (k, label) in _ranges)
                ChoiceChip(
                  label: Text(label),
                  selected: _range == k,
                  onSelected: (_) { setState(() => _range = k); _load(); },
                ),
            ]),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Actualizar'),
        ]),
      ),
      Expanded(
        child: _loading
            ? const Center(child: GardenLoadingIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: TextStyle(color: sub)))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                      children: _sections(text, sub, card),
                    ),
                  ),
      ),
    ]);
  }

  List<Widget> _sections(Color text, Color sub, Color card) {
    final d = _d!;
    final au = d['audience'] as Map<String, dynamic>;
    final us = d['users'] as Map<String, dynamic>;
    final bz = d['business'] as Map<String, dynamic>;
    final pf = d['preferences'] as Map<String, dynamic>;
    final bucket = d['bucket'] as String;

    return [
      _title('Negocio', text),
      _kpis(card, text, sub, [
        ('Reservas creadas', _fmt(_n(bz['bookingsCreated'])), null),
        ('Reservas pagadas', _fmt(_n(bz['bookingsPaid'])), '${bz['paidConversionPct']}% de las creadas'),
        ('Ventas (GMV)', _bs(_n(bz['gmv'])), null),
        ('Comisión Garden', _bs(_n(bz['commission'])), null),
        ('Ticket promedio', _bs(_n(bz['avgTicket'])), null),
        ('Cancelación', '${bz['cancelRatePct']}%', null),
        ('Recompra', '${bz['repeatRatePct']}%', 'clientes con 2+ pagos'),
        ('Promo usada', '${bz['promoUsagePct']}%', 'de las pagadas'),
        ('Propina', '${bz['tipRatePct']}%', 'de las completadas'),
        ('Calificación prom.', '${bz['avgRating']}', null),
        ('Tarda en pagar', '${_n(bz['medianMinutesToPay']).round()} min', 'mediana'),
        ('Reserva con', '${bz['medianLeadDays']} días', 'de anticipación (mediana)'),
        ('Registro → 1ª reserva', '${us['medianHoursSignupToFirstPaidBooking']} h', 'mediana'),
      ]),
      _chart('Reservas pagadas por ${_bucketName(bucket)}', _list(bz['series']), 'paid', card, text, sub, bucket),
      _chart('Ventas (Bs) por ${_bucketName(bucket)}', _list(bz['series']), 'gmv', card, text, sub, bucket),
      _chart('Usuarios nuevos por ${_bucketName(bucket)}', [
        for (final r in _list(us['newSeries']))
          {'bucket': r['bucket'], 'n': _n(r['clients']) + _n(r['caregivers'])}
      ], 'n', card, text, sub, bucket),

      _title('Embudo de reserva', text),
      _funnel(_list(d['funnel']), card, text, sub),
      _title('Retención', text),
      _retention(_list(us['retention']), card, text, sub),

      _title('Uso de la app', text),
      _kpis(card, text, sub, [
        ('Sesiones', _fmt(_n(au['sessions'])), null),
        ('Usuarios activos', _fmt(_n(au['activeUsers'])), '${au['devices']} dispositivos'),
        ('Activos por día', '${au['dauAvg']}', 'promedio (DAU)'),
        ('Activos por mes', _fmt(_n(au['mau'])), '(MAU, 30 días)'),
        ('Adherencia', '${au['stickinessPct']}%', 'DAU / MAU'),
        ('Duración de sesión', _dur(_n(au['avgSessionSec'])), 'mediana ${_dur(_n(au['medianSessionSec']))}'),
        ('Pantallas por sesión', '${au['avgScreensPerSession']}', null),
        ('Rebote', '${au['bounceRate']}%', 'sesiones de 1 pantalla'),
      ]),
      _chart('Sesiones por ${_bucketName(bucket)}', _list(au['series']), 'sessions', card, text, sub, bucket),
      _heat('Cuándo usan la app (sesiones)', _list(au['activityHeat']), card, text, sub),
      _heat('Cuándo reservan', _list(pf['bookingHeat']), card, text, sub),
      _screensTable(_list(d['screens']), card, text, sub),

      _title('Preferencias de los usuarios', text),
      _rank('Servicio más reservado', [for (final r in _list(pf['byService'])) {'key': r['key'], 'n': r['n']}], card, text, sub),
      _rank('Zonas más reservadas', _list(pf['byZone']), card, text, sub),
      _rank('Tamaño de mascota', _list(pf['byPetSize']), card, text, sub),
      _rank('Franja de paseo', _list(pf['byWalkSlot']), card, text, sub),
      _rank('Cómo pagan', _list(pf['byPaymentMethod']), card, text, sub),
      _rank('Motivos de cancelación', _list(pf['cancelReasons']), card, text, sub),
      _filters(_list(pf['filters']), card, text, sub),
      _topCaregivers(_list(d['topCaregivers']), card, text, sub),

      _title('Dispositivos y roles', text),
      _rank('Plataforma', _list(au['platform']), card, text, sub),
      _rank('Versión de la app', _list(au['versions']), card, text, sub),
      _rank('Quién usa la app', _list(au['roles']), card, text, sub),

      _title('Almacenamiento de analítica', text),
      _storage(d['storage'] as Map<String, dynamic>, card, text, sub),
    ];
  }

  String _bucketName(String b) => b == 'day' ? 'día' : (b == 'week' ? 'semana' : 'mes');

  // ── widgets ──────────────────────────────────────────────────────────
  Widget _title(String t, Color text) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 8),
        child: Text(t, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: text)),
      );

  Widget _box(Color card, Widget child) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(14)),
        child: child,
      );

  Widget _kpis(Color card, Color text, Color sub, List<(String, String, String?)> items) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final (label, value, note) in items)
            Container(
              width: 168,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontSize: 12, color: sub)),
                const SizedBox(height: 4),
                Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: text)),
                if (note != null) Text(note, style: TextStyle(fontSize: 11, color: sub)),
              ]),
            ),
        ],
      );

  String _bucketLabel(String raw, String bucket) {
    final p = raw.split('-');
    if (p.length < 3) return raw;
    return bucket == 'month' ? '${p[1]}/${p[0].substring(2)}' : '${p[2]}/${p[1]}';
  }

  Widget _chart(String title, List<Map<String, dynamic>> rows, String field, Color card, Color text, Color sub, String bucket) {
    final max = rows.fold<num>(0, (m, r) => _n(r[field]) > m ? _n(r[field]) : m);
    return _box(
      card,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: text)),
        const SizedBox(height: 10),
        if (rows.isEmpty || max == 0)
          Text('Sin datos en este período', style: TextStyle(color: sub, fontSize: 12))
        else
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final r in rows)
                  Expanded(
                    child: Tooltip(
                      message: '${_bucketLabel('${r['bucket']}', bucket)}: ${_fmt(_n(r[field]))}',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                          Container(
                            height: (_n(r[field]) / max * 100).toDouble().clamp(2, 100),
                            decoration: BoxDecoration(
                              color: GardenColors.primary,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (rows.isNotEmpty && max > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(_bucketLabel('${rows.first['bucket']}', bucket), style: TextStyle(fontSize: 10, color: sub)),
              Text('máx ${_fmt(max)}', style: TextStyle(fontSize: 10, color: sub)),
              Text(_bucketLabel('${rows.last['bucket']}', bucket), style: TextStyle(fontSize: 10, color: sub)),
            ]),
          ),
      ]),
    );
  }

  Widget _funnel(List<Map<String, dynamic>> steps, Color card, Color text, Color sub) {
    final first = steps.isEmpty ? 0 : _n(steps.first['n']);
    return _box(
      card,
      Column(children: [
        for (var i = 0; i < steps.length; i++) ...[
          Builder(builder: (_) {
            final n = _n(steps[i]['n']);
            final prev = i == 0 ? n : _n(steps[i - 1]['n']);
            final ofFirst = first > 0 ? n / first : 0.0;
            final drop = prev > 0 && i > 0 ? '${(n / prev * 100).round()}% del paso anterior' : '';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${steps[i]['step']}', style: TextStyle(color: text, fontSize: 13))),
                  Text(_fmt(n), style: TextStyle(fontWeight: FontWeight.w800, color: text)),
                ]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(value: ofFirst.clamp(0, 1).toDouble(), minHeight: 8,
                      color: GardenColors.primary, backgroundColor: sub.withValues(alpha: 0.15)),
                ),
                if (drop.isNotEmpty) Text(drop, style: TextStyle(fontSize: 11, color: sub)),
              ]),
            );
          }),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Los primeros pasos cuentan sesiones; el último cuenta reservas pagadas.',
              style: TextStyle(fontSize: 11, color: sub)),
        ),
      ]),
    );
  }

  Widget _retention(List<Map<String, dynamic>> rows, Color card, Color text, Color sub) => _box(
        card,
        rows.isEmpty
            ? Text('Aún no hay usuarios con edad suficiente para medir retención.', style: TextStyle(color: sub, fontSize: 12))
            : Row(children: [
                for (final r in rows)
                  Expanded(
                    child: Column(children: [
                      Text('${r['pct']}%', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: text)),
                      Text('Volvieron al día ${r['day']}+', style: TextStyle(fontSize: 11, color: sub)),
                      Text('${r['returned']} de ${r['base']}', style: TextStyle(fontSize: 11, color: sub)),
                    ]),
                  ),
              ]),
      );

  Widget _heat(String title, List<Map<String, dynamic>> cells, Color card, Color text, Color sub) {
    final grid = List.generate(7, (_) => List.filled(24, 0));
    var max = 0;
    for (final c in cells) {
      final v = _n(c['n']).toInt();
      grid[_n(c['dow']).toInt() % 7][_n(c['hour']).toInt() % 24] = v;
      if (v > max) max = v;
    }
    return _box(
      card,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: text)),
        const SizedBox(height: 8),
        if (max == 0)
          Text('Sin datos en este período', style: TextStyle(color: sub, fontSize: 12))
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(children: [
              Row(children: [
                const SizedBox(width: 30),
                for (var h = 0; h < 24; h++)
                  SizedBox(width: 18, child: Text(h % 3 == 0 ? '$h' : '', style: TextStyle(fontSize: 9, color: sub))),
              ]),
              for (var d = 0; d < 7; d++)
                Row(children: [
                  SizedBox(width: 30, child: Text(_dows[d], style: TextStyle(fontSize: 10, color: sub))),
                  for (var h = 0; h < 24; h++)
                    Tooltip(
                      message: '${_dows[d]} $h:00 — ${grid[d][h]}',
                      child: Container(
                        width: 16, height: 16, margin: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: GardenColors.primary.withValues(alpha: grid[d][h] == 0 ? 0.06 : 0.15 + 0.85 * grid[d][h] / max),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                ]),
            ]),
          ),
        Text('Hora de Bolivia', style: TextStyle(fontSize: 10, color: sub)),
      ]),
    );
  }

  Widget _rank(String title, List<Map<String, dynamic>> rows, Color card, Color text, Color sub) {
    final total = rows.fold<num>(0, (s, r) => s + _n(r['n']));
    final max = rows.fold<num>(0, (m, r) => _n(r['n']) > m ? _n(r['n']) : m);
    return _box(
      card,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: text)),
        const SizedBox(height: 8),
        if (rows.isEmpty) Text('Sin datos en este período', style: TextStyle(color: sub, fontSize: 12)),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(width: 130, child: Text(_lbl('${r['key']}'), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: text))),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: max == 0 ? 0 : (_n(r['n']) / max).toDouble(), minHeight: 8,
                      color: GardenColors.primary, backgroundColor: sub.withValues(alpha: 0.12)),
                ),
              ),
              SizedBox(width: 78, child: Text('${_fmt(_n(r['n']))} · ${total == 0 ? 0 : (_n(r['n']) / total * 100).round()}%',
                  textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: sub))),
            ]),
          ),
      ]),
    );
  }

  Widget _filters(List<Map<String, dynamic>> rows, Color card, Color text, Color sub) {
    final byPref = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      byPref.putIfAbsent('${r['pref']}', () => []).add(r);
    }
    final order = byPref.keys.toList()
      ..sort((a, b) => byPref[b]!.fold<num>(0, (s, r) => s + _n(r['n'])).compareTo(byPref[a]!.fold<num>(0, (s, r) => s + _n(r['n']))));
    return _box(
      card,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Qué filtran en el marketplace', style: TextStyle(fontWeight: FontWeight.w700, color: text)),
        const SizedBox(height: 8),
        if (rows.isEmpty) Text('Sin datos en este período', style: TextStyle(color: sub, fontSize: 12)),
        for (final pref in order)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              '${_prefName(pref)}: ${byPref[pref]!.take(5).map((r) => '${_lbl('${r['value']}')} (${r['n']})').join(' · ')}',
              style: TextStyle(fontSize: 12, color: text),
            ),
          ),
      ]),
    );
  }

  String _prefName(String k) => const {
        'service': 'Servicio', 'zone': 'Zona', 'pet_type': 'Tipo de mascota', 'size': 'Tamaño',
        'search': 'Búsqueda por texto', 'verified_only': 'Solo verificados', 'aggressive': 'Acepta agresivos',
        'puppies': 'Acepta cachorros', 'seniors': 'Acepta mayores', 'min_rating': 'Calificación mínima', 'sort': 'Orden',
      }[k] ?? k;

  Widget _screensTable(List<Map<String, dynamic>> rows, Color card, Color text, Color sub) => _box(
        card,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Pantallas más vistas y tiempo en cada una', style: TextStyle(fontWeight: FontWeight.w700, color: text)),
          const SizedBox(height: 8),
          if (rows.isEmpty) Text('Sin datos en este período', style: TextStyle(color: sub, fontSize: 12)),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text('${r['screen']}', style: TextStyle(fontSize: 12, color: text))),
                Text('${_fmt(_n(r['views']))} vistas · ${_dur(_n(r['avgSec']))}', style: TextStyle(fontSize: 11, color: sub)),
              ]),
            ),
        ]),
      );

  Widget _topCaregivers(List<Map<String, dynamic>> rows, Color card, Color text, Color sub) => _box(
        card,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Cuidadores más vistos → reservas', style: TextStyle(fontWeight: FontWeight.w700, color: text)),
          const SizedBox(height: 8),
          if (rows.isEmpty) Text('Sin datos en este período', style: TextStyle(color: sub, fontSize: 12)),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text('${r['name']}', style: TextStyle(fontSize: 12, color: text))),
                Text('${r['views']} vistas → ${r['booked']} reservas (${r['conversionPct']}%)',
                    style: TextStyle(fontSize: 11, color: sub)),
              ]),
            ),
        ]),
      );

  Widget _storage(Map<String, dynamic> s, Color card, Color text, Color sub) {
    final ret = s['retentionDays'] as Map<String, dynamic>;
    return _box(
      card,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final t in _list(s['tables']))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('${t['table']}: ${t['mb']} MB · ${_fmt(_n(t['rows']))} filas', style: TextStyle(fontSize: 12, color: text)),
          ),
        const SizedBox(height: 6),
        Text(
          'Eventos crudos se borran a los ${ret['events']} días y sesiones a los ${ret['sessions']}; '
          'los resúmenes diarios (analytics_daily) se conservan para siempre y pesan casi nada.',
          style: TextStyle(fontSize: 11, color: sub),
        ),
      ]),
    );
  }
}
