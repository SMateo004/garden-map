import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../design/garden_icons.dart';
import '../../theme/garden_theme.dart';
import '../../utils/premium_price.dart';
import '../../widgets/garden_loading_indicator.dart';

const _baseUrl = String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

Map<String, String> _headers(String token) => {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};

String _fmtDate(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '—';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String _statusLabel(String s) => switch (s) {
      'PENDING_PAYMENT' => 'QR generado, sin pagar',
      'PAYMENT_PENDING_APPROVAL' => 'Pago declarado',
      'PAID' => 'Activo / pagado',
      'REJECTED' => 'Rechazado',
      'EXPIRED' => 'QR vencido',
      'CANCELLED' => 'Cancelado',
      'REVOKED' => 'Quitado',
      _ => s,
    };

Future<Map<String, dynamic>?> _call(BuildContext context, String method, String path, String token, [Map<String, dynamic>? body]) async {
  try {
    final uri = Uri.parse('$_baseUrl$path');
    final res = method == 'PUT'
        ? await http.put(uri, headers: _headers(token), body: jsonEncode(body ?? {}))
        : method == 'GET'
            ? await http.get(uri, headers: _headers(token))
            : await http.post(uri, headers: _headers(token), body: jsonEncode(body ?? {}));
    final data = jsonDecode(res.body);
    if (data['success'] == true) {
      final d = data['data'];
      return d is Map ? d.cast<String, dynamic>() : {'items': d};
    }
    if (context.mounted) GardenErrorDialog.show(context, data['error']?['message'] ?? 'No se pudo completar');
  } catch (_) {
    if (context.mounted) GardenErrorDialog.show(context, 'Sin conexión. Intenta de nuevo.');
  }
  return null;
}

Future<String?> _askPassword(BuildContext context, String title, String message) {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(message, style: const TextStyle(fontSize: 13, height: 1.4)),
        const SizedBox(height: 12),
        TextField(controller: ctl, obscureText: true, decoration: const InputDecoration(labelText: 'Tu contraseña de admin')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        ElevatedButton(onPressed: () => ctl.text.isEmpty ? null : Navigator.pop(ctx, ctl.text), child: const Text('Confirmar')),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Admin > Comisiones > Premium: precios por duración, activar/pausar, ingresos.
// ═══════════════════════════════════════════════════════════════════════════

class AdminPremiumSettingsPanel extends StatefulWidget {
  final String adminToken;
  const AdminPremiumSettingsPanel({super.key, required this.adminToken});

  @override
  State<AdminPremiumSettingsPanel> createState() => _AdminPremiumSettingsPanelState();
}

class _Row {
  final TextEditingController weeks;
  final TextEditingController price;
  _Row(int w, int p)
      : weeks = TextEditingController(text: w > 0 ? '$w' : ''),
        price = TextEditingController(text: p > 0 ? '$p' : '');
}

class _AdminPremiumSettingsPanelState extends State<AdminPremiumSettingsPanel> {
  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  final List<_Row> _rows = [];
  Map<String, dynamic>? _revenue;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = await _call(context, 'GET', '/admin/premium/settings', widget.adminToken);
    if (!mounted) return;
    final r = await _call(context, 'GET', '/admin/premium/revenue', widget.adminToken);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _revenue = (r?['thisMonth'] as Map?)?.cast<String, dynamic>();
      if (s != null) {
        _enabled = s['enabled'] == true;
        _rows
          ..clear()
          ..addAll(PremiumPricePoint.listFrom(s['priceTable']).map((p) => _Row(p.weeks, p.price)));
        if (_rows.isEmpty) _rows.add(_Row(1, 0));
      }
    });
  }

  /// La tabla tal como está escrita (para la vista previa), ignorando filas vacías.
  List<PremiumPricePoint> get _draft {
    final out = <PremiumPricePoint>[];
    for (final r in _rows) {
      final w = int.tryParse(r.weeks.text.trim());
      final p = int.tryParse(r.price.text.trim());
      if (w != null && p != null && w > 0 && p > 0) out.add(PremiumPricePoint(w, p));
    }
    out.sort((a, b) => a.weeks.compareTo(b.weeks));
    return out;
  }

  /// Mismas reglas que el servidor, para avisar antes de guardar.
  String? get _problem {
    final points = <PremiumPricePoint>[];
    for (var i = 0; i < _rows.length; i++) {
      final w = int.tryParse(_rows[i].weeks.text.trim());
      final p = int.tryParse(_rows[i].price.text.trim());
      if (w == null || w < 1 || w > 52) return 'Fila ${i + 1}: semanas de 1 a 52.';
      if (p == null || p < 1 || p > 100000) return 'Fila ${i + 1}: precio entero de Bs 1 a Bs 100.000.';
      points.add(PremiumPricePoint(w, p));
    }
    points.sort((a, b) => a.weeks.compareTo(b.weeks));
    if (points.isEmpty || points.first.weeks != 1) return 'Debe existir el precio de 1 semana.';
    for (var i = 1; i < points.length; i++) {
      if (points[i].weeks == points[i - 1].weeks) return 'Hay dos precios para ${points[i].weeks} semana(s).';
      if (points[i].price < points[i - 1].price) {
        return '${points[i].weeks} semanas no puede costar menos que ${points[i - 1].weeks}.';
      }
    }
    return null;
  }

  Future<void> _save() async {
    final problem = _problem;
    if (problem != null) {
      GardenErrorDialog.show(context, problem);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Guardar precios de Premium?'),
        content: Text(_enabled
            ? 'Los cuidadores verán estos precios desde ya. Lo que ya compraron no cambia.'
            : 'Premium quedará pausado: los cuidadores no podrán comprarlo (tú sí podrás registrarlo presencialmente).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    final table = _draft.map((p) => {'weeks': p.weeks, 'price': p.price}).toList();
    final r = await _call(context, 'PUT', '/admin/premium/settings', widget.adminToken, {'enabled': _enabled, 'priceTable': table});
    if (!mounted) return;
    setState(() => _saving = false);
    if (r != null) {
      GardenSnackBar.success(context, 'Precios de Premium guardados');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    if (_loading) return const Center(child: GardenLoadingIndicator());
    final draft = _draft;
    final maxW = maxPremiumWeeks(draft);
    final previewWeeks = <int>{1, 2, 3, 4, 8, 12, 26, 52, maxW}.where((w) => w >= 1 && w <= maxW).toList()..sort();
    final problem = _problem;

    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Premium (perfiles destacados)', style: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      Text('Los cuidadores y empresas Premium aparecen primero en el marketplace con la insignia "Destacado". '
          'Pagan con QR (sin billetera) o los registras tú presencialmente desde su ficha.',
          style: TextStyle(color: sub, fontSize: 13, height: 1.4)),
      if (_revenue != null) ...[
        const SizedBox(height: 12),
        Text('Este mes: Bs ${(_revenue!['total'] as num? ?? 0).toStringAsFixed(0)} en ${_revenue!['count'] ?? 0} compra(s).',
            style: TextStyle(color: text, fontSize: 13.5, fontWeight: FontWeight.w700)),
      ],
      const SizedBox(height: 16),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _enabled,
        onChanged: _saving ? null : (v) => setState(() => _enabled = v),
        title: Text('Los cuidadores pueden comprarlo', style: TextStyle(color: text, fontWeight: FontWeight.w700)),
        subtitle: Text(_enabled ? 'Activo' : 'Pausado', style: TextStyle(color: sub)),
      ),
      const SizedBox(height: 8),
      Text('Precio por duración', style: TextStyle(color: text, fontSize: 15, fontWeight: FontWeight.w800)),
      Text('Define algunos puntos; entre uno y otro el precio se calcula solo. El último punto es la duración máxima (hasta 52 semanas).',
          style: TextStyle(color: sub, fontSize: 12.5, height: 1.4)),
      const SizedBox(height: 10),
      for (var i = 0; i < _rows.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _rows[i].weeks,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Semanas', isDense: true, border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _rows[i].price,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Precio (Bs)', isDense: true, border: OutlineInputBorder()),
              ),
            ),
            IconButton(
              tooltip: 'Quitar',
              onPressed: _rows.length <= 1 ? null : () => setState(() => _rows.removeAt(i)),
              icon: GardenIcon(GIcon.eliminar, size: GIconSize.sm, color: sub),
            ),
          ]),
        ),
      if (_rows.length < 20)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _rows.add(_Row(0, 0))),
            icon: const GardenIcon(GIcon.agregar, size: GIconSize.sm, color: GardenColors.primary),
            label: const Text('Agregar punto'),
          ),
        ),
      if (problem != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(problem, style: const TextStyle(color: GardenColors.error, fontSize: 12.5)),
        ),
      if (problem == null && previewWeeks.isNotEmpty) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(GardenRadius.lg), border: Border.all(color: border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Así lo verá el cuidador', style: TextStyle(color: sub, fontSize: 12, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final w in previewWeeks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(child: Text(premiumDurationLabel(w), style: TextStyle(color: text, fontSize: 13))),
                  Text('Bs ${premiumPriceForWeeks(draft, w)}', style: TextStyle(color: text, fontSize: 13, fontWeight: FontWeight.w800)),
                ]),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 18),
      GardenButton(label: 'Guardar', loading: _saving, onPressed: _saving ? null : _save),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Admin > Pagos: compras de Premium que esperan al admin.
