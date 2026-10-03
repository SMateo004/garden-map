import 'package:flutter/material.dart';

import '../narrative/booking_story.dart';
import '../theme/garden_theme.dart';
import 'garden_icons.dart';
import 'garden_pet_avatar.dart';
import 'garden_service.dart';
import 'garden_status_pill.dart';

// ── ENCABEZADO DEL SERVICIO EN VIVO ────────────────────────────────────────
// El momento pico de la app (plan, interfaz G): la mascota grande con su
// anillo en vivo, el icono del servicio animado y una frase que dice qué está
// pasando. Va sobre el degradado del servicio, con texto blanco.
//
// No incluye botones de navegación: la pantalla los superpone donde quiera.
class GardenLiveHero extends StatelessWidget {
  final Map<String, dynamic> booking;
  final bool caregiverView;
  final String? petPhotoUrl;
  final String? petSpecies;

  /// Cronómetro ya formateado por la pantalla ("00:23:10", "Noche 2 de 3").
  final String? timerLabel;

  /// Distancia recorrida en km (solo paseo).
  final double? distanceKm;

  final double height;

  const GardenLiveHero({
    super.key,
    required this.booking,
    this.caregiverView = false,
    this.petPhotoUrl,
    this.petSpecies,
    this.timerLabel,
    this.distanceKm,
    this.height = 300,
  });

  @override
  Widget build(BuildContext context) {
    final ctx = BookingStoryContext.fromBooking(booking, caregiverView: caregiverView);
    final story = BookingStory.of(booking['status'] as String?, ctx);
    final service = ctx.service ?? GardenService.paseo;

    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: service.hero,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 50, 20, 18),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  GardenPetAvatar(
                    name: ctx.pet,
                    imageUrl: petPhotoUrl,
                    species: petSpecies,
                    size: 84,
                    tone: story.tone,
                    service: service,
                    ringColor: Colors.white,
                    heroTag: booking['petId'] != null ? 'pet-${booking['petId']}-${booking['id']}' : null,
                  ),
                  Positioned(
                    right: -6,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: GardenIcon(
                        GIcon.forService(service),
                        size: GIconSize.lg,
                        state: GIconState.active,
                        live: story.isLive,
                        color: service.ink(false),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                story.headlineFor(caregiverView: caregiverView),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GardenText.h4.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (timerLabel != null)
                    _Capsule(
                      leading: GardenLiveDot(color: Colors.white, live: story.isLive, size: 8),
                      label: story.isLive ? 'En vivo · $timerLabel' : timerLabel!,
                    ),
                  if (distanceKm != null && distanceKm! > 0)
                    _Capsule(
                      leading: const GardenIcon(GIcon.distancia, size: GIconSize.sm, color: Colors.white),
                      label: '${distanceKm!.toStringAsFixed(distanceKm! < 10 ? 1 : 0).replaceAll('.', ',')} km',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Capsule extends StatelessWidget {
  final Widget leading;
  final String label;
  const _Capsule({required this.leading, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 8),
          Text(
            label,
            style: GardenText.metadata.copyWith(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
