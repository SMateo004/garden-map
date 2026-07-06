import 'dart:async';
import 'dart:ui' show ImageFilter, PlatformDispatcher;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── PALETA OFICIAL GARDEN ──────────────────────────────────────────────────
// Paleta: oliva #778C43 · vivid-green #58E262 · lima #D9EF9F · beige #DBD0C4
class GardenColors {
  // ── LIGHT MODE ──────────────────────────────────────────────────────────
  static const lightBackground      = Color(0xFFF2EDE4); // crema cálida profunda
  static const lightSurface         = Color(0xFFFAF7F2); // crema clara — reemplaza blanco puro
  static const lightSurfaceElevated = Color(0xFFF5F0E8); // crema beige — tarjetas elevadas
  static const lightBorder          = Color(0xFFDDD5C8); // beige cálido (ligeramente más visible)
  static const lightTextPrimary     = Color(0xFF1E2D0F); // casi negro con matiz verde
  static const lightTextSecondary   = Color(0xFF5C7238); // oliva medio
  static const lightTextHint        = Color(0xFF99AC75); // lima apagada

  // ── DARK MODE ───────────────────────────────────────────────────────────
  static const darkBackground       = Color(0xFF0D1A07); // verde bosque profundo
  static const darkSurface          = Color(0xFF162610); // superficie bosque
  static const darkSurfaceElevated  = Color(0xFF1F3317); // ligeramente más claro
  static const darkBorder           = Color(0xFF334D24); // borde verde musgo
  static const darkTextPrimary      = Color(0xFFF0F7E8); // blanco-crema con matiz verde
  static const darkTextSecondary    = Color(0xFF8CAB6A); // lima apagada
  static const darkTextHint         = Color(0xFF506038); // verde oscuro

  // ── COLORES DE MARCA (shared) ───────────────────────────────────────────
  static const primary      = Color(0xFF778C43); // verde oliva — identidad GARDEN
  static const primaryLight = Color(0xFF8FA353); // oliva más claro (hover/states)
  static const primaryDark  = Color(0xFF5C6E32); // oliva más oscuro (pressed)

  static const accent       = Color(0xFF58E262); // vivid green — energía y acción
  static const lime         = Color(0xFFD9EF9F); // lima pastel — chips, badges, fondos
  static const warmBeige    = Color(0xFFDBD0C4); // beige natural

  static const secondary    = Color(0xFF58E262); // alias de accent para actions secundarias
  static const polygon      = Color(0xFF8247E5); // blockchain purple
  static const success      = Color(0xFF58E262); // vivid green = éxito
  static const successDark  = Color(0xFF1A9954); // deep success (gradients, pressed)
  static const forest       = Color(0xFF0F7A3E); // deep forest green (HOSPEDAJE, active service)
  static const warning      = Color(0xFFFFB020); // ámbar
  static const error        = Color(0xFFE74C3C); // rojo
  static const star         = Color(0xFFFFB020); // estrella/rating
  static const info         = Color(0xFF4F8EF7); // info/AI/link blue
  static const infoDark     = Color(0xFF2D6FE0); // darker info blue
  static const orange       = Color(0xFFFF6B35); // notification/energy orange
  static const orangeDark   = Color(0xFFE55A25); // darker orange
  static const navy         = Color(0xFF1A1F2E); // dark navy card background
  static const navyDark     = Color(0xFF0A0E1A); // near-black navy (dark screens)

  // ── ALIASES (resuelven a light mode — nuevo default) ────────────────────
  static const background      = lightBackground;
  static const surface         = lightSurface;
  static const surfaceElevated = lightSurfaceElevated;
  static const border          = lightBorder;
  static const textPrimary     = lightTextPrimary;
  static const textSecondary   = lightTextSecondary;
  static const textHint        = lightTextHint;

  GardenColors._();
}

// ── GRADIENTES ─────────────────────────────────────────────────────────────
class GardenGradients {
  /// Oliva → oliva oscuro — botones y headers principales
  static const primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [GardenColors.primary, GardenColors.primaryDark],
  );

  /// Vivid green → oliva — CTAs especiales y onboarding
  static const fresh = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [GardenColors.accent, GardenColors.primary],
  );

  /// Lima → beige — fondos de sección y banners suaves
  static const nature = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [GardenColors.lime, GardenColors.warmBeige],
  );

  /// Dark mode: bosque profundo
  static const card = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [GardenColors.darkSurfaceElevated, GardenColors.darkSurface],
  );

  static const hero = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [GardenColors.primaryDark, GardenColors.darkBackground],
    stops: [0.0, 1.0],
  );

  static const verified = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [GardenColors.accent, Color(0xFF3CB84A)],
  );

  GardenGradients._();
}

