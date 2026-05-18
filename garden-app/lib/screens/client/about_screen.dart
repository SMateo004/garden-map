import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

// ─── Misma paleta día/noche que landing_screen ────────────────────────────────
class _P {
  final bool dark;
  const _P(this.dark);

  static bool get isNight {
    final h = DateTime.now().hour;
    return h < 7 || h >= 19;
  }

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
  List<Color> get heroGrad => dark
      ? [const Color(0xFF0A1A0A), const Color(0xFF060D06)]
      : [const Color(0xFFF0F7E8), const Color(0xFFE8F4DC)];
}

// ─── InheritedWidget ─────────────────────────────────────────────────────────
class _Theme extends InheritedWidget {
  final _P pal;
  const _Theme({required this.pal, required super.child});
  static _P of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<_Theme>()!.pal;
  @override bool updateShouldNotify(_Theme o) => pal.dark != o.pal.dark;
}

// ─── Screen ───────────────────────────────────────────────────────────────────
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});
  @override State<AboutScreen> createState() => _AboutState();
}

class _AboutState extends State<AboutScreen> {
  final _scroll   = ScrollController();
  bool  _isDark   = _P.isNight;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      final n = _P.isNight;
      if (n != _isDark && mounted) setState(() => _isDark = n);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final pal    = _P(_isDark);
    final w      = MediaQuery.of(context).size.width;
    final mobile = w < 768;

    return _Theme(
      pal: pal,
      child: Scaffold(
        backgroundColor: pal.bg,
        body: CustomScrollView(
          controller: _scroll,
          slivers: [
            _buildHeader(mobile, pal),
            SliverToBoxAdapter(child: _HeroSection(mobile: mobile)),
            SliverToBoxAdapter(child: _AboutSection(scroll: _scroll, mobile: mobile)),
            SliverToBoxAdapter(child: _MissionVisionSection(scroll: _scroll, mobile: mobile)),
            SliverToBoxAdapter(child: _ValuesSection(scroll: _scroll, mobile: mobile)),
            SliverToBoxAdapter(child: _TeamSection(scroll: _scroll, mobile: mobile)),
            SliverToBoxAdapter(child: _LegalSection(mobile: mobile, openUrl: _openUrl)),
            SliverToBoxAdapter(child: _FooterAbout(mobile: mobile)),
          ],
        ),
      ),
    );
  }

  SliverAppBar _buildHeader(bool mobile, _P pal) => SliverAppBar(
    backgroundColor: pal.bg,
    elevation: 0,
    scrolledUnderElevation: 0,
    pinned: true,
    toolbarHeight: 64,
    automaticallyImplyLeading: false,
    title: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        GestureDetector(
          onTap: () => context.go('/'),
          child: Image.asset(pal.logo, height: 40),
        ),
        const Spacer(),
        if (mobile)
          GestureDetector(
            onTap: () => context.go('/'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: pal.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.arrow_back_rounded, color: pal.textSec, size: 16),
                const SizedBox(width: 6),
                Text('Volver', style: TextStyle(color: pal.textSec, fontSize: 13, fontWeight: FontWeight.w500)),
              ]),
            ),
          )
        else ...[
          _NavBtn('Inicio', () => context.go('/'), pal),
          _NavBtn('Cuidadores', () => context.go('/marketplace'), pal),
          _NavBtn('Para cuidadores', () => context.go('/become-caregiver'), pal),
          const SizedBox(width: 16),
          Container(width: 1, height: 22, color: pal.border),
          const SizedBox(width: 16),
          _PillBtn('Registrarse', () => context.go('/register'), pal),
        ],
      ]),
    ),
    titleSpacing: 0,
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(1),
      child: Container(height: 1, color: pal.border),
    ),
  );
}

// ─── Hero ──────────────────────────────────────────────────────────────────────
class _HeroSection extends StatelessWidget {
  final bool mobile;
  const _HeroSection({required this.mobile});

