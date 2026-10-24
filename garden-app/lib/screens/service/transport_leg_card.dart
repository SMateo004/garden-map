import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../design/garden_icons.dart';
import '../../services/service_window.dart';
import '../../theme/garden_theme.dart';
import 'gps_tracking_screen.dart';
import '../../utils/navigation_launcher.dart';

/// Recojo / entrega a domicilio de una reserva de guardería u hospedaje
/// (`booking['transport']['legs']`, ver transport.service.ts en la API).
class TransportLegs {
  TransportLegs._();

  static List<Map<String, dynamic>> all(Map<String, dynamic>? booking) {
    final t = booking?['transport'];
    if (t is! Map) return const [];
    final legs = t['legs'];
    if (legs is! List) return const [];
    return legs.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  /// El viaje de ese tipo si existe y no fue cancelado.
  static Map<String, dynamic>? of(Map<String, dynamic>? booking, String kind) {
    for (final l in all(booking)) {
      if (l['kind'] == kind && l['status'] != 'CANCELLED') return l;
    }
    return null;
  }

  /// Viaje pendiente (todavía no hecho): programado, en camino o llegó.
  static Map<String, dynamic>? pending(Map<String, dynamic>? booking, String kind) {
    final l = of(booking, kind);
    if (l == null) return null;
    return const ['SCHEDULED', 'EN_ROUTE', 'ARRIVED'].contains(l['status']) ? l : null;
  }

  static bool isLive(Map<String, dynamic>? leg) => leg?['live'] == true;

  /// Algún viaje en curso: el cuidador comparte su ubicación.
  static Map<String, dynamic>? live(Map<String, dynamic>? booking) {
    for (final l in all(booking)) {
      if (isLive(l)) return l;
    }
    return null;
  }

  static String feeLabel(num? fee) => (fee ?? 0) <= 0 ? 'Gratis' : 'Bs ${(fee ?? 0).toStringAsFixed((fee ?? 0) % 1 == 0 ? 0 : 2)}';

  /// "hoy 09:00" / "sáb 12/10 18:30" (hora local del teléfono).
  static String whenLabel(Map<String, dynamic> leg) {
    final at = DateTime.tryParse(leg['scheduledAt'] as String? ?? '')?.toLocal();
    if (at == null) return leg['time'] as String? ?? '';
    final now = DateTime.now();
    final hm = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final days = DateTime(at.year, at.month, at.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days == 0) return 'hoy $hm';
    if (days == 1) return 'mañana $hm';
    const wd = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
    return '${wd[at.weekday - 1]} ${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')} $hm';
  }
}

/// Tarjeta de un viaje (recojo o entrega) con su estado y lo que cada uno puede hacer:
///  - Dueño: ver el mapa en vivo, cancelar mientras el cuidador no haya salido.
///  - Cuidador: avisos de la entrega ("salí a devolverlo" / "llegué"), "ya llegamos" tras
///    el recojo, y "no puedo hacer este viaje" ante un imprevisto.
/// Los avisos del recojo (en camino / llegué / recogí) viven en el botón principal de la
/// pantalla del servicio, igual que en el paseo.
class TransportLegCard extends StatefulWidget {
  final Map<String, dynamic> booking;
  final Map<String, dynamic> leg;
  /// 'CLIENT' | 'CAREGIVER'
  final String role;
  final String token;
  final String baseUrl;
  /// '/bookings' (titular y dueño) o '/caregiver-staff/bookings' (empleado de empresa).
  final String bookingsPath;
  final Future<void> Function() onChanged;
  /// Se llama al salir con la mascota / al cerrar el viaje (arranca o corta el GPS).
  final void Function(String event)? onTripEvent;

  const TransportLegCard({
    super.key,
    required this.booking,
    required this.leg,
    required this.role,
    required this.token,
    required this.baseUrl,
    required this.onChanged,
    this.bookingsPath = '/bookings',
    this.onTripEvent,
  });

  @override
  State<TransportLegCard> createState() => _TransportLegCardState();
}

class _TransportLegCardState extends State<TransportLegCard> {
  bool _busy = false;

  Map<String, dynamic> get leg => widget.leg;
  bool get _isPickup => leg['kind'] == 'PICKUP';
  bool get _isCaregiver => widget.role == 'CAREGIVER';
  String get _status => leg['status'] as String? ?? 'SCHEDULED';
  String get _pet => (widget.booking['petName'] as String?)?.split(',').first.trim() ?? 'tu mascota';
  String get _place => widget.booking['serviceType'] == 'HOSPEDAJE' ? 'el hospedaje' : 'la guardería';
  String get _bookingStatus => widget.booking['status'] as String? ?? '';
  String get _kindPath => _isPickup ? 'pickup' : 'dropoff';