// ── TIPOGRAFÍA ─────────────────────────────────────────────────────────────
// Fuentes: Nunito (400–900) para UI · JetBrains Mono (600) para metadata/monoespaciado
//
// Mapa de pesos:
//   fontRegular    400  — body text, descriptions, hints
//   fontMedium     500  — secondary labels, metadata
//   fontSemiBold   600  — nav labels, chips, secondary buttons
//   fontBold       700  — card titles, section headers
//   fontExtraBold  800  — screen titles, primary actions
//   fontBlack      900  — display, hero text, brand wordmark
//
// Letter-spacing:
//   Display  (900)      : -0.04em → -0.035em
//   Titles   (800)      : -0.025em → -0.02em
//   Headings (700)      : -0.02em → -0.01em
//   Body     (400–500)  : 0
//   Labels/caps ≤12px   : +0.06em → +0.12em (ALL CAPS only)
//
// Line-height:
//   Display  : 0.95 – 1.05
//   Titles   : 1.10 – 1.20
//   Headings : 1.20 – 1.35
//   Body     : 1.55 – 1.65
//   UI labels: 1.20 – 1.30
class GardenText {
  // ── Escala principal ─────────────────────────────────────────────────────

  /// 72sp · Black 900 · ls -0.04em · height 1.0 — splash, hero display
  static TextStyle get h1 => GoogleFonts.nunito(
    fontSize: 72, fontWeight: FontWeight.w900,
    letterSpacing: -2.88,   // -0.04em × 72
    height: 1.00,
  );

  /// 48sp · ExtraBold 800 · ls -0.025em · height 1.15 — títulos principales
  static TextStyle get h2 => GoogleFonts.nunito(
    fontSize: 48, fontWeight: FontWeight.w800,
    letterSpacing: -1.20,   // -0.025em × 48
    height: 1.15,
  );

  /// 28sp · ExtraBold 800 · ls -0.022em · height 1.20 — subtítulos de pantalla
  static TextStyle get h3 => GoogleFonts.nunito(
    fontSize: 28, fontWeight: FontWeight.w800,
    letterSpacing: -0.62,   // -0.022em × 28
    height: 1.20,
  );

  /// 20sp · Bold 700 · ls -0.015em · height 1.25 — encabezados de tarjeta
  static TextStyle get h4 => GoogleFonts.nunito(
    fontSize: 20, fontWeight: FontWeight.w700,
    letterSpacing: -0.30,   // -0.015em × 20
    height: 1.25,
  );

  /// 16sp · Medium 500 · ls 0 · height 1.60 — cuerpo de texto estándar
  static TextStyle get body => GoogleFonts.nunito(
    fontSize: 16, fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.60,
  );

  /// 13sp · JetBrains Mono SemiBold 600 — precios, métricas, timestamps
  static TextStyle get metadata => GoogleFonts.jetBrainsMono(
    fontSize: 13, fontWeight: FontWeight.w600,
    height: 1.40,
  );

  // ── Aliases para compatibilidad con código existente ─────────────────────

  /// 32sp · ExtraBold 800 · ls -0.025em · height 1.10 — section display titles
  static TextStyle get displayLarge  => GoogleFonts.nunito(
    fontSize: 32, fontWeight: FontWeight.w800,
    letterSpacing: -0.80,   // -0.025em × 32
    height: 1.10,
  );
  static TextStyle get displayMedium => h3;
  /// 24sp · Bold 700 · ls -0.018em · height 1.20
  static TextStyle get displaySmall  => GoogleFonts.nunito(
    fontSize: 24, fontWeight: FontWeight.w700,
    letterSpacing: -0.43,   // -0.018em × 24
    height: 1.20,
  );

  static TextStyle get headingLarge  => h4;
  /// 18sp · SemiBold 600 · ls -0.01em · height 1.30
  static TextStyle get headingMedium => GoogleFonts.nunito(
    fontSize: 18, fontWeight: FontWeight.w600,
    letterSpacing: -0.18,   // -0.01em × 18
    height: 1.30,
  );
  /// 16sp · SemiBold 600 · ls -0.01em · height 1.35
  static TextStyle get headingSmall  => GoogleFonts.nunito(
    fontSize: 16, fontWeight: FontWeight.w600,
    letterSpacing: -0.16,   // -0.01em × 16
    height: 1.35,
  );

  /// 16sp · Medium 500 · ls 0 · height 1.60
  static TextStyle get bodyLarge  => GoogleFonts.nunito(
    fontSize: 16, fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.60,
  );
  /// 14sp · Medium 500 · ls 0 · height 1.55
  static TextStyle get bodyMedium => GoogleFonts.nunito(
    fontSize: 14, fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.55,
  );
  /// 12sp · Regular 400 · ls 0 · height 1.50
  static TextStyle get bodySmall  => GoogleFonts.nunito(
    fontSize: 12, fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.50,
  );

