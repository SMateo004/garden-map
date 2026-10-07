import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../design/garden_icons.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/garden_loading_indicator.dart';
import 'admin_commission_allocation_screen.dart';
import 'admin_taxes_switch_card.dart';

/// Admin > Comisiones — ÚNICO lugar donde se configura la comisión de GARDEN.
/// Pestaña "Tarifas" (esta) y pestaña "Distribución" (a dónde va la comisión,
/// admin_commission_allocation_screen.dart). Técnica y Finanzas solo la leen.
///
/// - Comisión de GARDEN por servicio (Paseo / Guardería / Hospedaje) y una por
///   defecto para los servicios sin comisión propia.
/// - Comisión personalizada por cuidador o empresa (todos los servicios o uno).
/// - Impuestos (IVA + IT): interruptor que el admin aprueba o pone en pausa (la única
///   condición para cobrarlos) y la tasa que se aplica cuando están aprobados.
///
/// El cliente NUNCA ve la comisión: ve el precio del servicio y los impuestos
/// por separado (ver payment_screen.dart). Los cambios solo afectan reservas
/// nuevas; las ya creadas conservan sus montos.
class AdminPricingScreen extends StatefulWidget {
  final String adminToken;
  const AdminPricingScreen({super.key, required this.adminToken});

  @override
  State<AdminPricingScreen> createState() => _AdminPricingScreenState();
}

