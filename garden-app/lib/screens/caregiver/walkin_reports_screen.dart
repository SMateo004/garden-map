import 'package:flutter/material.dart';
import '../../theme/garden_theme.dart';
import '../../services/caregiver_crm_service.dart';
import '../../widgets/garden_loading_indicator.dart';

/// Reportes de negocio — solo dueño (nunca montado para staff, ni en el
/// backend ni acá). Ocupación histórica + cierre de caja de walk-ins, mismo
/// estilo de tarjetas numéricas que caregiver_home_screen.dart (no hay
/// librería de gráficos en el proyecto).
class WalkInReportsScreen extends StatefulWidget {
  final CaregiverCrmService service;
  const WalkInReportsScreen({super.key, required this.service});

  @override
  State<WalkInReportsScreen> createState() => _WalkInReportsScreenState();
}

class _WalkInReportsScreenState extends State<WalkInReportsScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _occupancy;
  Map<String, dynamic>? _cash;
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _iso(DateTime d) => d.toIso8601String().split('T').first;

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        widget.service.getOccupancyReport(from: _iso(_from), to: _iso(_to)),
        widget.service.getCashReport(from: _iso(_from), to: _iso(_to)),
      ]);
      if (mounted) setState(() {
        _occupancy = results[0];
        _cash = results[1];
      });
    } catch (e) {
      if (mounted) GardenErrorDialog.show(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (range == null) return;
    setState(() {
      _from = range.start;
      _to = range.end;
    });
    _load();
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

        Widget statCard(String label, String value, IconData icon, {Color? color}) => Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: borderColor)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: color ?? GardenColors.primary, size: 20),
                  const SizedBox(height: 10),
                  Text(value, style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(label, style: TextStyle(color: subtextColor, fontSize: 12)),
                ],
              ),
            );

        final peak = _occupancy?['peakDay'] as Map<String, dynamic>?;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            elevation: 0,
            title: Text('Reportes', style: TextStyle(color: textColor, fontWeight: FontWeight.w800)),
            iconTheme: IconThemeData(color: textColor),
            actions: [IconButton(onPressed: _pickRange, icon: const Icon(Icons.date_range_rounded), color: GardenColors.primary)],
          ),
          body: _isLoading
              ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                    children: [
                      Text(
                        '${_iso(_from)} → ${_iso(_to)}',
                        style: TextStyle(color: subtextColor, fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 16),
                      Text('Ocupación', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.5,
                        children: [
                          statCard('Ocupación promedio/día', '${_occupancy?['avgOccupancy'] ?? '—'} de ${_occupancy?['capacity'] ?? '—'}', Icons.pets_rounded),
                          statCard(
                            'Día pico',
                            peak != null ? '${peak['count']} el ${peak['date']}' : '—',
                            Icons.trending_up_rounded,
                            color: GardenColors.warning,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text('Cierre de caja walk-in', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text('Solo informativo — no pasa por Garden ni tiene comisión.', style: TextStyle(color: subtextColor, fontSize: 11.5)),
                      const SizedBox(height: 10),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.5,
                        children: [
                          statCard('Total cobrado', 'Bs ${((_cash?['totalCollected'] as num?) ?? 0).toStringAsFixed(2)}', Icons.payments_outlined, color: GardenColors.success),
                          statCard('Promedio por visita', 'Bs ${((_cash?['avgCollected'] as num?) ?? 0).toStringAsFixed(2)}', Icons.calculate_outlined),
                          statCard('Visitas con monto cargado', '${_cash?['visitsWithAmount'] ?? 0}', Icons.check_circle_outline),
                          statCard('Total visitas cerradas', '${_cash?['totalCheckedOutVisits'] ?? 0}', Icons.event_available_outlined),
                        ],
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}