  @override
  Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: pal.heroGrad,
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: mobile ? 28 : 120,
        vertical:   mobile ? 72 : 100,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: pal.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: pal.primary.withValues(alpha: 0.35)),
            ),
            child: Text('🌿 Nuestra historia',
              style: TextStyle(color: pal.accent, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.3)),
          ).animate().fadeIn(delay: 100.ms, duration: 600.ms).slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 28),
          Text(
            'Nacimos para darle\na tu mascota lo mejor.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: mobile ? 34 : 62,
              fontWeight: FontWeight.w900,
              color: pal.textPri,
              height: 1.1,
              letterSpacing: -2,
            ),
          ).animate().fadeIn(delay: 200.ms, duration: 700.ms).slideY(begin: 0.15, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(
              'GARDEN es una plataforma boliviana que conecta dueños de mascotas con cuidadores verificados. '
              'Creemos que cada mascota merece atención de calidad — con transparencia, tecnología y corazón.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: mobile ? 15 : 18,
                color: pal.textSec,
                height: 1.7,
                fontWeight: FontWeight.w400,
              ),
            ),
          ).animate().fadeIn(delay: 350.ms, duration: 700.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 48),
          // Stats row
          _StatsRow(mobile: mobile)
            .animate().fadeIn(delay: 500.ms, duration: 700.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final bool mobile;
  const _StatsRow({required this.mobile});

  @override
  Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    final stats = [
      ('🏙️', 'Santa Cruz', 'Ciudad de lanzamiento'),
      ('🐾', '2025', 'Año de fundación'),
      ('🔒', 'Blockchain', 'Pagos asegurados'),
      ('🤖', 'IA', 'Verificación de cuidadores'),
    ];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 16,
      children: stats.map((s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: pal.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 4))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(s.$1, style: const TextStyle(fontSize: 26)),
          const SizedBox(height: 6),
          Text(s.$2, style: GoogleFonts.inter(color: pal.textPri, fontWeight: FontWeight.w800, fontSize: 15)),
          Text(s.$3, style: TextStyle(color: pal.textSec, fontSize: 12)),
        ]),
      )).toList(),
    );
  }
}

// ─── Qué es GARDEN ────────────────────────────────────────────────────────────
class _AboutSection extends StatelessWidget {
  final ScrollController scroll;
  final bool mobile;
  const _AboutSection({required this.scroll, required this.mobile});

  @override
  Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return Container(
      color: pal.surface,
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: mobile ? 28 : 120, vertical: 96),
      child: mobile
          ? _content(pal)
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 5, child: _content(pal)),
                const SizedBox(width: 80),
                Expanded(flex: 4, child: _visual(pal)),
              ],
            ),
    );
  }

  Widget _content(_P pal) => _Reveal(
    scroll: scroll,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Tag('¿Qué es GARDEN?'),
      const SizedBox(height: 20),
      Text('Una plataforma con propósito',
        style: GoogleFonts.inter(
          fontSize: mobile ? 26 : 40,
          fontWeight: FontWeight.w900,
          color: pal.textPri,
          height: 1.2,
          letterSpacing: -1.2,
        )),
      const SizedBox(height: 24),
      Text(
        'GARDEN es la primera plataforma boliviana especializada en el cuidado de mascotas. '
        'Conectamos a dueños con cuidadores certificados y verificados por inteligencia artificial, '
        'garantizando que cada servicio — desde un paseo hasta hospedaje completo — se realice con el '
        'más alto estándar de confianza y calidad.',
        style: GoogleFonts.inter(color: pal.textSec, fontSize: mobile ? 14 : 16, height: 1.75),
      ),
      const SizedBox(height: 20),
      Text(
        'Nuestro sistema de escrow blockchain protege cada pago: el cuidador solo recibe el dinero cuando '
        'vos confirmás que el servicio fue completado correctamente. Sin riesgos, sin sorpresas.',
        style: GoogleFonts.inter(color: pal.textSec, fontSize: mobile ? 14 : 16, height: 1.75),
      ),
    ]),
  );

  Widget _visual(_P pal) => _Reveal(
    scroll: scroll,
    delay: 150.ms,
    child: Container(
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            pal.primary.withValues(alpha: 0.12),
            pal.primary.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: pal.primary.withValues(alpha: 0.25)),
      ),
      child: Column(children: [
        _FeatureRow(Icons.verified_rounded, 'Cuidadores verificados por IA', pal),
        _FeatureRow(Icons.hexagon_outlined, 'Pagos protegidos con escrow', pal),
        _FeatureRow(Icons.location_on_rounded, 'GPS en tiempo real en cada paseo', pal),
        _FeatureRow(Icons.star_rounded, 'Solo reseñas de clientes reales', pal),
        _FeatureRow(Icons.support_agent_rounded, 'Soporte de emergencia 24/7', pal),
      ]),
    ),
  );
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final _P pal;
  const _FeatureRow(this.icon, this.label, this.pal);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: pal.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: pal.accent, size: 18),
      ),
      const SizedBox(width: 14),
      Expanded(child: Text(label,
        style: GoogleFonts.inter(color: pal.textPri, fontWeight: FontWeight.w600, fontSize: 14))),
    ]),
  );
}

