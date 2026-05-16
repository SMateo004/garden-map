import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Palette (día/noche) ──────────────────────────────────────────────────────
class _P {
  final bool dark;
  const _P(this.dark);

  /// true = noche (7pm–7am), false = día (7am–7pm)
  static bool get isNight {
    final h = DateTime.now().hour;
    return h < 7 || h >= 19;
  }

  // ── Colores día: crema cálida, neutral, profesional ──
  Color get bg        => dark ? const Color(0xFF090E09) : const Color(0xFFFAF8F5);
  Color get surface   => dark ? const Color(0xFF101710) : const Color(0xFFFFFFFF);
  Color get surfaceEl => dark ? const Color(0xFF172017) : const Color(0xFFF3EFE8);
  Color get border    => dark ? const Color(0xFF1E301E) : const Color(0xFFE3DDD5);
  Color get primary   => const Color(0xFF4A7C23);
  Color get accent    => dark ? const Color(0xFF7BC142) : const Color(0xFF3A6218);
  Color get textPri   => dark ? const Color(0xFFF2F6F0) : const Color(0xFF1A1714);
  Color get textSec   => dark ? const Color(0xFF9BAE90) : const Color(0xFF6B6059);
  Color get textMut   => dark ? const Color(0xFF556050) : const Color(0xFF9E9488);
  String get logo => dark
      ? 'assets/images/logo-horizontal-dark.png'
      : 'assets/images/logo-horizontal.png';
  // Hero: noche = negro profundo / día = crema muy suave
  List<Color> get heroGrad => dark
      ? [const Color(0xFF0A1A0A), const Color(0xFF060D06), const Color(0xFF0B190A)]
      : [const Color(0xFFFDF9F3), const Color(0xFFF8F3EA), const Color(0xFFFBF7F0)];
}

// ─── InheritedWidget para acceso global a la paleta ───────────────────────────
class _Theme extends InheritedWidget {
  final _P pal;
  const _Theme({required this.pal, required super.child});
  static _P of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<_Theme>()!.pal;
  @override bool updateShouldNotify(_Theme o) => pal.dark != o.pal.dark;
}

// ─── Data ─────────────────────────────────────────────────────────────────────
class _Pain  { final String emoji, title, desc; const _Pain(this.emoji, this.title, this.desc); }
class _Bene  { final IconData icon; final String title, desc; const _Bene(this.icon, this.title, this.desc); }
class _Testi { final String name, city, quote, initials; final Color color;
               const _Testi(this.name, this.city, this.quote, this.initials, this.color); }
class _Faq   { final String q, a; const _Faq(this.q, this.a); }

/// Datos de cada mascota animada.
/// [emoji] se usa hasta que haya imagen real en assets/images/pets/
/// [imagePath] es opcional — si existe, se usa la imagen; si no, el emoji
class _PetData {
  final String emoji, service;
  final bool fromLeft;
  final String? imagePath; // e.g. 'assets/images/pets/dog_walk.png'
  const _PetData(this.emoji, this.service, {required this.fromLeft, this.imagePath});
}

const _pains = [
  _Pain('😟', '¿Realmente puedo confiar?',
      'Dejás a tu mejor amigo con un desconocido sin ninguna garantía real.'),
  _Pain('😰', '¿Estará bien mientras no estoy?',
      'Sin actualizaciones en tiempo real, la ansiedad no para.'),
  _Pain('💸', 'Precios opacos, cero protección',
      'Pagás por adelantado sin saber si el servicio va a valer lo que costó.'),
];

const _benes = [
  _Bene(Icons.verified_rounded,       'Verificación por IA',     'Análisis fotométrico + antecedentes antes de publicar cada cuidador.'),
  _Bene(Icons.hexagon_outlined,       'Escrow Blockchain',        'Tu pago queda bloqueado en Polygon hasta que vos confirmés el servicio.'),
  _Bene(Icons.location_on_rounded,    'GPS en tiempo real',       'Seguí cada paseo desde tu teléfono con precisión al metro.'),
  _Bene(Icons.local_hospital_rounded, 'Soporte de emergencia',    'Red veterinaria aliada disponible 24/7 para cualquier imprevisto.'),
  _Bene(Icons.star_rounded,           'Reseñas verificadas',      'Solo clientes reales puntúan. Sin reviews falsos, nunca.'),
  _Bene(Icons.chat_bubble_rounded,    'Chat integrado',           'Hablá con el cuidador antes, durante y después del servicio.'),
];

const _testis = [
  _Testi('María González', 'Santa Cruz',
      '"Mi golden quedó en las mejores manos. El cuidador mandó fotos cada hora. Definitivamente volvería."',
      'MG', Color(0xFF4A7C23)),
  _Testi('Roberto Méndez', 'Santa Cruz',
      '"El escrow me dio total tranquilidad. No pagué hasta confirmar que todo salió perfecto."',
      'RM', Color(0xFF2E6B8A)),
  _Testi('Ana Paredes', 'Santa Cruz',
      '"Mi gato llegó relajado después de 3 días. No esperaba ese nivel de cuidado."',
      'AP', Color(0xFF8A4A2E)),
];

