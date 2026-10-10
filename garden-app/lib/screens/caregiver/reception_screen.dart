import 'package:flutter/material.dart';
import '../../theme/garden_theme.dart';
import '../../services/caregiver_crm_service.dart';
import '../../widgets/garden_loading_indicator.dart';
import 'walkin_clients_screen.dart';
import 'walkin_visit_detail_screen.dart';
import 'walkin_reports_screen.dart';
import 'walkin_reservations_screen.dart';
import '../../design/garden_icons.dart';

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
      if (mounted) GardenErrorDialog.show(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkOut(String visitId) async {
    try {
      await _service.checkOut(visitId);
      await _load();
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, friendlyError(e));
    }
  }

  GIcon _serviceIcon(String type) => type == 'HOSPEDAJE' ? GIcon.hospedaje : GIcon.guarderia;

  String _elapsed(DateTime since) {
    final diff = DateTime.now().difference(since);
    if (diff.inHours >= 24) return '${diff.inDays}d';
    if (diff.inHours >= 1) return '${diff.inHours}h ${diff.inMinutes % 60}m';
    return '${diff.inMinutes}m';
  }

  Future<void> _openCheckInFlow() async {
    final didCheckIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => WalkInCheckInFlowScreen(service: _service, isOwner: _isOwner)),
    );
    if (didCheckIn == true) _load();
  }

  Future<void> _openVisitDetail(String visitId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WalkInVisitDetailScreen(service: _service, visitId: visitId)),
    );
    _load();
  }

  bool get _isOwner => widget.apiPrefix == 'caregiver';

  /// Entrada de una reserva de mostrador que llega hoy (su lugar ya estaba contado).
  Future<void> _checkInReservation(Map<String, dynamic> r) async {
    try {
      await _service.checkIn(r['petId'] as String,
          serviceType: r['serviceType'] as String, reservationId: r['reservationId'] as String);
      if (!mounted) return;
      GardenSnackBar.success(context, 'Entrada de ${r['petName']} registrada');
      _load();
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, friendlyError(e));
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

        final occupied = _dashboard?['occupied'] as int? ?? 0;
        final capacity = _dashboard?['capacity'] as int? ?? 0;
        final overCapacity = _dashboard?['overCapacity'] == true;
        final entries = (_dashboard?['entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final committedToday = _dashboard?['committedToday'] as int?;
        final arrivingToday = (_dashboard?['arrivingToday'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final summaryColor = overCapacity ? GardenColors.error : (occupied == capacity && capacity > 0 ? GardenColors.warning : GardenColors.success);

        final fab = FloatingActionButton.extended(
          onPressed: _openCheckInFlow,
          backgroundColor: GardenColors.primary,
          icon: const GardenIcon(GIcon.agregar, size: GIconSize.lg, color: Colors.white),
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
                            GardenIcon(GIcon.huella, size: GIconSize.xl, state: GIconState.active, color: summaryColor),
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
                                  // Presentes + los que llegan hoy (reservas de la app y de mostrador).
                                  if (committedToday != null && committedToday > occupied)
                                    Text('$committedToday de $capacity lugares tomados hoy contando las llegadas',
                                        style: TextStyle(color: subtextColor, fontSize: 12.5)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => WalkInClientsScreen(service: _service)),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor),
                          ),
                          child: Row(
                            children: [
                              GardenIcon(GIcon.equipo, size: GIconSize.md, color: GardenColors.primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text('Clientes y mascotas registradas',
                                    style: TextStyle(color: textColor, fontSize: 13.5, fontWeight: FontWeight.w600)),
                              ),
                              GardenIcon(GIcon.siguiente, size: GIconSize.lg, color: subtextColor),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => WalkInReservationsScreen(service: _service, isOwner: _isOwner),
                          ));
                          _load();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor),
                          ),
                          child: Row(
                            children: [
                              GardenIcon(GIcon.calendario, size: GIconSize.md, color: GardenColors.primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text('Reservas de mostrador',
                                    style: TextStyle(color: textColor, fontSize: 13.5, fontWeight: FontWeight.w600)),
                              ),
                              GardenIcon(GIcon.siguiente, size: GIconSize.lg, color: subtextColor),
                            ],
                          ),
                        ),
                      ),
                      if (_isOwner) ...[
                        const SizedBox(height: 8),
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => WalkInReportsScreen(service: _service)),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(
                              children: [
                                GardenIcon(GIcon.estadisticas, size: GIconSize.md, color: GardenColors.primary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text('Reportes de ocupación y caja',
                                      style: TextStyle(color: textColor, fontSize: 13.5, fontWeight: FontWeight.w600)),
                                ),
                                GardenIcon(GIcon.siguiente, size: GIconSize.lg, color: subtextColor),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (arrivingToday.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text('Llegan hoy', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        for (final r in arrivingToday)
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(children: [
                              GardenIcon(_serviceIcon(r['serviceType'] as String), size: GIconSize.lg),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(r['petName'] as String,
                                      style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700)),
                                  Text(
                                    r['serviceType'] == 'HOSPEDAJE'
                                        ? '${r['clientName']} · hasta el ${shortDay(r['endDate'] as String)}'
                                        : '${r['clientName']} · guardería',
                                    style: TextStyle(color: subtextColor, fontSize: 12),
                                  ),
                                ]),
                              ),
                              OutlinedButton(
                                onPressed: () => _checkInReservation(r),
                                child: const Text('Registrar entrada'),
                              ),
                            ]),
                          ),
                        Text('En el local', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w700)),
                      ],
                      const SizedBox(height: 8),
                      if (entries.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: Text('No hay mascotas en el local ahora.', style: TextStyle(color: subtextColor))),
                        )
                      else
                        for (final e in entries) ...[
                          InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: e['kind'] == 'WALK_IN' ? () => _openVisitDetail(e['id'] as String) : null,
                            child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(
                              children: [
                                GardenIcon(_serviceIcon(e['serviceType'] as String), size: GIconSize.lg, state: GIconState.active),
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
  /// Solo el dueño puede registrar por encima del cupo.
  final bool isOwner;
  const WalkInCheckInFlowScreen({super.key, required this.service, this.isOwner = false});

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
  /// false = entra ahora; true = reservar fechas a futuro (guarda el lugar en el cupo).
  bool _reserveLater = false;
  /// Hospedaje que entra ahora: día de salida opcional (guarda el lugar esos días).
  DateTime? _untilDate;
  DateTime? _startDate;
  DateTime? _endDate;

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
    } catch (e) {
      // Antes se tragaba y la lista vacía parecía "no hay clientes".
      if (mounted) GardenSnackBar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createClientAndContinue() async {
    if (_isLoading) return;
    if (_newClientNameCtrl.text.trim().isEmpty) {
      GardenSnackBar.warning(context, 'Escribe el nombre del cliente');
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
      if (mounted) GardenErrorDialog.show(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createPetAndContinue() async {
    if (_isLoading) return;
    if (_newPetNameCtrl.text.trim().isEmpty) {
      GardenSnackBar.warning(context, 'Escribe el nombre de la mascota');
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
      if (mounted) GardenErrorDialog.show(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmCheckIn() async {
    if (_isLoading) return;
    final petId = _selectedPet!['id'] as String;
    if (_reserveLater) {
      if (_startDate == null || (_serviceType == 'HOSPEDAJE' && _endDate == null)) {
        GardenErrorDialog.show(context, _serviceType == 'HOSPEDAJE' ? 'Elige el día de entrada y el de salida.' : 'Elige el día.');
        return;
      }
    }
    setState(() => _isLoading = true);
    try {
      final done = await runWithCapacityCheck(
        context,
        isOwner: widget.isOwner,
        action: (force) => _reserveLater
            ? widget.service.createReservation(
                petId,
                serviceType: _serviceType,
                startDate: isoDay(_startDate!),
                endDate: _serviceType == 'HOSPEDAJE' ? isoDay(_endDate!) : null,
                force: force,
              )
            : widget.service.checkIn(
                petId,
                serviceType: _serviceType,
                untilDate: _serviceType == 'HOSPEDAJE' && _untilDate != null ? isoDay(_untilDate!) : null,
                force: force,
              ),
      );
      if (done == null || !mounted) return;
      GardenSnackBar.success(context, _reserveLater ? '¡Reserva guardada!' : '¡Check-in registrado!');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, friendlyError(e));
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
              _step == 0 ? 'Elige o crea un cliente' : _step == 1 ? 'Elige o crea una mascota' : _reserveLater ? 'Reservar fechas' : 'Confirmar check-in',
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
          decoration: deco('Buscar cliente...').copyWith(prefixIcon: const GardenIcon(GIcon.buscar, size: GIconSize.lg, inheritColor: true)),
          onChanged: (v) => _loadClients(search: v),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            children: [
              for (final c in _clients)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: GardenIcon(GIcon.perfil, size: GIconSize.lg, inheritColor: true)),
                  title: Text(c['name'] as String, style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                  subtitle: Text('${(c['pets'] as List).length} mascota(s)', style: TextStyle(color: subtextColor, fontSize: 12)),
                  onTap: () => setState(() {
                    _selectedClient = c;
                    _step = 1;
                  }),
                ),
              Divider(color: borderColor, height: 32),
              Text('O crea uno nuevo', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              TextField(controller: _newClientNameCtrl, style: TextStyle(color: textColor), decoration: deco('Nombre del cliente')),
              const SizedBox(height: 8),
              TextField(controller: _newClientPhoneCtrl, style: TextStyle(color: textColor), decoration: deco('Teléfono (opcional)')),
              const SizedBox(height: 12),
              GardenButton(label: 'Crear y continuar', loading: _isLoading, onPressed: _isLoading ? null : _createClientAndContinue),
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
            leading: const CircleAvatar(child: GardenIcon(GIcon.huella, size: GIconSize.lg, state: GIconState.active, inheritColor: true)),
            title: Text(p['name'] as String, style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
            onTap: () => setState(() {
              _selectedPet = p;
              _step = 2;
            }),
          ),
        Divider(color: borderColor, height: 32),
        Text('O agrega una mascota nueva', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w700)),
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
        GardenButton(label: 'Agregar y continuar', loading: _isLoading, onPressed: _isLoading ? null : _createPetAndContinue),
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
          for (final (value, label) in [(false, 'Entra ahora'), (true, 'Reservar fechas')])
            ChoiceChip(
              label: Text(label),
              selected: _reserveLater == value,
              onSelected: (_) => setState(() {
                _reserveLater = value;
                // El paseo es fuera del local: no se reserva lugar.
                if (value && _serviceType == 'PASEO') _serviceType = 'HOSPEDAJE';
              }),
            ),
        ]),
        const SizedBox(height: 16),
        Text('Tipo de servicio', style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          for (final (value, label, icon) in [('HOSPEDAJE', 'Hospedaje', GIcon.hospedaje), ('GUARDERIA', 'Guardería', GIcon.guarderia), ('PASEO', 'Paseo', GIcon.paseo)])
            if (!_reserveLater || value != 'PASEO')
              ChoiceChip(
                avatar: GardenIcon(icon, size: GIconSize.sm, state: GIconState.active),
                label: Text(label),
                selected: _serviceType == value,
                onSelected: (_) => setState(() => _serviceType = value),
              ),
        ]),
        const SizedBox(height: 16),
        if (!_reserveLater && _serviceType == 'HOSPEDAJE')
          _dateRow('¿Hasta cuándo se queda? (opcional)', _untilDate, textColor, subtextColor, borderColor,
              first: DateTime.now().add(const Duration(days: 1)), onPicked: (d) => setState(() => _untilDate = d)),
        if (_reserveLater) ...[
          _dateRow(_serviceType == 'HOSPEDAJE' ? 'Entrada' : 'Día', _startDate, textColor, subtextColor, borderColor,
              first: DateTime.now(), onPicked: (d) => setState(() {
                    _startDate = d;
                    if (_endDate != null && !_endDate!.isAfter(d)) _endDate = null;
                  })),
          if (_serviceType == 'HOSPEDAJE')
            _dateRow('Salida', _endDate, textColor, subtextColor, borderColor,
                first: (_startDate ?? DateTime.now()).add(const Duration(days: 1)),
                onPicked: (d) => setState(() => _endDate = d)),
        ],
        if (!_reserveLater && _serviceType == 'HOSPEDAJE' && _untilDate != null || _reserveLater)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('El lugar queda guardado esos días y la app no lo vende.',
                style: TextStyle(color: subtextColor, fontSize: 12)),
          ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: GardenButton(
            label: _reserveLater ? 'Guardar reserva' : 'Confirmar check-in',
            loading: _isLoading,
            onPressed: _isLoading ? null : _confirmCheckIn,
          ),
        ),
      ],
    );
  }

  Widget _dateRow(String label, DateTime? value, Color textColor, Color subtextColor, Color borderColor,
      {required DateTime first, required ValueChanged<DateTime> onPicked}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final start = DateTime(first.year, first.month, first.day);
          final picked = await showDatePicker(
            context: context,
            initialDate: value != null && !value.isBefore(start) ? value : start,
            firstDate: start,
            lastDate: start.add(const Duration(days: 180)),
          );
          if (picked != null) onPicked(picked);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
          child: Row(children: [
            GardenIcon(GIcon.calendario, size: GIconSize.md, color: subtextColor),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: TextStyle(color: subtextColor, fontSize: 13))),
            Text(value == null ? 'Elegir' : shortDay(isoDay(value)),
                style: TextStyle(color: textColor, fontSize: 13.5, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}
