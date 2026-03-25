import 'dart:math' as math;
import 'package:flutter/material.dart';
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

// ── CONFIGURACIÓN POR TIPO ────────────────────────────────────────────────
class _EmptyConfig {
  final String emoji;
  final IconData icon;
  final Color color;
  final List<Color> gradientColors;

  const _EmptyConfig({
    required this.emoji,
    required this.icon,
    required this.color,
    required this.gradientColors,
  });
}

const _configs = <GardenEmptyType, _EmptyConfig>{
  GardenEmptyType.notifications: _EmptyConfig(
    emoji: '🔔',
    icon: Icons.notifications_none_rounded,
    color: GardenColors.primary,
    gradientColors: [Color(0xFFFF6B35), Color(0xFFE55A25)],
  ),
  GardenEmptyType.bookings: _EmptyConfig(
    emoji: '📅',
    icon: Icons.calendar_today_outlined,
    color: GardenColors.secondary,
    gradientColors: [Color(0xFF4F8EF7), Color(0xFF2D6FE0)],
  ),
  GardenEmptyType.reviews: _EmptyConfig(
    emoji: '⭐',
    icon: Icons.star_outline_rounded,
    color: GardenColors.star,
    gradientColors: [Color(0xFFFFB020), Color(0xFFE09000)],
  ),
  GardenEmptyType.caregivers: _EmptyConfig(
    emoji: '🐾',
    icon: Icons.pets_rounded,
    color: GardenColors.primary,
    gradientColors: [Color(0xFFFF6B35), Color(0xFFE55A25)],
  ),
  GardenEmptyType.identity: _EmptyConfig(
    emoji: '🪪',
    icon: Icons.verified_user_outlined,
    color: GardenColors.success,
    gradientColors: [Color(0xFF2ECC71), Color(0xFF1A9954)],
  ),
  GardenEmptyType.payments: _EmptyConfig(
    emoji: '💳',
    icon: Icons.check_circle_outline_rounded,
    color: GardenColors.success,
    gradientColors: [Color(0xFF2ECC71), Color(0xFF1A9954)],
  ),
  GardenEmptyType.withdrawals: _EmptyConfig(
    emoji: '💰',
    icon: Icons.account_balance_wallet_outlined,
    color: GardenColors.secondary,
    gradientColors: [Color(0xFF4F8EF7), Color(0xFF2D6FE0)],
  ),
  GardenEmptyType.chat: _EmptyConfig(
    emoji: '💬',
    icon: Icons.chat_bubble_outline_rounded,
    color: GardenColors.secondary,
    gradientColors: [Color(0xFF4F8EF7), Color(0xFF2D6FE0)],
  ),
  GardenEmptyType.pets: _EmptyConfig(
    emoji: '🐶',
    icon: Icons.pets_rounded,
    color: GardenColors.primary,
    gradientColors: [Color(0xFFFF6B35), Color(0xFFE55A25)],
  ),
  GardenEmptyType.generic: _EmptyConfig(
    emoji: '🌱',
    icon: Icons.inbox_outlined,
    color: GardenColors.primary,
    gradientColors: [Color(0xFFFF6B35), Color(0xFFE55A25)],
  ),
};

// ── WIDGET PRINCIPAL ──────────────────────────────────────────────────────
class GardenEmptyState extends StatefulWidget {
  final GardenEmptyType type;
  final String title;
  final String subtitle;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final bool compact;

  const GardenEmptyState({
    super.key,
    required this.type,
    required this.title,
    required this.subtitle,
    this.ctaLabel,
    this.onCta,
    this.compact = false,
  });

  @override
  State<GardenEmptyState> createState() => _GardenEmptyStateState();
}

class _GardenEmptyStateState extends State<GardenEmptyState>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _float;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _float = Tween<double>(begin: 0, end: -10).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _configs[widget.type]!;
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final illustrationSize = widget.compact ? 80.0 : 110.0;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return FadeTransition(
          opacity: _fade,
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: GardenSpacing.xxxl,
                vertical: widget.compact ? GardenSpacing.xl : GardenSpacing.huge,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── ILUSTRACIÓN FLOTANTE ───────────────────────
                  Transform.translate(
                    offset: Offset(0, _float.value),
                    child: _GardenIllustration(
                      config: cfg,
                      size: illustrationSize,
                      isDark: isDark,
                    ),
                  ),

                  SizedBox(height: widget.compact ? GardenSpacing.lg : GardenSpacing.xxl),

                  // ── TÍTULO ─────────────────────────────────────
                  Text(
                    widget.title,
                    style: TextStyle(
                      color: textColor,
                      fontSize: widget.compact ? 16 : 20,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: GardenSpacing.sm),

                  // ── SUBTÍTULO ──────────────────────────────────
                  Text(
                    widget.subtitle,
                    style: TextStyle(
                      color: subtextColor,
                      fontSize: widget.compact ? 13 : 14,
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  // ── CTA BUTTON ─────────────────────────────────
                  if (widget.ctaLabel != null && widget.onCta != null) ...[
                    SizedBox(height: widget.compact ? GardenSpacing.lg : GardenSpacing.xxl),
                    GardenButton(
                      label: widget.ctaLabel!,
                      color: cfg.color,
                      height: 48,
                      onPressed: widget.onCta,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── ILUSTRACIÓN SVG-LIKE ──────────────────────────────────────────────────
class _GardenIllustration extends StatelessWidget {
  final _EmptyConfig config;
  final double size;
  final bool isDark;

  const _GardenIllustration({
    required this.config,
    required this.size,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 40,
      height: size + 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ── Anillo exterior difuso ────────────────────────────
          Container(
            width: size + 40,
            height: size + 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: config.color.withValues(alpha: isDark ? 0.06 : 0.08),
            ),
          ),

          // ── Anillo medio ──────────────────────────────────────
          Container(
            width: size + 16,
            height: size + 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: config.color.withValues(alpha: isDark ? 0.10 : 0.12),
            ),
          ),

          // ── Círculo principal con gradiente ───────────────────
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  config.gradientColors[0].withValues(alpha: isDark ? 0.22 : 0.18),
                  config.gradientColors[1].withValues(alpha: isDark ? 0.14 : 0.10),
                ],
              ),
              border: Border.all(
                color: config.color.withValues(alpha: isDark ? 0.25 : 0.20),
                width: 1.5,
              ),
            ),
            child: Center(
              child: Text(
                config.emoji,
                style: TextStyle(fontSize: size * 0.42),
              ),
            ),
          ),

          // ── Puntos decorativos ────────────────────────────────
          ..._buildDecorations(size, config.color, isDark),
        ],
      ),
    );
  }

  List<Widget> _buildDecorations(double size, Color color, bool isDark) {
    final radius = (size / 2) + 8;
    final dots = [
      (angle: -45.0, dotSize: 8.0, opacity: 0.5),
      (angle: 135.0, dotSize: 6.0, opacity: 0.35),
      (angle: 200.0, dotSize: 5.0, opacity: 0.25),
    ];

    return dots.map((d) {
      final radians = d.angle * math.pi / 180;
      final dx = math.cos(radians) * radius;
      final dy = math.sin(radians) * radius;
      return Transform.translate(
        offset: Offset(dx, dy),
        child: Container(
          width: d.dotSize,
          height: d.dotSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: isDark ? d.opacity : d.opacity * 0.8),
          ),
        ),
      );
    }).toList();
  }
}
