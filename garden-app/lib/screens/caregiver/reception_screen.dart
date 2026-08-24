import 'package:flutter/material.dart';
import '../../theme/garden_theme.dart';
import '../../services/caregiver_crm_service.dart';
import '../../widgets/garden_loading_indicator.dart';

/// Dashboard de ocupación + CRM de mascotas walk-in — compartido entre el
/// dueño ('caregiver') y el staff ('caregiver-staff'), mismos endpoints,
/// solo cambia el prefijo. Solo para cuentas empresa.
class ReceptionScreen extends StatefulWidget {
  final String apiPrefix;
  /// true cuando se usa como pestaña embebida en un Scaffold ajeno (ej. el
  /// staff_home_screen.dart del empleado) — evita duplicar AppBar/Scaffold.
  final bool embedded;
  const ReceptionScreen({super.key, required this.apiPrefix, this.embedded = false});

  @override
  State<ReceptionScreen> createState() => _ReceptionScreenState();
}

class _ReceptionScreenState extends State<ReceptionScreen> {
  late final _service = CaregiverCrmService(prefix: widget.apiPrefix);
  bool _isLoading = true;
  Map<String, dynamic>? _dashboard;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final dashboard = await _service.getOccupancy();
      if (mounted) setState(() => _dashboard = dashboard);
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkOut(String visitId) async {
    try {
      await _service.checkOut(visitId);
      await _load();
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  String _serviceEmoji(String type) => type == 'HOSPEDAJE' ? '🏠' : '🏡';

  String _elapsed(DateTime since) {
    final diff = DateTime.now().difference(since);
    if (diff.inHours >= 24) return '${diff.inDays}d';
    if (diff.inHours >= 1) return '${diff.inHours}h ${diff.inMinutes % 60}m';
    return '${diff.inMinutes}m';
  }

  Future<void> _openCheckInFlow() async {
    final didCheckIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => WalkInCheckInFlowScreen(service: _service)),
    );
    if (didCheckIn == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
        final surface = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
        final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
        final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

        final occupied = _dashboard?['occupied'] as int? ?? 0;
        final capacity = _dashboard?['capacity'] as int? ?? 0;
        final overCapacity = _dashboard?['overCapacity'] == true;
        final entries = (_dashboard?['entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final summaryColor = overCapacity ? GardenColors.error : (occupied == capacity && capacity > 0 ? GardenColors.warning : GardenColors.success);

        final fab = FloatingActionButton.extended(
          onPressed: _openCheckInFlow,
          backgroundColor: GardenColors.primary,
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: const Text('Check-in walk-in', style: TextStyle(color: Colors.white)),
        );

        final body = _isLoading
              ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: summaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: summaryColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.pets_rounded, color: summaryColor, size: 32),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('$occupied de $capacity ocupados',
                                      style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
                                  if (overCapacity)
                                    Text('Por encima del máximo configurado',
                                        style: TextStyle(color: GardenColors.error, fontSize: 12.5, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (entries.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: Text('No hay mascotas en el local ahora.', style: TextStyle(color: subtextColor))),
                        )
                      else
                        for (final e in entries) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(
                              children: [
                                Text(_serviceEmoji(e['serviceType'] as String), style: const TextStyle(fontSize: 26)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Text(e['petName'] as String, style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700)),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: (e['kind'] == 'WALK_IN' ? GardenColors.warning : GardenColors.primary).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(e['kind'] == 'WALK_IN' ? 'Walk-in' : 'Reserva',
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                                  color: e['kind'] == 'WALK_IN' ? GardenColors.warning : GardenColors.primary)),
                                        ),
                                      ]),
                                      const SizedBox(height: 2),
                                      Text('${e['clientName']} · hace ${_elapsed(DateTime.parse(e['since'] as String))}',
                                          style: TextStyle(color: subtextColor, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                if (e['kind'] == 'WALK_IN')
                                  OutlinedButton(
                                    onPressed: () => _checkOut(e['id'] as String),
                                    style: OutlinedButton.styleFrom(foregroundColor: GardenColors.error, side: const BorderSide(color: GardenColors.error)),
                                    child: const Text('Check-out'),
                                  ),
                              ],
                            ),
                          ),
                        ],
                    ],
                  ),
                );

        if (widget.embedded) {
          return Stack(
            children: [
              Positioned.fill(child: body),
              Positioned(right: 16, bottom: 16, child: fab),
            ],
          );
        }

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            elevation: 0,
            title: Text('Recepción', style: TextStyle(color: textColor, fontWeight: FontWeight.w800)),
            iconTheme: IconThemeData(color: textColor),
          ),
          floatingActionButton: fab,
          body: body,
        );
      },
    );
  }
}

