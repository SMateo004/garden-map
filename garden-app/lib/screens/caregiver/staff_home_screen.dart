import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';
import '../../services/auth_service.dart';
import '../../services/caregiver_staff_service.dart';
import '../../widgets/garden_loading_indicator.dart';

/// Dashboard reducido del empleado de una empresa cuidadora: solo ve y
/// atiende reservas (check-in/check-out). Sin billetera, chat, precios ni
/// configuración — no existen rutas para eso en /api/caregiver-staff/*, así
/// que ni siquiera hay algo que mostrar acá para esas secciones.
class StaffHomeScreen extends StatefulWidget {
  const StaffHomeScreen({super.key});

  @override
  State<StaffHomeScreen> createState() => _StaffHomeScreenState();
}

class _StaffHomeScreenState extends State<StaffHomeScreen> {
  final _service = CaregiverStaffService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _bookings = [];
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final bookings = await _service.getBookings();
      if (mounted) setState(() => _bookings = bookings);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    await AuthService().clearToken();
    if (mounted) context.go('/login');
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'CONFIRMED': return 'Confirmada';
      case 'WAITING_CAREGIVER_APPROVAL': return 'Esperando aprobación';
      case 'IN_PROGRESS': return 'En curso';
      case 'COMPLETED': return 'Completada';
      case 'CANCELLED': return 'Cancelada';
      case 'PENDING_MG': return 'Meet & Greet pendiente';
      default: return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'IN_PROGRESS': return GardenColors.primary;
      case 'CONFIRMED': return GardenColors.success;
      case 'COMPLETED': return Colors.grey;
      case 'CANCELLED': return GardenColors.error;
      default: return GardenColors.warning;
    }
  }

  String _serviceEmoji(String type) {
    switch (type) {
      case 'PASEO': return '🐕';
      case 'HOSPEDAJE': return '🏠';
      case 'GUARDERIA': return '🏡';
      default: return '📋';
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
            index: _tab,
            children: [
              _buildBookingsTab(surface, textColor, subtextColor, borderColor),
              _buildAccountTab(textColor, subtextColor, borderColor),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            backgroundColor: surface,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.event_note_outlined), selectedIcon: Icon(Icons.event_note_rounded), label: 'Reservas'),
              NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Cuenta'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBookingsTab(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    if (_isLoading) return const Center(child: GardenLoadingIndicator(color: GardenColors.primary));
    if (_bookings.isEmpty) {
      return Center(
        child: Text('No hay reservas todavía.', style: TextStyle(color: subtextColor, fontSize: 14)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _bookings.length,
        itemBuilder: (context, index) {
          final b = _bookings[index];
          final status = b['status'] as String;
          final serviceType = b['serviceType'] as String? ?? '';
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => StaffBookingDetailScreen(bookingId: b['id'] as String),
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
                  Text(_serviceEmoji(serviceType), style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b['petName'] as String? ?? 'Mascota', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(b['clientName'] as String? ?? '', style: TextStyle(color: subtextColor, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                    child: Text(_statusLabel(status), style: TextStyle(color: _statusColor(status), fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAccountTab(Color textColor, Color subtextColor, Color borderColor) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cuenta', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.business_rounded, color: subtextColor),
            title: Text('Empresa', style: TextStyle(color: textColor)),
            subtitle: Text(AuthState.staffCompanyName, style: TextStyle(color: subtextColor)),
          ),
          Divider(color: borderColor),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout_rounded, color: GardenColors.error),
            title: const Text('Cerrar sesión', style: TextStyle(color: GardenColors.error, fontWeight: FontWeight.w600)),
            onTap: _logout,
          ),
        ],
      ),
    );
  }
}

/// Detalle de una reserva desde el punto de vista del staff — mismas
/// acciones operativas que el dueño (avisar en camino, llegué, iniciar,
/// agregar fotos, concluir) pero sin nada de chat/billetera/precios.
class StaffBookingDetailScreen extends StatefulWidget {
  final String bookingId;
  const StaffBookingDetailScreen({super.key, required this.bookingId});

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

                if (status == 'CONFIRMED') ...[
                  GardenButton(label: 'Avisar que voy en camino', outline: true, loading: _isActing, onPressed: _isActing ? null : _markEnRoute),
                  const SizedBox(height: 10),
                  if (isPaseo) ...[
                    GardenButton(label: '📍 Ya llegué', outline: true, loading: _isActing, onPressed: _isActing ? null : _markArrived),
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
                  GardenButton(label: 'Agregar foto', outline: true, icon: Icons.camera_alt_outlined, loading: _isActing, onPressed: _isActing ? null : _addPhotoEvent),
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