const _faqs = [
  _Faq('¿Cómo se verifican los cuidadores?',
      'Cada cuidador pasa por verificación de identidad con IA fotométrica, revisión de antecedentes y entrevista en video antes de aparecer en la plataforma.'),
  _Faq('¿Qué pasa si algo sale mal?',
      'Tu pago está protegido por escrow hasta que confirmés que el servicio fue correcto. Además contamos con cobertura de emergencia veterinaria para cualquier imprevisto.'),
  _Faq('¿Puedo ver a mi mascota durante el servicio?',
      'Sí. Durante los paseos tenés GPS en tiempo real. Durante hospedaje, los cuidadores envían fotos y actualizaciones por el chat integrado.'),
  _Faq('¿Cómo funciona el pago?',
      'Pagás al reservar, pero el dinero queda en escrow blockchain (Polygon). El cuidador lo recibe solo cuando vos confirmás que el servicio fue completado correctamente.'),
  _Faq('¿Cuánto cuesta?',
      'Cada cuidador fija sus propios precios. Vos comparás perfiles, reseñas y tarifas antes de reservar. Sin costos ocultos.'),
];

/// 3 escenas de mascotas — una por "stage" en el scroll.
/// Cuando subas imágenes reales a assets/images/pets/, ponés el path en imagePath.
const _petScenes = [
  _PetData('🐕', 'De paseo 🦮',       fromLeft: true,  imagePath: 'assets/images/pets/dog_walk.png'),
  _PetData('🐱', 'En hospedaje 🏠',   fromLeft: false, imagePath: 'assets/images/pets/cat_home.png'),
  _PetData('🐶', 'Con su cuidador 💚', fromLeft: true,  imagePath: 'assets/images/pets/dog_care.png'),
];

// ─── Main screen ──────────────────────────────────────────────────────────────
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});
  @override State<LandingScreen> createState() => _LandingState();
}

class _LandingState extends State<LandingScreen> {
  final _scroll    = ScrollController();
  bool _isDark     = _P.isNight;
  String  _svc     = 'paseo';
  String? _zone, _size;
  Timer?  _themeTimer;

  /// GlobalKeys para las 3 zonas de stage de mascotas (SizedBox en el scroll)
  final _stageKeys = List.generate(3, (_) => GlobalKey());

  static const _zones = {
    'EQUIPETROL': 'Equipetrol', 'URBARI': 'Urbari', 'NORTE': 'Norte',
    'LAS_PALMAS': 'Las Palmas', 'CENTRO_SAN_MARTIN': 'Centro/San Martín',
    'OTROS': 'Otros',
  };