/// Flujo de alta rápida: elegir/crear cliente walk-in → elegir/crear
/// mascota → elegir tipo de servicio → check-in.
class WalkInCheckInFlowScreen extends StatefulWidget {
  final CaregiverCrmService service;
  const WalkInCheckInFlowScreen({super.key, required this.service});

  @override
  State<WalkInCheckInFlowScreen> createState() => _WalkInCheckInFlowScreenState();
}

class _WalkInCheckInFlowScreenState extends State<WalkInCheckInFlowScreen> {
  int _step = 0;
  bool _isLoading = false;
  List<Map<String, dynamic>> _clients = [];
  final _clientSearchCtrl = TextEditingController();
  Map<String, dynamic>? _selectedClient;
  Map<String, dynamic>? _selectedPet;
  String _serviceType = 'HOSPEDAJE';

  final _newClientNameCtrl = TextEditingController();
  final _newClientPhoneCtrl = TextEditingController();
  final _newPetNameCtrl = TextEditingController();
  final _newPetBreedCtrl = TextEditingController();
  String _newPetSize = 'MEDIUM';
  String _newPetAnimalType = 'DOGS';

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  @override
  void dispose() {
    _clientSearchCtrl.dispose();
    _newClientNameCtrl.dispose();
    _newClientPhoneCtrl.dispose();
    _newPetNameCtrl.dispose();
    _newPetBreedCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadClients({String? search}) async {
    setState(() => _isLoading = true);
    try {
      final clients = await widget.service.listClients(search: search);
      if (mounted) setState(() => _clients = clients);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createClientAndContinue() async {
    if (_newClientNameCtrl.text.trim().isEmpty) {
      GardenSnackBar.warning(context, 'Ingresá el nombre del cliente');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final client = await widget.service.createClient(
        name: _newClientNameCtrl.text.trim(),
        phone: _newClientPhoneCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _selectedClient = {...client, 'pets': []};
        _step = 1;
      });
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createPetAndContinue() async {
    if (_newPetNameCtrl.text.trim().isEmpty) {
      GardenSnackBar.warning(context, 'Ingresá el nombre de la mascota');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final pet = await widget.service.createPet(_selectedClient!['id'] as String, {
        'name': _newPetNameCtrl.text.trim(),
        if (_newPetBreedCtrl.text.trim().isNotEmpty) 'breed': _newPetBreedCtrl.text.trim(),
        'size': _newPetSize,
        'animalType': _newPetAnimalType,
      });
      if (!mounted) return;
      setState(() {
        _selectedPet = pet;
        _step = 2;
      });
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmCheckIn() async {
    setState(() => _isLoading = true);
    try {
      await widget.service.checkIn(_selectedPet!['id'] as String, serviceType: _serviceType);
      if (!mounted) return;
      GardenSnackBar.success(context, '¡Check-in registrado!');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
        final surface = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
        final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
        final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

        InputDecoration deco(String hint) => InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: subtextColor, fontSize: 13),
              filled: true,
              fillColor: surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
            );

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            elevation: 0,
            iconTheme: IconThemeData(color: textColor),
            title: Text(
              _step == 0 ? 'Elegí o creá un cliente' : _step == 1 ? 'Elegí o creá una mascota' : 'Confirmar check-in',
              style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _isLoading
                  ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
                  : _step == 0
                      ? _buildClientStep(deco, textColor, subtextColor, surface, borderColor)
                      : _step == 1
                          ? _buildPetStep(deco, textColor, subtextColor, surface, borderColor)
                          : _buildConfirmStep(textColor, subtextColor, surface, borderColor),
            ),
          ),
        );
      },
    );
  }

  Widget _buildClientStep(InputDecoration Function(String) deco, Color textColor, Color subtextColor, Color surface, Color borderColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _clientSearchCtrl,
          style: TextStyle(color: textColor),
          decoration: deco('Buscar cliente...').copyWith(prefixIcon: const Icon(Icons.search_rounded)),
          onChanged: (v) => _loadClients(search: v),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            children: [
              for (final c in _clients)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
                  title: Text(c['name'] as String, style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                  subtitle: Text('${(c['pets'] as List).length} mascota(s)', style: TextStyle(color: subtextColor, fontSize: 12)),
                  onTap: () => setState(() {
                    _selectedClient = c;
                    _step = 1;
                  }),
                ),
              Divider(color: borderColor, height: 32),
              Text('O creá uno nuevo', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              TextField(controller: _newClientNameCtrl, style: TextStyle(color: textColor), decoration: deco('Nombre del cliente')),
              const SizedBox(height: 8),
              TextField(controller: _newClientPhoneCtrl, style: TextStyle(color: textColor), decoration: deco('Teléfono (opcional)')),
              const SizedBox(height: 12),
              GardenButton(label: 'Crear y continuar', onPressed: _createClientAndContinue),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPetStep(InputDecoration Function(String) deco, Color textColor, Color subtextColor, Color surface, Color borderColor) {
    final pets = (_selectedClient?['pets'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return ListView(
      children: [
        Text(_selectedClient?['name'] as String? ?? '', style: TextStyle(color: subtextColor, fontSize: 13)),
        const SizedBox(height: 12),
        for (final p in pets)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.pets_rounded)),
            title: Text(p['name'] as String, style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
            onTap: () => setState(() {
              _selectedPet = p;
              _step = 2;
            }),
          ),
        Divider(color: borderColor, height: 32),
        Text('O agregá una mascota nueva', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        TextField(controller: _newPetNameCtrl, style: TextStyle(color: textColor), decoration: deco('Nombre de la mascota')),
        const SizedBox(height: 8),
        TextField(controller: _newPetBreedCtrl, style: TextStyle(color: textColor), decoration: deco('Raza (opcional)')),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _newPetAnimalType,
              decoration: deco(''),
              items: const [DropdownMenuItem(value: 'DOGS', child: Text('Perro')), DropdownMenuItem(value: 'CATS', child: Text('Gato'))],
              onChanged: (v) => setState(() => _newPetAnimalType = v!),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _newPetSize,
              decoration: deco(''),
              items: const [
                DropdownMenuItem(value: 'SMALL', child: Text('Pequeño')),
                DropdownMenuItem(value: 'MEDIUM', child: Text('Mediano')),
                DropdownMenuItem(value: 'LARGE', child: Text('Grande')),
                DropdownMenuItem(value: 'GIANT', child: Text('Gigante')),
              ],
              onChanged: (v) => setState(() => _newPetSize = v!),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        GardenButton(label: 'Agregar y continuar', onPressed: _createPetAndContinue),
      ],
    );
  }

  Widget _buildConfirmStep(Color textColor, Color subtextColor, Color surface, Color borderColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${_selectedPet?['name']} · ${_selectedClient?['name']}', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        Text('Tipo de servicio', style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          for (final (value, label, emoji) in [('HOSPEDAJE', 'Hospedaje', '🏠'), ('GUARDERIA', 'Guardería', '🏡'), ('PASEO', 'Paseo', '🐕')])
            ChoiceChip(
              label: Text('$emoji $label'),
              selected: _serviceType == value,
              onSelected: (_) => setState(() => _serviceType = value),
            ),
        ]),
        const Spacer(),
        SizedBox(width: double.infinity, child: GardenButton(label: 'Confirmar check-in', onPressed: _confirmCheckIn)),
      ],
    );
  }
}
