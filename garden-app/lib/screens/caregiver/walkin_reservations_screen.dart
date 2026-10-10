import 'package:flutter/material.dart';

import '../../design/garden_icons.dart';
import '../../services/caregiver_crm_service.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/garden_loading_indicator.dart';
import 'walkin_clients_screen.dart';

/// 'AAAA-MM-DD' de una fecha local (lo que espera el backend para reservas de mostrador).
String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 'AAAA-MM-DD' → 'DD/MM'.
String shortDay(String iso) {
  final p = iso.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}' : iso;
}

/// Corre una acción de recepción que puede chocar con el cupo lleno (CAPACITY_FULL).
/// Al dueño le pregunta si igual quiere pasar el cupo y reintenta con force; al empleado le
/// llega el error tal cual (el backend ya le dice que solo el dueño puede). Devuelve null si
/// el dueño eligió no pasar el cupo.
Future<T?> runWithCapacityCheck<T>(
  BuildContext context, {
  required bool isOwner,
  required Future<T> Function(bool force) action,
}) async {
  try {
    return await action(false);
  } on CrmApiException catch (e) {
    if (e.code != 'CAPACITY_FULL' || !isOwner || !context.mounted) rethrow;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cupo lleno'),
        content: Text(e.message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No registrar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: GardenColors.warning, foregroundColor: Colors.white),
            child: const Text('Pasar el cupo'),
          ),
        ],
      ),
    );
    if (ok != true) return null;
    return action(true);
  }
}

/// Reservas de mostrador: lugares guardados para mascotas que llegan sin la app. Ocupan el
/// cupo igual que una reserva de la app, así el marketplace no vende ese lugar.
class WalkInReservationsScreen extends StatefulWidget {
  final CaregiverCrmService service;
  final bool isOwner;
  const WalkInReservationsScreen({super.key, required this.service, required this.isOwner});

  @override
  State<WalkInReservationsScreen> createState() => _WalkInReservationsScreenState();
}

class _WalkInReservationsScreenState extends State<WalkInReservationsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _reservations = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await widget.service.listReservations();
      if (mounted) setState(() => _reservations = rows);
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar reserva'),
        content: Text('Se libera el lugar de ${r['petName']} del ${shortDay(r['startDate'] as String)} al ${shortDay(r['endDate'] as String)}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: GardenColors.error, foregroundColor: Colors.white),
            child: const Text('Cancelar reserva'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.service.cancelReservation(r['id'] as String);
      if (!mounted) return;
      GardenSnackBar.success(context, 'Reserva cancelada');
      _load();
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, friendlyError(e));
    }
  }

  Future<void> _checkIn(Map<String, dynamic> r) async {
    try {
      await widget.service.checkIn(
        r['petId'] as String,
        serviceType: r['serviceType'] as String,
        reservationId: r['id'] as String,
      );
      if (!mounted) return;
      GardenSnackBar.success(context, 'Entrada de ${r['petName']} registrada');
      _load();
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final today = isoDay(DateTime.now());

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        title: Text('Reservas de mostrador', style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: _loading
          ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text('Para reservar fechas, entra a "Check-in walk-in", elige la mascota y marca "Reservar fechas".',
                      style: TextStyle(color: subtextColor, fontSize: 12.5)),
                  const SizedBox(height: 12),
                  if (_reservations.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text('No hay reservas de mostrador próximas.', style: TextStyle(color: subtextColor))),
                    ),
                  for (final r in _reservations)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: r['overCapacity'] == true ? GardenColors.warning : borderColor),
                      ),
                      child: Row(children: [
                        GardenIcon(r['serviceType'] == 'HOSPEDAJE' ? GIcon.hospedaje : GIcon.guarderia,
                            size: GIconSize.lg, state: GIconState.active),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${r['petName']} · ${r['clientName']}',
                                style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(
                              r['serviceType'] == 'HOSPEDAJE'
                                  ? 'Del ${shortDay(r['startDate'] as String)} al ${shortDay(r['endDate'] as String)}'
                                  : 'Guardería el ${shortDay(r['startDate'] as String)}',
                              style: TextStyle(color: subtextColor, fontSize: 12),
                            ),
                            if (r['status'] == 'CHECKED_IN')
                              const Text('Ya está en el local',
                                  style: TextStyle(color: GardenColors.success, fontSize: 12, fontWeight: FontWeight.w600)),
                            if (r['overCapacity'] == true)
                              const Text('Cargada por encima del cupo',
                                  style: TextStyle(color: GardenColors.warning, fontSize: 12, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                        if (r['status'] == 'RESERVED') ...[
                          if ((r['startDate'] as String).compareTo(today) <= 0)
                            TextButton(onPressed: () => _checkIn(r), child: const Text('Entrada')),
                          IconButton(
                            tooltip: 'Cancelar reserva',
                            icon: const GardenIcon(GIcon.cerrar, size: GIconSize.md, color: GardenColors.error),
                            onPressed: () => _cancel(r),
                          ),
                        ],
                      ]),
                    ),
                ],
              ),
            ),
    );
  }
}