  @override
  void initState() {
    super.initState();
    // Actualizar tema cada minuto (cambio automático al anochecer/amanecer)
    _themeTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final n = _P.isNight;
      if (n != _isDark && mounted) setState(() => _isDark = n);
    });
  }

  @override
  void dispose() {
    _themeTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _search() {
    var q = '?service=$_svc';
    if (_zone != null) q += '&zone=$_zone';
    if (_size  != null) q += '&size=$_size';
    context.go('/marketplace$q');
  }

  // ── Pet stage sliver (espacio visual para que la magia suceda) ───────────────
  Widget _petStage(int i) => SliverToBoxAdapter(
    child: SizedBox(key: _stageKeys[i], height: 130),
  );

  @override
  Widget build(BuildContext context) {
    final pal    = _P(_isDark);
    final w      = MediaQuery.of(context).size.width;
    final h      = MediaQuery.of(context).size.height;
    final mobile = w < 768;

    return _Theme(
      pal: pal,
      child: Scaffold(
        backgroundColor: pal.bg,
        endDrawer: mobile ? _MobileMenu(go: context.go) : null,
        body: Stack(children: [

          // ── Contenido principal ────────────────────────────────────────────
          Builder(builder: (ctx) => CustomScrollView(
            controller: _scroll,
            slivers: [
              _sliverHeader(ctx, mobile, pal),
              _sliverHero(mobile),
              // Stage 0 — después del hero
              _petStage(0),
              SliverToBoxAdapter(child: _PainSection(scroll: _scroll, mobile: mobile)),
              SliverToBoxAdapter(child: _MidCta(onTap: _search, mobile: mobile)),
              // Stage 1 — entre mid-CTA y beneficios
              _petStage(1),
              SliverToBoxAdapter(child: _BenefitsSection(scroll: _scroll, mobile: mobile)),
              SliverToBoxAdapter(child: _TestiSection(scroll: _scroll, mobile: mobile)),
              // Stage 2 — entre testimonios y FAQ
              _petStage(2),
              SliverToBoxAdapter(child: _FaqSection(scroll: _scroll, mobile: mobile)),
              SliverToBoxAdapter(child: _FinalCta(mobile: mobile)),
              SliverToBoxAdapter(child: _Footer(mobile: mobile)),
            ],
          )),

          // ── Overlay de mascotas (no captura eventos) ───────────────────────
          if (!MediaQuery.of(context).disableAnimations)
            IgnorePointer(
              child: _PetLayer(
                scroll:     _scroll,
                stageKeys:  _stageKeys,
                screenW:    w,
                screenH:    h,
              ),
            ),
        ]),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────
  Widget _sliverHeader(BuildContext ctx, bool mobile, _P pal) => SliverAppBar(
    backgroundColor: pal.bg,
    elevation: 0,
    scrolledUnderElevation: 0,
    pinned: true,
    toolbarHeight: 64,
    titleSpacing: 24,
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(1),
      child: Container(height: 1, color: pal.border),
    ),
    title: Image.asset(pal.logo, height: 60),
    actions: mobile
        ? [
            Builder(builder: (c) => IconButton(
              icon: Icon(Icons.menu_rounded, color: pal.textPri, size: 26),
              onPressed: () => Scaffold.of(c).openEndDrawer(),
            )),
            const SizedBox(width: 8),
          ]
        : [
            _NavLink('Buscar cuidadores', () => context.go('/marketplace')),
            _NavLink('Para cuidadores',   () => context.go('/become-caregiver')),
            _NavLink('Iniciar sesión',    () => context.go('/login')),
            const SizedBox(width: 12),
            _PrimaryBtn('Registrarse', () => context.go('/register'), w: 150, h: 40),
            const SizedBox(width: 24),
          ],
  );

  // ── Hero ────────────────────────────────────────────────────────────────────
  Widget _sliverHero(bool mobile) => SliverToBoxAdapter(
    child: Builder(builder: (context) {
      final pal = _Theme.of(context);
      // Alto fijo para que Positioned(bottom:0) funcione en el Stack
      final heroH = mobile ? 700.0 : 800.0;

      return SizedBox(
        width: double.infinity,
        height: heroH,
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: pal.heroGrad, stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [

              // ── Mascotas decorativas de fondo (solo desktop) ────────────────
              if (!mobile) ...[
                // Gato — izquierda
                Positioned(
                  left: 0, bottom: 0,
                  child: Opacity(
                    opacity: pal.dark ? 0.22 : 0.48,
                    child: Image.asset(
                      'assets/images/pets/cat_home.png',
                      height: heroH * 0.62,
                      fit: BoxFit.contain,
                    ),
                  ).animate().fadeIn(delay: 700.ms, duration: 900.ms)
                   .slideX(begin: -0.15, end: 0, delay: 700.ms, duration: 900.ms, curve: Curves.easeOutCubic),
                ),
                // Perro — derecha
                Positioned(
                  right: 0, bottom: 0,
                  child: Opacity(
                    opacity: pal.dark ? 0.22 : 0.48,
                    child: Image.asset(
                      'assets/images/pets/dog_walk.png',
                      height: heroH * 0.68,
                      fit: BoxFit.contain,
                    ),
                  ).animate().fadeIn(delay: 850.ms, duration: 900.ms)
                   .slideX(begin: 0.15, end: 0, delay: 850.ms, duration: 900.ms, curve: Curves.easeOutCubic),
                ),
              ],

              // ── Contenido central ──────────────────────────────────────────
              Positioned.fill(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      mobile ? 24 : 200, mobile ? 48 : 72,
                      mobile ? 24 : 200, mobile ? 48 : 64,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const _GreenTag('GARDEN · La plataforma líder en Bolivia')
                            .animate().fadeIn(duration: 500.ms)
                            .slideY(begin: 0.2, end: 0, duration: 500.ms, curve: Curves.easeOutCubic),
                        const SizedBox(height: 24),

                        Builder(builder: (ctx) {
                          final p = _Theme.of(ctx);
                          return Text(
                            'Tu mascota merece lo mejor.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: mobile ? 36 : 68, fontWeight: FontWeight.w900,
                              color: p.textPri, height: 1.05, letterSpacing: -2.5),
                          );
                        }).animate().fadeIn(delay: 150.ms, duration: 600.ms)
                          .slideY(begin: 0.2, end: 0, delay: 150.ms, duration: 600.ms, curve: Curves.easeOutCubic),
                        const SizedBox(height: 20),

                        Builder(builder: (ctx) {
                          final p = _Theme.of(ctx);
                          return Text(
                            mobile
                                ? 'Cuidadores verificados por IA.\nPagos asegurados con escrow blockchain.'
                                : 'Cuidadores verificados por IA. Pagos asegurados con escrow blockchain.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: mobile ? 15 : 19, fontWeight: FontWeight.w400,
                              color: p.textSec, height: 1.6),
                          );
                        }).animate().fadeIn(delay: 300.ms, duration: 600.ms)
                          .slideY(begin: 0.2, end: 0, delay: 300.ms, duration: 600.ms, curve: Curves.easeOutCubic),
                        const SizedBox(height: 36),

                        Wrap(
                          alignment: WrapAlignment.center, spacing: 12, runSpacing: 12,
                          children: [
                            _PrimaryBtn('Encontrar cuidador 🐾', _search, w: 230, h: 52),
                            _OutlineBtn('Cómo funciona', () {}, w: 170, h: 52),
                          ],
                        ).animate().fadeIn(delay: 450.ms, duration: 600.ms)
                         .slideY(begin: 0.2, end: 0, delay: 450.ms, duration: 600.ms, curve: Curves.easeOutCubic),
                        const SizedBox(height: 48),

                        _SearchBar(
                          mobile: mobile, svc: _svc, zone: _zone, size: _size, zones: _zones,
                          onSvcChange:  (v) => setState(() => _svc  = v),
                          onZoneChange: (v) => setState(() => _zone = v),
                          onSizeChange: (v) => setState(() => _size = v),
                          onSearch: _search,
                        ).animate().fadeIn(delay: 600.ms, duration: 600.ms)
                         .slideY(begin: 0.1, end: 0, delay: 600.ms, duration: 600.ms, curve: Curves.easeOutCubic),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }),
  );
}

// ─── Pet overlay ──────────────────────────────────────────────────────────────

class _PetLayer extends StatefulWidget {
  final ScrollController scroll;
  final List<GlobalKey>  stageKeys;
  final double screenW, screenH;
  const _PetLayer({
    required this.scroll, required this.stageKeys,
    required this.screenW, required this.screenH,
  });
  @override State<_PetLayer> createState() => _PetLayerState();
}

class _PetLayerState extends State<_PetLayer> with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;
  final List<double?> _capturedY = [null, null, null];

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(
      _petScenes.length,
      (_) => AnimationController(vsync: this, duration: const Duration(seconds: 7)),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.scroll.addListener(_check);
      _check();
    });
  }

  @override
  void dispose() {
    widget.scroll.removeListener(_check);
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  void _check() {
    if (!mounted) return;
    for (var i = 0; i < _petScenes.length; i++) {
      if (_ctrls[i].value > 0) continue; // ya lanzada
      final box = widget.stageKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final pos = box.localToGlobal(Offset.zero);
      // Lanzar cuando el stage entra a la pantalla (con margen)
      if (pos.dy < widget.screenH * 0.88 && pos.dy > -60) {
        _capturedY[i] = pos.dy - 20; // Y capturada una sola vez
        _ctrls[i].forward();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: List.generate(_petScenes.length, (i) {
        final scene = _petScenes[i];
        return AnimatedBuilder(
          animation: _ctrls[i],
          builder: (ctx, _) {
            final t = _ctrls[i].value;
            if (t == 0 || _capturedY[i] == null) return const SizedBox.shrink();

            // Movimiento horizontal lineal de lado a lado
            final startX = scene.fromLeft ? -130.0 : widget.screenW + 130;
            final endX   = scene.fromLeft ? widget.screenW + 130 : -130.0;
            final x      = startX + (endX - startX) * t;

            // Leve arco vertical (rebote natural mientras camina)
            final arc = -18.0 * math.sin(t * math.pi);

            return Positioned(
              left: x,
              top:  _capturedY[i]! + arc,
              child: _PetWidget(scene: scene),
            );
          },
        );
      }),
    );
  }
}

class _PetWidget extends StatelessWidget {
  final _PetData scene;
  const _PetWidget({required this.scene});

  @override
  Widget build(BuildContext context) {
    final pal = _Theme.of(context);

    Widget petVisual;
    if (scene.imagePath != null) {
      // Imagen real (PNG transparente subida por el usuario)
      petVisual = Image.asset(scene.imagePath!, height: 80, fit: BoxFit.contain);
    } else {
      // Placeholder emoji hasta tener imagen real
      petVisual = Text(scene.emoji, style: const TextStyle(fontSize: 52));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Flip horizontal si va de derecha a izquierda
        Transform.scale(
          scaleX: scene.fromLeft ? 1.0 : -1.0,
          child: petVisual,
        ),
        const SizedBox(height: 6),
        // Badge de servicio — texto NO se flipea
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: pal.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: pal.primary.withValues(alpha: 0.35)),
          ),
          child: Text(scene.service,
            style: TextStyle(color: pal.accent, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

// ─── Scroll reveal ────────────────────────────────────────────────────────────
class _Reveal extends StatefulWidget {
  final Widget child;
  final ScrollController scroll;
  final Duration delay;
  const _Reveal({required this.child, required this.scroll, this.delay = Duration.zero});
  @override State<_Reveal> createState() => _RevealState();
}
class _RevealState extends State<_Reveal> {
  bool _vis = false;
  final _key = GlobalKey();
  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _check(); widget.scroll.addListener(_check);
    });
  }
  @override void dispose() { widget.scroll.removeListener(_check); super.dispose(); }
  void _check() {
    if (_vis || !mounted) return;
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    if (box.localToGlobal(Offset.zero).dy < MediaQuery.of(context).size.height * 0.93) {
      widget.scroll.removeListener(_check);
      Future.delayed(widget.delay, () { if (mounted) setState(() => _vis = true); });
    }
  }
  @override Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return KeyedSubtree(
      key: _key,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 600), opacity: _vis ? 1.0 : 0.0,
        curve: Curves.easeOut,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 600),
          offset: _vis ? Offset.zero : const Offset(0, 0.05),
          curve: Curves.easeOut, child: widget.child,
        ),
      ),
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _GreenTag extends StatelessWidget {
  final String label;
  const _GreenTag(this.label);
  @override Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: pal.primary.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: pal.primary.withValues(alpha: 0.38)),
      ),
      child: Text(label, style: TextStyle(
        color: pal.accent, fontWeight: FontWeight.w600, fontSize: 12, letterSpacing: 0.5)),
    );
  }
}

