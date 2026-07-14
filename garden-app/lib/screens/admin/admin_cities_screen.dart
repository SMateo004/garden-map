import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';

/// Panel admin de ciudades y zonas (multi-ciudad). Reemplaza el enum fijo
/// `Zone` — acá se agregan ciudades nuevas (ej. Cochabamba) y sus zonas
/// (color, coordenadas del mapa, activar/desactivar), sin necesitar un
/// release de la app.
class AdminCitiesScreen extends StatefulWidget {
  final String adminToken;
  const AdminCitiesScreen({super.key, required this.adminToken});

  @override
  State<AdminCitiesScreen> createState() => _AdminCitiesScreenState();
}

class _AdminCitiesScreenState extends State<AdminCitiesScreen> {
  List<Map<String, dynamic>> _cities = [];
  bool _isLoading = true;
  String? _expandedCityId;
  Map<String, List<Map<String, dynamic>>> _zonesByCity = {};

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');
  Map<String, String> get _headers => {'Authorization': 'Bearer ${widget.adminToken}', 'Content-Type': 'application/json'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(Uri.parse('$_baseUrl/admin/cities'), headers: _headers);
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        setState(() {
          _cities = (data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        });
      }
    } catch (e) {
      debugPrint('AdminCities load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadZones(String cityId) async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/admin/city-zones?cityId=$cityId'), headers: _headers);
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        setState(() {
          _zonesByCity[cityId] = (data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        });
      }
    } catch (e) {
      debugPrint('AdminCities loadZones error: $e');
    }
  }

  Future<void> _toggleCityActive(String id, bool current) async {
    await http.patch(Uri.parse('$_baseUrl/admin/cities/$id'), headers: _headers, body: jsonEncode({'active': !current}));
    _load();
  }

  Future<void> _toggleZoneActive(String cityId, String zoneId, bool current) async {
    await http.patch(Uri.parse('$_baseUrl/admin/city-zones/$zoneId'), headers: _headers, body: jsonEncode({'active': !current}));
    _loadZones(cityId);
  }

  void _showCityForm() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CityFormSheet(adminToken: widget.adminToken, baseUrl: _baseUrl, onSaved: _load),
    );
  }

  void _showZoneForm(String cityId, {Map<String, dynamic>? zone}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ZoneFormSheet(
        adminToken: widget.adminToken,
        baseUrl: _baseUrl,
        cityId: cityId,
        zone: zone,
        onSaved: () => _loadZones(cityId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Scaffold(
      backgroundColor: bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCityForm,
        backgroundColor: GardenColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('Agregar ciudad', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
          : RefreshIndicator(
              color: GardenColors.primary,
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: _cities.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final city = _cities[i];
                  final cityId = city['id'] as String;
                  final active = city['active'] as bool? ?? true;
                  final expanded = _expandedCityId == cityId;
                  final zoneCount = (city['_count']?['zones'] as int?) ?? 0;

                  return Container(
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(GardenRadius.lg),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Container(
                            width: 42, height: 42,
                            decoration: BoxDecoration(
                              color: (active ? GardenColors.primary : Colors.grey).withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.location_city_rounded, color: active ? GardenColors.primary : Colors.grey, size: 22),
                          ),
                          title: Text(city['name'] as String, style: TextStyle(color: textColor, fontWeight: FontWeight.w700)),
                          subtitle: Text('$zoneCount zona${zoneCount == 1 ? '' : 's'} · ${active ? 'Activa' : 'Inactiva'}',
                              style: TextStyle(color: subtextColor, fontSize: 12.5)),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Switch(value: active, onChanged: (_) => _toggleCityActive(cityId, active), activeColor: GardenColors.primary),
                            IconButton(
                              icon: Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: subtextColor),
                              onPressed: () {
                                setState(() => _expandedCityId = expanded ? null : cityId);
                                if (!expanded && !_zonesByCity.containsKey(cityId)) _loadZones(cityId);
                              },
                            ),
                          ]),
                        ),
                        if (expanded) ...[
                          Divider(height: 1, color: borderColor),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Zonas', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13)),
                                    TextButton.icon(
                                      onPressed: () => _showZoneForm(cityId),
                                      icon: const Icon(Icons.add_rounded, size: 16),
                                      label: const Text('Agregar zona'),
                                    ),
                                  ],
                                ),
                                ...(_zonesByCity[cityId] ?? []).map((zone) {
                                  final zActive = zone['active'] as bool? ?? true;
                                  final color = Color(0xFF000000 | (int.tryParse((zone['color'] as String).replaceFirst('#', ''), radix: 16) ?? 0));
                                  return ListTile(
                                    dense: true,
                                    leading: Container(width: 14, height: 14, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                                    title: Text(zone['label'] as String, style: TextStyle(color: textColor, fontSize: 14)),
                                    subtitle: Text('${zone['lat']}, ${zone['lng']}', style: TextStyle(color: subtextColor, fontSize: 11)),
                                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                      IconButton(
                                        icon: Icon(Icons.edit_outlined, size: 18, color: subtextColor),
                                        onPressed: () => _showZoneForm(cityId, zone: zone),
                                      ),
                                      Switch(
                                        value: zActive,
                                        onChanged: (_) => _toggleZoneActive(cityId, zone['id'] as String, zActive),
                                        activeColor: GardenColors.primary,
                                      ),
                                    ]),
                                  );
                                }),
                                if ((_zonesByCity[cityId] ?? []).isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    child: Text('Sin zonas todavía', style: TextStyle(color: subtextColor, fontSize: 13)),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

// ── CITY FORM SHEET ──────────────────────────────────────────────────────────

class _CityFormSheet extends StatefulWidget {
  final String adminToken;
  final String baseUrl;
  final VoidCallback onSaved;

  const _CityFormSheet({required this.adminToken, required this.baseUrl, required this.onSaved});

  @override
  State<_CityFormSheet> createState() => _CityFormSheetState();
}

class _CityFormSheetState extends State<_CityFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _slug = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/admin/cities'),
        headers: {'Authorization': 'Bearer ${widget.adminToken}', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': _name.text.trim(),
          'slug': _slug.text.trim().toLowerCase().replaceAll(' ', '-'),
          'centerLat': double.parse(_lat.text.trim()),
          'centerLng': double.parse(_lng.text.trim()),
        }),
      );
      final data = jsonDecode(res.body);
      if (mounted) {
        if (data['success'] == true) {
          Navigator.pop(context);
          widget.onSaved();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['error']?['message'] ?? 'Error al guardar'), backgroundColor: GardenColors.error));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error de conexión'), backgroundColor: GardenColors.error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final inputFill = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;

    final deco = InputDecoration(
      filled: true, fillColor: inputFill,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(GardenRadius.md), borderSide: BorderSide(color: borderColor)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GardenRadius.md), borderSide: BorderSide(color: borderColor)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GardenRadius.md), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );

    return Container(
      decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Text('Nueva ciudad', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 20),
              TextFormField(controller: _name, style: TextStyle(color: textColor), decoration: deco.copyWith(labelText: 'Nombre (ej. Cochabamba)'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null),
              const SizedBox(height: 14),
              TextFormField(controller: _slug, style: TextStyle(color: textColor), decoration: deco.copyWith(labelText: 'Slug interno (ej. cochabamba)'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: TextFormField(controller: _lat, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), style: TextStyle(color: textColor), decoration: deco.copyWith(labelText: 'Latitud centro'),
                    validator: (v) => double.tryParse(v ?? '') == null ? 'Inválido' : null)),
                const SizedBox(width: 10),
                Expanded(child: TextFormField(controller: _lng, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), style: TextStyle(color: textColor), decoration: deco.copyWith(labelText: 'Longitud centro'),
                    validator: (v) => double.tryParse(v ?? '') == null ? 'Inválido' : null)),
              ]),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(backgroundColor: GardenColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GardenRadius.md))),
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Crear ciudad', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── ZONE FORM SHEET ──────────────────────────────────────────────────────────

