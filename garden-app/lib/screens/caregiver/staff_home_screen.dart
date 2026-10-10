import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';
import '../../services/auth_service.dart';
import '../../services/caregiver_staff_service.dart';
import '../../services/business_features.dart';
import '../../design/garden_icons.dart';
import '../../narrative/booking_story.dart';
import '../../design/garden_status_pill.dart';
import '../../design/garden_service_icon.dart';
import '../../design/garden_service.dart';
import '../../widgets/garden_loading_indicator.dart';
import '../../widgets/mode_switcher_card.dart';
import 'reception_screen.dart';

/// Dashboard reducido del empleado de una empresa cuidadora: ve y atiende reservas
/// (check-in/check-out). Sin billetera, precios ni configuración. Aceptar/rechazar
/// reservas, chatear con clientes y la recepción aparecen solo si el admin habilitó esa
/// función para la empresa y (los dos primeros) el dueño le dio el permiso — whoami.
class StaffHomeScreen extends StatefulWidget {
  const StaffHomeScreen({super.key});

  @override
  State<StaffHomeScreen> createState() => _StaffHomeScreenState();
}

class _StaffHomeScreenState extends State<StaffHomeScreen> {
  final _service = CaregiverStaffService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _bookings = [];
  /// Respuesta de whoami: trae `businessFeatures` (lo que el admin habilitó a la empresa).
  Map<String, dynamic>? _whoami;
  String? _bookingsError;
  int _tab = 0;