  /// 14sp · ExtraBold 800 · ls +0.10 · height 1.20 — CTA labels, primary buttons
  static TextStyle get labelLarge  => GoogleFonts.nunito(
    fontSize: 14, fontWeight: FontWeight.w800,
    letterSpacing: 0.10,
    height: 1.20,
  );
  /// 12sp · Bold 700 · ls +0.08 · height 1.25
  static TextStyle get labelMedium => GoogleFonts.nunito(
    fontSize: 12, fontWeight: FontWeight.w700,
    letterSpacing: 0.08,
    height: 1.25,
  );
  /// 10sp · Bold 700 · ls +1.20 · height 1.20 — eyebrow / ALL CAPS
  static TextStyle get labelSmall  => GoogleFonts.nunito(
    fontSize: 10, fontWeight: FontWeight.w700,
    letterSpacing: 1.20,
    height: 1.20,
  );

  /// 11sp · Regular 400 · height 1.40 — captions, fine print
  static TextStyle get caption    => GoogleFonts.nunito(
    fontSize: 11, fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.40,
  );

  // ── Monospace (JetBrains Mono — no tocar) ───────────────────────────────
  static TextStyle get price      => GoogleFonts.jetBrainsMono(
    fontSize: 18, fontWeight: FontWeight.w800,
    color: GardenColors.primary, letterSpacing: -0.30,
  );
  static TextStyle get priceSmall => GoogleFonts.jetBrainsMono(
    fontSize: 14, fontWeight: FontWeight.w700,
    color: GardenColors.primary,
  );

  GardenText._();
}

// ── ESPACIADO ──────────────────────────────────────────────────────────────
class GardenSpacing {
  static const double xs   = 4;
  static const double sm   = 8;
  static const double md   = 12;
  static const double lg   = 16;
  static const double xl   = 20;
  static const double xxl  = 24;
  static const double xxxl = 32;
  static const double huge = 48;

  GardenSpacing._();
}

// ── BORDES Y RADIOS ────────────────────────────────────────────────────────
class GardenRadius {
  static const double xs   = 6;
  static const double sm   = 8;
  static const double md   = 12;
  static const double lg   = 16;
  static const double xl   = 20;
  static const double xxl  = 24;
  static const double full = 999;

  static final xs_   = BorderRadius.circular(xs);
  static final sm_   = BorderRadius.circular(sm);
  static final md_   = BorderRadius.circular(md);
  static final lg_   = BorderRadius.circular(lg);
  static final xl_   = BorderRadius.circular(xl);
  static final xxl_  = BorderRadius.circular(xxl);
  static final full_ = BorderRadius.circular(full);

  GardenRadius._();
}

// ── SOMBRAS ────────────────────────────────────────────────────────────────
class GardenShadows {
  static final card = [
    BoxShadow(
      color: const Color(0xFF778C43).withValues(alpha: 0.10),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  static final elevated = [
    BoxShadow(
      color: const Color(0xFF778C43).withValues(alpha: 0.16),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  static final primary = [
    BoxShadow(
      color: GardenColors.primary.withValues(alpha: 0.28),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  static final accent = [
    BoxShadow(
      color: GardenColors.accent.withValues(alpha: 0.25),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  GardenShadows._();
}

// ── LIQUID GLASS ───────────────────────────────────────────────────────────

/// Contenedor glass morphism — fondo difuminado + tinte + borde luminoso.
/// Úsalo para bottom bars flotantes, modales, paneles de filtro.
class GlassBox extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final double blurSigma;

  const GlassBox({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.blurSigma = 22,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(GardenRadius.xxl);

    // BackdropFilter causa crashes nativos en Android — usar fallback opaco allí.
    final useBlur = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;

    const creamLight = Color(0xFFFAF7F2);
    final tintLight = creamLight.withValues(alpha: useBlur ? 0.78 : 0.94);
    final tintDark  = const Color(0xFF162610).withValues(alpha: useBlur ? 0.82 : 0.95);

    final decoration = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          isDark ? tintDark : tintLight,
          isDark
              ? const Color(0xFF0D1A07).withValues(alpha: useBlur ? 0.75 : 0.93)
              : creamLight.withValues(alpha: useBlur ? 0.60 : 0.90),
        ],
      ),
      borderRadius: radius,
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.09)
            : const Color(0xFFDBD0C4).withValues(alpha: 0.55),
        width: 1.0,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.08),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    );

    final inner = Container(padding: padding, decoration: decoration, child: child);

    if (!useBlur) {
      return ClipRRect(borderRadius: radius, child: inner);
    }

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: inner,
      ),
    );
  }
}

/// Barra de navegación inferior flotante con efecto Liquid Glass.
/// Reemplaza el BottomNavigationBar estándar. Usa con extendBody: true en Scaffold.
class LiquidGlassNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<GardenNavItem> items;

