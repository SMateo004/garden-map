import 'package:flutter/material.dart';

import '../design/garden_paw_mark.dart';
import '../design/garden_depth.dart';
import '../design/garden_icons.dart';
import '../theme/garden_motion.dart';
import '../theme/garden_theme.dart';

// ── TIPOS DE ESTADO VACÍO ─────────────────────────────────────────────────
enum GardenEmptyType {
  notifications,
  bookings,
  reviews,
  caregivers,
  identity,
  payments,
  withdrawals,
  chat,
  pets,
  generic,
}

// ── QUÉ SE DIBUJA EN CADA TIPO ────────────────────────────────────────────
// La huella de GARDEN solo donde la escena es de la familia (mascotas, chat,
// buscar cuidador, reservas, notificaciones). Dinero, identidad y los listados
// de admin llevan un icono sereno del sistema.
class _EmptyConfig {
  final bool mark;
  final GIcon icon;
  const _EmptyConfig({this.mark = false, required this.icon});
}

const _configs = <GardenEmptyType, _EmptyConfig>{
  GardenEmptyType.notifications: _EmptyConfig(mark: true, icon: GIcon.notificaciones),
  GardenEmptyType.bookings: _EmptyConfig(mark: true, icon: GIcon.reservas),
  GardenEmptyType.reviews: _EmptyConfig(icon: GIcon.estrella),
  GardenEmptyType.caregivers: _EmptyConfig(mark: true, icon: GIcon.buscar),
  GardenEmptyType.identity: _EmptyConfig(icon: GIcon.identidadVerificada),
  GardenEmptyType.payments: _EmptyConfig(icon: GIcon.pagoProtegido),
  GardenEmptyType.withdrawals: _EmptyConfig(icon: GIcon.retiro),
  GardenEmptyType.chat: _EmptyConfig(mark: true, icon: GIcon.chat),
  GardenEmptyType.pets: _EmptyConfig(mark: true, icon: GIcon.mascotas),
  GardenEmptyType.generic: _EmptyConfig(icon: GIcon.huella),
};

// ── WIDGET PRINCIPAL ──────────────────────────────────────────────────────
// Estado vacío = invitación con una acción, nunca solo "No hay datos".
// Entra una vez (fundido + pop corto) y queda quieto: sin bucles.
class GardenEmptyState extends StatelessWidget {
  final GardenEmptyType type;
  final String title;
  final String subtitle;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final bool compact;

  /// Fuerza la huella de GARDEN aunque el tipo lleve icono (ej. un error de
  /// conexión en una lista de la familia).
  final bool mark;

  const GardenEmptyState({
    super.key,
    required this.type,
    required this.title,
    required this.subtitle,
    this.ctaLabel,
    this.onCta,
    this.compact = false,
    this.mark = false,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = _configs[type]!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final size = compact ? 84.0 : 116.0;
    final Widget illustration = mark || cfg.mark
        ? GardenPawMark(size: size, floatCycles: GardenPawMark.settleCycles)
        : GardenClay(
            size: size,
            tint: GardenColors.primary.withValues(alpha: isDark ? 0.14 : 0.10),
            interactive: false,
            child: Center(
              child: GardenIcon(
                cfg.icon,
                size: compact ? GIconSize.xl : GIconSize.hero,
                state: GIconState.active,
              ),
            ),
          );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: GardenMotion.resolve(context, GardenMotion.expressive),
      curve: GardenMotion.enter,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
      ),
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: GardenSpacing.xxxl,
            vertical: compact ? GardenSpacing.xl : GardenSpacing.huge,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              illustration,
              SizedBox(height: compact ? GardenSpacing.lg : GardenSpacing.xxl),
              Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontSize: compact ? 16 : 20,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: GardenSpacing.sm),
              Text(
                subtitle,
                style: TextStyle(color: subtextColor, fontSize: compact ? 13 : 14, height: 1.6),
                textAlign: TextAlign.center,
              ),
              if (ctaLabel != null && onCta != null) ...[
                SizedBox(height: compact ? GardenSpacing.lg : GardenSpacing.xxl),
                GardenButton(label: ctaLabel!, height: 48, onPressed: onCta),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
