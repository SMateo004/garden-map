import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── PALETA OFICIAL GARDEN ──────────────────────────────────────────────────
// Paleta: oliva #778C43 · vivid-green #58E262 · lima #D9EF9F · beige #DBD0C4
class GardenColors {
  // ── LIGHT MODE ──────────────────────────────────────────────────────────
  static const lightBackground      = Color(0xFFF5F2EC); // crema cálida (beige muy claro)
  static const lightSurface         = Color(0xFFFFFFFF);
  static const lightSurfaceElevated = Color(0xFFF8FBF3); // tinte lima casi imperceptible
  static const lightBorder          = Color(0xFFDBD0C4); // beige exacto de la paleta
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
// Escala: H1 72/900 · H2 48/800 · H3 28/800 · H4 20/700 · Body 16/500 · Meta 13/600
class GardenText {
  // ── Escala principal ─────────────────────────────────────────────────────

  /// 72sp · Nunito Black 900 · ls -0.04em — pantallas hero, splash
  static TextStyle get h1 => GoogleFonts.nunito(
    fontSize: 72, fontWeight: FontWeight.w900,
    letterSpacing: -2.88,   // -0.04em × 72
    height: 1.10,
  );

  /// 48sp · Nunito ExtraBold 800 · ls -0.03em — títulos principales de sección
  static TextStyle get h2 => GoogleFonts.nunito(
    fontSize: 48, fontWeight: FontWeight.w800,
    letterSpacing: -1.44,   // -0.03em × 48
    height: 1.15,
  );

  /// 28sp · Nunito ExtraBold 800 · ls -0.02em — subtítulos de pantalla
  static TextStyle get h3 => GoogleFonts.nunito(
    fontSize: 28, fontWeight: FontWeight.w800,
    letterSpacing: -0.56,   // -0.02em × 28
    height: 1.20,
  );

  /// 20sp · Nunito Bold 700 — encabezados de tarjeta
  static TextStyle get h4 => GoogleFonts.nunito(
    fontSize: 20, fontWeight: FontWeight.w700,
    height: 1.30,
  );

  /// 16sp · Nunito Medium 500 · height 1.5 — cuerpo de texto estándar
  static TextStyle get body => GoogleFonts.nunito(
    fontSize: 16, fontWeight: FontWeight.w500,
    height: 1.50,
  );

  /// 13sp · JetBrains Mono SemiBold 600 — precios, métricas, timestamps
  static TextStyle get metadata => GoogleFonts.jetBrainsMono(
    fontSize: 13, fontWeight: FontWeight.w600,
    height: 1.40,
  );

  // ── Aliases para compatibilidad con código existente ─────────────────────

  static TextStyle get displayLarge  => GoogleFonts.nunito(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.2);
  static TextStyle get displayMedium => h3;
  static TextStyle get displaySmall  => GoogleFonts.nunito(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.2, height: 1.3);

  static TextStyle get headingLarge  => h4;
  static TextStyle get headingMedium => GoogleFonts.nunito(fontSize: 18, fontWeight: FontWeight.w600, height: 1.4);
  static TextStyle get headingSmall  => GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4);

  static TextStyle get bodyLarge  => GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w400, height: 1.6);
  static TextStyle get bodyMedium => GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w400, height: 1.5);
  static TextStyle get bodySmall  => GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w400, height: 1.5);

  static TextStyle get labelLarge  => GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3);
  static TextStyle get labelMedium => GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.2);
  static TextStyle get labelSmall  => GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.3);

  static TextStyle get caption    => GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w400, height: 1.4);
  static TextStyle get price      => GoogleFonts.jetBrainsMono(fontSize: 18, fontWeight: FontWeight.w800, color: GardenColors.primary, letterSpacing: -0.3);
  static TextStyle get priceSmall => GoogleFonts.jetBrainsMono(fontSize: 14, fontWeight: FontWeight.w700, color: GardenColors.primary);

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

    final tintLight = Colors.white.withValues(alpha: useBlur ? 0.72 : 0.92);
    final tintDark  = const Color(0xFF162610).withValues(alpha: useBlur ? 0.82 : 0.95);

    final decoration = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          isDark ? tintDark : tintLight,
          isDark
              ? const Color(0xFF0D1A07).withValues(alpha: useBlur ? 0.75 : 0.93)
              : Colors.white.withValues(alpha: useBlur ? 0.55 : 0.88),
        ],
      ),
      borderRadius: radius,
      border: Border.all(
        color: Colors.white.withValues(alpha: isDark ? 0.09 : 0.50),
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
                      const SizedBox(height: 3),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 240),
                        style: GoogleFonts.nunito(
                          color: labelColor,
                          fontSize: 10,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          letterSpacing: selected ? 0.1 : 0,
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
  const GardenNavItem(this.icon, this.activeIcon, this.label);
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
                style: GoogleFonts.nunito(
                  color: textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  decoration: TextDecoration.none,
                ),
                child: title!,
              ),
            if (title != null && content != null) const SizedBox(height: 12),
            if (content != null)
              DefaultTextStyle(
                style: GoogleFonts.nunito(
                  color: subtextColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  height: 1.5,
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
  const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'https://garden-api-1ldd.onrender.com/api');
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
    if (icon != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: textColor, size: 18),
          const SizedBox(width: 8),
          Text(label, style: GoogleFonts.nunito(color: textColor, fontWeight: FontWeight.w700, fontSize: 15)),
        ],
      );
    }
    return Text(label, style: GoogleFonts.nunito(color: textColor, fontWeight: FontWeight.w700, fontSize: 15));
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
    default:
      return GardenBadge(text: status, color: GardenColors.textSecondary);
  }
}

// ── TEMA GLOBAL ────────────────────────────────────────────────────────────
class ThemeNotifier extends ChangeNotifier {
  bool _isDark = false; // light mode por defecto

  bool get isDark => _isDark;

  void toggle() {
    _isDark = !_isDark;
    notifyListeners();
  }

  void setDark(bool dark) {
    if (_isDark != dark) {
      _isDark = dark;
      notifyListeners();
    }
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

  // Base text theme con Nunito. Todos los widgets de Material que usan el
  // textTheme del theme (AppBar, ListTile, etc.) heredan Nunito automáticamente.
  final baseTextTheme = ThemeData(brightness: dark ? Brightness.dark : Brightness.light).textTheme;
  final nunitoTextTheme = GoogleFonts.nunitoTextTheme(baseTextTheme).apply(
    bodyColor: textP,
    displayColor: textP,
  );

  return ThemeData(
    brightness: dark ? Brightness.dark : Brightness.light,
    primaryColor: GardenColors.primary,
    scaffoldBackgroundColor: bg,
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
      titleTextStyle: GoogleFonts.nunito(
        fontSize: 18,
        fontWeight: FontWeight.w700,
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
        textStyle: GoogleFonts.nunito(fontWeight: FontWeight.w700, fontSize: 15),
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
          : Colors.white.withValues(alpha: 0.55),
      selectedColor: GardenColors.primary.withValues(alpha: 0.18),
      checkmarkColor: GardenColors.primary,
      labelStyle: GoogleFonts.nunito(color: textP, fontSize: 13, fontWeight: FontWeight.w500),
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
      backgroundColor: dark ? GardenColors.darkSurfaceElevated : GardenColors.primaryDark,
      contentTextStyle: GoogleFonts.nunito(color: Colors.white, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: GardenRadius.md_),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: GardenRadius.xl_),
    ),
  );
}
