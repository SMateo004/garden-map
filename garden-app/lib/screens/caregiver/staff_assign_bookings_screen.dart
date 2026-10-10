import 'package:flutter/material.dart';

import '../../design/garden_service.dart';
import '../../design/garden_service_icon.dart';
import '../../design/garden_status_pill.dart';
import '../../narrative/booking_story.dart';
import '../../services/caregiver_staff_service.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/garden_loading_indicator.dart';

/// El dueño asigna sus reservas (por aceptar, confirmadas o en curso) a empleados activos.
/// Al empleado le llega un aviso y la ve en "Asignadas a mí". Asignar no cambia quién
/// cobra: la reserva sigue siendo de la empresa.
class StaffAssignBookingsScreen extends StatefulWidget {
  final List<Map<String, dynamic>> activeMembers;
  const StaffAssignBookingsScreen({super.key, required this.activeMembers});

  @override
  State<StaffAssignBookingsScreen> createState() => _StaffAssignBookingsScreenState();
}

class _StaffAssignBookingsScreenState extends State<StaffAssignBookingsScreen> {
  static const _assignable = {'WAITING_CAREGIVER_APPROVAL', 'CONFIRMED', 'IN_PROGRESS'};

  final _service = CaregiverStaffService();
  bool _loading = true;
  String? _saving;
  List<Map<String, dynamic>> _bookings = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final all = await _service.getOwnerBookings();
      if (mounted) setState(() => _bookings = all.where((b) => _assignable.contains(b['status'])).toList());
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _assign(Map<String, dynamic> booking, String? memberId) async {
    final id = booking['id'] as String;
    setState(() => _saving = id);
    try {
      await _service.assignBooking(id, memberId);
      if (!mounted) return;
      setState(() => booking['assignedStaffMemberId'] = memberId);
      GardenSnackBar.success(context, memberId == null ? 'Asignación quitada' : 'Reserva asignada');
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  String _name(Map<String, dynamic> m) => '${m['firstName'] ?? ''} ${m['lastName'] ?? ''}'.trim();

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final memberIds = widget.activeMembers.map((m) => m['id']).toSet();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        title: Text('Asignar reservas', style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: _loading
          ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_bookings.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text('No hay reservas para asignar.', style: TextStyle(color: subtextColor))),
                    ),
                  for (final b in _bookings)
                    Builder(builder: (context) {
                      final status = b['status'] as String;
                      final service = GardenService.fromApi(b['serviceType'] as String?) ?? GardenService.paseo;
                      final story = BookingStory.of(status, BookingStoryContext.fromBooking(b, caregiverView: true));
                      final current = b['assignedStaffMemberId'] as String?;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            GardenServiceIcon(service, size: 28, live: status == 'IN_PROGRESS'),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text('${b['petName'] ?? 'Mascota'} · ${b['clientName'] ?? ''}',
                                  style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                            ),
                            GardenStatusPill(story, service: service, dense: true),
                          ]),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String?>(
                            initialValue: memberIds.contains(current) ? current : null,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Asignada a',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            items: [
                              const DropdownMenuItem<String?>(value: null, child: Text('Sin asignar')),
                              for (final m in widget.activeMembers)
                                DropdownMenuItem<String?>(value: m['id'] as String, child: Text(_name(m))),
                            ],
                            onChanged: _saving == b['id'] ? null : (v) => _assign(b, v),
                          ),
                        ]),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
