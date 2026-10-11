import 'dart:async';

import 'package:flutter/material.dart';

import '../narrative/booking_story.dart';
import '../theme/garden_motion.dart';
import '../theme/garden_theme.dart';
import 'garden_icons.dart';
import 'garden_service.dart';

/// Reserva en una línea: para el inicio cuando el servicio NO está en curso.
/// La tarjeta grande (GardenBookingHeroCard) queda para cuando la mascota
/// está siendo cuidada en ese momento; el resto es discreto.
class GardenBookingMiniCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final VoidCallback? onTap;
  final ValueChanged<StoryAction>? onAction;

  const GardenBookingMiniCard({super.key, required this.booking, this.onTap, this.onAction});

  static const double height = 46;

  static const _urgent = {
    StoryAction.pay,
    StoryAction.viewMeet,
    StoryAction.chooseOtherTime,
    StoryAction.rate,
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;

    final ctx = BookingStoryContext.fromBooking(booking);
    final story = BookingStory.of(booking['status'] as String?, ctx);
    final svc = ctx.service ?? GardenService.paseo;
    // "mañana 8:00": corto, para que entre en la franja.
    final when = ctx.start == null
        ? null
        : BookingStory.whenLabel(ctx.start!, now: DateTime.now()).replaceAll(' a las ', ' ');
    final title = '${svc.label} de ${ctx.pet}';
    final next = story.nextFor(caregiverView: false);
    final urgent = next != null && _urgent.contains(next.action) && onAction != null;
    final statusInk = StoryColors.of(story.tone, isDark: isDark, service: svc).ink;

    // Una franja fina, sin borde ni sombra: está, pero no compite con el resto
    // del inicio. Lo único que resalta es una acción pendiente (Pagar…).
    return Semantics(
      button: true,
      label: '$title${when == null ? '' : ', $when'}. ${story.pill}',
      excludeSemantics: !urgent,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsets.only(left: 14, right: 8),
          decoration: BoxDecoration(
            color: surface.withValues(alpha: isDark ? 0.55 : 0.7),
            borderRadius: BorderRadius.circular(GardenRadius.full),
          ),
          child: Row(children: [
            GardenIcon(GIcon.forService(svc), size: GIconSize.sm, color: svc.ink(isDark)),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: title, style: TextStyle(color: textColor.withValues(alpha: 0.85), fontWeight: FontWeight.w700)),
                  if (when != null) TextSpan(text: ' · $when'),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 8),
            if (urgent)
              TextButton(
                onPressed: () => onAction!(next.action),
                style: TextButton.styleFrom(
                  foregroundColor: GardenColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(next.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
              )
            else ...[
              // Solo el puntito del color del estado (el nombre del estado lo
              // lee el lector de pantalla): así la hora entra completa.
              Container(width: 7, height: 7, decoration: BoxDecoration(color: statusInk, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              GardenIcon(GIcon.siguiente, size: GIconSize.xs, color: subtextColor.withValues(alpha: 0.6)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Varias reservas en un solo lugar: se ve una a la vez y pasa sola cada
/// pocos segundos (se pausa mientras la persona la desliza, y no se mueve sola
/// con "reducir movimiento"). Puntos abajo para saber cuántas hay.
class GardenBookingCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> bookings;
  final Widget Function(BuildContext context, Map<String, dynamic> booking) itemBuilder;
  final double height;
  final Duration interval;

  const GardenBookingCarousel({
    super.key,
    required this.bookings,
    required this.itemBuilder,
    this.height = GardenBookingMiniCard.height,
    this.interval = const Duration(seconds: 5),
  });

  @override
  State<GardenBookingCarousel> createState() => _GardenBookingCarouselState();
}

class _GardenBookingCarouselState extends State<GardenBookingCarousel> {
  final _page = PageController();
  Timer? _auto;
  int _index = 0;
  bool _touching = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restart();
  }

  @override
  void didUpdateWidget(GardenBookingCarousel old) {
    super.didUpdateWidget(old);
    if (_index >= widget.bookings.length) _index = 0;
    _restart();
  }

  void _restart() {
    _auto?.cancel();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.bookings.length < 2 || reduced) return;
    _auto = Timer.periodic(widget.interval, (_) {
      if (!mounted || _touching || !_page.hasClients) return;
      final next = (_index + 1) % widget.bookings.length;
      _page.animateToPage(next,
          duration: GardenMotion.resolve(context, GardenMotion.standard), curve: GardenMotion.move);
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.bookings;
    if (items.isEmpty) return const SizedBox.shrink();
    if (items.length == 1) return widget.itemBuilder(context, items.first);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dotOff = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: widget.height,
        child: Listener(
          onPointerDown: (_) => _touching = true,
          onPointerUp: (_) => _touching = false,
          onPointerCancel: (_) => _touching = false,
          child: PageView.builder(
            controller: _page,
            itemCount: items.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => widget.itemBuilder(context, items[i]),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Semantics(
        label: 'Reserva ${_index + 1} de ${items.length}',
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < items.length; i++)
            AnimatedContainer(
              duration: GardenMotion.resolve(context, GardenMotion.quick),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _index ? 12 : 4,
              height: 4,
              decoration: BoxDecoration(
                color: i == _index ? GardenColors.primary : dotOff,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ]),
      ),
    ]);
  }
}