class _PrimaryBtn extends StatefulWidget {
  final String label; final VoidCallback onTap; final double w, h;
  const _PrimaryBtn(this.label, this.onTap, {this.w = 160, this.h = 44});
  @override State<_PrimaryBtn> createState() => _PrimaryBtnState();
}
class _PrimaryBtnState extends State<_PrimaryBtn> {
  bool _h = false;
  @override Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: widget.w, height: widget.h,
          decoration: BoxDecoration(
            color: _h ? pal.accent : pal.primary,
            borderRadius: BorderRadius.circular(12),
            boxShadow: _h ? [BoxShadow(color: pal.primary.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 8))] : [],
          ),
          child: Center(child: Text(widget.label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))),
        ),
      ),
    );
  }
}

class _OutlineBtn extends StatefulWidget {
  final String label; final VoidCallback onTap; final double w, h;
  const _OutlineBtn(this.label, this.onTap, {this.w = 160, this.h = 44});
  @override State<_OutlineBtn> createState() => _OutlineBtnState();
}
class _OutlineBtnState extends State<_OutlineBtn> {
  bool _h = false;
  @override Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: widget.w, height: widget.h,
          decoration: BoxDecoration(
            color: _h ? pal.primary.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _h ? pal.accent : pal.textSec.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Center(child: Text(widget.label,
            style: TextStyle(color: _h ? pal.accent : pal.textSec, fontWeight: FontWeight.w600, fontSize: 14))),
        ),
      ),
    );
  }
}