class _ZoneFormSheet extends StatefulWidget {
  final String adminToken;
  final String baseUrl;
  final String cityId;
  final Map<String, dynamic>? zone;
  final VoidCallback onSaved;

  const _ZoneFormSheet({required this.adminToken, required this.baseUrl, required this.cityId, this.zone, required this.onSaved});

  @override
  State<_ZoneFormSheet> createState() => _ZoneFormSheetState();
}

class _ZoneFormSheetState extends State<_ZoneFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _keyCtrl;
  late final TextEditingController _label;
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  late Color _color;
  bool _saving = false;

  bool get _isEditing => widget.zone != null;

  static const _palette = [
    Color(0xFF4CAF50), Color(0xFF2196F3), Color(0xFF00BCD4), Color(0xFFFF9800),
    Color(0xFFE91E63), Color(0xFF3F51B5), Color(0xFF9C27B0), Color(0xFF00897B),
    Color(0xFF6D4C41), Color(0xFFFFC107),
  ];

  @override
  void initState() {
    super.initState();
    final z = widget.zone;
    _keyCtrl = TextEditingController(text: z?['key'] as String? ?? '');
    _label = TextEditingController(text: z?['label'] as String? ?? '');
    _lat = TextEditingController(text: z != null ? (z['lat'] as num).toString() : '');
    _lng = TextEditingController(text: z != null ? (z['lng'] as num).toString() : '');
    _color = z != null
        ? Color(0xFF000000 | (int.tryParse((z['color'] as String).replaceFirst('#', ''), radix: 16) ?? 0x4CAF50))
        : _palette.first;
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _label.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  String _colorHex(Color c) => '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final body = {
        'cityId': widget.cityId,
        'key': _keyCtrl.text.trim(),
        'label': _label.text.trim(),
        'color': _colorHex(_color),
        'lat': double.parse(_lat.text.trim()),
        'lng': double.parse(_lng.text.trim()),
      };
      final uri = _isEditing
          ? Uri.parse('${widget.baseUrl}/admin/city-zones/${widget.zone!['id']}')
          : Uri.parse('${widget.baseUrl}/admin/city-zones');
      final headers = {'Authorization': 'Bearer ${widget.adminToken}', 'Content-Type': 'application/json'};
      final res = _isEditing
          ? await http.patch(uri, headers: headers, body: jsonEncode(body))
          : await http.post(uri, headers: headers, body: jsonEncode(body));
      final data = jsonDecode(res.body);
      if (mounted) {
        if (data['success'] == true) {
          Navigator.pop(context);
          widget.onSaved();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['error']?['message'] ?? 'Error al guardar'), backgroundColor: GardenColors.error));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error de conexión'), backgroundColor: GardenColors.error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final inputFill = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;

    final deco = InputDecoration(
      filled: true, fillColor: inputFill,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(GardenRadius.md), borderSide: BorderSide(color: borderColor)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GardenRadius.md), borderSide: BorderSide(color: borderColor)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GardenRadius.md), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );

    return Container(
      decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Text(_isEditing ? 'Editar zona' : 'Nueva zona', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 20),
              TextFormField(controller: _keyCtrl, enabled: !_isEditing, style: TextStyle(color: textColor), decoration: deco.copyWith(labelText: 'Key interno (ej. cala cala)'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null),
              const SizedBox(height: 14),
              TextFormField(controller: _label, style: TextStyle(color: textColor), decoration: deco.copyWith(labelText: 'Nombre visible (ej. Cala Cala)'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: TextFormField(controller: _lat, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), style: TextStyle(color: textColor), decoration: deco.copyWith(labelText: 'Latitud'),
                    validator: (v) => double.tryParse(v ?? '') == null ? 'Inválido' : null)),
                const SizedBox(width: 10),
                Expanded(child: TextFormField(controller: _lng, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), style: TextStyle(color: textColor), decoration: deco.copyWith(labelText: 'Longitud'),
                    validator: (v) => double.tryParse(v ?? '') == null ? 'Inválido' : null)),
              ]),
              const SizedBox(height: 14),
              Text('Color en el mapa', style: TextStyle(color: subtextColor, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 10, children: _palette.map((c) {
                final selected = c.toARGB32() == _color.toARGB32();
                return GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: c, shape: BoxShape.circle,
                      border: selected ? Border.all(color: textColor, width: 2.5) : null,
                    ),
                    child: selected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                  ),
                );
              }).toList()),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(backgroundColor: GardenColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GardenRadius.md))),
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_isEditing ? 'Guardar cambios' : 'Crear zona', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
