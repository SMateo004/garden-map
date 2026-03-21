import 'package:flutter/material.dart';

// ── PALETA OFICIAL GARDEN ──────────────────────────────────────────────────
class GardenColors {
  // ── LIGHT MODE (Rover/Airbnb style) ──
  static const lightBackground      = Color(0xFFFAF8F5); // crema suave
  static const lightSurface         = Color(0xFFFFFFFF);
  static const lightSurfaceElevated = Color(0xFFF5F3F0);
  static const lightBorder          = Color(0xFFE8E4DF);
  static const lightTextPrimary     = Color(0xFF1A1A2E);
  static const lightTextSecondary   = Color(0xFF6B7280);
  static const lightTextHint        = Color(0xFF9CA3AF);

  // ── DARK MODE ──
  static const darkBackground       = Color(0xFF0A0E1A);
  static const darkSurface          = Color(0xFF141824);
  static const darkSurfaceElevated  = Color(0xFF1E2433);
  static const darkBorder           = Color(0xFF2A3147);
  static const darkTextPrimary      = Color(0xFFFFFFFF);
  static const darkTextSecondary    = Color(0xFF8892A4);
  static const darkTextHint         = Color(0xFF4A5568);

  // ── COMPARTIDOS ──
  static const primary      = Color(0xFFFF6B35); // naranja GARDEN (igual en ambos modos)
  static const primaryLight = Color(0xFFFF8C5A);
  static const primaryDark  = Color(0xFFE55A25);
  static const secondary    = Color(0xFF4F8EF7); // azul para acciones secundarias
  static const polygon      = Color(0xFF8247E5);
  static const success      = Color(0xFF2ECC71);
  static const warning      = Color(0xFFFFB020);
  static const error        = Color(0xFFE74C3C);
  static const star         = Color(0xFFFFB020);

  // Aliases de compatibilidad (resuelven al dark mode por defecto)
  static const background     = darkBackground;
  static const surface        = darkSurface;
  static const surfaceElevated= darkSurfaceElevated;
  static const border         = darkBorder;
  static const textPrimary    = darkTextPrimary;
  static const textSecondary  = darkTextSecondary;
  static const textHint       = darkTextHint;
  static const accent         = primary; // el naranja es el nuevo acento

  GardenColors._();
}

// ── GRADIENTES ─────────────────────────────────────────────────────────────
class GardenGradients {
  static const primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [GardenColors.primary, GardenColors.primaryDark],
  );

  static const secondary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [GardenColors.secondary, Color(0xFF2D6FE0)],
  );

  static const card = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [GardenColors.darkSurfaceElevated, GardenColors.darkSurface],
  );

  static const hero = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [GardenColors.primary, GardenColors.darkBackground],
    stops: [0.0, 1.0],
  );

  static const verified = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [GardenColors.success, Color(0xFF1A9954)],
  );

  GardenGradients._();
}

// ── TIPOGRAFÍA ─────────────────────────────────────────────────────────────
class GardenText {
  static const String fontFamily = 'Inter';

  // Quitar el color fijo de las constantes para que hereden del tema o se especifique en el widget
  static const displayLarge  = TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.2);
  static const displayMedium = TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.3, height: 1.2);
  static const displaySmall  = TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.2, height: 1.3);

  static const headingLarge  = TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.3);
  static const headingMedium = TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.4);
  static const headingSmall  = TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4);

  static const bodyLarge  = TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.6);
  static const bodyMedium = TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.5);
  static const bodySmall  = TextStyle(fontSize: 13, fontWeight: FontWeight.w400, height: 1.5);

  static const labelLarge  = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3);
  static const labelMedium = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.2);
  static const labelSmall  = TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.3);

  static const caption = TextStyle(fontSize: 11, fontWeight: FontWeight.w400, height: 1.4);
  static const price   = TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: GardenColors.primary, letterSpacing: -0.3);
  static const priceSmall = TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: GardenColors.primary);

  GardenText._();
}