  bool get _receptionEnabled => BusinessFeatures.has(_whoami, BusinessFeatures.reception);
  bool get _canManageBookings => _whoami?['canManageBookings'] == true;
  bool get _canChat => _whoami?['canChat'] == true;
  /// Filtro "Asignadas a mí" (las que el dueño le asignó a este empleado).
  bool _onlyMine = false;
  String? get _myStaffMemberId => _whoami?['staffMemberId'] as String?;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _bookingsError = null;
    });
    try {
      final who = await _service.whoami();
      if (mounted) setState(() => _whoami = who);
    } catch (_) {}
    try {
      final bookings = await _service.getBookings(assignedToMe: _onlyMine);
      if (mounted) setState(() => _bookings = bookings);
    } catch (e) {
      // Ej.: el admin deshabilitó el equipo de la empresa (FEATURE_DISABLED).
      if (mounted) setState(() => _bookingsError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    await AuthService().clearToken();
    if (mounted) context.go('/login');
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
        final tabCount = _receptionEnabled ? 3 : 2;
        final tab = _tab.clamp(0, tabCount - 1);

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AuthState.staffCompanyName, style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w800)),
                Text('Panel de empleado', style: TextStyle(color: subtextColor, fontSize: 11.5)),
              ],
            ),
          ),
          body: IndexedStack(
            index: tab,
            children: [
              _buildBookingsTab(surface, textColor, subtextColor, borderColor),
              // Recepción solo si el admin la habilitó para la empresa.
              if (_receptionEnabled) const ReceptionScreen(apiPrefix: 'caregiver-staff', embedded: true),
              _buildAccountTab(textColor, subtextColor, borderColor),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            backgroundColor: surface,
            destinations: [
              const NavigationDestination(icon: GardenIcon(GIcon.nota, size: GIconSize.lg, inheritColor: true), selectedIcon: GardenIcon(GIcon.nota, size: GIconSize.lg, inheritColor: true), label: 'Reservas'),
              if (_receptionEnabled)
                const NavigationDestination(icon: GardenIcon(GIcon.habitacion, size: GIconSize.lg, inheritColor: true), selectedIcon: GardenIcon(GIcon.habitacion, size: GIconSize.lg, inheritColor: true), label: 'Recepción'),
              const NavigationDestination(icon: GardenIcon(GIcon.perfil, size: GIconSize.lg, inheritColor: true), selectedIcon: GardenIcon(GIcon.perfil, size: GIconSize.lg, state: GIconState.active, inheritColor: true), label: 'Cuenta'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBookingsTab(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    if (_isLoading) return const Center(child: GardenLoadingIndicator(color: GardenColors.primary));
    if (_bookingsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_bookingsError!, textAlign: TextAlign.center, style: TextStyle(color: subtextColor, fontSize: 14)),
        ),
      );
    }
    final filter = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(spacing: 8, children: [
        for (final (mine, label) in [(false, 'Todas'), (true, 'Asignadas a mí')])
          ChoiceChip(
            label: Text(label),
            selected: _onlyMine == mine,
            onSelected: (_) {
              setState(() => _onlyMine = mine);
              _load();
            },
          ),
      ]),
    );
    if (_bookings.isEmpty) {
      return Column(children: [
        filter,
        Expanded(
          child: Center(
            child: Text(_onlyMine ? 'No tienes reservas asignadas.' : 'No hay reservas todavía.',
                style: TextStyle(color: subtextColor, fontSize: 14)),
          ),
        ),
      ]);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _bookings.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(padding: const EdgeInsets.only(bottom: 8), child: filter);
          }
          final b = _bookings[index - 1];
          final assignedToMe = _myStaffMemberId != null && b['assignedStaffMemberId'] == _myStaffMemberId;
          final status = b['status'] as String;
          final service = GardenService.fromApi(b['serviceType'] as String?) ?? GardenService.paseo;
          final story = BookingStory.of(status, BookingStoryContext.fromBooking(b, caregiverView: true));
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => StaffBookingDetailScreen(
                  bookingId: b['id'] as String,
                  canManageBookings: _canManageBookings,
                  canChat: _canChat,
                ),
              ));
              _load();
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  GardenServiceIcon(service, size: 32, live: status == 'IN_PROGRESS'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b['petName'] as String? ?? 'Mascota', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(b['clientName'] as String? ?? '', style: TextStyle(color: subtextColor, fontSize: 12.5)),
                        if (assignedToMe)
                          const Text('Asignada a ti',
                              style: TextStyle(color: GardenColors.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  GardenStatusPill(story, service: service, dense: true),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAccountTab(Color textColor, Color subtextColor, Color borderColor) {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final company = AuthState.staffCompanyName.isEmpty ? 'Tu empresa' : AuthState.staffCompanyName;
    final initial = company.trim().isEmpty ? 'G' : company.trim()[0].toUpperCase();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        // Quién eres y para quién trabajas ahora mismo.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(GardenRadius.xl),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: GardenColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(initial, style: GardenText.h3.copyWith(color: GardenColors.primary)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(company, style: GardenText.h4.copyWith(color: textColor)),
                    const SizedBox(height: 2),
                    Text('Trabajas en el equipo', style: GardenText.bodySmall.copyWith(color: subtextColor)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const ModeSwitcherCard(),
        const SizedBox(height: 20),
        Material(
          color: surface,
          borderRadius: BorderRadius.circular(GardenRadius.lg),
          child: InkWell(
            borderRadius: BorderRadius.circular(GardenRadius.lg),
            onTap: _logout,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(GardenRadius.lg),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  const GardenIcon(GIcon.salir, color: GardenColors.error),
                  const SizedBox(width: 14),
                  Text('Cerrar sesión',
                      style: GardenText.labelLarge.copyWith(color: GardenColors.error, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Detalle de una reserva desde el punto de vista del staff — mismas
/// acciones operativas que el dueño (avisar en camino, llegué, iniciar,
/// agregar fotos, concluir) pero sin nada de chat/billetera/precios.
class StaffBookingDetailScreen extends StatefulWidget {
  final String bookingId;
  /// Permisos que dio el dueño (y que el admin habilitó para la empresa) — whoami.
  final bool canManageBookings;
  final bool canChat;
  const StaffBookingDetailScreen({
    super.key,
    required this.bookingId,
    this.canManageBookings = false,
    this.canChat = false,
  });

  @override
  State<StaffBookingDetailScreen> createState() => _StaffBookingDetailScreenState();
}

class _StaffBookingDetailScreenState extends State<StaffBookingDetailScreen> {
  final _service = CaregiverStaffService();
  Map<String, dynamic>? _booking;
  bool _isLoading = true;
  bool _isActing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final booking = await _service.getBookingById(widget.bookingId);
      if (mounted) setState(() => _booking = booking);
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int get _minPhotos => (_booking?['serviceType'] == 'PASEO') ? 2 : 3;

  int get _photoCount {
    final events = (_booking?['serviceEvents'] as List?) ?? [];
    return events.where((e) => (e as Map)['type'] == 'PHOTO').length;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _isActing = true);
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _accept() => _run(() => _service.acceptBooking(widget.bookingId));

  Future<void> _reject() async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar reserva'),
        content: TextField(
          controller: reasonCtrl,
          maxLength: 300,
          decoration: const InputDecoration(hintText: 'Motivo (opcional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: GardenColors.error, foregroundColor: Colors.white),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text;
    reasonCtrl.dispose();
    if (ok != true) return;
    await _run(() => _service.rejectBooking(widget.bookingId, reason: reason));
  }

  Future<void> _markEnRoute() => _run(() => _service.markEnRoute(widget.bookingId));
  Future<void> _markArrived() => _run(() => _service.markArrived(widget.bookingId));
  Future<void> _confirmEnd(bool accepted) => _run(() => _service.confirmEnd(widget.bookingId, accepted));

  Future<void> _startService() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (picked == null) return;
    await _run(() async {
      final bytes = await picked.readAsBytes();
      final url = await _service.uploadServicePhoto(bytes, picked.name.isEmpty ? 'start.jpg' : picked.name);
      await _service.startService(widget.bookingId, url);
    });
  }

  Future<void> _addPhotoEvent() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (picked == null) return;
    await _run(() async {
      final bytes = await picked.readAsBytes();
      await _service.addEvent(widget.bookingId, bytes, picked.name.isEmpty ? 'event.jpg' : picked.name);
    });
  }

  Future<void> _conclude() => _run(() => _service.concludeService(widget.bookingId));

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
        final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
        final surface = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
        final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

        if (_isLoading || _booking == null) {
          return Scaffold(backgroundColor: bg, body: const Center(child: GardenLoadingIndicator(color: GardenColors.primary)));
        }

        final b = _booking!;
        final status = b['status'] as String;
        final serviceType = b['serviceType'] as String? ?? '';
        final isPaseo = serviceType == 'PASEO';
        final canConclude = _photoCount >= _minPhotos;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            elevation: 0,
            iconTheme: IconThemeData(color: textColor),
            title: Text(b['petName'] as String? ?? 'Reserva', style: TextStyle(color: textColor, fontWeight: FontWeight.w800)),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: borderColor)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row('Dueño', b['clientName'] as String? ?? '-', textColor, subtextColor),
                      _row('Mascota', b['petName'] as String? ?? '-', textColor, subtextColor),
                      _row('Servicio', serviceType, textColor, subtextColor),
                      _row('Estado', status, textColor, subtextColor),
                      if (b['specialNeeds'] != null) _row('Necesidades especiales', b['specialNeeds'] as String, textColor, subtextColor),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                if (widget.canChat) ...[
                  GardenButton(
                    label: 'Chat con el cliente',
                    gIcon: GIcon.chat,
                    outline: true,
                    onPressed: () => context.push('/chat/${widget.bookingId}',
                        extra: {'otherPersonName': b['clientName'] as String? ?? 'Cliente'}),
                  ),
                  const SizedBox(height: 16),
                ],

                if (status == 'WAITING_CAREGIVER_APPROVAL') ...[
                  if (widget.canManageBookings)
                    Row(children: [
                      Expanded(child: GardenButton(label: 'Aceptar', loading: _isActing, onPressed: _isActing ? null : _accept)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GardenButton(
                          label: 'Rechazar',
                          outline: true,
                          color: GardenColors.error,
                          loading: _isActing,
                          onPressed: _isActing ? null : _reject,
                        ),
                      ),
                    ])
                  else
                    Text('Esta reserva espera que el dueño la acepte o la rechace.',
                        style: TextStyle(color: subtextColor, fontSize: 13)),
                  const SizedBox(height: 16),
                ],

                if (status == 'CONFIRMED') ...[
                  GardenButton(label: 'Avisar que voy en camino', outline: true, loading: _isActing, onPressed: _isActing ? null : _markEnRoute),
                  const SizedBox(height: 10),
                  if (isPaseo) ...[
                    GardenButton(label: 'Ya llegué', outline: true, loading: _isActing, onPressed: _isActing ? null : _markArrived),
                    const SizedBox(height: 10),
                  ],
                  GardenButton(label: 'Iniciar servicio (foto)', loading: _isActing, onPressed: _isActing ? null : _startService),
                ],

                if (status == 'IN_PROGRESS') ...[
                  if (b['clientMarkedEndAt'] != null) ...[
                    Text('El dueño marcó el servicio como terminado. Confirmalo:', style: TextStyle(color: subtextColor, fontSize: 13)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: GardenButton(label: 'Confirmar', loading: _isActing, onPressed: _isActing ? null : () => _confirmEnd(true))),
                      const SizedBox(width: 10),
                      Expanded(child: GardenButton(label: 'Rechazar', outline: true, color: GardenColors.error, loading: _isActing, onPressed: _isActing ? null : () => _confirmEnd(false))),
                    ]),
                    const SizedBox(height: 20),
                  ],
                  Text('Fotos del servicio: $_photoCount / $_minPhotos mínimas', style: TextStyle(color: subtextColor, fontSize: 13)),
                  const SizedBox(height: 10),
                  GardenButton(label: 'Agregar foto', outline: true, gIcon: GIcon.foto, loading: _isActing, onPressed: _isActing ? null : _addPhotoEvent),
                  const SizedBox(height: 10),
                  GardenButton(
                    label: canConclude ? 'Concluir servicio' : 'Faltan fotos para concluir',
                    loading: _isActing,
                    onPressed: (_isActing || !canConclude) ? null : _conclude,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _row(String label, String value, Color textColor, Color subtextColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: TextStyle(color: subtextColor, fontSize: 12.5))),
          Expanded(child: Text(value, style: TextStyle(color: textColor, fontSize: 13.5, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
