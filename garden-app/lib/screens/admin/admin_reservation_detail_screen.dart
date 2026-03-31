import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';

class AdminReservationDetailScreen extends StatefulWidget {
  final String bookingId;
  const AdminReservationDetailScreen({super.key, required this.bookingId});

  @override
  State<AdminReservationDetailScreen> createState() => _AdminReservationDetailScreenState();
}

class _AdminReservationDetailScreenState extends State<AdminReservationDetailScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  String _adminToken = '';
  late TabController _tabController;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://garden-api-1ldd.onrender.com/api');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _adminToken = prefs.getString('access_token') ?? '';
    await _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/admin/reservations/${widget.bookingId}'),
        headers: {'Authorization': 'Bearer $_adminToken'},
      );
      final body = jsonDecode(res.body);
      if (body['success'] == true) {
        setState(() { _data = body['data'] as Map<String, dynamic>; _loading = false; });
      } else {
        setState(() { _error = body['error']?['message'] ?? 'Error al cargar reserva'; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final bg = isDark ? GardenColors.darkBackground : const Color(0xFFF7F8FA);
        final surface = isDark ? GardenColors.darkSurface : Colors.white;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
        final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
        final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: surface,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: textColor),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Detalle de Reserva', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: GardenColors.primary)),
              if (_data != null)
                Text(_data!['id'].toString().substring(0, 12).toUpperCase(),
                  style: TextStyle(fontSize: 10, color: subtextColor, fontFamily: 'monospace')),
            ]),
            actions: [
              if (_data != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _statusBadge(_data!['status'] as String? ?? ''),
                ),
            ],
            bottom: _loading ? null : TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: GardenColors.primary,
              unselectedLabelColor: subtextColor,
              indicatorColor: GardenColors.primary,
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              tabs: const [
                Tab(text: 'General'),
                Tab(text: 'Pago'),
                Tab(text: 'Servicio'),
                Tab(text: 'Reseña'),
                Tab(text: 'Chat'),
                Tab(text: 'Disputa'),
              ],
            ),
          ),
          body: _loading
            ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
            : _error != null
              ? _buildError()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildGeneralTab(surface, textColor, subtextColor, borderColor, bg),
                    _buildPaymentTab(surface, textColor, subtextColor, borderColor, bg),
                    _buildServiceTab(surface, textColor, subtextColor, borderColor, bg),
                    _buildReviewTab(surface, textColor, subtextColor, borderColor),
                    _buildChatTab(surface, textColor, subtextColor, borderColor),
                    _buildDisputeTab(surface, textColor, subtextColor, borderColor),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildError() => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline_rounded, size: 48, color: GardenColors.error),
      const SizedBox(height: 12),
      Text(_error!, style: const TextStyle(color: GardenColors.error), textAlign: TextAlign.center),
      const SizedBox(height: 16),
      ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
    ]),
  ));

  // ── TAB 1: GENERAL ──────────────────────────────────────────
  Widget _buildGeneralTab(Color surface, Color textColor, Color subtextColor, Color borderColor, Color bg) {
    final d = _data!;
    final isPaseo = d['serviceType'] == 'PASEO';
    return ListView(padding: const EdgeInsets.all(16), children: [

      // Service info header
      _card(surface, borderColor, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: GardenColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(isPaseo ? Icons.directions_walk_rounded : Icons.home_rounded, color: GardenColors.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isPaseo ? 'Paseo' : 'Hospedaje',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
            Text('${d['petName']}${d['petBreed'] != null ? ' · ${d['petBreed']}' : ''}',
              style: TextStyle(color: subtextColor, fontSize: 13)),
          ])),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          if (isPaseo) ...[
            _infoChip(Icons.calendar_today_outlined, d['walkDate'] ?? '—', subtextColor),
            const SizedBox(width: 8),
            if (d['timeSlot'] != null) _infoChip(Icons.schedule_outlined, d['timeSlot'].toString(), subtextColor),
            if (d['startTime'] != null) _infoChip(Icons.access_time_rounded, d['startTime'].toString(), subtextColor),
          ] else ...[
            _infoChip(Icons.calendar_today_outlined, '${d['startDate'] ?? '?'} → ${d['endDate'] ?? '?'}', subtextColor),
            if (d['totalDays'] != null) ...[
              const SizedBox(width: 8),
              _infoChip(Icons.nights_stay_outlined, '${d['totalDays']} días', subtextColor),
            ],
          ],
        ]),
      ])),

      // Mascota
      _sectionTitle('MASCOTA', Icons.pets_rounded),
      _card(surface, borderColor, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (d['petPhotoUrl'] != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(d['petPhotoUrl'] as String, width: 56, height: 56, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(width: 56, height: 56, color: borderColor,
                  child: Icon(Icons.pets_rounded, color: subtextColor))),
            )
          else
            Container(width: 56, height: 56, decoration: BoxDecoration(color: GardenColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.pets_rounded, color: GardenColors.primary, size: 28)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d['petName'] as String? ?? '—', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textColor)),
            if (d['petBreed'] != null) Text(d['petBreed'] as String, style: TextStyle(color: subtextColor, fontSize: 12)),
            Row(children: [
              if (d['petAge'] != null) _miniTag('${d['petAge']} años', Colors.teal),
              if (d['petSize'] != null) ...[const SizedBox(width: 6), _miniTag(d['petSize'].toString(), GardenColors.primary)],
            ]),
          ])),
        ]),
        if (d['specialNeeds'] != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: GardenColors.warning.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8),
              border: Border.all(color: GardenColors.warning.withValues(alpha: 0.3))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_rounded, size: 16, color: GardenColors.warning),
              const SizedBox(width: 6),
              Expanded(child: Text(d['specialNeeds'] as String,
                style: const TextStyle(fontSize: 12, color: GardenColors.warning))),
            ]),
          ),
        ],
      ])),

      // Cliente
      _sectionTitle('CLIENTE / DUEÑO', Icons.person_outline_rounded),
      _card(surface, borderColor, child: Column(children: [
        Row(children: [
          GardenAvatar(imageUrl: null, size: 44, initials: (d['clientName'] as String? ?? 'C')[0]),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d['clientName'] as String? ?? '—', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textColor)),
            Text(d['clientEmail'] as String? ?? '—', style: TextStyle(color: subtextColor, fontSize: 12)),
            if (d['clientPhone'] != null)
              Text(d['clientPhone'] as String, style: const TextStyle(color: GardenColors.primary, fontSize: 12)),
          ])),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _outlineBtn(Icons.visibility_outlined, 'Ver perfil cliente', () {
            // Navigate to client view (same admin panel but with user info)
            _showUserQuickView(context, {
              'name': d['clientName'],
              'email': d['clientEmail'],
              'phone': d['clientPhone'],
              'role': 'CLIENT',
              'id': d['clientId'],
            }, surface, textColor, subtextColor, borderColor);
          })),
          const SizedBox(width: 8),
          Expanded(child: _outlineBtn(Icons.copy_rounded, 'Copiar email', () {
            Clipboard.setData(ClipboardData(text: d['clientEmail'] as String? ?? ''));
            _snack('Email copiado');
          })),
        ]),
      ])),

      // Cuidador
      _sectionTitle('CUIDADOR', Icons.supervisor_account_outlined),
      _card(surface, borderColor, child: Column(children: [
        Row(children: [
          GardenAvatar(imageUrl: null, size: 44, initials: (d['caregiverName'] as String? ?? 'C')[0]),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d['caregiverName'] as String? ?? '—', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textColor)),
            Text(d['caregiverEmail'] as String? ?? '—', style: TextStyle(color: subtextColor, fontSize: 12)),
            if (d['caregiverPhone'] != null)
              Text(d['caregiverPhone'] as String, style: const TextStyle(color: GardenColors.primary, fontSize: 12)),
          ])),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _outlineBtn(Icons.manage_accounts_outlined, 'Ver perfil admin', () {
            context.push('/admin'); // go back to admin and navigate from there
          })),
          const SizedBox(width: 8),
          Expanded(child: _outlineBtn(Icons.copy_rounded, 'Copiar email', () {
            Clipboard.setData(ClipboardData(text: d['caregiverEmail'] as String? ?? ''));
            _snack('Email copiado');
          })),
        ]),
      ])),

      // Timestamps
      _sectionTitle('FECHAS Y ESTADO', Icons.schedule_outlined),
      _card(surface, borderColor, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _dataRow('Creada', _fmtDate(d['createdAt'] as String? ?? ''), textColor, subtextColor),
        _dataRow('Actualizada', _fmtDate(d['updatedAt'] as String? ?? ''), textColor, subtextColor),
        if (d['cancelledAt'] != null) _dataRow('Cancelada', _fmtDate(d['cancelledAt'] as String), textColor, subtextColor),
        if (d['cancellationReason'] != null) _dataRow('Motivo cancelación', d['cancellationReason'] as String, textColor, subtextColor),
      ])),

      // IDs técnicos
      _sectionTitle('IDENTIFICADORES', Icons.tag_rounded),
      _card(surface, borderColor, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _idBadge('Booking ID', d['id'] as String? ?? '—', subtextColor, borderColor),
        const SizedBox(height: 6),
        _idBadge('Client ID', d['clientId'] as String? ?? '—', subtextColor, borderColor),
        const SizedBox(height: 6),
        _idBadge('Caregiver Profile ID', d['caregiverId'] as String? ?? '—', subtextColor, borderColor),
        if (d['petId'] != null) ...[
          const SizedBox(height: 6),
          _idBadge('Pet ID', d['petId'] as String, subtextColor, borderColor),
        ],
        if (d['qrId'] != null) ...[
          const SizedBox(height: 6),
          _idBadge('QR ID', d['qrId'] as String, subtextColor, borderColor),
        ],
      ])),
    ]);
  }

  // ── TAB 2: PAGO ─────────────────────────────────────────────
  Widget _buildPaymentTab(Color surface, Color textColor, Color subtextColor, Color borderColor, Color bg) {
    final d = _data!;
    final total = (d['totalAmount'] as num?)?.toDouble() ?? 0.0;
    final commission = (d['commissionAmount'] as num?)?.toDouble() ?? 0.0;
    final caregiversPayout = (d['caregiverPayoutAmount'] as num?)?.toDouble() ?? (total - commission);
    final txs = (d['walletTransactions'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return ListView(padding: const EdgeInsets.all(16), children: [

      // Resumen visual
      _card(surface, borderColor, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.account_balance_wallet_rounded, size: 16, color: GardenColors.primary),
          SizedBox(width: 6),
          Text('RESUMEN DE PAGO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: GardenColors.primary, letterSpacing: 1)),
        ]),
        const SizedBox(height: 16),
        // Total pagado
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('TOTAL PAGADO POR CLIENTE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: subtextColor, letterSpacing: 1)),
            const SizedBox(height: 4),
            Text('Bs ${total.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: GardenColors.primary)),
          ])),
          if (d['paidAt'] != null)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('PAGADO EL', style: TextStyle(fontSize: 9, color: subtextColor, letterSpacing: 1)),
              const SizedBox(height: 4),
              Text(_fmtDateShort(d['paidAt'] as String),
                style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w600)),
            ]),
        ]),
        const SizedBox(height: 16),
        // Distribución visual
        Container(
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
          child: Column(children: [
            _payRow('Pago al cuidador (90%)', caregiversPayout, GardenColors.success, Icons.person_rounded),
            Divider(height: 1, color: borderColor),
            _payRow('Comisión Garden (10%)', commission, GardenColors.primary, Icons.eco_rounded),
          ]),
        ),
        const SizedBox(height: 12),
        // Barra visual de distribución
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Row(children: [
            Flexible(
              flex: 90,
              child: Container(height: 10, color: GardenColors.success),
            ),
            Flexible(
              flex: 10,
              child: Container(height: 10, color: GardenColors.primary),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Cuidador 90%', style: TextStyle(fontSize: 10, color: GardenColors.success, fontWeight: FontWeight.bold)),
          Text('Garden 10%', style: TextStyle(fontSize: 10, color: GardenColors.primary, fontWeight: FontWeight.bold)),
        ]),
      ])),

      const SizedBox(height: 4),

      // Detalles del pago
      _card(surface, borderColor, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _dataRow('Método de pago', d['paymentMethod'] as String? ?? 'Manual / QR', textColor, subtextColor),
        _dataRow('Precio por unidad', 'Bs ${(d['pricePerUnit'] as num? ?? 0).toStringAsFixed(2)}', textColor, subtextColor),
        _dataRow('Estado del pago al cuidador', d['payoutStatus'] as String? ?? '—', textColor, subtextColor),
        if (d['refundAmount'] != null) _dataRow('Monto de reembolso', 'Bs ${(d['refundAmount'] as num).toStringAsFixed(2)}', textColor, GardenColors.warning),
        if (d['refundStatus'] != null) _dataRow('Estado reembolso', d['refundStatus'] as String, textColor, subtextColor),
      ])),

      // Transacciones en billetera
      if (txs.isNotEmpty) ...[
        _sectionTitle('TRANSACCIONES EN BILLETERA', Icons.receipt_long_outlined),
        ...txs.map((tx) => _card(surface, borderColor, child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _txColor(tx['type'] as String? ?? '').withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_txIcon(tx['type'] as String? ?? ''), size: 18, color: _txColor(tx['type'] as String? ?? '')),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tx['description'] as String? ?? tx['type'] as String? ?? '—',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
            Text('${tx['userName']} · ${_fmtDateShort(tx['createdAt'] as String? ?? '')}',
              style: TextStyle(color: subtextColor, fontSize: 11)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Bs ${(tx['amount'] as num).toStringAsFixed(2)}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _txColor(tx['type'] as String? ?? ''))),
            Text('Saldo: Bs ${(tx['balance'] as num).toStringAsFixed(2)}',
              style: TextStyle(fontSize: 10, color: subtextColor)),
          ]),
        ]))),
      ],
    ]);
  }

  // ── TAB 3: SERVICIO ─────────────────────────────────────────
  Widget _buildServiceTab(Color surface, Color textColor, Color subtextColor, Color borderColor, Color bg) {
    final d = _data!;
    final startedAt = d['serviceStartedAt'] as String?;
    final endedAt = d['serviceEndedAt'] as String?;
    // serviceTrackingData is stored as a JSON array of GPS points: [{lat, lng, timestamp}, ...]
    final trackingPoints = d['serviceTrackingData'] is List ? (d['serviceTrackingData'] as List) : null;
    final events = d['serviceEvents'] is List ? (d['serviceEvents'] as List) : null;
    final startPhoto = d['serviceStartPhoto'] as String?;
    final endPhoto = d['serviceEndPhoto'] as String?;

    Duration? serviceDuration;
    if (startedAt != null && endedAt != null) {
      try {
        serviceDuration = DateTime.parse(endedAt).difference(DateTime.parse(startedAt));
      } catch (_) {}
    }

    return ListView(padding: const EdgeInsets.all(16), children: [

      // Tiempos
      _card(surface, borderColor, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.timer_outlined, size: 14, color: GardenColors.primary),
          SizedBox(width: 6),
          Text('EJECUCIÓN DEL SERVICIO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: GardenColors.primary, letterSpacing: 1)),
        ]),
        const SizedBox(height: 12),
        if (startedAt == null && endedAt == null)
          Center(child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('El servicio aún no ha comenzado o no tiene registro de tiempo.',
              style: TextStyle(color: subtextColor, fontSize: 13), textAlign: TextAlign.center),
          ))
        else ...[
          Row(children: [
            Expanded(child: _timeBox('INICIO', startedAt, Icons.play_arrow_rounded, GardenColors.success, subtextColor, borderColor)),
            const SizedBox(width: 10),
            Expanded(child: _timeBox('FIN', endedAt, Icons.stop_rounded, GardenColors.error, subtextColor, borderColor)),
          ]),
          if (serviceDuration != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: GardenColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: GardenColors.primary.withValues(alpha: 0.2)),
              ),
              child: Column(children: [
                const Text('DURACIÓN REAL', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: GardenColors.primary, letterSpacing: 1)),
                const SizedBox(height: 4),
                Text(_formatDuration(serviceDuration),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: GardenColors.primary)),
              ]),
            ),
          ],
        ],
      ])),

      // Fotos del servicio
      if (startPhoto != null || endPhoto != null) ...[
        _sectionTitle('FOTOS DEL SERVICIO', Icons.photo_camera_outlined),
        _card(surface, borderColor, child: Row(children: [
          if (startPhoto != null)
            Expanded(child: _servicePhoto(startPhoto, 'Foto inicio', Icons.play_arrow_rounded, GardenColors.success, subtextColor, borderColor)),
          if (startPhoto != null && endPhoto != null) const SizedBox(width: 10),
          if (endPhoto != null)
            Expanded(child: _servicePhoto(endPhoto, 'Foto fin', Icons.stop_rounded, GardenColors.error, subtextColor, borderColor)),
        ])),
      ],

      // Eventos del servicio
      if (events != null && events.isNotEmpty) ...[
        _sectionTitle('EVENTOS DEL SERVICIO', Icons.event_note_outlined),
        ...events.map((e) {
          final ev = e as Map<String, dynamic>? ?? {};
          final isEmergency = (ev['type'] as String? ?? '').toLowerCase().contains('emergency') ||
                               (ev['type'] as String? ?? '').toLowerCase().contains('incident');
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isEmergency ? GardenColors.error.withValues(alpha: 0.07) : surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isEmergency ? GardenColors.error.withValues(alpha: 0.3) : borderColor),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(
                isEmergency ? Icons.warning_rounded : Icons.circle,
                size: isEmergency ? 18 : 8,
                color: isEmergency ? GardenColors.error : GardenColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (ev['type'] != null)
                  Text(ev['type'] as String, style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold,
                    color: isEmergency ? GardenColors.error : textColor)),
                if (ev['description'] != null)
                  Text(ev['description'] as String, style: TextStyle(fontSize: 12, color: textColor)),
                if (ev['note'] != null)
                  Text(ev['note'] as String, style: TextStyle(fontSize: 11, color: subtextColor)),
                if (ev['timestamp'] != null)
                  Text(_fmtDate(ev['timestamp'] as String), style: TextStyle(fontSize: 10, color: subtextColor)),
              ])),
            ]),
          );
        }),
      ],

      // Tracking GPS data
      if (trackingPoints != null && trackingPoints.isNotEmpty) ...[
        _sectionTitle('TRACKING GPS (${trackingPoints.length} puntos)', Icons.gps_fixed_rounded),
        _card(surface, borderColor, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _dataRow('Puntos registrados', '${trackingPoints.length}', textColor, subtextColor),
          if (trackingPoints.first is Map) ...[
            const SizedBox(height: 4),
            _dataRow('Primer punto', '${(trackingPoints.first as Map)['lat']}, ${(trackingPoints.first as Map)['lng']}', textColor, subtextColor),
            if (trackingPoints.length > 1)
              _dataRow('Último punto', '${(trackingPoints.last as Map)['lat']}, ${(trackingPoints.last as Map)['lng']}', textColor, subtextColor),
          ],
        ])),
      ],

      if (startedAt == null && endedAt == null && (events == null || events.isEmpty) && startPhoto == null && endPhoto == null)
        Center(child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.hourglass_empty_rounded, size: 48, color: subtextColor),
            const SizedBox(height: 12),
            Text('Sin datos de ejecución del servicio todavía',
              style: TextStyle(color: subtextColor), textAlign: TextAlign.center),
          ]),
        )),
    ]);
  }

  // ── TAB 4: RESEÑA ────────────────────────────────────────────
  Widget _buildReviewTab(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final d = _data!;
    final review = d['review'] as Map<String, dynamic>?;
    final ownerRating = d['ownerRating'] as int?;
    final caregiverRating = d['caregiverRating'] as int?;

    if (review == null && ownerRating == null && caregiverRating == null) {
      return _emptyState(Icons.star_outline_rounded, 'Sin reseña', 'El cliente aún no ha calificado este servicio.', subtextColor);
    }

    return ListView(padding: const EdgeInsets.all(16), children: [

      // Reseña pública
      if (review != null) ...[
        _sectionTitle('RESEÑA PÚBLICA', Icons.rate_review_outlined),
        _card(surface, borderColor, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _starRow(review['rating'] as int? ?? 0),
            const Spacer(),
            Text(_fmtDateShort(review['createdAt'] as String? ?? ''),
              style: TextStyle(fontSize: 11, color: subtextColor)),
          ]),
          if (review['comment'] != null) ...[
            const SizedBox(height: 10),
            Text('"${review['comment']}"',
              style: TextStyle(fontSize: 14, color: textColor, fontStyle: FontStyle.italic, height: 1.4)),
          ],
          if (review['photo'] != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(review['photo'] as String, height: 120, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox()),
            ),
          ],
          if (review['caregiverResponse'] != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: GardenColors.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: GardenColors.primary.withValues(alpha: 0.2)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('RESPUESTA DEL CUIDADOR', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: GardenColors.primary, letterSpacing: 1)),
                const SizedBox(height: 4),
                Text(review['caregiverResponse'] as String, style: TextStyle(fontSize: 13, color: textColor, height: 1.4)),
                if (review['respondedAt'] != null) ...[
                  const SizedBox(height: 4),
                  Text(_fmtDateShort(review['respondedAt'] as String),
                    style: TextStyle(fontSize: 10, color: subtextColor)),
                ],
              ]),
            ),
          ],
        ])),
      ],

      // Calificación del dueño (interna)
      if (ownerRating != null) ...[
        _sectionTitle('CALIFICACIÓN DEL DUEÑO (INTERNA)', Icons.person_rounded),
        _card(surface, borderColor, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _starRow(ownerRating),
          if (d['ownerComment'] != null) ...[
            const SizedBox(height: 8),
            Text(d['ownerComment'] as String, style: TextStyle(fontSize: 13, color: textColor, height: 1.4)),
          ],
        ])),
      ],

      // Calificación del cuidador (interna)
      if (caregiverRating != null) ...[
        _sectionTitle('CALIFICACIÓN DEL CUIDADOR AL DUEÑO', Icons.supervisor_account_outlined),
        _card(surface, borderColor, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _starRow(caregiverRating),
          if (d['caregiverComment'] != null) ...[
            const SizedBox(height: 8),
            Text(d['caregiverComment'] as String, style: TextStyle(fontSize: 13, color: textColor, height: 1.4)),
          ],
        ])),
      ],
    ]);
  }

  // ── TAB 5: CHAT ──────────────────────────────────────────────
  Widget _buildChatTab(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final d = _data!;
    final chatAvailable = d['chatAvailable'] as bool? ?? false;
    final chatExpiresAt = d['chatExpiresAt'] as String?;
    final messages = (d['messages'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    if (!chatAvailable) {
      return _emptyState(
        Icons.chat_bubble_outline_rounded,
        'Chat no disponible',
        'El historial del chat solo está disponible durante los 7 días posteriores a la finalización del servicio. Después se elimina automáticamente.',
        subtextColor,
      );
    }

    return Column(children: [
      // Banner de expiración
      if (chatExpiresAt != null)
        Container(
          color: GardenColors.warning.withValues(alpha: 0.1),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            const Icon(Icons.timer_outlined, size: 14, color: GardenColors.warning),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Chat disponible hasta el ${_fmtDateShort(chatExpiresAt)} · Se eliminará automáticamente',
              style: const TextStyle(fontSize: 11, color: GardenColors.warning, fontWeight: FontWeight.w600),
            )),
          ]),
        ),

      Expanded(
        child: messages.isEmpty
          ? _emptyState(Icons.chat_bubble_outline_rounded, 'Sin mensajes', 'No hay mensajes en este chat.', subtextColor)
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              itemCount: messages.length,
              itemBuilder: (_, i) {
                final msg = messages[i];
                final isCaregiver = msg['senderRole'] == 'CAREGIVER';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: isCaregiver ? MainAxisAlignment.end : MainAxisAlignment.start,
                    children: [
                      if (!isCaregiver) ...[
                        GardenAvatar(imageUrl: null, size: 28, initials: (msg['senderName'] as String? ?? 'U')[0]),
                        const SizedBox(width: 8),
                      ],
                      Flexible(child: Column(
                        crossAxisAlignment: isCaregiver ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${msg['senderName']} · ${isCaregiver ? 'Cuidador' : 'Cliente'}',
                            style: TextStyle(fontSize: 10, color: subtextColor, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isCaregiver
                                ? GardenColors.primary.withValues(alpha: 0.12)
                                : surface,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(14),
                                topRight: const Radius.circular(14),
                                bottomLeft: isCaregiver ? const Radius.circular(14) : const Radius.circular(3),
                                bottomRight: isCaregiver ? const Radius.circular(3) : const Radius.circular(14),
                              ),
                              border: Border.all(color: isCaregiver
                                ? GardenColors.primary.withValues(alpha: 0.3)
                                : borderColor),
                            ),
                            child: Text(msg['message'] as String? ?? '',
                              style: TextStyle(fontSize: 13, color: textColor)),
                          ),
                          const SizedBox(height: 2),
                          Text(_fmtDate(msg['createdAt'] as String? ?? ''),
                            style: TextStyle(fontSize: 9, color: subtextColor)),
                        ],
                      )),
                      if (isCaregiver) ...[
                        const SizedBox(width: 8),
                        GardenAvatar(imageUrl: null, size: 28, initials: (msg['senderName'] as String? ?? 'U')[0]),
                      ],
                    ],
                  ),
                );
              },
            ),
      ),
    ]);
  }

  // ── TAB 6: DISPUTA ───────────────────────────────────────────
  Widget _buildDisputeTab(Color surface, Color textColor, Color subtextColor, Color borderColor) {
    final d = _data!;
    final dispute = d['dispute'] as Map<String, dynamic>?;

    if (dispute == null) {
      return _emptyState(Icons.gavel_outlined, 'Sin disputa', 'No se ha abierto ninguna disputa para esta reserva.', subtextColor);
    }

    final aiVerdict = dispute['aiVerdict'] as String?;
    Color verdictColor = Colors.grey;
    String verdictLabel = 'Sin veredicto';
    if (aiVerdict == 'CLIENT_WINS') { verdictColor = GardenColors.success; verdictLabel = 'Gana el Cliente'; }
    else if (aiVerdict == 'CAREGIVER_WINS') { verdictColor = GardenColors.primary; verdictLabel = 'Gana el Cuidador'; }
    else if (aiVerdict == 'PARTIAL') { verdictColor = GardenColors.warning; verdictLabel = 'Resolución Parcial'; }

    return ListView(padding: const EdgeInsets.all(16), children: [

      // Estado de la disputa
      _card(surface, borderColor, child: Row(children: [
        const Icon(Icons.gavel_rounded, color: GardenColors.error, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Disputa abierta', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textColor)),
          Text(_fmtDateShort(dispute['createdAt'] as String? ?? ''), style: TextStyle(color: subtextColor, fontSize: 11)),
        ])),
        _disputeStatusChip(dispute['status'] as String? ?? ''),
      ])),

      // Veredicto IA
      if (aiVerdict != null) ...[
        _sectionTitle('VEREDICTO DE LA IA', Icons.psychology_rounded),
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: verdictColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: verdictColor.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.smart_toy_rounded, color: GardenColors.primary, size: 18),
              const SizedBox(width: 8),
              Text(verdictLabel,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: verdictColor)),
            ]),
            if (dispute['aiAnalysis'] != null) ...[
              const SizedBox(height: 10),
              Text(dispute['aiAnalysis'] as String,
                style: TextStyle(fontSize: 13, color: textColor, height: 1.5)),
            ],
            if (dispute['aiRecommendations'] != null) ...[
              const SizedBox(height: 10),
              const Text('RECOMENDACIONES', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
              const SizedBox(height: 4),
              Text(dispute['aiRecommendations'] as String,
                style: TextStyle(fontSize: 12, color: subtextColor, height: 1.4)),
            ],
          ]),
        ),
      ],

      // Razones del cliente
      if ((dispute['clientReasons'] as List?)?.isNotEmpty == true) ...[
        _sectionTitle('RAZONES DEL CLIENTE', Icons.person_rounded),
        _card(surface, borderColor, child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: (dispute['clientReasons'] as List).map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.circle, size: 6, color: GardenColors.error),
              const SizedBox(width: 8),
              Expanded(child: Text(r.toString(), style: TextStyle(fontSize: 13, color: textColor))),
            ]),
          )).toList(),
        )),
      ],

      // Respuesta del cuidador
      if ((dispute['caregiverResponse'] as List?)?.isNotEmpty == true) ...[
        _sectionTitle('RESPUESTA DEL CUIDADOR', Icons.supervisor_account_outlined),
        _card(surface, borderColor, child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: (dispute['caregiverResponse'] as List).map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.circle, size: 6, color: GardenColors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(r.toString(), style: TextStyle(fontSize: 13, color: textColor))),
            ]),
          )).toList(),
        )),
      ],

      // Resolución
      if (dispute['resolution'] != null) ...[
        _sectionTitle('RESOLUCIÓN FINAL', Icons.check_circle_outline_rounded),
        _card(surface, borderColor, child: Text(dispute['resolution'] as String,
          style: TextStyle(fontSize: 14, color: textColor, height: 1.5))),
      ],

      // ID disputa
      _sectionTitle('IDENTIFICADORES', Icons.tag_rounded),
      _card(surface, borderColor, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _idBadge('Dispute ID', dispute['id'] as String? ?? '—', subtextColor, borderColor),
      ])),
    ]);
  }

  // ── HELPERS ──────────────────────────────────────────────────

  void _showUserQuickView(BuildContext context, Map<String, dynamic> user, Color surface, Color textColor, Color subtextColor, Color borderColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            GardenAvatar(imageUrl: null, size: 48, initials: (user['name'] as String? ?? 'U')[0]),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user['name'] as String? ?? '—', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
              Text(user['email'] as String? ?? '—', style: TextStyle(color: subtextColor, fontSize: 13)),
              if (user['phone'] != null)
                Text(user['phone'] as String, style: const TextStyle(color: GardenColors.primary, fontSize: 12)),
            ])),
          ]),
          const SizedBox(height: 16),
          _idBadge('User ID', user['id'] as String? ?? '—', subtextColor, borderColor),
          const SizedBox(height: 16),
          GardenButton(label: 'Cerrar', height: 44, outline: true, onPressed: () => Navigator.pop(context)),
        ]),
      ),
    );
  }

  Widget _card(Color surface, Color borderColor, {required Widget child}) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
    child: child,
  );

  Widget _sectionTitle(String title, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Row(children: [
      Icon(icon, size: 14, color: GardenColors.primary),
      const SizedBox(width: 6),
      Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: GardenColors.primary, letterSpacing: 1)),
    ]),
  );

  Widget _dataRow(String label, String value, Color textColor, Color subtextColor) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 140, child: Text(label, style: TextStyle(fontSize: 11, color: subtextColor, fontWeight: FontWeight.w600))),
      Expanded(child: Text(value, style: TextStyle(fontSize: 12, color: textColor))),
    ]),
  );

  Widget _idBadge(String label, String value, Color subtextColor, Color borderColor) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(color: subtextColor.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(6), border: Border.all(color: borderColor)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label: ', style: TextStyle(color: subtextColor, fontSize: 10, fontWeight: FontWeight.bold)),
      Flexible(child: Text(value.length > 32 ? '${value.substring(0, 32)}…' : value,
        style: TextStyle(color: subtextColor, fontSize: 10, fontFamily: 'monospace'))),
      const SizedBox(width: 4),
      GestureDetector(
        onTap: () { Clipboard.setData(ClipboardData(text: value)); _snack('$label copiado'); },
        child: const Icon(Icons.copy_rounded, size: 12, color: GardenColors.primary),
      ),
    ]),
  );

  Widget _infoChip(IconData icon, String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _miniTag(String text, Color color) => Container(
    margin: const EdgeInsets.only(top: 3),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
    child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
  );

  Widget _outlineBtn(IconData icon, String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GardenColors.primary.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 14, color: GardenColors.primary),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: GardenColors.primary, fontWeight: FontWeight.w600)),
      ]),
    ),
  );

  Widget _payRow(String label, double amount, Color color, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600))),
      Text('Bs ${amount.toStringAsFixed(2)}',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
    ]),
  );

  Widget _timeBox(String label, String? iso, IconData icon, Color color, Color subtextColor, Color borderColor) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, size: 14, color: color), const SizedBox(width: 5), Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color, letterSpacing: 1))]),
      const SizedBox(height: 4),
      Text(iso != null ? _fmtDate(iso) : 'Sin registrar', style: TextStyle(fontSize: 12, color: iso != null ? color : subtextColor, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _servicePhoto(String url, String label, IconData icon, Color color, Color subtextColor, Color borderColor) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Stack(children: [
      Image.network(url, height: 130, width: double.infinity, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(height: 130, color: borderColor,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.broken_image_outlined, color: subtextColor),
            Text('No disponible', style: TextStyle(color: subtextColor, fontSize: 11)),
          ]))),
      Positioned(bottom: 6, left: 6, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: Colors.white),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ]),
      )),
    ]),
  );

  Widget _starRow(int rating) => Row(children: List.generate(5, (i) => Icon(
    i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
    color: Colors.amber, size: 20,
  )));

  Widget _statusBadge(String status) {
    final color = _statusColor(status);
    final label = _statusLabel(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _disputeStatusChip(String status) {
    Color c;
    String l;
    switch (status) {
      case 'RESOLVED': c = GardenColors.success; l = 'Resuelta'; break;
      case 'PENDING_CAREGIVER': c = GardenColors.warning; l = 'Esperando cuidador'; break;
      case 'PENDING_AI': c = GardenColors.primary; l = 'Análisis IA'; break;
      default: c = GardenColors.error; l = 'Pendiente';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8), border: Border.all(color: c.withValues(alpha: 0.4))),
      child: Text(l, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _emptyState(IconData icon, String title, String subtitle, Color subtextColor) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 48, color: subtextColor.withValues(alpha: 0.5)),
        const SizedBox(height: 12),
        Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: subtextColor)),
        const SizedBox(height: 6),
        Text(subtitle, style: TextStyle(color: subtextColor, fontSize: 13), textAlign: TextAlign.center),
      ]),
    ),
  );

  Color _statusColor(String s) => switch (s) {
    'CONFIRMED'                  => GardenColors.success,
    'IN_PROGRESS'                => GardenColors.primary,
    'COMPLETED'                  => Colors.grey,
    'CANCELLED'                  => GardenColors.error,
    'WAITING_CAREGIVER_APPROVAL' => Colors.orange,
    'PENDING_PAYMENT'            => GardenColors.warning,
    'PAYMENT_PENDING_APPROVAL'   => Colors.deepOrange,
    _                            => Colors.grey,
  };

  String _statusLabel(String s) => switch (s) {
    'CONFIRMED'                  => 'Confirmada',
    'IN_PROGRESS'                => 'En curso',
    'COMPLETED'                  => 'Completada',
    'CANCELLED'                  => 'Cancelada',
    'WAITING_CAREGIVER_APPROVAL' => 'Esp. cuidador',
    'PENDING_PAYMENT'            => 'Pago pendiente',
    'PAYMENT_PENDING_APPROVAL'   => 'Aprobando pago',
    _                            => s,
  };

  Color _txColor(String type) => switch (type) {
    'EARNING'    => GardenColors.success,
    'COMMISSION' => GardenColors.primary,
    'REFUND'     => GardenColors.warning,
    'WITHDRAWAL' => Colors.orange,
    _            => Colors.grey,
  };

  IconData _txIcon(String type) => switch (type) {
    'EARNING'    => Icons.arrow_downward_rounded,
    'COMMISSION' => Icons.eco_rounded,
    'REFUND'     => Icons.replay_rounded,
    'WITHDRAWAL' => Icons.account_balance_rounded,
    _            => Icons.swap_horiz_rounded,
  };

  String _fmtDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return iso.length > 10 ? iso.substring(0, 10) : iso; }
  }

  String _fmtDateShort(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) { return iso.length > 10 ? iso.substring(0, 10) : iso; }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}min';
    return '$m minutos';
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 1)));
  }
}