// ═══════════════════════════════════════════════════════════════════════════

class AdminPremiumPurchasesSection extends StatefulWidget {
  final String adminToken;
  /// Se llama después de aprobar/rechazar, para que el panel refresque contadores.
  final VoidCallback? onChanged;
  const AdminPremiumPurchasesSection({super.key, required this.adminToken, this.onChanged});

  @override
  State<AdminPremiumPurchasesSection> createState() => AdminPremiumPurchasesSectionState();
}

class AdminPremiumPurchasesSectionState extends State<AdminPremiumPurchasesSection> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final r = await _call(context, 'GET', '/admin/premium/purchases', widget.adminToken);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _items = ((r?['items'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
    });
  }

  Future<void> _act(String id, String path, [Map<String, dynamic>? body]) async {
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    final r = await _call(context, 'POST', path, widget.adminToken, body);
    if (!mounted) return;
    setState(() => _busy.remove(id));
    if (r != null) {
      GardenSnackBar.success(context, 'Listo');
      await reload();
      widget.onChanged?.call();
    }
  }

  Future<void> _approve(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Aprobar Premium?'),
        content: Text('Confirma que llegaron Bs ${(p['amount'] as num).toStringAsFixed(0)} de ${p['caregiverName']}. '
            'Se activa al instante por ${p['weeks']} semana(s).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, llegó')),
        ],
      ),
    );
    if (ok == true) await _act(p['id'] as String, '/admin/premium/purchases/${p['id']}/approve');
  }

  Future<void> _reject(Map<String, dynamic> p) async {
    final ctl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Rechazar el pago?'),
        content: TextField(controller: ctl, decoration: const InputDecoration(labelText: 'Motivo (lo verá el cuidador)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Rechazar')),
        ],
      ),
    );
    if (reason != null) await _act(p['id'] as String, '/admin/premium/purchases/${p['id']}/reject', {'reason': reason});
  }

  Future<void> _review(Map<String, dynamic> p, String outcome) async {
    final notReceived = outcome == 'NOT_RECEIVED';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(notReceived ? '¿El dinero no llegó?' : '¿Confirmar que llegó?'),
        content: Text(notReceived
            ? 'Se quitará este Premium a ${p['caregiverName']} y se le avisará.'
            : 'Queda verificado; el Premium sigue activo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok == true) await _act(p['id'] as String, '/admin/premium/purchases/${p['id']}/review', {'outcome': outcome});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final actionable = _items.where((p) => p['status'] != 'PENDING_PAYMENT').toList();
    final waitingQr = _items.where((p) => p['status'] == 'PENDING_PAYMENT').length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const GardenIcon(GIcon.estrella, size: GIconSize.sm, color: GardenColors.star, state: GIconState.active),
        const SizedBox(width: 6),
        Text('Premium por aprobar', style: TextStyle(color: text, fontWeight: FontWeight.w800, fontSize: 14)),
        const SizedBox(width: 8),
        Text('${actionable.length}', style: TextStyle(color: sub, fontWeight: FontWeight.w800)),
        const Spacer(),
        IconButton(onPressed: reload, icon: GardenIcon(GIcon.repetir, size: GIconSize.sm, color: sub)),
      ]),
      if (_loading)
        const Padding(padding: EdgeInsets.all(12), child: Center(child: GardenLoadingIndicator()))
      else if (actionable.isEmpty)
        Text(waitingQr > 0 ? 'Sin pagos declarados ($waitingQr QR generado(s) sin pagar todavía).' : 'Sin compras pendientes.',
            style: TextStyle(color: sub, fontSize: 13))
      else
        for (final p in actionable)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(GardenRadius.lg), border: Border.all(color: border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p['caregiverName']} · ${p['weeks']} sem · Bs ${(p['amount'] as num).toStringAsFixed(0)}',
                  style: TextStyle(color: text, fontWeight: FontWeight.w800)),
              Text(
                p['autoApprovedAt'] != null
                    ? 'Aprobado automáticamente el ${_fmtDate(p['autoApprovedAt'] as String?)} — verifica si el dinero llegó'
                    : '${_statusLabel(p['status'] as String)} el ${_fmtDate((p['paymentDeclaredAt'] ?? p['createdAt']) as String?)}',
                style: TextStyle(color: sub, fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (p['status'] == 'PAYMENT_PENDING_APPROVAL') ...[
                  ElevatedButton(onPressed: _busy.contains(p['id']) ? null : () => _approve(p), child: const Text('Aprobar')),
                  OutlinedButton(onPressed: _busy.contains(p['id']) ? null : () => _reject(p), child: const Text('Rechazar')),
                ] else if (p['autoApprovedAt'] != null) ...[
                  ElevatedButton(onPressed: _busy.contains(p['id']) ? null : () => _review(p, 'CONFIRMED'), child: const Text('Llegó')),
                  OutlinedButton(onPressed: _busy.contains(p['id']) ? null : () => _review(p, 'NOT_RECEIVED'), child: const Text('No llegó')),
                ],
              ]),
            ]),
          ),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Ficha del cuidador (admin): estado de Premium, quién paga la comisión,
