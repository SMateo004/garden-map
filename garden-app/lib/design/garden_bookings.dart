import 'package:flutter/material.dart';

import '../narrative/booking_story.dart';
import '../theme/garden_theme.dart';
import 'garden_service.dart';
import 'garden_wallet.dart';

/// Orden de "Mis reservas": lo que está pasando, lo que viene (lo más
/// cercano primero) y lo que ya pasó (lo más reciente primero, por mes).

const _liveStatuses = {'IN_PROGRESS'};
const _upcomingStatuses = {
  'PENDING_MG',
  'PENDING_PAYMENT',
  'PAYMENT_PENDING_APPROVAL',
  'WAITING_CAREGIVER_APPROVAL',
  'CONFIRMED',
  'SLOT_CONFLICT',
};

/// Un grupo de la lista: título ("En curso", "Próximas", "Octubre") y sus reservas.
class BookingGroup {
  final String title;
  final bool emphasis;
  final List<Map<String, dynamic>> bookings;
  const BookingGroup(this.title, this.bookings, {this.emphasis = false});
}

/// [caregiverView]: las solicitudes que esperan respuesta del cuidador van
/// aparte, arriba de todo ("Por responder"), porque tienen plazo.
List<BookingGroup> groupBookings(List<Map<String, dynamic>> list, {DateTime? now, bool caregiverView = false}) {
  DateTime start(Map<String, dynamic> b) =>
      BookingStoryContext.bookingStart(b) ??
      DateTime.tryParse(b['createdAt'] as String? ?? '')?.toLocal() ??
      DateTime(2000);

  final live = list.where((b) => _liveStatuses.contains(b['status'])).toList();
  bool toAnswer(Map<String, dynamic> b) => caregiverView && b['status'] == 'WAITING_CAREGIVER_APPROVAL';
  final answer = list.where(toAnswer).toList()..sort((a, b) => start(a).compareTo(start(b)));
  final upcoming = list.where((b) => _upcomingStatuses.contains(b['status']) && !toAnswer(b)).toList()
    ..sort((a, b) => start(a).compareTo(start(b)));
  final past = list
      .where((b) => !_liveStatuses.contains(b['status']) && !_upcomingStatuses.contains(b['status']))
      .toList()
    ..sort((a, b) => start(b).compareTo(start(a)));

  final groups = <BookingGroup>[
    if (answer.isNotEmpty) BookingGroup('Por responder', answer, emphasis: true),
    if (live.isNotEmpty) BookingGroup('En curso', live, emphasis: true),
    if (upcoming.isNotEmpty) BookingGroup('Próximas', upcoming),
  ];
  String? month;
  for (final b in past) {
    final m = walletMonthLabel(start(b), now: now);
    if (m != month) {
      groups.add(BookingGroup(m, []));
      month = m;
    }
    groups.last.bookings.add(b);
  }
  return groups;
}

/// "Paseo · 60 min", "Guardería · 4 h", "Hospedaje · 2 noches".
String bookingServiceLine(Map<String, dynamic> b) {
  final svc = GardenService.fromApi(b['serviceType'] as String?) ?? GardenService.paseo;
  final mins = (b['duration'] as num?)?.toInt();
  switch (svc) {
    case GardenService.hospedaje:
      final n = (b['totalDays'] as num?)?.toInt();
      return n != null && n > 0 ? '${svc.label} · $n noche${n == 1 ? '' : 's'}' : svc.label;
    case GardenService.guarderia:
      if (mins == null || mins <= 0) return svc.label;
      final h = mins ~/ 60, m = mins % 60;
      return '${svc.label} · ${h > 0 ? '$h h' : ''}${h > 0 && m > 0 ? ' ' : ''}${m > 0 ? '$m min' : ''}';
    case GardenService.paseo:
      return mins != null && mins > 0 ? '${svc.label} · $mins min' : svc.label;
  }
}

/// Encabezado de grupo: "EN CURSO · 1", "PRÓXIMAS · 3", "SEPTIEMBRE".
class GardenListHeader extends StatelessWidget {
  final String title;
  final int? count;
  final bool emphasis;
  const GardenListHeader(this.title, {super.key, this.count, this.emphasis = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final color = emphasis ? GardenService.paseo.ink(isDark) : sub;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
      child: Row(children: [
        if (emphasis) ...[
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 7),
        ],
        Text(title.toUpperCase(),
            style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
        if (count != null) ...[
          const SizedBox(width: 6),
          Text('· $count', style: TextStyle(color: sub, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
        const SizedBox(width: 10),
        Expanded(child: Divider(height: 1, color: sub.withValues(alpha: 0.18))),
      ]),
    );
  }
}
