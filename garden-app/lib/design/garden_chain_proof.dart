import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/garden_theme.dart';
import 'garden_icons.dart';

// ── COMPROBANTE EN BLOCKCHAIN ──────────────────────────────────────────────
// Lo que prometen los Términos (sección 19): cada reserva pagada queda
// registrada en Polygon y el dueño y el cuidador ven el comprobante en el
// detalle de la reserva. Cuatro estados, todos honestos:
//
//   registrada  → enlaces a cada transacción en polygonscan.com
//   pendiente   → todavía no se confirmó (la cola lo envía sola)
//   anterior    → pagada antes de que empezara el registro: se dice
//   de prueba   → reserva de prueba del equipo: no se registra
//
// Nunca se muestra "registrado" sin un txHash real detrás. La red de pruebas
// (Amoy) se nombra como tal: no es un registro permanente.

enum ChainProofStatus { recorded, pending, beforeStart, test, notPaid }

class ChainProofRecord {
  final String kind;
  final String label;
  final String txHash;
  final String? explorerUrl;
  final DateTime? confirmedAt;
  const ChainProofRecord({required this.kind, required this.label, required this.txHash, this.explorerUrl, this.confirmedAt});
}

class ChainProof {
  final ChainProofStatus status;
  final DateTime recordsSince;
  final String? networkName;
  final bool testnet;
  final List<ChainProofRecord> records;

  const ChainProof({
    required this.status,
    required this.recordsSince,
    this.networkName,
    this.testnet = false,
    this.records = const [],
  });

  /// `blockchain` de GET /bookings/:id/history (booking-history.service.ts).
  factory ChainProof.fromJson(Map<String, dynamic> j) {
    final reason = j['reason'] as String?;
    final status = switch (j['status'] as String?) {
      'RECORDED' => ChainProofStatus.recorded,
      'PENDING' => ChainProofStatus.pending,
      _ => reason == 'BEFORE_START'
          ? ChainProofStatus.beforeStart
          : reason == 'TEST_BOOKING' ? ChainProofStatus.test : ChainProofStatus.notPaid,
    };
    final net = j['network'] as Map<String, dynamic>?;
    return ChainProof(
      status: status,
      recordsSince: DateTime.tryParse(j['recordsSince'] as String? ?? '')?.toLocal() ?? DateTime(2026, 10, 4),
      networkName: net?['name'] as String?,
      testnet: net?['testnet'] == true,
      records: [
        for (final r in (j['records'] as List? ?? const []).cast<Map<String, dynamic>>())
          ChainProofRecord(
            kind: r['kind'] as String,
            label: r['label'] as String,
            txHash: r['txHash'] as String,
            explorerUrl: r['explorerUrl'] as String?,
            confirmedAt: DateTime.tryParse(r['confirmedAt'] as String? ?? '')?.toLocal(),
          ),
      ],
    );
  }
}

class GardenChainProof extends StatelessWidget {
  final ChainProof proof;

  /// Abre el enlace de la transacción. Por defecto, en el navegador.
  final void Function(String url)? onOpen;

  const GardenChainProof({super.key, required this.proof, this.onOpen});

  static const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  static const _monthsLong = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  static String _date(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String _longDate(DateTime d) => '${d.day} de ${_monthsLong[d.month - 1]} de ${d.year}';

  static String _shortHash(String h) => h.length > 14 ? '${h.substring(0, 8)}…${h.substring(h.length - 6)}' : h;

  void _open(String url) {
    if (onOpen != null) {
      onOpen!(url);
    } else {
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (proof.status == ChainProofStatus.notPaid) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    final (GIcon icon, GIconState iconState, String title, String body) = switch (proof.status) {
      ChainProofStatus.recorded => (
          GIcon.verificado,
          GIconState.active,
          proof.testnet ? 'Registrada en la red de pruebas' : 'Registrada en blockchain',
          proof.testnet
              ? 'Esta reserva quedó en ${proof.networkName ?? 'una red de pruebas'}, que no es un registro permanente.'
              : 'Esta reserva quedó registrada en la red principal de Polygon. '
                  'Esos registros no se pueden borrar ni modificar, ni siquiera por Garden.',
        ),
      ChainProofStatus.pending => (
          GIcon.esperando,
          GIconState.idle,
          'Registro pendiente',
          'El registro en la red de Polygon todavía no se confirmó. Se hace solo: '
              'cuando esté listo verás aquí el enlace al comprobante.',
        ),
      ChainProofStatus.beforeStart => (
          GIcon.info,
          GIconState.idle,
          'Sin registro en blockchain',
          'Esta reserva se pagó antes del ${_longDate(proof.recordsSince)}, '
              'cuando empezamos a registrar las reservas en blockchain.',
        ),
      _ => (
          GIcon.info,
          GIconState.idle,
          'Sin registro en blockchain',
          'Es una reserva de prueba del equipo de Garden: no se registra.',
        ),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GardenRadius.lg),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GardenIcon(icon, size: GIconSize.lg, state: iconState),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: GardenText.h4.copyWith(color: text, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(body, style: TextStyle(color: sub, fontSize: 12.5, height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
          if (proof.status == ChainProofStatus.recorded) ...[
            const SizedBox(height: 8),
            for (final r in proof.records) _recordRow(r, text, sub, border),
            const SizedBox(height: 6),
            Text(
              'Solo se registran identificadores internos, montos, fechas y estados. Nunca tu nombre ni otros datos personales.',
              style: TextStyle(color: sub, fontSize: 11.5, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  Widget _recordRow(ChainProofRecord r, Color text, Color sub, Color border) {
    final url = r.explorerUrl;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: border)),
      ),
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.label, style: TextStyle(color: text, fontSize: 13, fontWeight: FontWeight.w700)),
                Text(
                  [if (r.confirmedAt != null) _date(r.confirmedAt!), _shortHash(r.txHash)].join(' · '),
                  style: TextStyle(color: sub, fontSize: 11.5),
                ),
              ],
            ),
          ),
          if (url != null)
            TextButton.icon(
              onPressed: () => _open(url),
              icon: const GardenIcon(GIcon.abrirFuera, size: GIconSize.sm),
              label: const Text('Ver en Polygonscan'),
              style: TextButton.styleFrom(
                foregroundColor: GardenColors.primary,
                textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
        ],
      ),
    );
  }
}