// activación presencial y quitar una compra.
// ═══════════════════════════════════════════════════════════════════════════

class AdminCaregiverPremiumCard extends StatefulWidget {
  final String adminToken;
  final String caregiverProfileId;
  const AdminCaregiverPremiumCard({super.key, required this.adminToken, required this.caregiverProfileId});

  @override
  State<AdminCaregiverPremiumCard> createState() => _AdminCaregiverPremiumCardState();
}

class _AdminCaregiverPremiumCardState extends State<AdminCaregiverPremiumCard> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _call(context, 'GET', '/admin/premium/caregivers/${widget.caregiverProfileId}', widget.adminToken);
    if (mounted) setState(() { _data = r; _loading = false; });
  }

  Future<void> _activate() async {
    final settings = (_data?['settings'] as Map?)?.cast<String, dynamic>();
    final table = PremiumPricePoint.listFrom(settings?['priceTable']);
    if (table.isEmpty) {
      GardenErrorDialog.show(context, 'Primero configura los precios en Comisiones > Premium.');
      return;
    }
    final input = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ManualActivationDialog(table: table),
    );
    if (input == null || !mounted) return;
    final password = await _askPassword(
      context,
      'Registrar pago presencial',
      'Se cobra Bs ${input['amount']} por ${premiumDurationLabel(input['weeks'] as int)} y se activa al instante.',
    );
    if (password == null || !mounted) return;
    setState(() => _busy = true);
    final r = await _call(context, 'POST', '/admin/premium/caregivers/${widget.caregiverProfileId}/activate', widget.adminToken, {
      'weeks': input['weeks'],
      'paymentKind': input['paymentKind'],
      'note': input['note'],
      'adminPassword': password,
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) {
      GardenSnackBar.success(context, 'Premium activado hasta el ${_fmtDate(r['premiumUntil'] as String?)}');
      _load();
    }
  }

  Future<void> _revoke(Map<String, dynamic> p) async {
    final reasonCtl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Quitar esta compra?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${p['weeks']} semana(s) · Bs ${(p['amount'] as num).toStringAsFixed(0)}. El tiempo de compras posteriores se corre para no regalar el período quitado. No se devuelve dinero automáticamente.',
              style: const TextStyle(fontSize: 13, height: 1.4)),
          const SizedBox(height: 10),
          TextField(controller: reasonCtl, decoration: const InputDecoration(labelText: 'Motivo (mínimo 5 letras)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, reasonCtl.text.trim()), child: const Text('Continuar')),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    final password = await _askPassword(context, 'Quitar Premium', 'Confirma con tu contraseña.');
    if (password == null || !mounted) return;
    setState(() => _busy = true);
    final r = await _call(context, 'POST', '/admin/premium/purchases/${p['id']}/revoke', widget.adminToken,
        {'reason': reason, 'adminPassword': password});
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) {
      GardenSnackBar.success(context, 'Compra quitada');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    if (_loading) return const Padding(padding: EdgeInsets.all(12), child: Center(child: GardenLoadingIndicator()));
    if (_data == null) return const SizedBox.shrink();
    final active = _data!['active'] == true;
    final payer = _data!['commissionPaidBy'] == 'CAREGIVER' ? 'El cuidador (absorbe la comisión)' : 'El dueño (recargo en su precio)';
    final purchases = ((_data!['purchases'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(GardenRadius.lg), border: Border.all(color: border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GardenIcon(GIcon.estrella, size: GIconSize.sm, state: active ? GIconState.active : GIconState.idle,
              color: active ? GardenColors.star : sub),
          const SizedBox(width: 6),
          Expanded(
            child: Text(active ? 'Premium hasta el ${_fmtDate(_data!['premiumUntil'] as String?)}' : 'Sin Premium',
                style: TextStyle(color: text, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Paga la comisión: $payer', style: TextStyle(color: sub, fontSize: 12.5)),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _busy ? null : _activate,
          icon: const GardenIcon(GIcon.agregar, size: GIconSize.sm, color: GardenColors.primary),
          label: const Text('Registrar Premium (pago presencial)'),
        ),
        if (purchases.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Compras', style: TextStyle(color: sub, fontSize: 12, fontWeight: FontWeight.w800)),
          for (final p in purchases)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(
                  child: Text(
                    '${p['weeks']} sem · Bs ${(p['amount'] as num).toStringAsFixed(0)} · ${_statusLabel(p['status'] as String)}'
                    '${p['method'] == 'ADMIN' ? ' (presencial)' : ''}'
                    '${p['activatedUntil'] != null && p['status'] == 'PAID' ? ' · hasta ${_fmtDate(p['activatedUntil'] as String?)}' : ''}',
                    style: TextStyle(color: text, fontSize: 12.5),
                  ),
                ),
                if (p['status'] == 'PAID')
                  TextButton(onPressed: _busy ? null : () => _revoke(p), child: const Text('Quitar')),
              ]),
            ),
        ],
      ]),
    );
  }
}