class _NavLink extends StatefulWidget {
  final String label; final VoidCallback onTap;
  const _NavLink(this.label, this.onTap);
  @override State<_NavLink> createState() => _NavLinkState();
}
class _NavLinkState extends State<_NavLink> {
  bool _h = false;
  @override Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 150),
            style: TextStyle(color: _h ? pal.accent : pal.textSec, fontWeight: FontWeight.w500, fontSize: 14),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}

// ─── Search bar ───────────────────────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  final bool mobile; final String svc; final String? zone, size;
  final Map<String, String> zones;
  final ValueChanged<String> onSvcChange;
  final ValueChanged<String?> onZoneChange, onSizeChange;
  final VoidCallback onSearch;
  const _SearchBar({
    required this.mobile, required this.svc, required this.zone, required this.size,
    required this.zones, required this.onSvcChange, required this.onZoneChange,
    required this.onSizeChange, required this.onSearch,
  });
  @override Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 860),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pal.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: pal.dark ? 0.5 : 0.1), blurRadius: 48, offset: const Offset(0, 16))],
      ),
      child: Wrap(
        alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10, runSpacing: 10,
        children: [
          _SvcToggle(selected: svc, onChanged: onSvcChange),
          _DDark<String>(
            w: 190, value: zone, hint: 'Zona', icon: Icons.location_on_rounded,
            items: zones.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            onChanged: onZoneChange,
          ),
          _DDark<String>(
            w: 155, value: size, hint: 'Tamaño', icon: Icons.straighten,
            items: ['PEQUEÑO','MEDIANO','GRANDE','GIGANTE'].map((e) =>
              DropdownMenuItem(value: e, child: Text(e[0]+e.substring(1).toLowerCase()))).toList(),
            onChanged: onSizeChange,
          ),
          _PrimaryBtn('Buscar 🔍', onSearch, w: 140, h: 52),
        ],
      ),
    );
  }
}