// ─── Misión y Visión ──────────────────────────────────────────────────────────
class _MissionVisionSection extends StatelessWidget {
  final ScrollController scroll;
  final bool mobile;
  const _MissionVisionSection({required this.scroll, required this.mobile});

  @override
  Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: mobile ? 28 : 120, vertical: 96),
      child: Column(children: [
        _Reveal(scroll: scroll, child: _Tag('Nuestra brújula')),
        const SizedBox(height: 20),
        _Reveal(
          scroll: scroll,
          delay: 100.ms,
          child: Text('Misión & Visión',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: mobile ? 28 : 44,
              fontWeight: FontWeight.w900,
              color: pal.textPri,
              letterSpacing: -1.5,
            )),
        ),
        const SizedBox(height: 56),
        mobile
            ? Column(children: [
                _Reveal(scroll: scroll, delay: 150.ms, child: _MVCard(
                  icon: Icons.flag_rounded,
                  tag: 'MISIÓN',
                  title: 'Conectar con confianza',
                  body: 'Conectar a dueños de mascotas con cuidadores verificados, garantizando transparencia, '
                      'seguridad y bienestar animal a través de tecnología de vanguardia — en cada ciudad de Bolivia.',
                  pal: pal,
                  gradient: [pal.primary.withValues(alpha: 0.18), pal.primary.withValues(alpha: 0.06)],
                )),
                const SizedBox(height: 20),
                _Reveal(scroll: scroll, delay: 250.ms, child: _MVCard(
                  icon: Icons.visibility_rounded,
                  tag: 'VISIÓN',
                  title: 'Líderes en Latinoamérica',
                  body: 'Ser la plataforma de referencia en Latinoamérica para el cuidado responsable y verificado '
                      'de mascotas — donde cada dueño encuentre paz mental y cada cuidador encuentre una vocación digna.',
                  pal: pal,
                  gradient: [const Color(0xFF2E6B8A).withValues(alpha: 0.18), const Color(0xFF2E6B8A).withValues(alpha: 0.06)],
                  accentColor: const Color(0xFF2E6B8A),
                )),
              ])
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _Reveal(scroll: scroll, delay: 150.ms, child: _MVCard(
                    icon: Icons.flag_rounded,
                    tag: 'MISIÓN',
                    title: 'Conectar con confianza',
                    body: 'Conectar a dueños de mascotas con cuidadores verificados, garantizando transparencia, '
                        'seguridad y bienestar animal a través de tecnología de vanguardia — en cada ciudad de Bolivia.',
                    pal: pal,
                    gradient: [pal.primary.withValues(alpha: 0.18), pal.primary.withValues(alpha: 0.06)],
                  ))),
                  const SizedBox(width: 24),
                  Expanded(child: _Reveal(scroll: scroll, delay: 250.ms, child: _MVCard(
                    icon: Icons.visibility_rounded,
                    tag: 'VISIÓN',
                    title: 'Líderes en Latinoamérica',
                    body: 'Ser la plataforma de referencia en Latinoamérica para el cuidado responsable y verificado '
                        'de mascotas — donde cada dueño encuentre paz mental y cada cuidador encuentre una vocación digna.',
                    pal: pal,
                    gradient: [const Color(0xFF2E6B8A).withValues(alpha: 0.18), const Color(0xFF2E6B8A).withValues(alpha: 0.06)],
                    accentColor: const Color(0xFF2E6B8A),
                  ))),
                ],
              ),
      ]),
    );
  }
}

class _MVCard extends StatelessWidget {
  final IconData icon;
  final String tag, title, body;
  final _P pal;
  final List<Color> gradient;
  final Color? accentColor;
  const _MVCard({
    required this.icon, required this.tag, required this.title,
    required this.body, required this.pal, required this.gradient, this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? pal.primary;
    return Container(
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(tag,
              style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.2)),
          ),
        ]),
        const SizedBox(height: 24),
        Text(title,
          style: GoogleFonts.inter(
            color: pal.textPri,
            fontWeight: FontWeight.w800,
            fontSize: 22,
            letterSpacing: -0.5,
          )),
        const SizedBox(height: 14),
        Text(body,
          style: GoogleFonts.inter(color: pal.textSec, fontSize: 15, height: 1.75)),
      ]),
    );
  }
}