  const LiquidGlassNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      color: Colors.transparent,
      padding: EdgeInsets.fromLTRB(20, 6, 20, bottomPad + 14),
      child: GlassBox(
        borderRadius: BorderRadius.circular(30),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: List.generate(items.length, (i) {
              final item = items[i];
              final selected = i == selectedIndex;
              final iconColor = selected
                  ? GardenColors.primary
                  : (isDark ? GardenColors.darkTextSecondary : const Color(0xFF8A9A7A));
              final labelColor = selected
                  ? GardenColors.primary
                  : (isDark ? GardenColors.darkTextSecondary : const Color(0xFF8A9A7A));

              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeInOut,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: selected
                                  ? GardenColors.primary.withValues(alpha: 0.13)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              border: selected
                                  ? Border.all(
                                      color: GardenColors.primary.withValues(alpha: 0.22),
                                      width: 1.0,
                                    )
                                  : null,
                            ),
                            child: Icon(
                              selected ? item.activeIcon : item.icon,
                              color: iconColor,
                              size: 22,
                            ),
                          ),
                          if (item.showDot)
                            Positioned(
                              top: 4,
                              right: 10,
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: GardenColors.error,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: isDark ? GardenColors.darkSurface : Colors.white, width: 1.5),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 240),
                        // Nav labels — SemiBold 600 inactive / Bold 700 active (nav labels spec)
                        style: GoogleFonts.nunito(
                          color: labelColor,
                          fontSize: 10,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                          letterSpacing: selected ? 0.10 : 0.06,
                          height: 1.20,
                        ),
                        child: Text(item.label),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class GardenNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  /// Muestra un punto rojo sobre el ícono — ej. mensajes de chat sin leer.
  final bool showDot;
  const GardenNavItem(this.icon, this.activeIcon, this.label, {this.showDot = false});
}

// ── LIQUID GLASS DIALOG ────────────────────────────────────────────────────

/// Diálogo con efecto Liquid Glass.
/// Reemplaza AlertDialog/Dialog con fondo glass morphism.
/// Uso: showDialog(context: ctx, builder: (_) => GardenGlassDialog(...))
class GardenGlassDialog extends StatelessWidget {
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? contentPadding;

  const GardenGlassDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor     = isDark ? GardenColors.darkTextPrimary    : GardenColors.lightTextPrimary;
    final subtextColor  = isDark ? GardenColors.darkTextSecondary  : GardenColors.lightTextSecondary;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: GlassBox(
        borderRadius: BorderRadius.circular(GardenRadius.xl),
        padding: contentPadding ?? const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              DefaultTextStyle(
                // Dialog title — ExtraBold 800 (screen titles / primary actions spec)
                style: GoogleFonts.nunito(
                  color: textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.18,   // -0.01em × 18
                  height: 1.30,
                  decoration: TextDecoration.none,
                ),
                child: title!,
              ),
            if (title != null && content != null) const SizedBox(height: 12),
            if (content != null)
              DefaultTextStyle(
                // Dialog body — Regular 400 (body text spec), height 1.55
                style: GoogleFonts.nunito(
                  color: subtextColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0,
                  height: 1.55,
                  decoration: TextDecoration.none,
                ),
                child: content!,
              ),
            if (actions != null && actions!.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions!
                    .map((a) => Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: a,
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── WIDGETS REUTILIZABLES ──────────────────────────────────────────────────

/// Tarjeta GARDEN
class GardenCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final List<BoxShadow>? shadows;
  final VoidCallback? onTap;
  final bool gradient;

  const GardenCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.shadows,
    this.onTap,
    this.gradient = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: margin,
        padding: padding ?? const EdgeInsets.all(GardenSpacing.lg),
        decoration: BoxDecoration(
          color: gradient ? null : (color ?? theme.colorScheme.surface),
          gradient: gradient ? GardenGradients.card : null,
          borderRadius: GardenRadius.lg_,
          border: Border.all(color: theme.colorScheme.outline, width: 1),
          boxShadow: shadows ?? GardenShadows.card,
        ),
        child: child,
      ),
    );
  }
}

/// Badge de estado con colores semánticos
class GardenBadge extends StatelessWidget {
  final String text;
  final Color color;
  final Color? textColor;
  final IconData? icon;
  final double fontSize;

  const GardenBadge({
    super.key,
    required this.text,
    required this.color,
    this.textColor,
    this.icon,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GardenSpacing.md,
        vertical: GardenSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: GardenRadius.full_,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 2, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: textColor ?? color,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton loader animado
class GardenSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const GardenSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.radius = GardenRadius.sm,
  });

  @override
  State<GardenSkeleton> createState() => _GardenSkeletonState();
}

