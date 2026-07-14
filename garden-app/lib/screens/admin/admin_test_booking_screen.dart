import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';

/// Herramienta de admin EXCLUSIVA para pruebas: crea una reserva a mano
/// (cuidador + dueño + horario elegidos manualmente, sin Meet&Greet, sin
/// chequeo de disponibilidad, sin pago real) directo al estado "esperando
/// confirmación del cuidador". El toggle "Ya está pagado" solo controla si
/// se guarda la fecha de pago — no cambia el estado final.
///
/// Solo se puede borrar una reserva creada por esta misma herramienta (el
/// backend lo garantiza con el flag createdByAdmin) — así, si no existe la
/// reserva, tampoco existe ningún pago/payout real asociado a ella.
class AdminTestBookingScreen extends StatefulWidget {
  final String adminToken;
  const AdminTestBookingScreen({super.key, required this.adminToken});

  @override
  State<AdminTestBookingScreen> createState() => _AdminTestBookingScreenState();
}

class _AdminTestBookingScreenState extends State<AdminTestBookingScreen> {
  String get _baseUrl => const String.fromEnvironment(
        'API_URL',
        defaultValue: 'https://api.gardenbo.com/api',
      );

  // ── Búsqueda de cuidador ──
  final _caregiverSearchCtrl = TextEditingController();
  List<Map<String, dynamic>> _caregiverResults = [];
  Map<String, dynamic>? _selectedCaregiver;
  bool _searchingCaregiver = false;

  // ── Búsqueda de dueño ──
  final _ownerSearchCtrl = TextEditingController();
  List<Map<String, dynamic>> _ownerResults = [];
  Map<String, dynamic>? _selectedOwner;
  List<Map<String, dynamic>> _ownerPets = [];
  String? _selectedPetId;
  final _petNameCtrl = TextEditingController();
  bool _searchingOwner = false;
  bool _loadingPets = false;

  // ── Servicio y horario ──
  String _serviceType = 'PASEO';
  DateTime? _walkDate;
  TimeOfDay? _walkTime;
  DateTime? _startDate;
  DateTime? _endDate;

  // ── Precio + pago ──
  final _priceCtrl = TextEditingController(text: '100');
  bool _paid = true;

  // ── Contraseña admin ──
  final _passwordCtrl = TextEditingController();
  bool _creating = false;
  String? _error;

  // Reservas de prueba creadas en esta sesión — cada una con botón de borrar.
  final List<Map<String, dynamic>> _createdThisSession = [];
  final Set<String> _deleting = {};

  @override
  void dispose() {
    _caregiverSearchCtrl.dispose();
    _ownerSearchCtrl.dispose();
    _petNameCtrl.dispose();
    _priceCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${widget.adminToken}',
        'Content-Type': 'application/json',
      };