// ─── Valores ──────────────────────────────────────────────────────────────────
class _ValuesSection extends StatelessWidget {
  final ScrollController scroll;
  final bool mobile;
  const _ValuesSection({required this.scroll, required this.mobile});

  static const _values = [
    (Icons.shield_rounded,       'Confianza',     'Cada cuidador pasa por verificación de identidad con IA antes de aparecer en la plataforma.'),
    (Icons.favorite_rounded,     'Bienestar',     'El bienestar de cada mascota es nuestra prioridad absoluta, antes que cualquier métrica de negocio.'),
    (Icons.lightbulb_rounded,    'Innovación',    'Escrow blockchain, GPS en tiempo real y IA fotométrica — tecnología al servicio del amor por las mascotas.'),
    (Icons.handshake_rounded,    'Comunidad',     'Construimos una comunidad de dueños y cuidadores que comparten el mismo compromiso con los animales.'),
  ];

  @override
  Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return Container(
      color: pal.surface,
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: mobile ? 28 : 120, vertical: 96),
      child: Column(children: [
        _Reveal(scroll: scroll, child: _Tag('Lo que nos mueve')),
        const SizedBox(height: 20),
        _Reveal(scroll: scroll, delay: 100.ms,
          child: Text('Nuestros valores',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: mobile ? 28 : 44,
              fontWeight: FontWeight.w900,
              color: pal.textPri,
              letterSpacing: -1.5,
            ))),
        const SizedBox(height: 56),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 20,
          runSpacing: 20,
          children: List.generate(_values.length, (i) => _Reveal(
            scroll: scroll,
            delay: Duration(milliseconds: 80 * i),
            child: _ValueCard(_values[i], mobile: mobile, pal: pal),
          )),
        ),
      ]),
    );
  }
}

class _ValueCard extends StatefulWidget {
  final (IconData, String, String) data;
  final bool mobile;
  final _P pal;
  const _ValueCard(this.data, {required this.mobile, required this.pal});
  @override State<_ValueCard> createState() => _ValueCardState();
}
class _ValueCardState extends State<_ValueCard> {
  bool _h = false;
  @override Widget build(BuildContext context) {
    final (icon, title, desc) = widget.data;
    final pal = widget.pal;
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: widget.mobile ? double.infinity : 280,
        padding: const EdgeInsets.all(28),
        transform: Matrix4.translationValues(0, _h ? -6 : 0, 0),
        decoration: BoxDecoration(
          color: _h ? pal.surfaceEl : pal.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _h ? pal.primary.withValues(alpha: 0.5) : pal.border),
          boxShadow: _h ? [BoxShadow(color: pal.primary.withValues(alpha: 0.1), blurRadius: 28, offset: const Offset(0, 10))] : [],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: pal.primary.withValues(alpha: _h ? 0.22 : 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: pal.accent, size: 22),
          ),
          const SizedBox(height: 18),
          Text(title, style: GoogleFonts.inter(color: pal.textPri, fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 10),
          Text(desc, style: TextStyle(color: pal.textSec, fontSize: 13, height: 1.7)),
        ]),
      ),
    );
  }
}

// ─── Equipo fundador ──────────────────────────────────────────────────────────
class _TeamSection extends StatelessWidget {
  final ScrollController scroll;
  final bool mobile;
  const _TeamSection({required this.scroll, required this.mobile});