class _GardenSkeletonState extends State<GardenSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.06, end: 0.18).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: _animation.value)
              : GardenColors.primary.withValues(alpha: _animation.value * 0.5),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Fixes image URLs so that localhost-based URLs work on Android emulator.
/// When the app is run with --dart-define=API_URL=http://10.0.2.2:3000/api,
/// any stored URL like http://localhost:3000/uploads/... gets rewritten to
/// http://10.0.2.2:3000/uploads/... so the emulator can reach the host machine.
String fixImageUrl(String url) {
  if (!url.startsWith('http://localhost') && !url.startsWith('http://127.0.0.1')) {
    return url;
  }
  const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');
  final apiUri = Uri.tryParse(apiUrl);
  if (apiUri == null) return url;
  final apiHost = apiUri.host;
  if (apiHost == 'localhost' || apiHost == '127.0.0.1') return url;
  return url.replaceFirst(
    RegExp(r'http://(localhost|127\.0\.0\.1)(:\d+)?'),
    '${apiUri.scheme}://$apiHost${apiUri.hasPort ? ":${apiUri.port}" : ""}',
  );
}

/// Avatar con placeholder inteligente
class GardenAvatar extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final String? initials;
  final Color? backgroundColor;

  const GardenAvatar({
    super.key,
    this.imageUrl,
    required this.size,
    this.initials,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: SizedBox(
        width: size,
        height: size,
        child: imageUrl != null && imageUrl!.isNotEmpty
            ? Image.network(
                fixImageUrl(imageUrl!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildPlaceholder(isDark),
                loadingBuilder: (_, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return GardenSkeleton(width: size, height: size, radius: size / 2);
                },
              )
            : _buildPlaceholder(isDark),
      ),
    );
  }

  Widget _buildPlaceholder(bool isDark) {
    final bg = backgroundColor ??
        (isDark ? GardenColors.darkSurfaceElevated : GardenColors.lime.withValues(alpha: 0.4));
    final iconColor = isDark ? GardenColors.darkTextSecondary : GardenColors.primary;
    return Container(
      color: bg,
      child: initials != null
          ? Center(
              child: Text(
                initials!.substring(0, initials!.length > 2 ? 2 : initials!.length).toUpperCase(),
                style: TextStyle(
                  color: iconColor,
                  fontSize: size * 0.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : Icon(Icons.person_rounded, color: iconColor, size: size * 0.5),
    );
  }
}

/// Botón primario de GARDEN
class GardenButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool outline;
  final Color? color;
  final IconData? icon;
  final double height;
  final double? width;

  const GardenButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.outline = false,
    this.color,
    this.icon,
    this.height = 52,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final btnColor = color ?? GardenColors.primary;

    final radius = BorderRadius.circular(GardenRadius.lg);

    if (outline) {
      final useBlur = kIsWeb ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS;

      final outlinedBtn = OutlinedButton(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: btnColor.withValues(alpha: useBlur ? 0.06 : 0.10),
          side: BorderSide(color: btnColor, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: radius),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
          minimumSize: Size(0, height),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: _buildChild(btnColor),
      );

      if (!useBlur) {
        return SizedBox(
          width: width ?? double.infinity,
          height: height,
          child: outlinedBtn,
        );
      }

      return SizedBox(
        width: width ?? double.infinity,
        height: height,
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: outlinedBtn,
          ),
        ),
      );
    }

    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Base gradient
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [btnColor, Color.lerp(btnColor, Colors.black, 0.20)!],
                ),
                boxShadow: [
                  BoxShadow(
                    color: btnColor.withValues(alpha: 0.30),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
            ),
            // Glass shimmer — reflexión de luz en el tercio superior
            Positioned(
              top: 0, left: 0, right: 0,
              height: height * 0.52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Borde luminoso superior
            Positioned(
              top: 0, left: 0, right: 0,
              height: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ),
            // Contenido del botón
            ElevatedButton(
              onPressed: loading ? null : onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                overlayColor: Colors.white.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(borderRadius: radius),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                minimumSize: Size(0, height),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: _buildChild(Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChild(Color textColor) {
    if (loading) {
      return SizedBox(
        width: 20, height: 20,
        child: CircularProgressIndicator(color: textColor, strokeWidth: 2),
      );
    }
    // GardenButton text — ExtraBold 800 (primary actions per spec)
    if (icon != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: textColor, size: 18),
          const SizedBox(width: 8),
          Text(label, style: GoogleFonts.nunito(color: textColor, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.10)),
        ],
      );
    }
    return Text(label, style: GoogleFonts.nunito(color: textColor, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.10));
  }
}

/// Input de GARDEN
class GardenInput extends StatelessWidget {
  final String hint;
  final TextEditingController? controller;
  final IconData? prefixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int? maxLines;
  final int? maxLength;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final Widget? suffixIcon;

