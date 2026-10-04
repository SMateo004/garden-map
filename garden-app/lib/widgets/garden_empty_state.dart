import 'package:flutter/material.dart';

import '../design/brote.dart';
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
// Brote solo donde la escena es de la familia (mascotas, chat, buscar
// cuidador, reservas, notificaciones). Dinero, identidad y los listados de
// admin llevan un icono sereno del sistema: Brote nunca va en pantallas de
// dinero, pago, disputas ni verificación (plan de rediseño).
class _EmptyConfig {
  final BrotePose? brote;
  final GIcon icon;
  const _EmptyConfig({this.brote, required this.icon});
}

const _configs = <GardenEmptyType, _EmptyConfig>{
  GardenEmptyType.notifications: _EmptyConfig(brote: BrotePose.durmiendo, icon: GIcon.notificaciones),
  GardenEmptyType.bookings: _EmptyConfig(brote: BrotePose.esperando, icon: GIcon.reservas),
  GardenEmptyType.reviews: _EmptyConfig(icon: GIcon.estrella),
  GardenEmptyType.caregivers: _EmptyConfig(brote: BrotePose.buscando, icon: GIcon.buscar),
  GardenEmptyType.identity: _EmptyConfig(icon: GIcon.identidadVerificada),
  GardenEmptyType.payments: _EmptyConfig(icon: GIcon.pagoProtegido),
  GardenEmptyType.withdrawals: _EmptyConfig(icon: GIcon.retiro),
  GardenEmptyType.chat: _EmptyConfig(brote: BrotePose.hola, icon: GIcon.chat),
  GardenEmptyType.pets: _EmptyConfig(brote: BrotePose.hola, icon: GIcon.mascotas),
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

  /// Fuerza una pose de Brote (ej. [BrotePose.oops] para un error de
  /// conexión). Si es null se usa la del tipo.
  final BrotePose? brote;

  const GardenEmptyState({
    super.key,
    required this.type,
    required this.title,
    required this.subtitle,
    this.ctaLabel,
    this.onCta,
    this.compact = false,
    this.brote,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = _configs[type]!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final size = compact ? 84.0 : 116.0;
    final pose = brote ?? cfg.brote;

    final Widget illustration = pose != null
        ? Brote(pose: pose, size: size)
        : Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: GardenColors.primary.withValues(alpha: isDark ? 0.14 : 0.10),
            ),
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