  @override
  Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: mobile ? 28 : 120, vertical: 96),
      child: Column(children: [
        _Reveal(scroll: scroll, child: _Tag('Las personas detrás de GARDEN')),
        const SizedBox(height: 20),
        _Reveal(scroll: scroll, delay: 100.ms,
          child: Text('Equipo fundador',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: mobile ? 28 : 44,
              fontWeight: FontWeight.w900,
              color: pal.textPri,
              letterSpacing: -1.5,
            ))),
        const SizedBox(height: 16),
        _Reveal(scroll: scroll, delay: 180.ms,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(
              'Dos personas con una misión compartida: transformar cómo Bolivia cuida a sus mascotas.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: pal.textSec, fontSize: mobile ? 14 : 16, height: 1.6),
            ),
          )),
        const SizedBox(height: 64),
        mobile
            ? Column(children: [
                _Reveal(scroll: scroll, delay: 200.ms,
                  child: _FounderCard(
                    initials: 'SM',
                    name: 'Sai Mateo Vargas',
                    role: 'Founder & CEO',
                    bio: 'Visionario detrás de GARDEN. Lidera la estrategia, producto y tecnología '
                        'con el objetivo de hacer de Bolivia un referente en cuidado animal responsable.',
                    color: const Color(0xFF4A7C23),
                    pal: pal,
                  )),
                const SizedBox(height: 24),
                _Reveal(scroll: scroll, delay: 300.ms,
                  child: _FounderCard(
                    initials: 'AA',
                    name: 'Airo Arroyo',
                    role: 'Co-Founder & COO',
                    bio: 'Motor operativo de GARDEN. Garantiza que cada proceso, cuidador y servicio '
                        'funcione con la excelencia que nuestras mascotas merecen.',
                    color: const Color(0xFF2E6B8A),
                    pal: pal,
                  )),
              ])
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Reveal(scroll: scroll, delay: 200.ms,
                    child: _FounderCard(
                      initials: 'SM',
                      name: 'Sai Mateo Vargas',
                      role: 'Founder & CEO',
                      bio: 'Visionario detrás de GARDEN. Lidera la estrategia, producto y tecnología '
                          'con el objetivo de hacer de Bolivia un referente en cuidado animal responsable.',
                      color: const Color(0xFF4A7C23),
                      pal: pal,
                    )),
                  const SizedBox(width: 28),
                  _Reveal(scroll: scroll, delay: 320.ms,
                    child: _FounderCard(
                      initials: 'AA',
                      name: 'Airo Arroyo',
                      role: 'Co-Founder & COO',
                      bio: 'Motor operativo de GARDEN. Garantiza que cada proceso, cuidador y servicio '
                          'funcione con la excelencia que nuestras mascotas merecen.',
                      color: const Color(0xFF2E6B8A),
                      pal: pal,
                    )),
                ],
              ),
      ]),
    );
  }
}

class _FounderCard extends StatefulWidget {
  final String initials, name, role, bio;
  final Color color;
  final _P pal;
  const _FounderCard({
    required this.initials, required this.name, required this.role,
    required this.bio, required this.color, required this.pal,
  });
  @override State<_FounderCard> createState() => _FounderCardState();
}
class _FounderCardState extends State<_FounderCard> {
  bool _h = false;
  @override Widget build(BuildContext context) {
    final pal = widget.pal;
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 320,
        transform: Matrix4.translationValues(0, _h ? -8 : 0, 0),
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _h ? widget.color.withValues(alpha: 0.5) : pal.border),
          boxShadow: _h
              ? [BoxShadow(color: widget.color.withValues(alpha: 0.14), blurRadius: 36, offset: const Offset(0, 12))]
              : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: Column(children: [
          // Top gradient banner
          Container(
            height: 80,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              gradient: LinearGradient(
                colors: [widget.color.withValues(alpha: 0.5), widget.color.withValues(alpha: 0.2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          // Avatar (overlaps banner)
          Transform.translate(
            offset: const Offset(0, -40),
            child: Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
                border: Border.all(color: pal.surface, width: 4),
                boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 6))],
              ),
              child: Center(child: Text(widget.initials,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24))),
            ),
          ),
          // Content
          Transform.translate(
            offset: const Offset(0, -28),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
              child: Column(children: [
                Text(widget.name,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: pal.textPri, fontWeight: FontWeight.w900, fontSize: 19)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: widget.color.withValues(alpha: 0.3)),
                  ),
                  child: Text(widget.role,
                    style: TextStyle(color: widget.color, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
                const SizedBox(height: 18),
                Text(widget.bio,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: pal.textSec, fontSize: 13, height: 1.7)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Legal / T&C ─────────────────────────────────────────────────────────────
class _LegalSection extends StatelessWidget {
  final bool mobile;
  final Future<void> Function(String) openUrl;
  const _LegalSection({required this.mobile, required this.openUrl});

  @override
  Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return Container(
      color: pal.surface,
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: mobile ? 28 : 120, vertical: 72),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 700),
          padding: EdgeInsets.symmetric(horizontal: mobile ? 28 : 56, vertical: 48),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [pal.primary.withValues(alpha: 0.08), pal.primary.withValues(alpha: 0.02)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: pal.primary.withValues(alpha: 0.22)),
          ),
          child: Column(children: [
            Icon(Icons.gavel_rounded, color: pal.accent, size: 36),
            const SizedBox(height: 20),
            Text('Transparencia legal',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: pal.textPri, fontWeight: FontWeight.w900, fontSize: mobile ? 22 : 28, letterSpacing: -0.8)),
            const SizedBox(height: 14),
            Text(
              'Creemos en la transparencia total. Podés leer en detalle nuestros términos de uso, '
              'política de privacidad y cómo gestionamos tus datos y pagos.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: pal.textSec, fontSize: 14, height: 1.7),
            ),
            const SizedBox(height: 32),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 14,
              runSpacing: 12,
              children: [
                _LegalBtn(
                  icon: Icons.description_outlined,
                  label: 'Términos y condiciones',
                  onTap: () => openUrl('https://garden-app.vercel.app/terms'),
                  pal: pal,
                  filled: true,
                ),
                _LegalBtn(
                  icon: Icons.privacy_tip_outlined,
                  label: 'Política de privacidad',
                  onTap: () => openUrl('https://garden-app.vercel.app/privacy'),
                  pal: pal,
                  filled: false,
                ),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

class _LegalBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final _P pal;
  final bool filled;
  const _LegalBtn({required this.icon, required this.label, required this.onTap, required this.pal, required this.filled});
  @override State<_LegalBtn> createState() => _LegalBtnState();
}
class _LegalBtnState extends State<_LegalBtn> {
  bool _h = false;
  @override Widget build(BuildContext context) {
    final pal = widget.pal;
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          decoration: BoxDecoration(
            color: widget.filled
                ? (_h ? pal.accent : pal.primary)
                : (_h ? pal.primary.withValues(alpha: 0.08) : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.filled
                  ? Colors.transparent
                  : (_h ? pal.accent : pal.primary.withValues(alpha: 0.45)),
              width: 1.5,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(widget.icon,
              color: widget.filled ? Colors.white : (_h ? pal.accent : pal.textSec),
              size: 16),
            const SizedBox(width: 8),
            Text(widget.label,
              style: TextStyle(
                color: widget.filled ? Colors.white : (_h ? pal.accent : pal.textSec),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              )),
          ]),
        ),
      ),
    );
  }
}

// ─── Footer mínimo ────────────────────────────────────────────────────────────
class _FooterAbout extends StatelessWidget {
  final bool mobile;
  const _FooterAbout({required this.mobile});