  Future<bool> _post(String action, [Map<String, dynamic>? body]) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}${widget.bookingsPath}/${widget.booking['id']}/transport/$_kindPath/$action'),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
        body: jsonEncode(body ?? {}),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        await widget.onChanged();
        return true;
      }
      if (mounted) GardenErrorDialog.show(context, data['error']?['message'] as String? ?? 'No se pudo completar');
    } catch (_) {
      if (mounted) GardenErrorDialog.show(context, 'Sin conexión. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return false;
  }

  Future<void> _cancel() async {
    final fee = (leg['fee'] as num?) ?? 0;
    final reasonCtl = TextEditingController();
    // Sin el monto exacto: lo que se devuelve es fee + su impuesto (si aplica), y el
    // impuesto no viaja en el viaje que recibe el cliente (ver transport.view.ts).
    final money = fee > 0 ? ' Se devuelve lo que pagó por este viaje a la billetera Garden del dueño.' : '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isCaregiver
            ? (_isPickup ? '¿No puedes ir a recogerlo?' : '¿No puedes devolverlo a casa?')
            : (_isPickup ? '¿Lo llevas tú?' : '¿Lo recoges tú?')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            _isCaregiver
                ? (_isPickup
                    ? 'El dueño tendrá que llevar a $_pet a $_place. Avísale también por el chat.$money'
                    : 'El dueño tendrá que recoger a $_pet en $_place. Avísale también por el chat.$money')
                : (_isPickup
                    ? 'Se cancela el recojo y tú llevas a $_pet a $_place.${fee > 0 ? ' Te devolvemos lo que pagaste por este viaje a tu billetera Garden.' : ''}'
                    : 'Se cancela la entrega y tú recoges a $_pet en $_place.${fee > 0 ? ' Te devolvemos lo que pagaste por este viaje a tu billetera Garden.' : ''}'),
            style: const TextStyle(fontSize: 13.5, height: 1.4),
          ),
          if (_isCaregiver) ...[
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtl,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Motivo (lo verá el dueño)'),
            ),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, cancelar el viaje')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (_isCaregiver && reasonCtl.text.trim().length < 3) {
      GardenErrorDialog.show(context, 'Cuéntale al dueño el motivo (al menos unas palabras).');
      return;
    }
    if (await _post('cancel', {'reason': reasonCtl.text.trim()}) && mounted) {
      widget.onTripEvent?.call('cancelled');
      GardenSnackBar.success(context, _isPickup ? 'Recojo cancelado' : 'Entrega cancelada');
    }
  }

  void _openMap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GpsTrackingScreen(
          bookingId: widget.booking['id'] as String,
          role: widget.role,
          petName: widget.booking['petName'] as String? ?? '',
          token: widget.token,
          petPhoto: widget.booking['petPhoto'] as String?,
          bookingsPath: widget.bookingsPath,
        ),
      ),
    );
  }

  /// Texto del estado, desde el punto de vista de quien mira.
  String _statusLine() {
    final when = TransportLegs.whenLabel(leg);
    switch (_status) {
      case 'SCHEDULED':
        return _isPickup ? 'Programado para $when' : 'Programada para $when';
      case 'EN_ROUTE':
        return _isPickup
            ? (_isCaregiver ? 'Vas en camino a su casa' : 'El cuidador va en camino a tu casa')
            : (_isCaregiver ? 'Vas de regreso con $_pet' : '$_pet va de regreso a casa');
      case 'ARRIVED':
        return _isPickup
            ? (_isCaregiver ? 'Llegaste a su casa' : 'El cuidador está en tu puerta')
            : (_isCaregiver ? 'Llegaste: entrégalo y finaliza el servicio' : '$_pet está en tu puerta');
      case 'DONE':
        if (_isPickup) {
          return leg['atBaseAt'] != null
              ? 'Hecho: ${_isCaregiver ? 'ya están' : 'ya está'} en $_place'
              : (_isCaregiver ? 'Recogido: vas camino a $_place' : 'Recogido: va camino a $_place');
        }
        return 'Entregado en casa';
      case 'CANCELLED':
        return 'Cancelado';
    }
    return _status;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final live = TransportLegs.isLive(leg);
    final fee = leg['fee'] as num?;
    final distance = (leg['distanceKm'] as num?)?.toDouble();
    final address = leg['address'] as String?;
    final reference = leg['addressReference'] as String?;

    // Lo que se puede tocar ahora.
    final canCancel = _isCaregiver
        ? const ['SCHEDULED', 'EN_ROUTE'].contains(_status) &&
            (_isPickup ? const ['WAITING_CAREGIVER_APPROVAL', 'CONFIRMED'].contains(_bookingStatus) : const ['WAITING_CAREGIVER_APPROVAL', 'CONFIRMED', 'IN_PROGRESS'].contains(_bookingStatus))
        : _status == 'SCHEDULED' &&
            (_isPickup ? const ['WAITING_CAREGIVER_APPROVAL', 'CONFIRMED'].contains(_bookingStatus) : const ['WAITING_CAREGIVER_APPROVAL', 'CONFIRMED', 'IN_PROGRESS'].contains(_bookingStatus));
    final dropoffEnRouteBlock = ServiceWindow.blockReason(leg, 'enRouteOpensAt', 'salir a devolverlo');
    final showDropoffEnRoute = _isCaregiver && !_isPickup && _status == 'SCHEDULED' && _bookingStatus == 'IN_PROGRESS';
    final showDropoffArrive = _isCaregiver && !_isPickup && _status == 'EN_ROUTE' && _bookingStatus == 'IN_PROGRESS';
    final showAtBase = _isCaregiver && _isPickup && _status == 'DONE' && leg['atBaseAt'] == null && live;
    // Navegación a la casa del dueño: mientras el viaje está por hacerse o en camino.
    final lat = (leg['addressLat'] as num?)?.toDouble();
    final lng = (leg['addressLng'] as num?)?.toDouble();
    final showNavigate = _isCaregiver &&
        lat != null &&
        lng != null &&
        const ['SCHEDULED', 'EN_ROUTE', 'ARRIVED'].contains(_status) &&
        (_isPickup ? _bookingStatus == 'CONFIRMED' : _bookingStatus == 'IN_PROGRESS');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GardenRadius.xl),
        border: Border.all(color: live ? GardenColors.primary.withValues(alpha: 0.5) : border, width: live ? 1.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GardenIcon(_isPickup ? GIcon.auto : GIcon.inicio,
              size: GIconSize.sm, color: GardenColors.primary, state: live ? GIconState.active : GIconState.idle),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_isPickup ? 'Recojo a domicilio' : 'Entrega a domicilio',
                style: TextStyle(color: text, fontWeight: FontWeight.w800, fontSize: 14.5)),
          ),
          Text(TransportLegs.feeLabel(fee), style: TextStyle(color: sub, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ]),
        const SizedBox(height: 6),
        Text(_statusLine(), style: TextStyle(color: text, fontSize: 13.5, fontWeight: FontWeight.w600)),
        if (_isCaregiver && address != null && _status != 'DONE') ...[
          const SizedBox(height: 4),
          Text(
            [address, if (reference != null && reference.isNotEmpty) reference, if (distance != null) '${distance.toStringAsFixed(1)} km'].join(' · '),
            style: TextStyle(color: sub, fontSize: 12.5, height: 1.35),
          ),
        ],
        if (!_isCaregiver && _status == 'SCHEDULED')
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _isPickup ? 'Ten lista a $_pet a esa hora. Te avisamos cuando salga hacia tu casa.' : 'Te avisamos cuando salga de $_place con $_pet.',
              style: TextStyle(color: sub, fontSize: 12.5, height: 1.35),
            ),
          ),
        if (_status == 'CANCELLED' && (leg['cancelReason'] as String?)?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Motivo: ${leg['cancelReason']}', style: TextStyle(color: sub, fontSize: 12.5)),
          ),
        if (live || showDropoffEnRoute || showDropoffArrive || showAtBase || canCancel || showNavigate) const SizedBox(height: 12),
        if (showNavigate && _status != 'ARRIVED') ...[
          GardenNavigateButton(lat: lat, lng: lng, label: address, outline: true),
          const SizedBox(height: 8),
        ],
        if (showDropoffEnRoute) ...[
          GardenButton(
            label: dropoffEnRouteBlock ?? 'Salí a devolver a $_pet',
            loading: _busy,
            gIcon: GIcon.auto,
            onPressed: (_busy || dropoffEnRouteBlock != null)
                ? null
                : () async {
                    if (await _post('en-route')) widget.onTripEvent?.call('dropoff_en_route');
                  },
          ),
          const SizedBox(height: 8),
        ],
        if (showDropoffArrive) ...[
          GardenButton(
            label: 'Llegué a su casa',
            loading: _busy,
            gIcon: GIcon.ubicacion,
            onPressed: _busy ? null : () => _post('arrive'),
          ),
          const SizedBox(height: 8),
        ],
        if (showAtBase) ...[
          GardenButton(
            label: 'Ya llegamos a $_place',
            loading: _busy,
            outline: true,
            gIcon: GIcon.hecho,
            onPressed: _busy
                ? null
                : () async {
                    if (await _post('at-base')) widget.onTripEvent?.call('at_base');
                  },
          ),
          const SizedBox(height: 8),
        ],
        Wrap(spacing: 8, runSpacing: 6, children: [
          if (live)
            OutlinedButton.icon(
              onPressed: _openMap,
              icon: const GardenIcon(GIcon.mapa, size: GIconSize.sm, color: GardenColors.primary),
              label: Text(_isCaregiver ? 'Ver mi recorrido' : 'Seguir en el mapa'),
            ),
          if (canCancel)
            TextButton(
              onPressed: _busy ? null : _cancel,
              child: Text(_isCaregiver
                  ? 'No puedo hacer este viaje'
                  : (_isPickup ? 'Mejor lo llevo yo' : 'Mejor lo recojo yo')),
            ),
        ]),
      ]),
    );
  }
}