// ── ESPACIADO ──────────────────────────────────────────────────────────────
class GardenSpacing {
  static const double xs  = 4;
  static const double sm  = 8;
  static const double md  = 12;
  static const double lg  = 16;
  static const double xl  = 20;
  static const double xxl = 24;
  static const double xxxl= 32;
  static const double huge= 48;

  GardenSpacing._();
}

// ── BORDES Y RADIOS ────────────────────────────────────────────────────────
class GardenRadius {
  static const double xs  = 6;
  static const double sm  = 8;
  static const double md  = 12;
  static const double lg  = 16;
  static const double xl  = 20;
  static const double xxl = 24;
  static const double full= 999;

  static final xs_  = BorderRadius.circular(xs);
  static final sm_  = BorderRadius.circular(sm);
  static final md_  = BorderRadius.circular(md);
  static final lg_  = BorderRadius.circular(lg);
  static final xl_  = BorderRadius.circular(xl);
  static final xxl_ = BorderRadius.circular(xxl);
  static final full_= BorderRadius.circular(full);

  GardenRadius._();
}

// ── SOMBRAS ────────────────────────────────────────────────────────────────
class GardenShadows {
  static final card = [
    BoxShadow(
      color: Colors.black.withOpacity(0.3),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  static final elevated = [
    BoxShadow(
      color: Colors.black.withOpacity(0.4),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  static final primary = [
    BoxShadow(
      color: GardenColors.primary.withOpacity(0.3),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  static final accent = [
    BoxShadow(
      color: GardenColors.accent.withOpacity(0.3),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  GardenShadows._();
}

// ── WIDGETS REUTILIZABLES ──────────────────────────────────────────────────

/// Tarjeta con glassmorphism
class GardenCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final List<BoxShadow>? shadows;
  final VoidCallback? onTap;
  final bool gradient;

  const GardenCard({
    Key? key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.shadows,
    this.onTap,
    this.gradient = false,
  }) : super(key: key);

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
    Key? key,
    required this.text,
    required this.color,
    this.textColor,
    this.icon,
    this.fontSize = 12,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GardenSpacing.md,
        vertical: GardenSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: GardenRadius.full_,
        border: Border.all(color: color.withOpacity(0.4)),
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
    Key? key,
    required this.width,
    required this.height,
    this.radius = GardenRadius.sm,
  }) : super(key: key);

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
    _animation = Tween<double>(begin: 0.05, end: 0.15).animate(
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
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(_animation.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Avatar con placeholder inteligente
class GardenAvatar extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final String? initials;
  final Color? backgroundColor;

  const GardenAvatar({
    Key? key,
    this.imageUrl,
    required this.size,
    this.initials,
    this.backgroundColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: SizedBox(
        width: size,
        height: size,
        child: imageUrl != null && imageUrl!.isNotEmpty
            ? Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildPlaceholder(),
                loadingBuilder: (_, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return GardenSkeleton(width: size, height: size, radius: size / 2);
                },
              )
            : _buildPlaceholder(),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: backgroundColor ?? GardenColors.darkSurfaceElevated,
      child: initials != null
          ? Center(
              child: Text(
                initials!.substring(0, initials!.length > 2 ? 2 : initials!.length).toUpperCase(),
                style: TextStyle(
                  color: GardenColors.darkTextSecondary,
                  fontSize: size * 0.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : Icon(Icons.person_rounded, color: GardenColors.darkTextSecondary, size: size * 0.5),
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
    Key? key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.outline = false,
    this.color,
    this.icon,
    this.height = 52,
    this.width,
  }) : super(key: key);



  @override
  Widget build(BuildContext context) {
    final btnColor = color ?? GardenColors.primary;

    if (outline) {
      return SizedBox(
        width: width ?? double.infinity,
        height: height,
        child: OutlinedButton(
          onPressed: loading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: btnColor, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: GardenRadius.md_),
          ),
          child: _buildChild(btnColor),
        ),
      );
    }

    return SizedBox(
      width: width ?? double.infinity,
      height: height,

      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [btnColor, Color.lerp(btnColor, Colors.black, 0.2)!],
          ),
          borderRadius: GardenRadius.md_,
          boxShadow: [
            BoxShadow(
              color: btnColor.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: GardenRadius.md_),
          ),
          child: _buildChild(Colors.white),
        ),
      ),
    );
  }

  Widget _buildChild(Color textColor) {
    if (loading) {
      return SizedBox(
        width: 20, height: 20,
        child: CircularProgressIndicator(
          color: textColor, strokeWidth: 2,
        ),
      );
    }
    if (icon != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: textColor, size: 18),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15)),
        ],
      );
    }
    return Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15));
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
    Key? key,
    required this.hint,
    this.controller,
    this.prefixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.maxLines = 1,
    this.maxLength,
    this.validator,
    this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: maxLines,
      maxLength: maxLength,
      validator: validator,
      onChanged: onChanged,
      style: GardenText.bodyMedium,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GardenText.bodyMedium.copyWith(color: GardenColors.textHint),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: GardenColors.textSecondary, size: 20)
            : null,
        filled: true,
        fillColor: GardenColors.surfaceElevated,
        border: OutlineInputBorder(
          borderRadius: GardenRadius.md_,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: GardenRadius.md_,
          borderSide: const BorderSide(color: GardenColors.border, width: 1),
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
      return const GardenBadge(text: 'Pendiente de pago', color: GardenColors.textSecondary);
    case 'PAYMENT_PENDING_APPROVAL':
      return const GardenBadge(text: 'Pago en revisión', color: GardenColors.warning, icon: Icons.schedule);
    case 'WAITING_CAREGIVER_APPROVAL':
      return const GardenBadge(text: 'Esperando cuidador', color: GardenColors.primary, icon: Icons.hourglass_top);
    case 'CONFIRMED':
      return const GardenBadge(text: 'Confirmada', color: GardenColors.success, icon: Icons.check_circle_outline);
    case 'IN_PROGRESS':
      return const GardenBadge(text: 'En curso', color: GardenColors.success, icon: Icons.play_circle_outline);
    case 'COMPLETED':
      return const GardenBadge(text: 'Completada', color: GardenColors.textSecondary, icon: Icons.done_all);
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
  bool _isDark = true; // dark por defecto

  bool get isDark => _isDark;

  void toggle() {
    _isDark = !_isDark;
    notifyListeners();
  }
}