  const GardenInput({
    super.key,
    required this.hint,
    this.controller,
    this.prefixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.maxLines = 1,
    this.maxLength,
    this.validator,
    this.onChanged,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
    final borderCol = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final hintCol   = isDark ? GardenColors.darkTextHint : GardenColors.lightTextHint;
    final textCol   = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: maxLines,
      maxLength: maxLength,
      validator: validator,
      onChanged: onChanged,
      style: GardenText.bodyMedium.copyWith(
        color: isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GardenText.bodyMedium.copyWith(color: hintCol),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: textCol, size: 20)
            : null,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: surfaceEl,
        border: OutlineInputBorder(
          borderRadius: GardenRadius.md_,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: GardenRadius.md_,
          borderSide: BorderSide(color: borderCol, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: GardenRadius.md_,
          borderSide: const BorderSide(color: GardenColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: GardenRadius.md_,
          borderSide: const BorderSide(color: GardenColors.error, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: GardenSpacing.lg,
          vertical: GardenSpacing.md,
        ),
      ),
    );
  }
}

// ── HELPER: Badge de estado de booking ────────────────────────────────────
GardenBadge bookingStatusBadge(String status) {
  switch (status) {
    case 'PENDING_MG':
      return const GardenBadge(text: 'Meet & Greet', color: Color(0xFF6C63FF), icon: Icons.handshake_outlined);
    case 'PENDING_PAYMENT':
      return const GardenBadge(text: 'Pendiente de pago', color: GardenColors.warmBeige, textColor: Color(0xFF7A6A5A));
    case 'PAYMENT_PENDING_APPROVAL':
      return const GardenBadge(text: 'Pago en revisión', color: GardenColors.warning, icon: Icons.schedule);
    case 'WAITING_CAREGIVER_APPROVAL':
      return const GardenBadge(text: 'Esperando cuidador', color: GardenColors.primary, icon: Icons.hourglass_top);
    case 'CONFIRMED':
      return const GardenBadge(text: 'Confirmada', color: GardenColors.success, icon: Icons.check_circle_outline);
    case 'IN_PROGRESS':
      return const GardenBadge(text: 'En curso', color: GardenColors.accent, icon: Icons.play_circle_outline);
    case 'COMPLETED':
      return const GardenBadge(text: 'Completada', color: GardenColors.primary, icon: Icons.done_all);
    case 'CANCELLED':
      return const GardenBadge(text: 'Cancelada', color: GardenColors.error);
    case 'REJECTED_BY_CAREGIVER':
      return const GardenBadge(text: 'Rechazada', color: GardenColors.error);
    case 'MG_PASSED':
      return const GardenBadge(text: 'M&G aprobado', color: GardenColors.success, icon: Icons.check_circle_outline);
    case 'MG_FAILED':
      return const GardenBadge(text: 'M&G no salió bien', color: GardenColors.error);
    default:
      return const GardenBadge(text: 'Pendiente', color: GardenColors.textSecondary);
  }
}

// ── TEMA GLOBAL ────────────────────────────────────────────────────────────

/// Los tres modos de tema que soporta la app.
enum GardenThemeMode {
  /// Sigue la configuración del sistema operativo del teléfono.
  system,
  /// Siempre claro.
  light,
  /// Siempre oscuro.
  dark,
}

class ThemeNotifier extends ChangeNotifier {
  static const String _prefKey = 'garden_theme_mode';

  GardenThemeMode _mode = GardenThemeMode.system;
  bool _isDark = false;

  ThemeNotifier() {
    // Escucha los cambios de brillo del sistema operativo en tiempo real
    PlatformDispatcher.instance.onPlatformBrightnessChanged = _onSystemBrightnessChanged;
    // Estado inicial — se recalcula en init() una vez cargadas las prefs
    _isDark = _computeIsDark();
  }

  void _onSystemBrightnessChanged() {
    if (_mode == GardenThemeMode.system) _updateDark();
  }

  bool _computeIsDark() {
    switch (_mode) {
      case GardenThemeMode.dark:
        return true;
      case GardenThemeMode.light:
        return false;
      case GardenThemeMode.system:
        return PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    }
  }

  void _updateDark() {
    final v = _computeIsDark();
    if (_isDark != v) {
      _isDark = v;
      notifyListeners();
    }
  }

  // ── Getters públicos ──────────────────────────────────────────────────────
  bool get isDark => _isDark;
  GardenThemeMode get mode => _mode;

  // ── Inicialización asíncrona (llamar desde _bootstrap) ────────────────────
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey);
    if (stored != null) {
      _mode = GardenThemeMode.values.firstWhere(
        (m) => m.name == stored,
        orElse: () => GardenThemeMode.system,
      );
    }
    _updateDark();
  }

