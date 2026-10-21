import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:http/http.dart' as http;
import '../../design/garden_icons.dart';
import '../../services/auth_state.dart';
import '../../theme/garden_motion.dart';
import '../../theme/garden_theme.dart';
import '../../utils/premium_price.dart';
import '../../widgets/garden_loading_indicator.dart';

const _baseUrl = String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

/// Garden Premium: el cuidador o la empresa elige cuántas semanas quiere aparecer
/// primero en el marketplace con la insignia "Destacado", ve el precio al instante y
/// paga con QR (como una reserva, sin billetera). El precio lo cobra el servidor con
/// la tabla del admin; acá solo se muestra.
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _data;
  List<PremiumPricePoint> _table = const [];
  int _weeks = 1;
  Timer? _poll;

  Map<String, String> get _headers =>
      {'Authorization': 'Bearer ${AuthState.token}', 'Content-Type': 'application/json'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final res = await http.get(Uri.parse('$_baseUrl/caregiver/premium'), headers: _headers);
      final body = jsonDecode(res.body);
      if (!mounted) return;
      if (body['success'] != true) {
        setState(() { _error = body['error']?['message'] ?? 'No se pudo cargar Premium'; _loading = false; });
        return;
      }
      final data = (body['data'] as Map).cast<String, dynamic>();
      final table = PremiumPricePoint.listFrom(data['priceTable']);
      setState(() {
        _data = data;
        _table = table;
        final maxW = maxPremiumWeeks(table);
        if (maxW > 0) _weeks = _weeks.clamp(1, maxW);
        _loading = false;
      });
      _syncPolling();
    } catch (_) {
      if (mounted) setState(() { _error = 'Sin conexión. Desliza para reintentar.'; _loading = false; });
    }
  }

  /// Mientras se verifica un pago, vuelve a preguntar cada 30 s para mostrar la
  /// activación sin que el cuidador tenga que refrescar.
  void _syncPolling() {
    final open = _data?['openPurchase'] as Map?;
    final waiting = open != null && open['status'] == 'PAYMENT_PENDING_APPROVAL';
    if (waiting && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 30), (_) => _load(silent: true));
    } else if (!waiting) {
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<Map<String, dynamic>?> _post(String path, [Map<String, dynamic>? body]) async {
    setState(() => _busy = true);
    try {
      final res = await http.post(Uri.parse('$_baseUrl$path'), headers: _headers, body: jsonEncode(body ?? {}));
      final data = jsonDecode(res.body);
      if (data['success'] == true) return (data['data'] as Map?)?.cast<String, dynamic>() ?? {};
      if (mounted) GardenErrorDialog.show(context, data['error']?['message'] ?? 'No se pudo completar');
    } catch (_) {
      if (mounted) GardenErrorDialog.show(context, 'Sin conexión. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return null;
  }

  Future<void> _buy() async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    final r = await _post('/caregiver/premium/purchases', {'weeks': _weeks});
    if (r != null) await _load(silent: true);
  }

  Future<void> _declare(String id, num amount) async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Ya pagaste?'),
        content: Text('Confirma solo si ya transferiste Bs ${amount.toStringAsFixed(0)} con el QR. '
            'Verificaremos el depósito y activaremos tu Premium.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Todavía no')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, ya pagué')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await _post('/caregiver/premium/purchases/$id/declared');
    if (r != null) await _load(silent: true);
  }

  Future<void> _cancel(String id) async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar este pago?'),
        content: const Text('Si ya transferiste, NO lo canceles: toca "Ya realicé el pago".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancelar pago')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await _post('/caregiver/premium/purchases/$id/cancel');
    if (r != null) await _load(silent: true);
  }

  static String _date(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text('Garden Premium', style: TextStyle(color: textColor, fontWeight: FontWeight.w800)),
        iconTheme: IconThemeData(color: textColor),
      ),
      body: _loading
          ? const Center(child: GardenLoadingIndicator())
          : _error != null
              ? _errorView(sub)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      _statusCard(textColor, sub, surface, border),
                      const SizedBox(height: 16),
                      _mainSection(textColor, sub, surface, border),
                      const SizedBox(height: 20),
                      _benefits(textColor, sub),
                      _history(textColor, sub, surface, border),
                    ],
                  ),
                ),
    );
  }

  Widget _errorView(Color sub) => ListView(children: [
        const SizedBox(height: 120),
        Center(child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: sub))),
        const SizedBox(height: 12),
        Center(child: TextButton(onPressed: _load, child: const Text('Reintentar'))),
      ]);

  Widget _card(Color surface, Color border, Widget child, {Color? accent}) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(GardenRadius.xl),
          border: Border.all(color: accent ?? border, width: accent != null ? 1.5 : 1),
        ),
        child: child,
      );

  Widget _statusCard(Color textColor, Color sub, Color surface, Color border) {
    final active = _data?['active'] == true;
    final until = _date(_data?['premiumUntil'] as String?);
    return _card(
      surface,
      border,
      Row(children: [
        GardenIcon(GIcon.estrella, size: GIconSize.lg, state: active ? GIconState.active : GIconState.idle,
            color: active ? GardenColors.warning : sub),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(active ? 'Eres Destacado' : 'Todavía no eres Premium',
                style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(
              active
                  ? 'Apareces primero en el marketplace hasta el $until. Lo que compres ahora se suma después de esa fecha.'
                  : 'Aparece primero en el marketplace, con la insignia "Destacado".',
              style: TextStyle(color: sub, fontSize: 13, height: 1.35),
            ),
          ]),
        ),
      ]),
      accent: active ? GardenColors.warning.withValues(alpha: 0.6) : null,
    );
  }

  Widget _mainSection(Color textColor, Color sub, Color surface, Color border) {
    final open = (_data?['openPurchase'] as Map?)?.cast<String, dynamic>();
    if (open != null) return _openPurchase(open, textColor, sub, surface, border);
    if (_data?['enabled'] != true || _table.isEmpty) {
      return _card(surface, border,
          Text('Premium no está disponible por ahora. Vuelve a revisar pronto.', style: TextStyle(color: sub, fontSize: 14)));
    }
    if (_data?['canBuy'] != true) {
      return _card(surface, border,
          Text('Tu perfil debe estar aprobado y activo para hacerte Premium.', style: TextStyle(color: sub, fontSize: 14)));
    }
    return _picker(textColor, sub, surface, border);
  }

  Widget _picker(Color textColor, Color sub, Color surface, Color border) {
    final maxW = maxPremiumWeeks(_table);
    final price = premiumPriceForWeeks(_table, _weeks);
    final perWeek = price == null ? null : price / _weeks;
    final start = (_data?['active'] == true) ? DateTime.tryParse(_data?['premiumUntil'] as String? ?? '')?.toLocal() : null;
    final ends = (start ?? DateTime.now()).add(Duration(days: 7 * _weeks));
    final quick = <int>[1, 2, 4, 12, 26, 52].where((w) => w <= maxW).toList();

    return _card(
      surface,
      border,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('¿Por cuánto tiempo?', style: TextStyle(color: sub, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: GardenMotion.resolve(context, GardenMotion.quick),
          child: Text(premiumDurationLabel(_weeks),
              key: ValueKey(_weeks), style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w900)),
        ),
        if (maxW > 1)
          Slider(
            value: _weeks.toDouble(),
            min: 1,
            max: maxW.toDouble(),
            divisions: maxW - 1,
            label: premiumDurationLabel(_weeks),
            activeColor: GardenColors.primary,
            onChanged: _busy ? null : (v) {
              final w = v.round();
              if (w != _weeks) {
                HapticFeedback.selectionClick();
                setState(() => _weeks = w);
              }
            },
          ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final w in quick)
            ChoiceChip(
              label: Text(w == 52 ? '1 año' : w == 1 ? '1 sem' : '$w sem'),
              selected: _weeks == w,
              onSelected: _busy ? null : (_) => setState(() => _weeks = w),
              selectedColor: GardenColors.primary.withValues(alpha: 0.18),
            ),
        ]),
        const SizedBox(height: 18),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Total', style: TextStyle(color: sub, fontSize: 12, fontWeight: FontWeight.w700)),
              AnimatedSwitcher(
                duration: GardenMotion.resolve(context, GardenMotion.quick),
                child: Text(price == null ? '—' : 'Bs $price',
                    key: ValueKey(price), style: TextStyle(color: textColor, fontSize: 30, fontWeight: FontWeight.w900)),
              ),
              if (perWeek != null && _weeks > 1)
                Text('Bs ${perWeek.toStringAsFixed(1)} por semana', style: TextStyle(color: sub, fontSize: 12.5)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Termina', style: TextStyle(color: sub, fontSize: 12, fontWeight: FontWeight.w700)),
            Text(_date(ends.toIso8601String()), style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w800)),
          ]),
        ]),
        const SizedBox(height: 16),
        GardenButton(
          label: price == null ? 'Elige una duración' : 'Pagar Bs $price con QR',
          gIcon: GIcon.pagarQr,
          loading: _busy,
          onPressed: price == null || _busy ? null : _buy,
        ),
        const SizedBox(height: 8),
        Text('Se paga solo con QR bancario (no con la billetera).', style: TextStyle(color: sub, fontSize: 12)),
      ]),
    );
  }

  Widget _qrImage(String? url) {
    if (url == null || url.isEmpty) return const SizedBox(height: 0);
    Widget img;
    if (url.startsWith('data:') && url.contains(',')) {
      try {
        img = Image.memory(base64Decode(url.split(',').last), width: 230, height: 230, fit: BoxFit.contain);
      } catch (_) {
        img = const SizedBox(height: 0);
      }
    } else {
      img = Image.network(url, width: 230, height: 230, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const SizedBox(width: 230, height: 60, child: Center(child: Text('No se pudo mostrar el QR'))));
    }
    return Center(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(GardenRadius.lg)),
        child: img,
      ),
    );
  }

  Widget _openPurchase(Map<String, dynamic> p, Color textColor, Color sub, Color surface, Color border) {
    final amount = (p['amount'] as num?) ?? 0;
    final weeks = (p['weeks'] as num?)?.toInt() ?? 1;
    final id = p['id'] as String;
    if (p['status'] == 'PAYMENT_PENDING_APPROVAL') {
      return _card(
        surface,
        border,
        Row(children: [
          const GardenIcon(GIcon.esperando, size: GIconSize.lg, color: GardenColors.warning),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Estamos verificando tu pago de Bs ${amount.toStringAsFixed(0)} (${premiumDurationLabel(weeks)}). '
              'Te avisamos apenas se active.',
              style: TextStyle(color: textColor, fontSize: 14, height: 1.4),
            ),
          ),
        ]),
        accent: GardenColors.warning.withValues(alpha: 0.5),
      );
    }
    final expires = DateTime.tryParse(p['qrExpiresAt'] as String? ?? '')?.toLocal();
    return _card(
      surface,
      border,
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Paga Bs ${amount.toStringAsFixed(0)}', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w900)),
        Text('${premiumDurationLabel(weeks)} de Premium', style: TextStyle(color: sub, fontSize: 13)),
        const SizedBox(height: 14),
        _qrImage(p['qrImageUrl'] as String?),
        const SizedBox(height: 10),
        Text(
          '1. Escanea el QR con la app de tu banco y paga exactamente Bs ${amount.toStringAsFixed(0)}.\n'
          '2. Vuelve aquí y toca "Ya realicé el pago".'
          '${expires != null ? '\nEl QR vence a las ${expires.hour.toString().padLeft(2, '0')}:${expires.minute.toString().padLeft(2, '0')}.' : ''}',
          style: TextStyle(color: sub, fontSize: 13, height: 1.45),
        ),
        const SizedBox(height: 14),
        GardenButton(
          label: 'Ya realicé el pago',
          gIcon: GIcon.confirmado,
          loading: _busy,
          onPressed: _busy ? null : () => _declare(id, amount),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: _busy ? null : () => _cancel(id),
          child: Text('Cancelar y elegir otra duración', style: TextStyle(color: sub)),
        ),
      ]),
    );
  }

  Widget _benefits(Color textColor, Color sub) {
    Widget row(GIcon icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            GardenIcon(icon, size: GIconSize.sm, color: GardenColors.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(color: textColor, fontSize: 13.5))),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Qué incluye', style: TextStyle(color: sub, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
      const SizedBox(height: 10),
      row(GIcon.buscar, 'Apareces primero en el marketplace de tu zona.'),
      row(GIcon.estrella, 'Tu perfil muestra la insignia "Destacado".'),
      row(GIcon.calendario, 'Si ya eres Premium, el tiempo nuevo se suma al que te queda.'),
    ]);
  }

  Widget _history(Color textColor, Color sub, Color surface, Color border) {
    final list = ((_data?['history'] as List?) ?? const []).cast<Map>();
    if (list.isEmpty) return const SizedBox.shrink();
    String label(String s) => switch (s) {
          'PAID' => 'Activado',
          'REJECTED' => 'Pago no confirmado',
          'EXPIRED' => 'QR vencido',
          'CANCELLED' => 'Cancelado',
          'REVOKED' => 'Quitado',
          _ => 'Pendiente',
        };
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Historial', style: TextStyle(color: sub, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
        const SizedBox(height: 8),
        for (final h in list)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Expanded(
                child: Text('${premiumDurationLabel((h['weeks'] as num?)?.toInt() ?? 1)} · Bs ${(h['amount'] as num? ?? 0).toStringAsFixed(0)}',
                    style: TextStyle(color: textColor, fontSize: 13.5, fontWeight: FontWeight.w600)),
              ),
              Text('${label(h['status'] as String? ?? '')} · ${_date((h['paidAt'] ?? h['createdAt']) as String?)}',
                  style: TextStyle(color: sub, fontSize: 12)),
            ]),
          ),
      ]),
    );
  }
}
