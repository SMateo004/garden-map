import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';
import '../../utils/txt_saver.dart';
import '../../widgets/garden_loading_indicator.dart';

/// Pantalla de solo-auditoría: un archivo .txt descargable por mes, con TODO
/// el registro de auditoría del sistema (AuditLog) — quién hizo qué, cuándo,
/// sobre qué. Generado automáticamente al pedirlo (nada se pre-genera ni se
/// guarda aparte); simplemente se lee del log en el momento de la descarga.
class AuditScreen extends StatefulWidget {
  final String adminToken;
  const AuditScreen({super.key, required this.adminToken});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  String? _downloadingMonth;
  String? _error;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  static const _monthNames = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  /// Últimos 24 meses (incluye el actual) — no depende de saber de antemano
  /// si hay datos ese mes; si no hay, el TXT simplemente sale con 0 registros.
  List<(int year, int month)> get _months {
    final now = DateTime.now();
    return List.generate(24, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return (d.year, d.month);
    });
  }

  Future<void> _download(int year, int month) async {
    final monthStr = '$year-${month.toString().padLeft(2, '0')}';
    setState(() { _downloadingMonth = monthStr; _error = null; });
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/admin/audit-log/export?month=$monthStr'),
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );
      if (res.statusCode != 200) {
        throw Exception('Error ${res.statusCode} al generar la auditoría');
      }
      await saveTxt(res.body, 'garden-audit-$monthStr.txt');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Auditoría de ${_monthNames[month - 1]} $year descargada'),
          backgroundColor: GardenColors.success,
        ));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _downloadingMonth = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.fact_check_outlined, color: GardenColors.primary, size: 22),
            const SizedBox(width: 8),
            Text('Auditoría', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 6),
          Text(
            'Un archivo .txt por mes con TODO el registro de auditoría del sistema '
            '(pagos aprobados/rechazados, reembolsos, disputas resueltas, retiros, '
            'suspensiones — quién, qué, cuándo). Se genera al momento de descargar, '
            'directo del log real — nada queda pre-armado ni se puede editar.',
            style: TextStyle(color: subtextColor, fontSize: 13, height: 1.4),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: GardenColors.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
              child: Text(_error!, style: const TextStyle(color: GardenColors.error, fontSize: 12)),
            ),
          ],
          const SizedBox(height: 20),
          ..._months.map((m) {
            final (year, month) = m;
            final monthStr = '$year-${month.toString().padLeft(2, '0')}';
            final isDownloading = _downloadingMonth == monthStr;
            final isCurrent = year == DateTime.now().year && month == DateTime.now().month;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: surfaceEl,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: GardenColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.description_outlined, size: 18, color: GardenColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(children: [
                    Text('${_monthNames[month - 1]} $year', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                    if (isCurrent) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: GardenColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                        child: const Text('En curso', style: TextStyle(color: GardenColors.success, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ]),
                ),
                OutlinedButton.icon(
                  onPressed: isDownloading ? null : () => _download(year, month),
                  icon: isDownloading
                      ? const GardenLoadingIndicator(size: 14, color: GardenColors.primary)
                      : const Icon(Icons.download_rounded, size: 16),
                  label: Text(isDownloading ? 'Generando...' : 'Descargar .txt'),
                  style: OutlinedButton.styleFrom(foregroundColor: GardenColors.primary, side: const BorderSide(color: GardenColors.primary)),
                ),
              ]),
            );
          }),
        ],
      ),
    );
  }
}