  // ── Cambiar modo ──────────────────────────────────────────────────────────
  Future<void> setMode(GardenThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    _updateDark();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, mode.name);
    notifyListeners();
  }

  /// Compatibilidad con código anterior (alterna claro ↔ oscuro).
  void toggle() {
    setMode(_isDark ? GardenThemeMode.light : GardenThemeMode.dark);
  }

  @override
  void dispose() {
    PlatformDispatcher.instance.onPlatformBrightnessChanged = null;
    super.dispose();
  }
}

final themeNotifier = ThemeNotifier();

ThemeData gardenTheme({bool dark = false}) {
  final bg       = dark ? GardenColors.darkBackground      : GardenColors.lightBackground;
  final surface  = dark ? GardenColors.darkSurface         : GardenColors.lightSurface;
  final surfaceEl= dark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;
  final border   = dark ? GardenColors.darkBorder          : GardenColors.lightBorder;
  final textP    = dark ? GardenColors.darkTextPrimary     : GardenColors.lightTextPrimary;

  final textH    = dark ? GardenColors.darkTextHint        : GardenColors.lightTextHint;

  // TextTheme explícito — Nunito con pesos, letter-spacing y line-heights
  // según el spec de la tabla de tokens de tipografía.
  // Todos los widgets de Material heredan estos valores automáticamente.
  final nunitoTextTheme = TextTheme(
    // ── Display — Black 900, ls -0.038em, height 0.95–1.05 ──────────────
    displayLarge:  GoogleFonts.nunito(color: textP, fontSize: 57, fontWeight: FontWeight.w900, letterSpacing: -2.17, height: 1.00),
    displayMedium: GoogleFonts.nunito(color: textP, fontSize: 45, fontWeight: FontWeight.w900, letterSpacing: -1.71, height: 1.00),
    displaySmall:  GoogleFonts.nunito(color: textP, fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -0.90, height: 1.05),
    // ── Headline — ExtraBold 800, ls -0.025em, height 1.10–1.20 ─────────
    headlineLarge:  GoogleFonts.nunito(color: textP, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.80, height: 1.10),
    headlineMedium: GoogleFonts.nunito(color: textP, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.62, height: 1.15),
    headlineSmall:  GoogleFonts.nunito(color: textP, fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.43, height: 1.20),
    // ── Title — Bold 700, ls -0.015em, height 1.20–1.35 ─────────────────
    titleLarge:  GoogleFonts.nunito(color: textP, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.30, height: 1.25),
    titleMedium: GoogleFonts.nunito(color: textP, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.16, height: 1.30),
    titleSmall:  GoogleFonts.nunito(color: textP, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing:  0.00, height: 1.30),
    // ── Body — Medium 500 / Regular 400, ls 0, height 1.55–1.65 ─────────
    bodyLarge:  GoogleFonts.nunito(color: textP, fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: 0, height: 1.60),
    bodyMedium: GoogleFonts.nunito(color: textP, fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0, height: 1.55),
    bodySmall:  GoogleFonts.nunito(color: textP, fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: 0, height: 1.50),
    // ── Label — Bold/ExtraBold, ls +0.06–1.20, height 1.20–1.30 ─────────
    labelLarge:  GoogleFonts.nunito(color: textP, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.10, height: 1.20),
    labelMedium: GoogleFonts.nunito(color: textP, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.08, height: 1.25),
    labelSmall:  GoogleFonts.nunito(color: textP, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.20, height: 1.20),
  );

  return ThemeData(
    brightness: dark ? Brightness.dark : Brightness.light,
    primaryColor: GardenColors.primary,
    scaffoldBackgroundColor: bg,
    fontFamily: GoogleFonts.nunito().fontFamily,
    textTheme: nunitoTextTheme,
    colorScheme: ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: GardenColors.primary,
      onPrimary: Colors.white,
      secondary: GardenColors.accent,
      onSecondary: Colors.white,
      surface: surface,
      onSurface: textP,
      error: GardenColors.error,
      onError: Colors.white,
      outline: border,
      surfaceContainerHighest: surfaceEl,
      // Tintes suaves con la paleta
      primaryContainer: GardenColors.lime,
      onPrimaryContainer: GardenColors.primaryDark,
      secondaryContainer: dark
          ? GardenColors.darkSurfaceElevated
          : GardenColors.lime.withValues(alpha: 0.5),
      onSecondaryContainer: textP,
    ),
    iconTheme: IconThemeData(color: textP),
    appBarTheme: AppBarTheme(
      backgroundColor: surface.withValues(alpha: 0.92),
      foregroundColor: textP,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      // AppBar title — Bold 700, ls -0.01em (heading range), height 1.30
      titleTextStyle: GoogleFonts.nunito(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.18,
        height: 1.30,
        color: textP,
      ),
      shadowColor: Colors.transparent,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: GardenColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: GardenRadius.md_),
        // Botones primarios — ExtraBold 800 (primary actions)
        textStyle: GoogleFonts.nunito(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.10),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: GardenColors.primary,
        side: const BorderSide(color: GardenColors.primary),
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: GardenRadius.md_),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: GardenColors.primary),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceEl,
      hintStyle: GardenText.bodyMedium.copyWith(color: textH),
      border: OutlineInputBorder(
        borderRadius: GardenRadius.md_,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: GardenRadius.md_,
        borderSide: BorderSide(color: border, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: GardenRadius.md_,
        borderSide: const BorderSide(color: GardenColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: GardenSpacing.lg,
        vertical: GardenSpacing.md,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: dark
          ? Colors.white.withValues(alpha: 0.06)
          : const Color(0xFFF5F0E8).withValues(alpha: 0.80),
      selectedColor: GardenColors.primary.withValues(alpha: 0.18),
      checkmarkColor: GardenColors.primary,
      // Chips — SemiBold 600 (nav labels, chips, secondary buttons)
      labelStyle: GoogleFonts.nunito(color: textP, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.06),
      side: BorderSide(color: border),
      shape: RoundedRectangleBorder(borderRadius: GardenRadius.md_),
      elevation: 0,
      pressElevation: 0,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? GardenColors.primary : null),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? GardenColors.primary.withValues(alpha: 0.3)
              : null),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? GardenColors.primary : null),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: GardenRadius.lg_,
        side: BorderSide(color: border, width: 1),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: GardenColors.primary,
    ),
    snackBarTheme: SnackBarThemeData(
      // Use a near-black so the default snackbar is always readable in both modes
      backgroundColor: const Color(0xFF1A2210),
      contentTextStyle: GoogleFonts.nunito(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      shape: RoundedRectangleBorder(borderRadius: GardenRadius.md_),
      behavior: SnackBarBehavior.floating,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      elevation: 8,
      actionTextColor: GardenColors.lime,
    ),
    dialogTheme: DialogThemeData(
      // Solid surface so plain AlertDialogs are always readable.
      // GardenGlassDialog is unaffected — it sets backgroundColor: transparent
      // directly on its Dialog widget, overriding the theme.
      backgroundColor: dark ? GardenColors.darkSurface : GardenColors.lightSurface,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: GardenRadius.xl_),
      titleTextStyle: GoogleFonts.nunito(
        color: dark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.18,
        height: 1.30,
        decoration: TextDecoration.none,
      ),
      contentTextStyle: GoogleFonts.nunito(
        color: dark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.55,
        decoration: TextDecoration.none,
      ),
    ),
  );
}

