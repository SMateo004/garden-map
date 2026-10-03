import 'package:flutter/material.dart';

import '../narrative/booking_story.dart';
import '../theme/garden_motion.dart';
import '../theme/garden_theme.dart';
import 'garden_icons.dart';
import 'garden_service.dart';

// ── AVATAR DE MASCOTA ──────────────────────────────────────────────────────
// La mascota es la protagonista: este avatar aparece en el inicio, el chat,
// el mapa y las reservas. El anillo dice el estado de un vistazo (como las
// historias de una red social) y pulsa solo si el servicio está en vivo.
//
//   GardenPetAvatar(name: 'Luna', imageUrl: url, species: 'DOG')
//   GardenPetAvatar(..., tone: story.tone, service: svc, caregiverImageUrl: cgUrl)
//
// [heroTag]: usar 'pet-<petId>' para que la foto viaje entre pantallas.
class GardenPetAvatar extends StatefulWidget {
  final String? name;
  final String? imageUrl;
  final String? species;
  final double size;
  final StoryTone? tone;
  final GardenService? service;
  final String? caregiverImageUrl;
  final String? caregiverName;
  final Object? heroTag;

  const GardenPetAvatar({
    super.key,
    this.name,
    this.imageUrl,
    this.species,
    this.size = 48,
    this.tone,
    this.service,
    this.caregiverImageUrl,
    this.caregiverName,
    this.heroTag,
  });

  @override
  State<GardenPetAvatar> createState() => _GardenPetAvatarState();
}

class _GardenPetAvatarState extends State<GardenPetAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  bool get _live => widget.tone == StoryTone.live;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(GardenPetAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final run = _live && !GardenMotion.reduced(context);
    if (run && !_pulse.isAnimating) _pulse.repeat();
    if (!run && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = widget.size;
    final ringWidth = (s * 0.055).clamp(2.0, 3.5);
    final gap = ringWidth;
    final ring = widget.tone == null
        ? null
        : StoryColors.of(widget.tone!, isDark: isDark, service: widget.service).ink;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;

    Widget photo = ClipOval(
      child: SizedBox.square(
        dimension: s,
        child: (widget.imageUrl?.isNotEmpty ?? false)
            ? Image.network(
                fixImageUrl(widget.imageUrl!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(isDark),
              )
            : _placeholder(isDark),
      ),
    );
    if (widget.heroTag != null) photo = Hero(tag: widget.heroTag!, child: photo);

    final outer = s + (ring != null ? (ringWidth + gap) * 2 : 0);

    return Semantics(
      label: widget.name,
      image: true,
      child: SizedBox.square(
        dimension: outer,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (ring != null)
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => Container(
                  width: outer,
                  height: outer,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: ring, width: ringWidth),
                    boxShadow: _pulse.isAnimating
                        ? [
                            BoxShadow(
                              color: ring.withValues(alpha: 0.45 * (1 - _pulse.value)),
                              spreadRadius: s * 0.12 * _pulse.value,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            photo,
            if (widget.caregiverImageUrl != null || widget.caregiverName != null)
              Positioned(
                right: -s * 0.06,
                bottom: -s * 0.06,
                child: Container(
                  padding: EdgeInsets.all((s * 0.04).clamp(1.5, 3.0)),
                  decoration: BoxDecoration(color: surface, shape: BoxShape.circle),
                  child: GardenAvatar(
                    imageUrl: widget.caregiverImageUrl,
                    size: s * 0.42,
                    initials: _initial(widget.caregiverName),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String? _initial(String? name) {
    final n = name?.trim();
    return (n == null || n.isEmpty) ? null : n.substring(0, 1);
  }

  Widget _placeholder(bool isDark) => ColoredBox(
        color: isDark ? GardenColors.darkSurfaceElevated : GardenColors.lime.withValues(alpha: 0.55),
        child: Center(
          child: GardenIcon(
            GIcon.forSpecies(widget.species),
            state: GIconState.active,
            size: widget.size >= 64 ? GIconSize.xl : GIconSize.lg,
          ),
        ),
      );
}
