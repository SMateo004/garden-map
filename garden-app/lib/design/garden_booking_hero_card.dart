import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../narrative/booking_story.dart';
import '../theme/garden_motion.dart';
import '../theme/garden_theme.dart';
import 'garden_icons.dart';
import 'garden_pet_avatar.dart';
import 'garden_status_pill.dart';

// ── TARJETA PROTAGONISTA DE UNA RESERVA ────────────────────────────────────
// La reserva que más importa ahora (en vivo, por confirmar, recién
// terminada), contada desde la mascota. Va arriba de todo en el inicio del
// dueño y del cuidador: si Luna está paseando, nada compite con eso.
//
//   GardenBookingHeroCard(
//     booking: json,                // respuesta de /bookings/my
//     petPhotoUrl: '...',           // de /client/pets (la reserva no la trae)
//     onTap: () => ..., onAction: (a) => ...,
//   )
class GardenBookingHeroCard extends StatefulWidget {
  final Map<String, dynamic> booking;
  final bool caregiverView;
  final String? petPhotoUrl;
  final String? petSpecies;
  final VoidCallback? onTap;
  final ValueChanged<StoryAction>? onAction;

  /// Acción secundaria siempre disponible (chat), salvo que ya sea la principal.
  final VoidCallback? onChat;

  const GardenBookingHeroCard({
    super.key,
    required this.booking,
    this.caregiverView = false,
    this.petPhotoUrl,
    this.petSpecies,
    this.onTap,
    this.onAction,
    this.onChat,
  });

  @override
  State<GardenBookingHeroCard> createState() => _GardenBookingHeroCardState();
}

class _GardenBookingHeroCardState extends State<GardenBookingHeroCard> {
  Timer? _tick;

  bool get _live => widget.booking['status'] == 'IN_PROGRESS';

  @override
  void initState() {
    super.initState();
    _syncTick();
  }

  @override
  void didUpdateWidget(GardenBookingHeroCard old) {
    super.didUpdateWidget(old);
    _syncTick();
  }

  // Refresca "23 min" cada 30 s mientras el servicio está en vivo.
  void _syncTick() {
    if (_live && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    } else if (!_live) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final b = widget.booking;
    final ctx = BookingStoryContext.fromBooking(b, caregiverView: widget.caregiverView);
    final story = BookingStory.of(b['status'] as String?, ctx);
    final colors = StoryColors.of(story.tone, isDark: isDark, service: ctx.service);
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final next = story.nextFor(caregiverView: widget.caregiverView);

    final startedAt = DateTime.tryParse(b['serviceStartedAt'] as String? ?? '')?.toLocal();
    final trailing = story.isLive && startedAt != null
        ? BookingStory.elapsedLabel(startedAt, now: DateTime.now())
        : null;
    final showChat = widget.onChat != null && next?.action != StoryAction.chat;

    final card = Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: colors.soft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.ink.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GardenPetAvatar(
                name: ctx.pet,
                imageUrl: widget.petPhotoUrl,
                species: widget.petSpecies,
                size: 52,
                tone: story.tone,
                service: ctx.service,
                caregiverImageUrl: widget.caregiverView ? null : b['caregiverPhoto'] as String?,
                caregiverName: widget.caregiverView ? null : ctx.caregiver,
                heroTag: b['petId'] != null ? 'pet-${b['petId']}-${b['id']}' : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GardenStatusPill(story, service: ctx.service, trailing: trailing, dense: true),
                    const SizedBox(height: 6),
                    Text(
                      story.headlineFor(caregiverView: widget.caregiverView),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GardenText.bodyMedium.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (ctx.service != null) ...[
                const SizedBox(width: 8),
                GardenIcon(
                  GIcon.forService(ctx.service!),
                  size: GIconSize.xl,
                  state: GIconState.active,
                  live: story.isLive,
                ),
              ],
            ],
          ),
          if (next != null || showChat) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (next != null)
                  Expanded(
                    child: _ActionButton(
                      label: next.label,
                      color: colors.ink,
                      filled: true,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        widget.onAction?.call(next.action);
                      },
                    ),
                  ),
                if (next != null && showChat) const SizedBox(width: 8),
                if (showChat)
                  _ActionButton(
                    label: 'Chat',
                    icon: GIcon.chat,
                    color: colors.ink,
                    filled: false,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onChat!();
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );

    // Cuando la reserva cambia de estado, la tarjeta entra con un pop corto.
    return AnimatedSwitcher(
      duration: GardenMotion.resolve(context, GardenMotion.expressive),
      switchInCurve: GardenMotion.pop,
      switchOutCurve: GardenMotion.exit,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween<double>(begin: 0.96, end: 1).animate(a), child: child),
      ),
      child: Semantics(
        key: ValueKey('${b['id']}-${b['status']}'),
        button: widget.onTap != null,
        child: GestureDetector(onTap: widget.onTap, behavior: HitTestBehavior.opaque, child: card),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final GIcon? icon;
  final Color color;
  final bool filled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.color,
    required this.filled,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = filled ? (isDark ? GardenColors.darkBackground : Colors.white) : color;
    return Material(
      color: filled ? color : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: filled ? BorderSide.none : BorderSide(color: color.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                GardenIcon(icon!, size: GIconSize.sm, color: fg, state: GIconState.active),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GardenText.labelLarge.copyWith(color: fg, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