class _SvcToggle extends StatelessWidget {
  final String selected; final ValueChanged<String> onChanged;
  const _SvcToggle({required this.selected, required this.onChanged});
  @override Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return Container(
      width: 230, height: 52,
      decoration: BoxDecoration(color: pal.surfaceEl, borderRadius: BorderRadius.circular(14), border: Border.all(color: pal.border)),
      child: Row(children: ['paseo','hospedaje'].map((s) {
        final active = selected == s;
        return Expanded(child: GestureDetector(
          onTap: () => onChanged(s),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: active ? pal.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Center(child: Text(
              s == 'paseo' ? 'Paseo 🦮' : 'Hospedaje 🏠',
              style: TextStyle(
                color: active ? Colors.white : pal.textSec,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500, fontSize: 13),
            )),
          ),
        ));
      }).toList()),
    );
  }
}

class _DDark<T> extends StatelessWidget {
  final double w; final T? value; final String hint; final IconData icon;
  final List<DropdownMenuItem<T>> items; final ValueChanged<T?> onChanged;
  const _DDark({required this.w, required this.value, required this.hint,
    required this.icon, required this.items, required this.onChanged});
  @override Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return Container(
      width: w, height: 52, padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: pal.surfaceEl, borderRadius: BorderRadius.circular(14), border: Border.all(color: pal.border)),
      child: DropdownButtonHideUnderline(child: DropdownButton<T>(
        value: value,
        hint: Text(hint, style: TextStyle(color: pal.textSec, fontSize: 13, fontWeight: FontWeight.w500)),
        isExpanded: true,
        icon: Icon(icon, color: pal.accent, size: 18),
        dropdownColor: pal.surface,
        style: TextStyle(color: pal.textPri, fontSize: 13, fontWeight: FontWeight.w500),
        items: items, onChanged: onChanged,
      )),
    );
  }
}

// ─── Sections ─────────────────────────────────────────────────────────────────

class _PainSection extends StatelessWidget {
  final ScrollController scroll; final bool mobile;
  const _PainSection({required this.scroll, required this.mobile});
  @override Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: mobile ? 24 : 80, vertical: 96),
      child: Column(children: [
        _Reveal(scroll: scroll, child: const _GreenTag('¿Te suena familiar?')),
        const SizedBox(height: 20),
        _Reveal(scroll: scroll, delay: 100.ms,
          child: Text('Los problemas que resolvemos', textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: mobile ? 28 : 44, fontWeight: FontWeight.w900,
              color: pal.textPri, letterSpacing: -1.5))),
        const SizedBox(height: 56),
        Wrap(alignment: WrapAlignment.center, spacing: 20, runSpacing: 20,
          children: List.generate(_pains.length, (i) => _Reveal(
            scroll: scroll, delay: Duration(milliseconds: 80 * i),
            child: _PainCard(_pains[i], mobile: mobile),
          ))),
      ]),
    );
  }
}

class _PainCard extends StatefulWidget {
  final _Pain p; final bool mobile;
  const _PainCard(this.p, {required this.mobile});
  @override State<_PainCard> createState() => _PainCardState();
}
class _PainCardState extends State<_PainCard> {
  bool _h = false;
  @override Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: widget.mobile ? double.infinity : 310,
        padding: const EdgeInsets.all(28),
        transform: Matrix4.translationValues(0, _h ? -5 : 0, 0),
        decoration: BoxDecoration(
          color: _h ? pal.surfaceEl : pal.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _h ? pal.primary.withValues(alpha: 0.5) : pal.border),
          boxShadow: _h ? [BoxShadow(color: pal.primary.withValues(alpha: 0.1), blurRadius: 28, offset: const Offset(0, 10))] : [],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.p.emoji, style: const TextStyle(fontSize: 38)),
          const SizedBox(height: 16),
          Text(widget.p.title, style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: pal.textPri)),
          const SizedBox(height: 8),
          Text(widget.p.desc, style: TextStyle(color: pal.textSec, fontSize: 14, height: 1.65)),
        ]),
      ),
    );
  }
}

class _MidCta extends StatelessWidget {
  final VoidCallback onTap; final bool mobile;
  const _MidCta({required this.onTap, required this.mobile});
  @override Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: mobile ? 24 : 80, vertical: 16),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: mobile ? 28 : 64, vertical: 56),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [pal.primary.withValues(alpha: 0.2), pal.primary.withValues(alpha: 0.06)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: pal.primary.withValues(alpha: 0.28)),
        ),
        child: Column(children: [
          Text('Únete a miles de dueños que ya confían en GARDEN',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: mobile ? 22 : 32, fontWeight: FontWeight.w800,
              color: pal.textPri, letterSpacing: -1, height: 1.2)),
          const SizedBox(height: 28),
          _PrimaryBtn('Buscar cuidadores ahora', onTap, w: 260, h: 52),
        ]),
      ),
    );
  }
}

