import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../design/garden_chain_proof.dart';
import '../design/garden_icons.dart';
import '../theme/garden_theme.dart';

String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

/// Sección de detalle al final de una reserva pasada: cómo se pagó (QR,
/// tarjeta, billetera…) y todo lo que pasó, en orden. La usan el dueño y el
/// cuidador. Se carga sola al aparecer — no es un botón ni una pantalla aparte.
class BookingHistoryDetail extends StatefulWidget {
  final String bookingId;
  final String token;
  final bool isDark;
  const BookingHistoryDetail({super.key, required this.bookingId, required this.token, required this.isDark});

  /// Solo las reservas ya cerradas muestran el historial.
  static bool appliesTo(String? status) =>
      status == 'COMPLETED' || status == 'CANCELLED' || status == 'REJECTED_BY_CAREGIVER';

  @override
  State<BookingHistoryDetail> createState() => _BookingHistoryDetailState();
}

class _BookingHistoryDetailState extends State<BookingHistoryDetail> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/bookings/${widget.bookingId}/history'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      final body = jsonDecode(res.body);
      if (body['success'] == true) {
        if (mounted) setState(() { _data = body['data'] as Map<String, dynamic>; _loading = false; });
      } else {
        throw Exception(body['error']?['message'] ?? 'No se pudo cargar el historial');
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  static String _bs(num v) => 'Bs ${v.toStringAsFixed(2)}';

  static String _fmt(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    const m = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${m[d.month - 1]} ${d.year} · $hh:$mm';
  }

  static GIcon _methodIcon(String method) => switch (method) {
        'WALLET' => GIcon.billetera,
        'QR' || 'WALLET_QR' => GIcon.pagarQr,
        'PENDING' => GIcon.esperando,
        _ => GIcon.pagoProtegido,
      };

  static GIcon _kindIcon(String kind) => switch (kind) {
        'CREATED' => GIcon.reservas,
        'PAYMENT_REQUESTED' => GIcon.esperando,
        'PAID' => GIcon.pagoProtegido,
        'EN_ROUTE' => GIcon.enVivo,
        'ARRIVED' => GIcon.ubicacion,
        'STARTED' => GIcon.cronometro,
        'EXTENSION' || 'EXTENSION_REQUESTED' => GIcon.repetir,
        'INCIDENT' || 'ACCIDENT' || 'ILLNESS' || 'COMPLICATION' || 'CLIENT_SOS' => GIcon.emergencia,
        'INCIDENT_RESOLVED' => GIcon.confirmado,
        'NOTE' || 'WALK_UPDATE' => GIcon.nota,
        'PHOTO' => GIcon.foto,
        'CLIENT_MARKED_END' || 'ENDED' => GIcon.terminado,
        'CANCELLED' => GIcon.cancelado,
        'REFUND' => GIcon.reembolso,
        'RATED' => GIcon.estrella,
        'AUTO_RELEASE' || 'PAYOUT' => GIcon.billetera,
        'DISPUTE_OPENED' || 'DISPUTE_APPEALED' || 'DISPUTE_RESOLVED' || 'APPEAL_RESOLVED' => GIcon.enRevision,
        'CHAIN_RECORD' => GIcon.verificado,
        _ => GIcon.reloj,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtext = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    Widget content;
    if (_loading) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    } else if (_error != null) {
      content = Row(children: [
        Expanded(child: Text(_error!, style: TextStyle(color: subtext, fontSize: 12.5))),
        TextButton(onPressed: _load, child: const Text('Reintentar')),
      ]);
    } else {
      content = _body(textColor, subtext, border);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, color: border),
          const SizedBox(height: 14),
          Text('Pago e historial', style: GardenText.h4.copyWith(color: textColor, fontSize: 15)),
          const SizedBox(height: 10),
          content,
        ],
      ),
    );
  }

  Widget _body(Color textColor, Color subtext, Color border) {
    final d = _data!;
    final pay = d['payment'] as Map<String, dynamic>;
    final timeline = (d['timeline'] as List).cast<Map<String, dynamic>>();
    final movements = (d['movements'] as List).cast<Map<String, dynamic>>();
    final isClient = d['viewerRole'] == 'CLIENT';
    final chain = d['blockchain'] as Map<String, dynamic>?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paymentCard(pay, isClient, textColor, subtext, border),
        if (chain != null) ...[
          const SizedBox(height: 14),
          GardenChainProof(proof: ChainProof.fromJson(chain)),
        ],
        const SizedBox(height: 16),
        Text('Qué pasó', style: TextStyle(color: subtext, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        const SizedBox(height: 10),
        for (var i = 0; i < timeline.length; i++)
          _timelineRow(timeline[i], isLast: i == timeline.length - 1, textColor: textColor, subtext: subtext, border: border),
        if (movements.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Movimientos de dinero', style: TextStyle(color: subtext, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(height: 4),
          for (var i = 0; i < movements.length; i++) ...[
            if (i > 0) Divider(height: 1, color: border),
            _movementRow(movements[i], textColor, subtext),
          ],
        ],
      ],
    );
  }

  Widget _paymentCard(Map<String, dynamic> pay, bool isClient, Color textColor, Color subtext, Color border) {
    final method = pay['method'] as String;
    final status = pay['status'] as String;
    final wallet = (pay['walletAmount'] as num).toDouble();
    final external = (pay['externalAmount'] as num).toDouble();
    final donation = (pay['donationAmount'] as num?)?.toDouble() ?? 0;
    final tip = (pay['tipAmount'] as num?)?.toDouble() ?? 0;
    final refund = (pay['refundAmount'] as num?)?.toDouble();
    final ref = pay['reference'] as String?;
    final paidAt = pay['paidAt'] as String?;

    final statusLabel = switch (status) {
      'PAID' => 'Pagado',
      'REFUNDED' => 'Reembolsado',
      'PARTIALLY_REFUNDED' => 'Reembolso parcial',
      _ => 'Pendiente',
    };
    final statusColor = switch (status) {
      'PAID' => GardenColors.success,
      'REFUNDED' || 'PARTIALLY_REFUNDED' => GardenColors.warning,
      _ => subtext,
    };

    Widget line(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Expanded(child: Text(label, style: TextStyle(color: subtext, fontSize: 13))),
              Text(value, style: TextStyle(color: textColor, fontSize: 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
            ],
          ),
        );

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GardenIcon(_methodIcon(method), size: GIconSize.lg, state: GIconState.active),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Método de pago', style: TextStyle(color: subtext, fontSize: 11, fontWeight: FontWeight.w600)),
                    Text(pay['methodLabel'] as String, style: GardenText.h4.copyWith(color: textColor, fontSize: 15)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(GardenRadius.full),
                ),
                child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          line(isClient ? 'Total pagado' : 'Total de la reserva', _bs(pay['totalAmount'] as num), bold: true),
          if (method != 'PENDING' && wallet > 0) line('Con billetera', _bs(wallet)),
          if (method != 'PENDING' && external > 0.005) line(_externalLabel(method), _bs(external)),
          if (donation > 0) line('Donación', _bs(donation)),
          if (tip > 0) line(isClient ? 'Propina' : 'Propina recibida', _bs(tip)),
          if (!isClient && pay['caregiverNetAmount'] != null) ...[
            line('Comisión Garden', _bs(pay['commissionAmount'] as num)),
            if ((pay['taxAmount'] as num) > 0) line('Impuestos', _bs(pay['taxAmount'] as num)),
            line('Tu ganancia', _bs(pay['caregiverNetAmount'] as num), bold: true),
          ],
          if (refund != null && refund > 0) line('Reembolso', _bs(refund)),
          if (paidAt != null) line('Fecha de pago', _fmt(paidAt)),
          if (ref != null) line('Referencia', '…$ref'),
        ],
    );
  }

  static String _externalLabel(String method) => switch (method) {
        'CARD' || 'WALLET_CARD' => 'Con tarjeta',
        'QR' || 'WALLET_QR' => 'Con QR bancario',
        _ => 'Otro método',
      };

  Widget _timelineRow(Map<String, dynamic> e, {required bool isLast, required Color textColor, required Color subtext, required Color border}) {
    final detail = e['detail'] as String?;
    final amount = (e['amount'] as num?)?.toDouble();
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                GardenIcon(_kindIcon(e['kind'] as String), size: GIconSize.md, state: GIconState.active),
                if (!isLast) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 4), color: border)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e['title'] as String, style: TextStyle(color: textColor, fontSize: 13.5, fontWeight: FontWeight.w700)),
                  if (detail != null && detail.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(detail, style: TextStyle(color: subtext, fontSize: 12.5)),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    '${_fmt(e['at'] as String)} · ${_actor(e['actor'] as String)}${amount != null ? ' · ${_bs(amount)}' : ''}',
                    style: TextStyle(color: subtext, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _actor(String a) => switch (a) {
        'CLIENTE' => 'Dueño',
        'CUIDADOR' => 'Cuidador',
        'SOPORTE' => 'Soporte Garden',
        _ => 'Sistema',
      };

  Widget _movementRow(Map<String, dynamic> m, Color textColor, Color subtext) {
    final amount = (m['amount'] as num).toDouble();
    final status = m['status'] as String;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m['label'] as String, style: TextStyle(color: textColor, fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  '${_fmt(m['at'] as String)}${status != 'COMPLETED' ? ' · ${status == 'PENDING' ? 'pendiente' : 'rechazado'}' : ''}',
                  style: TextStyle(color: subtext, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Text(
            _bs(amount),
            style: TextStyle(color: textColor, fontSize: 13.5, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
