import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';
import '../../widgets/garden_loading_indicator.dart';

class AdminVetsScreen extends StatefulWidget {
  final String adminToken;
  const AdminVetsScreen({super.key, required this.adminToken});

  @override
  State<AdminVetsScreen> createState() => _AdminVetsScreenState();
}

class _AdminVetsScreenState extends State<AdminVetsScreen> {
  List<Map<String, dynamic>> _vets = [];
  bool _isLoading = true;

  String get _baseUrl => const String.fromEnvironment(
        'API_URL',
        defaultValue: 'https://api.gardenbo.com/api',
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/admin/vets'),
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        setState(() {
          _vets = (data['data'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('AdminVets load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _delete(String id) async {
    final confirmed = await _confirm('¿Eliminar esta veterinaria?');
    if (!confirmed) return;
    await http.delete(
      Uri.parse('$_baseUrl/admin/vets/$id'),
      headers: {'Authorization': 'Bearer ${widget.adminToken}'},
    );
    _load();
  }

  Future<void> _toggleActive(String id, bool current) async {
    await http.patch(
      Uri.parse('$_baseUrl/admin/vets/$id'),
      headers: {
        'Authorization': 'Bearer ${widget.adminToken}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'isActive': !current}),
    );
    _load();
  }

  Future<bool> _confirm(String msg) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Confirmar'),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child:
                    const Text('Confirmar', style: TextStyle(color: GardenColors.error)),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showForm({Map<String, dynamic>? vet}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VetFormSheet(
        adminToken: widget.adminToken,
        baseUrl: _baseUrl,
        vet: vet,
        onSaved: _load,
      ),
    );
  }

  void _showRedemptionForm() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RedemptionFormSheet(adminToken: widget.adminToken, baseUrl: _baseUrl),
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'donor-redemption-fab',
            onPressed: _showRedemptionForm,
            backgroundColor: const Color(0xFF232323),
            foregroundColor: const Color(0xFFD4AF37),
            icon: const Icon(Icons.card_giftcard_rounded),
            label: const Text('Registrar canje', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'add-vet-fab',
            onPressed: () => _showForm(),
            backgroundColor: GardenColors.primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Agregar', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
          : RefreshIndicator(
              color: GardenColors.primary,
              onRefresh: _load,
              child: _vets.isEmpty
                  ? _EmptyVets(onAdd: () => _showForm())
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      itemCount: _vets.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final vet = _vets[i];
                        final isActive = vet['isActive'] as bool? ?? true;
                        return Container(
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(GardenRadius.lg),
                            border: Border.all(color: borderColor),
                          ),
                          child: Column(
                            children: [
                              ListTile(
                                contentPadding:
                                    const EdgeInsets.fromLTRB(16, 10, 12, 4),
                                leading: Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? const Color(0xFF00897B).withValues(alpha: 0.12)
                                        : Colors.grey.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.local_hospital_rounded,
                                    color: isActive
                                        ? const Color(0xFF00897B)
                                        : Colors.grey,
                                    size: 22,
                                  ),
                                ),
                                title: Text(
                                  vet['name'] as String,
                                  style: TextStyle(
                                    color: textColor,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 3),
                                    if ((vet['address'] ?? '').toString().isNotEmpty)
                                      Text(
                                        vet['address'] as String,
                                        style: TextStyle(
                                            color: subtextColor, fontSize: 12),
                                      ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Tel: ${vet['phone']}',
                                      style: const TextStyle(
                                          color: GardenColors.primary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      'Lat: ${vet['lat']}, Lng: ${vet['lng']}',
                                      style: TextStyle(
                                          color: subtextColor, fontSize: 11),
                                    ),
                                  ],
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? GardenColors.success.withValues(alpha: 0.1)
                                        : Colors.grey.withValues(alpha: 0.1),
                                    borderRadius:
                                        BorderRadius.circular(GardenRadius.full),
                                    border: Border.all(
                                      color: isActive
                                          ? GardenColors.success.withValues(alpha: 0.3)
                                          : Colors.grey.withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: Text(
                                    isActive ? 'Activa' : 'Inactiva',
                                    style: TextStyle(
                                      color: isActive
                                          ? GardenColors.success
                                          : Colors.grey,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              Divider(height: 1, color: borderColor),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextButton.icon(
                                      onPressed: () => _showForm(vet: vet),
                                      icon: const Icon(Icons.edit_rounded, size: 15),
                                      label: const Text('Editar',
                                          style: TextStyle(fontSize: 12)),
                                      style: TextButton.styleFrom(
                                          foregroundColor: GardenColors.primary),
                                    ),
                                  ),
                                  Container(width: 1, height: 36, color: borderColor),
                                  Expanded(
                                    child: TextButton.icon(
                                      onPressed: () =>
                                          _toggleActive(vet['id'] as String, isActive),
                                      icon: Icon(
                                        isActive
                                            ? Icons.visibility_off_rounded
                                            : Icons.visibility_rounded,
                                        size: 15,
                                      ),
                                      label: Text(
                                        isActive ? 'Desactivar' : 'Activar',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      style: TextButton.styleFrom(
                                          foregroundColor: isActive
                                              ? GardenColors.warning
                                              : GardenColors.success),
                                    ),
                                  ),
                                  Container(width: 1, height: 36, color: borderColor),
                                  Expanded(
                                    child: TextButton.icon(
                                      onPressed: () =>
                                          _delete(vet['id'] as String),
                                      icon: const Icon(Icons.delete_outline_rounded,
                                          size: 15),
                                      label: const Text('Eliminar',
                                          style: TextStyle(fontSize: 12)),
                                      style: TextButton.styleFrom(
                                          foregroundColor: GardenColors.error),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY STATE
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyVets extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyVets({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final textColor = themeNotifier.isDark
        ? GardenColors.darkTextPrimary
        : GardenColors.lightTextPrimary;
    final subtextColor = themeNotifier.isDark
        ? GardenColors.darkTextSecondary
        : GardenColors.lightTextSecondary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: GardenColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.local_hospital_rounded,
                  color: GardenColors.primary, size: 36),
            ),
            const SizedBox(height: 20),
            Text('Sin veterinarias registradas',
                style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              'Agrega las veterinarias asociadas para que los cuidadores las vean en emergencias.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subtextColor, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAdd,
              style: ElevatedButton.styleFrom(
                backgroundColor: GardenColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(GardenRadius.md)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Agregar veterinaria',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VET FORM SHEET (crear / editar)
// ─────────────────────────────────────────────────────────────────────────────

class _VetFormSheet extends StatefulWidget {
  final String adminToken;
  final String baseUrl;
  final Map<String, dynamic>? vet; // null → crear, non-null → editar
  final VoidCallback onSaved;

  const _VetFormSheet({
    required this.adminToken,
    required this.baseUrl,
    required this.onSaved,
    this.vet,
  });

  @override
  State<_VetFormSheet> createState() => _VetFormSheetState();
}

class _VetFormSheetState extends State<_VetFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  bool _isActive = true;
  bool _saving = false;

  bool get _isEditing => widget.vet != null;

  @override
  void initState() {
    super.initState();
    final v = widget.vet;
    _name = TextEditingController(text: v?['name'] as String? ?? '');
    _address = TextEditingController(text: v?['address'] as String? ?? '');
    _phone = TextEditingController(text: v?['phone'] as String? ?? '');
    _lat = TextEditingController(
        text: v != null ? (v['lat'] as num).toString() : '');
    _lng = TextEditingController(
        text: v != null ? (v['lng'] as num).toString() : '');
    _isActive = v?['isActive'] as bool? ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final body = {
      'name': _name.text.trim(),
      'address': _address.text.trim(),
      'phone': _phone.text.trim(),
      'lat': double.parse(_lat.text.trim()),
      'lng': double.parse(_lng.text.trim()),
      'isActive': _isActive,
    };

    try {
      final uri = _isEditing
          ? Uri.parse('${widget.baseUrl}/admin/vets/${widget.vet!['id']}')
          : Uri.parse('${widget.baseUrl}/admin/vets');

      final res = _isEditing
          ? await http.patch(uri,
              headers: {
                'Authorization': 'Bearer ${widget.adminToken}',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(body))
          : await http.post(uri,
              headers: {
                'Authorization': 'Bearer ${widget.adminToken}',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(body));

      final data = jsonDecode(res.body);
      if (mounted) {
        if (data['success'] == true) {
          Navigator.pop(context);
          widget.onSaved();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(data['message'] ?? 'Error al guardar'),
            backgroundColor: GardenColors.error,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Error de conexión'),
          backgroundColor: GardenColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor =
        isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final borderColor =
        isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final inputFill = isDark
        ? GardenColors.darkSurfaceElevated
        : GardenColors.lightSurfaceElevated;

    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: inputFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GardenRadius.md),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GardenRadius.md),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GardenRadius.md),
        borderSide: const BorderSide(color: GardenColors.primary, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: borderColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title
              Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00897B).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.local_hospital_rounded,
                      color: Color(0xFF00897B), size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  _isEditing ? 'Editar veterinaria' : 'Nueva veterinaria',
                  style: TextStyle(
                      color: textColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w900),
                ),
              ]),
              const SizedBox(height: 24),

              // Nombre
              Text('Nombre *',
                  style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _name,
                style: TextStyle(color: textColor, fontSize: 14),
                decoration: inputDecoration.copyWith(hintText: 'Ej. Clínica VetLife'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Obligatorio' : null,
              ),
              const SizedBox(height: 14),

              // Dirección
              Text('Dirección',
                  style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _address,
                style: TextStyle(color: textColor, fontSize: 14),
                decoration:
                    inputDecoration.copyWith(hintText: 'Av. Ejemplo #123'),
              ),
              const SizedBox(height: 14),

              // Teléfono
              Text('Teléfono *',
                  style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _phone,
                style: TextStyle(color: textColor, fontSize: 14),
                keyboardType: TextInputType.phone,
                decoration: inputDecoration.copyWith(
                    hintText: '+591 XXXXXXXX',
                    prefixIcon: const Icon(Icons.phone_rounded,
                        size: 18, color: GardenColors.primary)),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Obligatorio' : null,
              ),
              const SizedBox(height: 14),

              // Lat / Lng
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Latitud *',
                          style: TextStyle(
                              color: textColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _lat,
                        style: TextStyle(color: textColor, fontSize: 14),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        decoration:
                            inputDecoration.copyWith(hintText: '-17.3935'),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Obligatorio';
                          if (double.tryParse(v.trim()) == null) return 'Número inválido';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Longitud *',
                          style: TextStyle(
                              color: textColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _lng,
                        style: TextStyle(color: textColor, fontSize: 14),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        decoration:
                            inputDecoration.copyWith(hintText: '-66.1568'),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Obligatorio';
                          if (double.tryParse(v.trim()) == null) return 'Número inválido';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Text(
                '💡 Puedes obtener las coordenadas desde Google Maps → clic derecho → "¿Qué hay aquí?"',
                style: TextStyle(color: isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary, fontSize: 11, height: 1.4),
              ),
              const SizedBox(height: 16),

              // Estado activo
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: inputFill,
                  borderRadius: BorderRadius.circular(GardenRadius.md),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Activa',
                              style: TextStyle(
                                  color: textColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                          Text(
                            'Las inactivas no aparecen en emergencias',
                            style: TextStyle(
                                color: isDark
                                    ? GardenColors.darkTextSecondary
                                    : GardenColors.lightTextSecondary,
                                fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isActive,
                      onChanged: (v) => setState(() => _isActive = v),
                      activeColor: GardenColors.primary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Botón guardar
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GardenColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(GardenRadius.md)),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const GardenLoadingIndicator(size: 20, color: Colors.white)
                      : Text(
                          _isEditing ? 'Guardar cambios' : 'Agregar veterinaria',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REDEMPTION FORM SHEET — registrar canje de tarjeta de donador
// ─────────────────────────────────────────────────────────────────────────────

class _RedemptionFormSheet extends StatefulWidget {
  final String adminToken;
  final String baseUrl;

  const _RedemptionFormSheet({required this.adminToken, required this.baseUrl});

  @override
  State<_RedemptionFormSheet> createState() => _RedemptionFormSheetState();
}

class _RedemptionFormSheetState extends State<_RedemptionFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  final _businessCtrl = TextEditingController();
  DateTime _redeemedAt = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _businessCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _redeemedAt,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _redeemedAt = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/admin/donor-redemptions'),
        headers: {
          'Authorization': 'Bearer ${widget.adminToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'donorCode': _codeCtrl.text.trim().toUpperCase(),
          'businessName': _businessCtrl.text.trim(),
          'redeemedAt': _redeemedAt.toIso8601String(),
        }),
      );
      final data = jsonDecode(res.body);
      if (mounted) {
        if (data['success'] == true) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Canje registrado para ${data['data']?['userName'] ?? 'el cliente'}'),
            backgroundColor: GardenColors.success,
          ));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(data['error']?['message'] as String? ?? 'Error al registrar'),
            backgroundColor: GardenColors.error,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Error de conexión'),
          backgroundColor: GardenColors.error,
        ));
      }
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

    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: inputFill,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(GardenRadius.md), borderSide: BorderSide(color: borderColor)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GardenRadius.md), borderSide: BorderSide(color: borderColor)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GardenRadius.md), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );

    return Container(
      decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Row(children: [
                const Icon(Icons.card_giftcard_rounded, color: Color(0xFFD4AF37)),
                const SizedBox(width: 10),
                Text('Registrar canje de donador', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 4),
              Text(
                'Cargá el código que el negocio te informó — el uso queda asociado al cliente dueño de ese código.',
                style: TextStyle(color: subtextColor, fontSize: 12.5),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _codeCtrl,
                textCapitalization: TextCapitalization.characters,
                style: TextStyle(color: textColor, fontWeight: FontWeight.w700, letterSpacing: 1.5),
                decoration: inputDecoration.copyWith(labelText: 'Código de donador (ej. GRD-XXXXXXXX)'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _businessCtrl,
                style: TextStyle(color: textColor),
                decoration: inputDecoration.copyWith(labelText: 'Nombre del negocio/veterinaria'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(GardenRadius.md),
                child: InputDecorator(
                  decoration: inputDecoration.copyWith(labelText: 'Fecha del canje'),
                  child: Text(
                    '${_redeemedAt.day.toString().padLeft(2, '0')}/${_redeemedAt.month.toString().padLeft(2, '0')}/${_redeemedAt.year}',
                    style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF232323),
                    foregroundColor: const Color(0xFFD4AF37),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GardenRadius.md)),
                  ),
                  child: _saving
                      ? const GardenLoadingIndicator(size: 20, color: Color(0xFFD4AF37))
                      : const Text('Registrar canje', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