class _BenefitsSection extends StatelessWidget {
  final ScrollController scroll; final bool mobile;
  const _BenefitsSection({required this.scroll, required this.mobile});
  @override Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return Container(
      width: double.infinity, color: pal.surface,
      padding: EdgeInsets.symmetric(horizontal: mobile ? 24 : 80, vertical: 96),
      child: Column(children: [
        _Reveal(scroll: scroll, child: const _GreenTag('Todo lo que necesitás')),
        const SizedBox(height: 20),
        _Reveal(scroll: scroll, delay: 100.ms,
          child: Text('¿Por qué GARDEN?', textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: mobile ? 28 : 44, fontWeight: FontWeight.w900,
              color: pal.textPri, letterSpacing: -1.5))),
        const SizedBox(height: 56),
        Wrap(alignment: WrapAlignment.center, spacing: 16, runSpacing: 16,
          children: List.generate(_benes.length, (i) => _Reveal(
            scroll: scroll, delay: Duration(milliseconds: 70 * (i % 3)),
            child: _BeneCard(_benes[i], mobile: mobile),
          ))),
      ]),
    );
  }
}

class _BeneCard extends StatefulWidget {
  final _Bene b; final bool mobile;
  const _BeneCard(this.b, {required this.mobile});
  @override State<_BeneCard> createState() => _BeneCardState();
}
class _BeneCardState extends State<_BeneCard> {
  bool _h = false;
  @override Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: mobile ? double.infinity : 270,
        padding: const EdgeInsets.all(24),
        transform: Matrix4.translationValues(0, _h ? -4 : 0, 0),
        decoration: BoxDecoration(
          color: _h ? pal.surfaceEl : pal.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _h ? pal.primary.withValues(alpha: 0.5) : pal.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: pal.primary.withValues(alpha: _h ? 0.26 : 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(b.icon, color: pal.accent, size: 22),
          ),
          const SizedBox(height: 16),
          Text(b.title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: pal.textPri)),
          const SizedBox(height: 8),
          Text(b.desc, style: TextStyle(color: pal.textSec, fontSize: 13, height: 1.65)),
        ]),
      ),
    );
  }
  _Bene get b => widget.b;
  bool  get mobile => widget.mobile;
}

class _TestiSection extends StatelessWidget {
  final ScrollController scroll; final bool mobile;
  const _TestiSection({required this.scroll, required this.mobile});
  @override Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: mobile ? 24 : 80, vertical: 96),
      child: Column(children: [
        _Reveal(scroll: scroll, child: const _GreenTag('Lo que dicen nuestros usuarios')),
        const SizedBox(height: 20),
        _Reveal(scroll: scroll, delay: 100.ms,
          child: Text('Confianza que se siente', textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: mobile ? 28 : 44, fontWeight: FontWeight.w900,
              color: pal.textPri, letterSpacing: -1.5))),
        const SizedBox(height: 56),
        Wrap(alignment: WrapAlignment.center, spacing: 20, runSpacing: 20,
          children: List.generate(_testis.length, (i) => _Reveal(
            scroll: scroll, delay: Duration(milliseconds: 80 * i),
            child: _TestiCard(_testis[i], mobile: mobile),
          ))),
      ]),
    );
  }
}

class _TestiCard extends StatelessWidget {
  final _Testi t; final bool mobile;
  const _TestiCard(this.t, {required this.mobile});
  @override Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return Container(
      width: mobile ? double.infinity : 310,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pal.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: List.generate(5, (_) => const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 17))),
        const SizedBox(height: 16),
        Text(t.quote, style: TextStyle(color: pal.textPri, fontSize: 14, height: 1.75, fontStyle: FontStyle.italic)),
        const SizedBox(height: 20),
        Row(children: [
          CircleAvatar(radius: 20, backgroundColor: t.color.withValues(alpha: 0.22),
            child: Text(t.initials, style: TextStyle(color: t.color, fontWeight: FontWeight.w800, fontSize: 13))),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.name, style: TextStyle(color: pal.textPri, fontWeight: FontWeight.w700, fontSize: 14)),
            Text(t.city, style: TextStyle(color: pal.textSec, fontSize: 12)),
          ]),
        ]),
      ]),
    );
  }
}

class _FaqSection extends StatelessWidget {
  final ScrollController scroll; final bool mobile;
  const _FaqSection({required this.scroll, required this.mobile});
  @override Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return Container(
      width: double.infinity, color: pal.surface,
      padding: EdgeInsets.symmetric(horizontal: mobile ? 24 : 80, vertical: 96),
      child: Column(children: [
        _Reveal(scroll: scroll, child: const _GreenTag('Preguntas frecuentes')),
        const SizedBox(height: 20),
        _Reveal(scroll: scroll, delay: 100.ms,
          child: Text('Resolvemos tus dudas', textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: mobile ? 28 : 44, fontWeight: FontWeight.w900,
              color: pal.textPri, letterSpacing: -1.5))),
        const SizedBox(height: 56),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(children: List.generate(_faqs.length, (i) => _Reveal(
            scroll: scroll, delay: Duration(milliseconds: 60 * i),
            child: _FaqTile(_faqs[i]),
          ))),
        ),
      ]),
    );
  }
}

