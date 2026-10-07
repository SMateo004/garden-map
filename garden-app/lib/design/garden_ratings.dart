import 'package:flutter/material.dart';

import '../theme/garden_theme.dart';
import 'garden_depth.dart';
import 'garden_icons.dart';
import 'garden_service.dart';
import 'garden_service_icon.dart';

/// Piezas de "Mis calificaciones" (my_ratings_screen.dart): lo que falta
/// calificar, con su plazo, y las reseñas ya escritas.

const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

String _dateLabel(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// "hoy a las 14:00", "mañana a las 09:30", "el 12 oct a las 18:00".
String gardenDeadlineLabel(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  bool same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  final day = same(d, n)
      ? 'hoy'
      : same(d, n.add(const Duration(days: 1)))
          ? 'mañana'
          : 'el ${d.day} ${_months[d.month - 1]}';
  return '$day a las $hh:$mm';
}

class GardenRatingsSectionTitle extends StatelessWidget {
  final String text;
  const GardenRatingsSectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10),
      child: Text(text, style: GardenText.h4.copyWith(color: c, fontSize: 17, fontWeight: FontWeight.w900)),
    );
  }
}

/// Fila de cinco estrellas (solo lectura).
class GardenStars extends StatelessWidget {
  final int rating;
  final GIconSize size;
  const GardenStars(this.rating, {super.key, this.size = GIconSize.sm});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final off = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    return Semantics(
      label: '$rating de 5 estrellas',
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 5; i++)
          GardenIcon(GIcon.estrella,
              size: size,
              state: i < rating ? GIconState.active : GIconState.idle,
              color: i < rating ? GardenColors.star : off),
      ]),
    );
  }
}

/// Servicio terminado que todavía se puede calificar.
class GardenPendingRatingCard extends StatelessWidget {
  final String caregiverName;
  final String? caregiverPhoto;
  final String? petName;
  final GardenService? service;

  /// Hasta cuándo se puede calificar (después el pago se libera solo).
  final DateTime? deadline;
  final VoidCallback onRate;

  const GardenPendingRatingCard({
    super.key,
    required this.caregiverName,
    required this.onRate,
    this.caregiverPhoto,
    this.petName,
    this.service,
    this.deadline,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final what = [
      if (service != null) service!.label,
      if (petName != null && petName!.isNotEmpty) 'de $petName',
    ].join(' ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GardenRadius.lg),
        border: Border.all(color: GardenColors.star.withValues(alpha: 0.55), width: 1.5),
        boxShadow: GardenShadows.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            GardenAvatar(imageUrl: caregiverPhoto, size: 48, initials: caregiverName),
            if (service != null)
              Positioned(
                right: -4,
                bottom: -4,
                child: GardenClay(
                  size: 24,
                  color: service!.soft(isDark),
                  interactive: false,
                  child: GardenServiceIcon(service!, size: 14, color: service!.ink(isDark)),
                ),
              ),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('¿Cómo te fue con $caregiverName?',
                  style: TextStyle(color: text, fontSize: 15, fontWeight: FontWeight.w800, height: 1.25)),
              if (what.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(what, style: TextStyle(color: sub, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ]),
          ),
        ]),
        if (deadline != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            const GardenIcon(GIcon.esperando, size: GIconSize.xs, color: GardenColors.warning),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Puedes calificar hasta ${gardenDeadlineLabel(deadline!)}',
                  style: const TextStyle(color: GardenColors.warning, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ]),
        ],
        const SizedBox(height: 12),
        GardenButton(label: 'Calificar', height: 46, onPressed: onRate),
      ]),
    );
  }
}

/// Reseña escrita por el dueño, con la respuesta del cuidador si la hay.
class GardenReviewCard extends StatelessWidget {
  final String caregiverName;
  final String? caregiverPhoto;
  final int rating;
  final String? comment;
  final GardenService? service;
  final DateTime? date;
  final String? response;
  final VoidCallback? onOpenCaregiver;

  const GardenReviewCard({
    super.key,
    required this.caregiverName,
    required this.rating,
    this.caregiverPhoto,
    this.comment,
    this.service,
    this.date,
    this.response,
    this.onOpenCaregiver,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final text = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final elevated = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    final first = caregiverName.split(' ').first;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GardenRadius.lg),
        border: Border.all(color: border),
        boxShadow: GardenShadows.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: onOpenCaregiver,
            borderRadius: BorderRadius.circular(12),
            child: Row(children: [
              GardenAvatar(imageUrl: caregiverPhoto, size: 42, initials: caregiverName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(caregiverName, style: TextStyle(color: text, fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 3),
                  Row(children: [
                    if (service != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: service!.soft(isDark),
                          borderRadius: BorderRadius.circular(GardenRadius.full),
                        ),
                        child: Text(service!.label,
                            style: TextStyle(color: service!.ink(isDark), fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (date != null) Text(_dateLabel(date!), style: TextStyle(color: sub, fontSize: 11)),
                  ]),
                ]),
              ),
              if (onOpenCaregiver != null) GardenIcon(GIcon.siguiente, size: GIconSize.sm, color: sub),
            ]),
          ),
          const SizedBox(height: 12),
          GardenStars(rating, size: GIconSize.md),
          if (comment != null && comment!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(comment!.trim(), style: TextStyle(color: text, fontSize: 14, height: 1.5)),
          ] else ...[
            const SizedBox(height: 6),
            Text('Sin comentario', style: TextStyle(color: sub, fontSize: 12, fontStyle: FontStyle.italic)),
          ],
          if (response != null && response!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            // Respuesta del cuidador como burbuja de chat (antes: cursiva sin autor).
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: elevated,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  GardenIcon(GIcon.responder, size: GIconSize.xs, color: isDark ? GardenColors.primaryLight : GardenColors.primary),
                  const SizedBox(width: 6),
                  Text('Respuesta de $first',
                      style: TextStyle(
                          color: isDark ? GardenColors.primaryLight : GardenColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 4),
                Text(response!.trim(), style: TextStyle(color: text, fontSize: 13, height: 1.45)),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}