  Future<void> _searchCaregivers(String query) async {
    if (query.trim().length < 2) {
      setState(() => _caregiverResults = []);
      return;
    }
    setState(() => _searchingCaregiver = true);
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/admin/caregivers?search=${Uri.encodeQueryComponent(query)}&status=APPROVED&limit=15'),
        headers: _headers,
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        setState(() => _caregiverResults = List<Map<String, dynamic>>.from(data['data']['caregivers'] as List));
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _searchingCaregiver = false);
    }
  }

  Future<void> _searchOwners(String query) async {
    if (query.trim().length < 2) {
      setState(() => _ownerResults = []);
      return;
    }
    setState(() => _searchingOwner = true);
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/admin/owners?search=${Uri.encodeQueryComponent(query)}&limit=15'),
        headers: _headers,
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        setState(() => _ownerResults = List<Map<String, dynamic>>.from(data['data']['owners'] as List? ?? []));
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _searchingOwner = false);
    }
  }

  Future<void> _selectOwner(Map<String, dynamic> owner) async {
    setState(() {
      _selectedOwner = owner;
      _ownerResults = [];
      _ownerSearchCtrl.text = owner['name'] as String? ?? '';
      _ownerPets = [];
      _selectedPetId = null;
      _loadingPets = true;
    });
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/admin/owners/${owner['id']}'),
        headers: _headers,
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        final pets = (data['data']['clientProfile']?['pets'] as List?) ?? [];
        setState(() => _ownerPets = List<Map<String, dynamic>>.from(pets));
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingPets = false);
    }
  }

  Future<void> _create() async {
    setState(() => _error = null);
    if (_selectedCaregiver == null) {
      setState(() => _error = 'Elegí un cuidador');
      return;
    }
    if (_selectedOwner == null) {
      setState(() => _error = 'Elegí un dueño');
      return;
    }
    if (_selectedPetId == null && _petNameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Elegí una mascota o escribí un nombre');
      return;
    }
    if (_serviceType == 'HOSPEDAJE' && (_startDate == null || _endDate == null)) {
      setState(() => _error = 'Elegí fecha de inicio y fin');
      return;
    }
    if (_serviceType != 'HOSPEDAJE' && _walkDate == null) {
      setState(() => _error = 'Elegí la fecha');
      return;
    }
    final price = double.tryParse(_priceCtrl.text.trim());
    if (price == null || price <= 0) {
      setState(() => _error = 'Precio inválido');
      return;
    }
    if (_passwordCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Ingresá tu contraseña de admin');
      return;
    }

    setState(() => _creating = true);
    try {
      final body = {
        'adminPassword': _passwordCtrl.text.trim(),
        'caregiverProfileId': _selectedCaregiver!['id'],
        'clientUserId': _selectedOwner!['id'],
        if (_selectedPetId != null) 'petId': _selectedPetId,
        if (_selectedPetId == null) 'petName': _petNameCtrl.text.trim(),
        'serviceType': _serviceType,
        if (_serviceType == 'HOSPEDAJE') ...{
          'startDate': _startDate!.toIso8601String(),
          'endDate': _endDate!.toIso8601String(),
        } else ...{
          'walkDate': _walkDate!.toIso8601String(),
          if (_walkTime != null)
            'startTime': '${_walkTime!.hour.toString().padLeft(2, '0')}:${_walkTime!.minute.toString().padLeft(2, '0')}',
        },
        'totalAmount': price,
        'paid': _paid,
      };
      final res = await http.post(Uri.parse('$_baseUrl/admin/bookings/test'), headers: _headers, body: jsonEncode(body));
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() {
          _createdThisSession.insert(0, {
            'id': data['data']['id'],
            'caregiver': _selectedCaregiver!['fullName'] ?? _selectedCaregiver!['email'],
            'owner': _selectedOwner!['name'],
            'service': _serviceType,
            'paid': _paid,
          });
          _passwordCtrl.clear();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Reserva de prueba creada'), backgroundColor: GardenColors.success));
        }
      } else {
        setState(() => _error = (data['error']?['message'] as String?) ?? 'Error al crear la reserva');
      }
    } catch (e) {
      setState(() => _error = 'Error de conexión');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _deleteTestBooking(String bookingId) async {
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Confirmar borrado'),
          content: TextField(
            controller: ctrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Tu contraseña de admin'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              style: ElevatedButton.styleFrom(backgroundColor: GardenColors.error),
              child: const Text('Borrar'),
            ),
          ],
        );
      },
    );
    if (password == null || password.trim().isEmpty) return;

    setState(() => _deleting.add(bookingId));
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/admin/bookings/$bookingId/test'),
        headers: _headers,
        body: jsonEncode({'adminPassword': password.trim()}),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() => _createdThisSession.removeWhere((b) => b['id'] == bookingId));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Reserva de prueba borrada'), backgroundColor: GardenColors.success));
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text((data['error']?['message'] as String?) ?? 'Error al borrar'),
            backgroundColor: GardenColors.error));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error de conexión'), backgroundColor: GardenColors.error));
      }
    } finally {
      if (mounted) setState(() => _deleting.remove(bookingId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final deco = InputDecoration(
      filled: true, fillColor: surfaceEl,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(GardenRadius.md), borderSide: BorderSide(color: border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GardenRadius.md), borderSide: BorderSide(color: border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GardenRadius.md), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );

    return Container(
      color: surface,
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.science_outlined, color: GardenColors.warning),
                const SizedBox(width: 8),
                Text('Crear reserva de prueba', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: GardenColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(GardenRadius.md),
                  border: Border.all(color: GardenColors.warning.withValues(alpha: 0.3)),
                ),
                child: Text(
                  'Solo para pruebas: crea la reserva directo en "esperando confirmación del cuidador", sin Meet & Greet, sin chequeo de disponibilidad ni pago real. Solo se puede borrar acá mismo — nunca aparece como reserva real para nadie más que el cuidador elegido.',
                  style: TextStyle(color: subtextColor, fontSize: 12.5),
                ),
              ),
              const SizedBox(height: 24),

              // ── Cuidador ──
              Text('Cuidador', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              TextField(
                controller: _caregiverSearchCtrl,
                style: TextStyle(color: textColor),
                decoration: deco.copyWith(
                  hintText: 'Buscar por nombre o email...',
                  suffixIcon: _searchingCaregiver ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
                ),
                onChanged: (v) {
                  setState(() => _selectedCaregiver = null);
                  _searchCaregivers(v);
                },
              ),
              if (_caregiverResults.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(border: Border.all(color: border), borderRadius: BorderRadius.circular(GardenRadius.md)),
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _caregiverResults.length,
                    itemBuilder: (_, i) {
                      final c = _caregiverResults[i];
                      return ListTile(
                        dense: true,
                        title: Text(c['fullName'] as String? ?? '—', style: TextStyle(color: textColor)),
                        subtitle: Text(c['email'] as String? ?? '', style: TextStyle(color: subtextColor, fontSize: 12)),
                        onTap: () => setState(() {
                          _selectedCaregiver = c;
                          _caregiverResults = [];
                          _caregiverSearchCtrl.text = c['fullName'] as String? ?? '';
                        }),
                      );
                    },
                  ),
                ),
              if (_selectedCaregiver != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('✓ ${_selectedCaregiver!['fullName']}', style: const TextStyle(color: GardenColors.success, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: 18),

              // ── Dueño ──
              Text('Dueño de mascota', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              TextField(
                controller: _ownerSearchCtrl,
                style: TextStyle(color: textColor),
                decoration: deco.copyWith(
                  hintText: 'Buscar por nombre o email...',
                  suffixIcon: _searchingOwner ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
                ),
                onChanged: (v) {
                  setState(() => _selectedOwner = null);
                  _searchOwners(v);
                },
              ),
              if (_ownerResults.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(border: Border.all(color: border), borderRadius: BorderRadius.circular(GardenRadius.md)),
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _ownerResults.length,
                    itemBuilder: (_, i) {
                      final o = _ownerResults[i];
                      return ListTile(
                        dense: true,
                        title: Text(o['name'] as String? ?? '—', style: TextStyle(color: textColor)),
                        subtitle: Text(o['email'] as String? ?? '', style: TextStyle(color: subtextColor, fontSize: 12)),
                        onTap: () => _selectOwner(o),
                      );
                    },
                  ),
                ),
              if (_selectedOwner != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('✓ ${_selectedOwner!['name']}', style: const TextStyle(color: GardenColors.success, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 10),
                if (_loadingPets)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                else if (_ownerPets.isNotEmpty) ...[
                  Text('Mascota', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _selectedPetId,
                    dropdownColor: surfaceEl,
                    style: TextStyle(color: textColor, fontSize: 14),
                    decoration: deco,
                    hint: Text('Elegí una mascota (o dejá vacío y escribí un nombre)', style: TextStyle(color: subtextColor, fontSize: 13)),
                    items: _ownerPets.map((p) => DropdownMenuItem(value: p['id'] as String, child: Text(p['name'] as String? ?? '—'))).toList(),
                    onChanged: (v) => setState(() => _selectedPetId = v),
                  ),
                  const SizedBox(height: 8),
                ],
                if (_selectedPetId == null) ...[
                  Text('Nombre de mascota (si no elegís una de arriba)', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  TextField(controller: _petNameCtrl, style: TextStyle(color: textColor), decoration: deco.copyWith(hintText: 'Ej: Firulais')),
                ],
              ],
              const SizedBox(height: 18),

              // ── Servicio ──
              Text('Servicio', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Row(children: [
                for (final s in ['PASEO', 'HOSPEDAJE', 'GUARDERIA']) ...[
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _serviceType = s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: _serviceType == s ? GardenColors.primary : surfaceEl,
                          borderRadius: BorderRadius.circular(GardenRadius.md),
                          border: Border.all(color: _serviceType == s ? GardenColors.primary : border),
                        ),
                        child: Text(s[0] + s.substring(1).toLowerCase(),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: _serviceType == s ? Colors.white : textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 14),

              if (_serviceType == 'HOSPEDAJE') ...[
                Row(children: [
                  Expanded(child: _datePickerField('Fecha inicio', _startDate, (d) => setState(() => _startDate = d), deco, textColor)),
                  const SizedBox(width: 10),
                  Expanded(child: _datePickerField('Fecha fin', _endDate, (d) => setState(() => _endDate = d), deco, textColor)),
                ]),
              ] else ...[
                Row(children: [
                  Expanded(child: _datePickerField('Fecha', _walkDate, (d) => setState(() => _walkDate = d), deco, textColor)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final t = await showTimePicker(context: context, initialTime: _walkTime ?? TimeOfDay.now());
                        if (t != null) setState(() => _walkTime = t);
                      },
                      child: InputDecorator(
                        decoration: deco.copyWith(labelText: 'Hora'),
                        child: Text(_walkTime != null ? _walkTime!.format(context) : 'Elegir hora', style: TextStyle(color: textColor)),
                      ),
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 18),

              // ── Precio + pago ──
              Text('Precio total (Bs)', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              TextField(
                controller: _priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: textColor),
                decoration: deco,
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _paid,
                activeColor: GardenColors.primary,
                title: Text('Ya está pagado', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                subtitle: Text('Solo guarda la fecha de pago — la reserva siempre queda esperando la confirmación del cuidador.', style: TextStyle(color: subtextColor, fontSize: 12)),
                onChanged: (v) => setState(() => _paid = v),
              ),
              const SizedBox(height: 18),

              // ── Contraseña admin ──
              Text('Tu contraseña de admin', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              TextField(
                controller: _passwordCtrl,
                obscureText: true,
                style: TextStyle(color: textColor),
                decoration: deco,
              ),

              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: GardenColors.error, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _creating ? null : _create,
                  style: ElevatedButton.styleFrom(backgroundColor: GardenColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GardenRadius.md))),
                  child: _creating
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Crear reserva de prueba', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),

              if (_createdThisSession.isNotEmpty) ...[
                const SizedBox(height: 32),
                Text('Creadas en esta sesión', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                ..._createdThisSession.map((b) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: surfaceEl, borderRadius: BorderRadius.circular(GardenRadius.md), border: Border.all(color: border)),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${b['owner']} → ${b['caregiver']}', style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13)),
                              Text('${b['service']} · ${b['paid'] == true ? 'Pagado' : 'No pagado'}', style: TextStyle(color: subtextColor, fontSize: 11.5)),
                            ],
                          ),
                        ),
                        _deleting.contains(b['id'])
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : IconButton(
                                icon: const Icon(Icons.delete_outline, color: GardenColors.error, size: 20),
                                onPressed: () => _deleteTestBooking(b['id'] as String),
                              ),
                      ]),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _datePickerField(String label, DateTime? value, void Function(DateTime) onPick, InputDecoration deco, Color textColor) {
    return GestureDetector(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (d != null) onPick(d);
      },
      child: InputDecorator(
        decoration: deco.copyWith(labelText: label),
        child: Text(
          value != null ? '${value.day}/${value.month}/${value.year}' : 'Elegir fecha',
          style: TextStyle(color: textColor),
        ),
      ),
    );
  }
}