class _FaqTile extends StatefulWidget {
  final _Faq faq; const _FaqTile(this.faq);
  @override State<_FaqTile> createState() => _FaqTileState();
}
class _FaqTileState extends State<_FaqTile> {
  bool _open = false;
  @override Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _open ? pal.surfaceEl : pal.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _open ? pal.primary.withValues(alpha: 0.4) : pal.border),
      ),
      child: Column(children: [
        GestureDetector(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Expanded(child: Text(widget.faq.q,
                style: TextStyle(color: pal.textPri, fontWeight: FontWeight.w600, fontSize: 15))),
              AnimatedRotation(
                duration: const Duration(milliseconds: 200), turns: _open ? 0.5 : 0,
                child: Icon(Icons.keyboard_arrow_down_rounded, color: pal.accent, size: 22)),
            ]),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          crossFadeState: _open ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Text(widget.faq.a, style: TextStyle(color: pal.textSec, fontSize: 14, height: 1.7)),
          ),
          secondChild: const SizedBox.shrink(),
        ),
      ]),
    );
  }
}

class _FinalCta extends StatelessWidget {
  final bool mobile; const _FinalCta({required this.mobile});
  @override Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: mobile ? 24 : 80, vertical: 96),
      child: Column(children: [
        Text('¿Listo para darle lo mejor?', textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: mobile ? 32 : 56, fontWeight: FontWeight.w900,
            color: pal.textPri, letterSpacing: -2, height: 1.05)),
        const SizedBox(height: 16),
        Text('Encontrá el cuidador perfecto hoy.',
          textAlign: TextAlign.center,
          style: TextStyle(color: pal.textSec, fontSize: 18)),
        const SizedBox(height: 40),
        Wrap(alignment: WrapAlignment.center, spacing: 16, runSpacing: 12, children: [
          _PrimaryBtn('Buscar cuidadores ahora 🐾', () => context.go('/marketplace'), w: 280, h: 56),
          _OutlineBtn('Convertirse en cuidador', () => context.go('/become-caregiver'), w: 230, h: 56),
        ]),
      ]),
    );
  }
}

class _Footer extends StatelessWidget {
  final bool mobile; const _Footer({required this.mobile});
  @override Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: mobile ? 24 : 80, vertical: 40),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: pal.border))),
      child: Column(children: [
        Image.asset(pal.logo, height: 36),
        const SizedBox(height: 16),
        Text('© 2025 GARDEN · Santa Cruz de la Sierra, Bolivia',
          style: TextStyle(color: pal.textMut, fontSize: 13)),
        const SizedBox(height: 12),
        Wrap(alignment: WrapAlignment.center, spacing: 24, children: [
          Text('Términos de uso', style: TextStyle(color: pal.textSec, fontSize: 13)),
          Text('Privacidad',      style: TextStyle(color: pal.textSec, fontSize: 13)),
          Text('Contacto',        style: TextStyle(color: pal.textSec, fontSize: 13)),
        ]),
      ]),
    );
  }
}

// ─── Mobile drawer ────────────────────────────────────────────────────────────
class _MobileMenu extends StatelessWidget {
  final void Function(String) go;
  const _MobileMenu({required this.go});
  @override Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return Drawer(
      backgroundColor: pal.surface,
      child: SafeArea(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Image.asset(pal.logo, height: 40),
          const SizedBox(height: 28),
          Divider(color: pal.border),
          const SizedBox(height: 16),
          _MI('Buscar cuidadores', Icons.search_rounded,
            () { Navigator.pop(context); go('/marketplace'); }, pal),
          _MI('Para cuidadores', Icons.pets_rounded,
            () { Navigator.pop(context); go('/become-caregiver'); }, pal),
          _MI('Iniciar sesión', Icons.login_rounded,
            () { Navigator.pop(context); go('/login'); }, pal),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () { Navigator.pop(context); go('/register'); },
            child: Container(
              width: double.infinity, height: 52,
              decoration: BoxDecoration(color: pal.primary, borderRadius: BorderRadius.circular(12)),
              child: const Center(child: Text('Registrarse',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
            ),
          ),
        ]),
      )),
    );
  }
}

class _MI extends StatelessWidget {
  final String label; final IconData icon; final VoidCallback onTap; final _P pal;
  const _MI(this.label, this.icon, this.onTap, this.pal);
  @override Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: pal.accent, size: 20),
    title: Text(label, style: TextStyle(color: pal.textPri, fontWeight: FontWeight.w500)),
    onTap: onTap,
  );
}
