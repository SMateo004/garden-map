import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, HapticFeedback;
import 'package:http/http.dart' as http;
import '../../design/garden_icons.dart';
import '../../services/auth_state.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/garden_loading_indicator.dart';

const _baseUrl = String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

/// Recojo y entrega a domicilio (guardería / hospedaje): el titular elige si lo ofrece, el
/// precio de cada viaje (0 = gratis, 100% para él, sin comisión) y hasta cuántos km va.
/// Ver transport.service.ts en la API.
class TransportSettingsScreen extends StatefulWidget {
  const TransportSettingsScreen({super.key});

  @override
  State<TransportSettingsScreen> createState() => _TransportSettingsScreenState();
}

class _TransportSettingsScreenState extends State<TransportSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _enabled = false;
  bool _eligible = true;
  bool _hasLocation = true;
  double _maxKm = 5;
  double _minKmLimit = 1;
  double _maxKmLimit = 30;
  int _maxFee = 500;
  List<String> _services = const [];
  final _pickupCtl = TextEditingController();
  final _dropoffCtl = TextEditingController();

  Map<String, String> get _headers =>
      {'Authorization': 'Bearer ${AuthState.token}', 'Content-Type': 'application/json'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pickupCtl.dispose();
    _dropoffCtl.dispose();
    super.dispose();
  }

  void _apply(Map<String, dynamic> d) {
    _enabled = d['enabled'] == true;
    _eligible = d['eligible'] != false;
    _hasLocation = d['hasLocation'] != false;
    _maxKm = ((d['maxKm'] as num?) ?? 5).toDouble();
    _services = ((d['services'] as List?) ?? const []).cast<String>();
    final limits = (d['limits'] as Map?)?.cast<String, dynamic>();
    _minKmLimit = ((limits?['minKm'] as num?) ?? 1).toDouble();
    _maxKmLimit = ((limits?['maxKm'] as num?) ?? 30).toDouble();
    _maxFee = ((limits?['maxFee'] as num?) ?? 500).toInt();
    _maxKm = _maxKm.clamp(_minKmLimit, _maxKmLimit);
    _pickupCtl.text = ((d['pickupFee'] as num?) ?? 0).round().toString();
    _dropoffCtl.text = ((d['dropoffFee'] as num?) ?? 0).round().toString();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await http.get(Uri.parse('$_baseUrl/caregiver/transport'), headers: _headers);
      final body = jsonDecode(res.body);
      if (!mounted) return;
      if (body['success'] == true) {
        setState(() { _apply((body['data'] as Map).cast<String, dynamic>()); _loading = false; });
      } else {
        setState(() { _error = body['error']?['message'] ?? 'No se pudo cargar'; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = 'Sin conexión. Intenta de nuevo.'; _loading = false; });
    }
  }

  /// Lo mismo que valida la API, para avisar antes de guardar.
  String? _feeProblem(String raw, String label) {
    final t = raw.trim();
    if (t.isEmpty) return 'Escribe el precio de $label (0 si es gratis).';
    final n = int.tryParse(t);
    if (n == null) return 'El precio de $label debe ser en bolivianos enteros.';
    if (n > _maxFee) return 'El precio de $label no puede pasar de Bs $_maxFee.';
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final problem = _feeProblem(_pickupCtl.text, 'recojo') ?? _feeProblem(_dropoffCtl.text, 'entrega');
    if (problem != null) {
      GardenErrorDialog.show(context, problem);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _saving = true);
    try {
      final res = await http.put(
        Uri.parse('$_baseUrl/caregiver/transport'),
        headers: _headers,
        body: jsonEncode({
          'enabled': _enabled,
          'pickupFee': int.parse(_pickupCtl.text.trim()),
          'dropoffFee': int.parse(_dropoffCtl.text.trim()),
          'maxKm': _maxKm,
        }),
      );
      final body = jsonDecode(res.body);
      if (!mounted) return;
      if (body['success'] == true) {
        setState(() => _apply((body['data'] as Map).cast<String, dynamic>()));
        GardenSnackBar.success(context, _enabled ? 'Listo. Los dueños ya pueden pedirlo.' : 'Guardado. No ofreces recojo ni entrega.');
      } else {
        GardenErrorDialog.show(context, body['error']?['message'] ?? 'No se pudo guardar');
      }
    } catch (_) {
      if (mounted) GardenErrorDialog.show(context, 'Sin conexión. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final servicesLabel = _services.map((s) => s == 'HOSPEDAJE' ? 'hospedaje' : 'guardería').join(' y ');

    Widget feeField(TextEditingController ctl, String label, String help) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextField(
            controller: ctl,
            enabled: _enabled && !_saving,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: label,
              prefixText: 'Bs ',
              helperText: help,
              border: const OutlineInputBorder(),
            ),
          ),
        );

    final pickupFee = int.tryParse(_pickupCtl.text.trim()) ?? 0;
    final dropoffFee = int.tryParse(_dropoffCtl.text.trim()) ?? 0;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text('Recojo y entrega', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
        iconTheme: IconThemeData(color: text),
      ),
      body: _loading
          ? const Center(child: GardenLoadingIndicator())
          : _error != null
              ? Center(child: TextButton(onPressed: _load, child: Text('$_error  Reintentar')))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    Text('Busca y devuelve a las mascotas en su casa',
                        style: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text(
                      'Para guardería y hospedaje. El dueño elige recojo, entrega o los dos al reservar, '
                      've el viaje en el mapa en vivo y recibe avisos cuando sales y cuando llegas. '
                      'Lo que cobras por cada viaje es todo tuyo: Garden no le cobra comisión.',
                      style: TextStyle(color: sub, fontSize: 13.5, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    if (!_eligible || !_hasLocation)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: GardenColors.warning.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(GardenRadius.lg),
                          border: Border.all(color: GardenColors.warning.withValues(alpha: 0.3)),
                        ),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const GardenIcon(GIcon.info, size: GIconSize.sm, color: GardenColors.warning),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              !_eligible
                                  ? 'Activa guardería u hospedaje en tus servicios para poder ofrecerlo.'
                                  : 'Marca tu dirección en el mapa (Editar perfil) para calcular hasta dónde recoges.',
                              style: TextStyle(color: text, fontSize: 12.5, height: 1.35),
                            ),
                          ),
                        ]),
                      ),
                    Container(
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(GardenRadius.xl),
                        border: Border.all(color: _enabled ? GardenColors.primary : border, width: _enabled ? 1.5 : 1),
                      ),
                      child: SwitchListTile(
                        value: _enabled,
                        onChanged: (_saving || (!_enabled && (!_eligible || !_hasLocation)))
                            ? null
                            : (v) => setState(() => _enabled = v),
                        title: Text('Ofrezco recojo y entrega', style: TextStyle(color: text, fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          _enabled ? 'En $servicesLabel' : 'Apagado',
                          style: TextStyle(color: sub, fontSize: 12.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Opacity(
                      opacity: _enabled ? 1 : 0.5,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        feeField(_pickupCtl, 'Precio del recojo', 'Ir a su casa y traer a la mascota · 0 = gratis'),
                        feeField(_dropoffCtl, 'Precio de la entrega', 'Devolverla a su casa · 0 = gratis'),
                        Text('¿Hasta dónde vas?', style: TextStyle(color: text, fontWeight: FontWeight.w800, fontSize: 15)),
                        Text('Distancia en línea recta desde tu dirección. Fuera de eso, el dueño no ve la opción.',
                            style: TextStyle(color: sub, fontSize: 12.5, height: 1.35)),
                        Row(children: [
                          Expanded(
                            child: Slider(
                              value: _maxKm,
                              min: _minKmLimit,
                              max: _maxKmLimit,
                              divisions: ((_maxKmLimit - _minKmLimit) * 2).round(),
                              label: '${_maxKm.toStringAsFixed(_maxKm % 1 == 0 ? 0 : 1)} km',
                              onChanged: _enabled && !_saving ? (v) => setState(() => _maxKm = (v * 2).round() / 2) : null,
                            ),
                          ),
                          SizedBox(
                            width: 64,
                            child: Text('${_maxKm.toStringAsFixed(_maxKm % 1 == 0 ? 0 : 1)} km',
                                textAlign: TextAlign.end,
                                style: TextStyle(color: text, fontWeight: FontWeight.w800, fontSize: 15)),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(GardenRadius.lg),
                            border: Border.all(color: border),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Así lo verá el dueño', style: TextStyle(color: sub, fontSize: 12, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 6),
                            Text('Recojo a domicilio · ${pickupFee == 0 ? 'Gratis' : 'Bs $pickupFee'}',
                                style: TextStyle(color: text, fontSize: 13.5)),
                            Text('Entrega a domicilio · ${dropoffFee == 0 ? 'Gratis' : 'Bs $dropoffFee'}',
                                style: TextStyle(color: text, fontSize: 13.5)),
                            Text('Hasta ${_maxKm.toStringAsFixed(_maxKm % 1 == 0 ? 0 : 1)} km de tu dirección',
                                style: TextStyle(color: sub, fontSize: 12.5)),
                          ]),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      GardenIcon(GIcon.info, size: GIconSize.sm, color: sub),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Los cambios valen para reservas nuevas. Si un día no puedes hacer un viaje, cancélalo '
                          'desde la reserva: al dueño se le devuelve ese monto y le avisamos.',
                          style: TextStyle(color: sub, fontSize: 12.5, height: 1.4),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 20),
                    GardenButton(label: 'Guardar', loading: _saving, onPressed: _saving ? null : _save),
                  ],
                ),
    );
  }
}