  @override
  Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: mobile ? 28 : 120, vertical: 40),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: pal.border))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Image.asset(pal.logo, height: 32),
          Text('© 2025 GARDEN · Bolivia',
            style: TextStyle(color: pal.textMut, fontSize: 12)),
        ],
      ),
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

class _Tag extends StatelessWidget {
  final String label;
  const _Tag(this.label);
  @override Widget build(BuildContext context) {
    final pal = _Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: pal.primary.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: pal.primary.withValues(alpha: 0.38)),
      ),
      child: Text(label,
        style: TextStyle(color: pal.accent, fontWeight: FontWeight.w600, fontSize: 12, letterSpacing: 0.5)),
    );
  }
}

class _NavBtn extends StatefulWidget {
  final String label; final VoidCallback onTap; final _P pal;
  const _NavBtn(this.label, this.onTap, this.pal);
  @override State<_NavBtn> createState() => _NavBtnState();
}
class _NavBtnState extends State<_NavBtn> {
  bool _h = false;
  @override Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _h = true),
    onExit:  (_) => setState(() => _h = false),
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _h ? widget.pal.border.withValues(alpha: 0.5) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(widget.label,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: _h ? widget.pal.textPri : widget.pal.textSec,
          )),
      ),
    ),
  );
}

class _PillBtn extends StatefulWidget {
  final String label; final VoidCallback onTap; final _P pal;
  const _PillBtn(this.label, this.onTap, this.pal);
  @override State<_PillBtn> createState() => _PillBtnState();
}
class _PillBtnState extends State<_PillBtn> {
  bool _h = false;
  @override Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _h = true),
    onExit:  (_) => setState(() => _h = false),
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 140, height: 40,
        decoration: BoxDecoration(
          color: _h ? widget.pal.accent : widget.pal.primary,
          borderRadius: BorderRadius.circular(12),
          boxShadow: _h ? [BoxShadow(color: widget.pal.primary.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 6))] : [],
        ),
        child: Center(child: Text(widget.label,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))),
      ),
    ),
  );
}

// ─── Scroll reveal (misma lógica que landing) ─────────────────────────────────
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
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