class _AdminPricingScreenState extends State<AdminPricingScreen> {
  static const _baseUrl = String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');
  static const _services = ['PASEO', 'GUARDERIA', 'HOSPEDAJE'];
  static const _serviceLabel = {
    'ALL': 'Todos los servicios',
    'PASEO': 'Paseo',
    'GUARDERIA': 'Guardería',
    'HOSPEDAJE': 'Hospedaje',
  };

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${widget.adminToken}',
        'Content-Type': 'application/json',
      };

  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic>? _cfg;

  final _defaultCtl = TextEditingController();
  final _taxCtl = TextEditingController();
  final Map<String, TextEditingController> _svcCtl = {for (final s in _services) s: TextEditingController()};

  // Simulador
  String _previewService = 'PASEO';
  final _previewPriceCtl = TextEditingController(text: '100');
  Map<String, dynamic>? _preview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _defaultCtl.dispose();
    _taxCtl.dispose();
    _previewPriceCtl.dispose();
    for (final c in _svcCtl.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _fmt(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  double? _parse(String raw) => double.tryParse(raw.trim().replaceAll(',', '.'));

  void _applyConfig(Map<String, dynamic> cfg) {
    _cfg = cfg;
    _defaultCtl.text = _fmt(cfg['defaultCommissionPct'] as num);
    _taxCtl.text = _fmt(cfg['taxRatePct'] as num);
    final services = cfg['services'] as Map<String, dynamic>;
    for (final s in _services) {
      final explicit = (services[s] as Map<String, dynamic>)['explicitPct'] as num?;
      _svcCtl[s]!.text = explicit == null ? '' : _fmt(explicit);
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? GardenColors.error : GardenColors.success,
    ));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse('$_baseUrl/admin/pricing'), headers: _headers);
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() => _applyConfig(data['data'] as Map<String, dynamic>));
      } else {
        _toast('No se pudo cargar la configuración', error: true);
      }
    } catch (_) {
      _toast('No se pudo cargar la configuración', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveGlobal() async {
    final maxCommission = ((_cfg?['limits'] as Map?)?['maxCommissionPct'] as num?)?.toDouble() ?? 50;
    final maxTax = ((_cfg?['limits'] as Map?)?['maxTaxRatePct'] as num?)?.toDouble() ?? 50;
    final def = _parse(_defaultCtl.text);
    final tax = _parse(_taxCtl.text);
    if (def == null || def < 0 || def > maxCommission) {
      _toast('La comisión por defecto debe estar entre 0 y ${_fmt(maxCommission)} %', error: true);
      return;
    }
    if (tax == null || tax < 0 || tax > maxTax) {
      _toast('Los impuestos deben estar entre 0 y ${_fmt(maxTax)} %', error: true);
      return;
    }
    final services = <String, double?>{};
    for (final s in _services) {
      final raw = _svcCtl[s]!.text.trim();
      if (raw.isEmpty) {
        services[s] = null;
        continue;
      }
      final v = _parse(raw);
      if (v == null || v < 0 || v > maxCommission) {
        _toast('${_serviceLabel[s]}: la comisión debe estar entre 0 y ${_fmt(maxCommission)} %', error: true);
        return;
      }
      services[s] = v;
    }

    setState(() => _saving = true);
    try {
      final res = await http.put(
        Uri.parse('$_baseUrl/admin/pricing/global'),
        headers: _headers,
        body: jsonEncode({'defaultCommissionPct': def, 'taxRatePct': tax, 'services': services}),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() => _applyConfig(data['data'] as Map<String, dynamic>));
        _toast('Guardado. Aplica a las reservas nuevas.');
      } else {
        _toast((data['error']?['message'] as String?) ?? 'No se pudo guardar', error: true);
      }
    } catch (_) {
      _toast('No se pudo guardar', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteOverride(Map<String, dynamic> o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar comisión personalizada'),
        content: Text('${o['companyName'] ?? o['caregiverName']} volverá a la comisión del servicio '
            '(${_serviceLabel[o['serviceType']]}).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final res = await http.delete(Uri.parse('$_baseUrl/admin/pricing/overrides/${o['id']}'), headers: _headers);
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() => _applyConfig(data['data'] as Map<String, dynamic>));
        _toast('Comisión personalizada eliminada');
      } else {
        _toast('No se pudo eliminar', error: true);
      }
    } catch (_) {
      _toast('No se pudo eliminar', error: true);
    }
  }

  Future<void> _openOverrideDialog({Map<String, dynamic>? existing}) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _OverrideDialog(baseUrl: _baseUrl, headers: _headers, existing: existing),
    );
    if (result == null) return;
    try {
      final res = await http.put(
        Uri.parse('$_baseUrl/admin/pricing/overrides'),
        headers: _headers,
        body: jsonEncode(result),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() => _applyConfig((data['data'] as Map<String, dynamic>)['config'] as Map<String, dynamic>));
        _toast('Comisión personalizada guardada');
      } else {
        _toast((data['error']?['message'] as String?) ?? 'No se pudo guardar', error: true);
      }
    } catch (_) {
      _toast('No se pudo guardar', error: true);
    }
  }

  Future<void> _runPreview() async {
    final price = _parse(_previewPriceCtl.text);
    if (price == null || price < 1) {
      _toast('Escribe un precio válido', error: true);
      return;
    }
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/admin/pricing/preview'),
        headers: _headers,
        body: jsonEncode({'serviceType': _previewService, 'caregiverPrice': price}),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) setState(() => _preview = data['data'] as Map<String, dynamic>);
    } catch (_) {
      _toast('No se pudo calcular', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtextColor = themeNotifier.isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        TabBar(
          labelColor: GardenColors.primary,
          unselectedLabelColor: subtextColor,
          indicatorColor: GardenColors.primary,
          tabs: const [Tab(text: 'Tarifas'), Tab(text: 'Distribución')],
        ),
        Expanded(
          child: TabBarView(children: [
            _buildRates(context),
            AdminCommissionAllocationScreen(adminToken: widget.adminToken),
          ]),
        ),
      ]),
    );
  }

  Widget _buildRates(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    if (_loading) {
      return const Center(child: GardenLoadingIndicator(color: GardenColors.primary));
    }

    final overrides = ((_cfg?['overrides'] as List?) ?? const []).cast<Map<String, dynamic>>();

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

    Widget pctField(String label, TextEditingController ctl, {String? hint}) => SizedBox(
          width: 190,
          child: TextField(
            controller: ctl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: label, hintText: hint, suffixText: '%', isDense: true),
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Comisiones e impuestos',
            style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          'El cliente ve el precio del servicio y los impuestos por separado; la comisión de GARDEN '
          'va incluida en el precio y no se muestra. Los cambios aplican a reservas nuevas.',
          style: TextStyle(color: subtextColor, fontSize: 12.5),
        ),
        const SizedBox(height: 18),
        card([
          title('Comisión de GARDEN por servicio',
              'Porcentaje que se suma al precio del cuidador. Deja vacío un servicio para que use la comisión por defecto.'),
          Wrap(spacing: 14, runSpacing: 14, children: [
            pctField('Por defecto', _defaultCtl),
            for (final s in _services)
              pctField(_serviceLabel[s]!, _svcCtl[s]!,
                  hint: 'usa ${_defaultCtl.text.isEmpty ? '—' : _defaultCtl.text} %'),
          ]),
        ]),
        AdminTaxesSwitchCard(adminToken: widget.adminToken, onChanged: _load),
        card([
          title('Tasa de impuestos (IVA 13 % + IT 3 %)',
              'Se aplica solo mientras los impuestos estén aprobados (interruptor de arriba). En pausa no se cobra ni se muestra.'),
          pctField('Impuestos', _taxCtl),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: _saving ? null : _saveGlobal,
              style: ElevatedButton.styleFrom(backgroundColor: GardenColors.primary, foregroundColor: Colors.white),
              child: Text(_saving ? 'Guardando…' : 'Guardar cambios'),
            ),
          ),
        ]),
        card([
          Row(children: [
            Expanded(
              child: title('Comisiones personalizadas',
                  'Empresas o cuidadores con una comisión distinta. Gana sobre la comisión del servicio.'),
            ),
            ElevatedButton.icon(
              onPressed: () => _openOverrideDialog(),
              icon: const GardenIcon(GIcon.agregar, size: GIconSize.sm, color: Colors.white),
              label: const Text('Agregar'),
              style: ElevatedButton.styleFrom(backgroundColor: GardenColors.primary, foregroundColor: Colors.white),
            ),
          ]),
          if (overrides.isEmpty)
            Text('Ninguna por ahora.', style: TextStyle(color: subtextColor, fontSize: 13))
          else
            ...overrides.map((o) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(GardenRadius.md),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          (o['isCompany'] == true && o['companyName'] != null)
                              ? '${o['companyName']} · empresa'
                              : '${o['caregiverName']}',
                          style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13.5),
                        ),
                        Text('${_serviceLabel[o['serviceType']] ?? o['serviceType']}',
                            style: TextStyle(color: subtextColor, fontSize: 12)),
                      ]),
                    ),
                    Text('${_fmt(o['pct'] as num)} %',
                        style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 15)),
                    IconButton(
                      tooltip: 'Editar',
                      icon: const GardenIcon(GIcon.editar),
                      onPressed: () => _openOverrideDialog(existing: o),
                    ),
                    IconButton(
                      tooltip: 'Quitar',
                      icon: const GardenIcon(GIcon.eliminar),
                      onPressed: () => _deleteOverride(o),
                    ),
                  ]),
                )),
        ]),
        card([
          title('Simulador', 'Cuánto paga el cliente por un precio de cuidador, con la configuración guardada.'),
          Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                initialValue: _previewService,
                isDense: true,
                decoration: const InputDecoration(labelText: 'Servicio', isDense: true),
                items: [for (final s in _services) DropdownMenuItem(value: s, child: Text(_serviceLabel[s]!))],
                onChanged: (v) => setState(() => _previewService = v ?? 'PASEO'),
              ),
            ),
            SizedBox(
              width: 150,
              child: TextField(
                controller: _previewPriceCtl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Precio del cuidador', prefixText: 'Bs ', isDense: true),
              ),
            ),
            OutlinedButton(onPressed: _runPreview, child: const Text('Calcular')),
          ]),
          if (_preview != null) ...[
            const SizedBox(height: 14),
            _previewRow('Precio del cuidador (recibe íntegro)', _preview!['caregiverPrice'], textColor, subtextColor),
            _previewRow('Comisión GARDEN (${_fmt(_preview!['commissionPct'] as num)} %, no visible al cliente)',
                _preview!['commission'], textColor, subtextColor),
            _previewRow('Precio que ve el cliente', _preview!['priceBeforeTax'], textColor, subtextColor),
            if (_preview!['taxesActive'] == true)
              _previewRow('Impuestos (${_fmt(_preview!['taxRatePct'] as num)} %)', _preview!['tax'], textColor, subtextColor)
            else
              _previewRow('Impuestos (en pausa)', 0, textColor, subtextColor),
            const Divider(height: 18),
            _previewRow('El cliente paga', _preview!['clientPays'], textColor, subtextColor, bold: true),
          ],
        ]),
      ],
    );
  }

  Widget _previewRow(String label, dynamic value, Color textColor, Color subtextColor, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(color: bold ? textColor : subtextColor, fontSize: 13))),
        Text('Bs ${_fmt(value as num)}',
            style: TextStyle(
                color: textColor, fontSize: 13.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
      ]),
    );
  }
}