// ── GARDEN SNACKBAR ──────────────────────────────────────────────────────────
// Typed snackbar helper. Use instead of raw SnackBar(...) to get consistent
// icons, colours, and typography across the app.
//
// Usage:
//   GardenSnackBar.success(context, '✅ Mascota guardada');
//   GardenSnackBar.error(context, 'No se pudo conectar');
//   GardenSnackBar.warning(context, 'Debes agregar al menos una mascota');
//   GardenSnackBar.info(context, 'Tu reserva está pendiente de pago');

enum _GSnackType { success, error, warning, info }

class GardenSnackBar {
  GardenSnackBar._();

  static void success(BuildContext context, String message, {Duration? duration}) =>
      _show(context, message, _GSnackType.success, duration: duration);

  static void error(BuildContext context, String message, {Duration? duration}) =>
      _show(context, message, _GSnackType.error, duration: duration);

  static void warning(BuildContext context, String message, {Duration? duration}) =>
      _show(context, message, _GSnackType.warning, duration: duration);

  static void info(BuildContext context, String message, {Duration? duration}) =>
      _show(context, message, _GSnackType.info, duration: duration);

  static void _show(
    BuildContext context,
    String message,
    _GSnackType type, {
    Duration? duration,
  }) {
    final Color bg;
    final IconData icon;
    switch (type) {
      case _GSnackType.success:
        bg   = const Color(0xFF2D6A35); // rich green
        icon = Icons.check_circle_rounded;
        break;
      case _GSnackType.error:
        bg   = const Color(0xFFC0392B); // strong red
        icon = Icons.error_rounded;
        break;
      case _GSnackType.warning:
        bg   = const Color(0xFFB45309); // amber-brown
        icon = Icons.warning_rounded;
        break;
      case _GSnackType.info:
        bg   = const Color(0xFF1A2210); // near-black (default)
        icon = Icons.info_rounded;
        break;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.nunito(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: bg,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          elevation: 8,
          duration: duration ?? const Duration(seconds: 3),
        ),
      );
  }
}