class _ManualActivationDialog extends StatefulWidget {
  final List<PremiumPricePoint> table;
  const _ManualActivationDialog({required this.table});

  @override
  State<_ManualActivationDialog> createState() => _ManualActivationDialogState();
}

class _ManualActivationDialogState extends State<_ManualActivationDialog> {
  int _weeks = 1;
  String _kind = 'CASH';
  final _note = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final maxW = maxPremiumWeeks(widget.table);
    final price = premiumPriceForWeeks(widget.table, _weeks);
    return AlertDialog(
      title: const Text('Premium presencial'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(premiumDurationLabel(_weeks), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          if (maxW > 1)
            Slider(
              value: _weeks.toDouble(),
              min: 1,
              max: maxW.toDouble(),
              divisions: maxW - 1,
              label: premiumDurationLabel(_weeks),
              onChanged: (v) => setState(() => _weeks = v.round()),
            ),
          Text('A cobrar: Bs ${price ?? '—'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Cómo pagó'),
            items: const [
              DropdownMenuItem(value: 'CASH', child: Text('Efectivo')),
              DropdownMenuItem(value: 'TRANSFER', child: Text('Transferencia')),
              DropdownMenuItem(value: 'OTHER', child: Text('Otro')),
            ],
            onChanged: (v) => setState(() => _kind = v ?? 'CASH'),
          ),
          TextField(controller: _note, maxLength: 300, decoration: const InputDecoration(labelText: 'Nota (opcional)')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: price == null
              ? null
              : () => Navigator.pop(context, {'weeks': _weeks, 'amount': price, 'paymentKind': _kind, 'note': _note.text.trim()}),
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}