/// Elegir cuidador/empresa (buscador) + servicio + porcentaje.
class _OverrideDialog extends StatefulWidget {
  final String baseUrl;
  final Map<String, String> headers;
  final Map<String, dynamic>? existing;
  const _OverrideDialog({required this.baseUrl, required this.headers, this.existing});

  @override
  State<_OverrideDialog> createState() => _OverrideDialogState();
}

class _OverrideDialogState extends State<_OverrideDialog> {
  final _searchCtl = TextEditingController();
  final _pctCtl = TextEditingController();
  bool _companiesOnly = true;
  bool _searching = false;
  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _picked;
  String _service = 'ALL';
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _picked = {
        'id': e['caregiverId'],
        'name': e['caregiverName'],
        'isCompany': e['isCompany'],
        'companyName': e['companyName'],
      };
      _service = e['serviceType'] as String;
      final p = e['pct'] as num;
      _pctCtl.text = p == p.roundToDouble() ? p.toInt().toString() : p.toString();
    } else {
      _search();
    }
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _pctCtl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _searching = true);
    try {
      final uri = Uri.parse('${widget.baseUrl}/admin/pricing/caregivers').replace(queryParameters: {
        'q': _searchCtl.text.trim(),
        'companiesOnly': _companiesOnly.toString(),
      });
      final res = await http.get(uri, headers: widget.headers);
      final data = jsonDecode(res.body);
      if (mounted && data['success'] == true) {
        setState(() => _results = (data['data'] as List).cast<Map<String, dynamic>>());
      }
    } catch (_) {
      // el buscador se puede reintentar
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _submit() {
    final pct = double.tryParse(_pctCtl.text.trim().replaceAll(',', '.'));
    if (_picked == null) {
      setState(() => _error = 'Elige un cuidador o empresa');
      return;
    }
    if (pct == null || pct < 0 || pct > 50) {
      setState(() => _error = 'La comisión debe estar entre 0 y 50 %');
      return;
    }
    Navigator.pop(context, {'caregiverId': _picked!['id'], 'serviceType': _service, 'pct': pct});
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Editar comisión personalizada' : 'Nueva comisión personalizada'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_picked != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text((_picked!['isCompany'] == true && _picked!['companyName'] != null)
                    ? '${_picked!['companyName']} · empresa'
                    : '${_picked!['name']}'),
                trailing: editing
                    ? null
                    : IconButton(
                        icon: const GardenIcon(GIcon.cerrar),
                        onPressed: () => setState(() => _picked = null),
                      ),
              )
            else ...[
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtl,
                    decoration: const InputDecoration(labelText: 'Buscar por nombre o empresa', isDense: true),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                IconButton(icon: const GardenIcon(GIcon.buscar), onPressed: _search),
              ]),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _companiesOnly,
                title: const Text('Solo empresas'),
                onChanged: (v) {
                  setState(() => _companiesOnly = v ?? true);
                  _search();
                },
              ),
              if (_searching)
                const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 190),
                  child: ListView(
                    shrinkWrap: true,
                    children: _results
                        .map((r) => ListTile(
                              dense: true,
                              title: Text((r['isCompany'] == true && r['companyName'] != null)
                                  ? '${r['companyName']} · empresa'
                                  : '${r['name']}'),
                              subtitle: r['isCompany'] == true ? Text('${r['name']}') : null,
                              onTap: () => setState(() => _picked = r),
                            ))
                        .toList(),
                  ),
                ),
            ],
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _service,
              isDense: true,
              decoration: const InputDecoration(labelText: 'Aplica a', isDense: true),
              items: const [
                DropdownMenuItem(value: 'ALL', child: Text('Todos los servicios')),
                DropdownMenuItem(value: 'PASEO', child: Text('Paseo')),
                DropdownMenuItem(value: 'GUARDERIA', child: Text('Guardería')),
                DropdownMenuItem(value: 'HOSPEDAJE', child: Text('Hospedaje')),
              ],
              onChanged: editing ? null : (v) => setState(() => _service = v ?? 'ALL'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pctCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Comisión de GARDEN', suffixText: '%', isDense: true),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
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