final themeNotifier = ThemeNotifier();

ThemeData gardenTheme({bool dark = true}) {
  final bg     = dark ? GardenColors.darkBackground      : GardenColors.lightBackground;
  final surface= dark ? GardenColors.darkSurface         : GardenColors.lightSurface;
  final surfaceEl= dark ? GardenColors.darkSurfaceElevated: GardenColors.lightSurfaceElevated;
  final border = dark ? GardenColors.darkBorder          : GardenColors.lightBorder;
  final textP  = dark ? GardenColors.darkTextPrimary     : GardenColors.lightTextPrimary;
  final textS  = dark ? GardenColors.darkTextSecondary   : GardenColors.lightTextSecondary;
  final textH  = dark ? GardenColors.darkTextHint        : GardenColors.lightTextHint;

  return ThemeData(
    brightness: dark ? Brightness.dark : Brightness.light,
    primaryColor: GardenColors.primary,
    scaffoldBackgroundColor: bg,
    // fontFamily: GardenText.fontFamily,
    colorScheme: ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: GardenColors.primary,
      secondary: GardenColors.secondary,
      surface: surface,
      onSurface: textP,
      error: GardenColors.error,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onError: Colors.white,
      outline: border,
      surfaceVariant: surfaceEl, // Para compatibilidad con widgets
    ),
    iconTheme: IconThemeData(
      color: textP,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: textP,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 18, fontWeight: FontWeight.w700,
        color: textP, fontFamily: 'Inter',
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: GardenColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: GardenRadius.md_),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: textP,
        side: BorderSide(color: border),
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: GardenRadius.md_),
      ),
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
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: surface,
      selectedItemColor: GardenColors.primary,
      unselectedItemColor: textS,
      elevation: 0,
    ),
    dividerTheme: DividerThemeData(
      color: border,
      thickness: 1,
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: GardenRadius.lg_,
        side: BorderSide(color: border, width: 1),
      ),
    ),
  );
}
