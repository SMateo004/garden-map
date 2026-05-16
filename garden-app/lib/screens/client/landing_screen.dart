import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Paleta oscura ────────────────────────────────────────────────────────────
abstract class _C {
  static const bg        = Color(0xFF090E09);
  static const surface   = Color(0xFF101710);
  static const surfaceEl = Color(0xFF172017);
  static const border    = Color(0xFF1E301E);
  static const primary   = Color(0xFF4A7C23);
  static const accent    = Color(0xFF7BC142);
  static const textPri   = Color(0xFFF2F6F0);
  static const textSec   = Color(0xFF9BAE90);
  static const textMut   = Color(0xFF556050);
}

// ─── Datos ────────────────────────────────────────────────────────────────────
class _Pain  { final String emoji, title, desc; const _Pain(this.emoji, this.title, this.desc); }
class _Bene  { final IconData icon; final String title, desc; const _Bene(this.icon, this.title, this.desc); }
class _Testi { final String name, city, quote, initials; final Color color;
               const _Testi(this.name, this.city, this.quote, this.initials, this.color); }
class _Faq   { final String q, a; const _Faq(this.q, this.a); }

const _pains = [
  _Pain('😟', '¿Realmente puedo confiar?',
      'Dejás a tu mejor amigo con un desconocido sin ninguna garantía real.'),
  _Pain('😰', '¿Estará bien mientras no estoy?',
      'Sin actualizaciones en tiempo real, la ansiedad no para.'),
  _Pain('💸', 'Precios opacos, cero protección',
      'Pagás por adelantado sin saber si el servicio va a valer lo que costó.'),
];

const _benes = [
  _Bene(Icons.verified_rounded,       'Verificación por IA',      'Análisis fotométrico + antecedentes antes de publicar cada cuidador.'),
  _Bene(Icons.hexagon_outlined,       'Escrow Blockchain',         'Tu pago queda bloqueado en Polygon hasta que vos confirmés el servicio.'),
  _Bene(Icons.location_on_rounded,    'GPS en tiempo real',        'Seguí cada paseo desde tu teléfono con precisión al metro.'),
  _Bene(Icons.local_hospital_rounded, 'Soporte de emergencia',     'Red veterinaria aliada disponible 24/7 para cualquier imprevisto.'),
  _Bene(Icons.star_rounded,           'Reseñas verificadas',       'Solo clientes reales puntúan. Sin reviews falsos, nunca.'),
  _Bene(Icons.chat_bubble_rounded,    'Chat integrado',            'Hablá con el cuidador antes, durante y después del servicio.'),
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

// ─── Main screen ──────────────────────────────────────────────────────────────
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});
  @override State<LandingScreen> createState() => _LandingState();
}

class _LandingState extends State<LandingScreen> {
  final _scroll   = ScrollController();
  String  _svc    = 'paseo';
  String? _zone, _size;

  static const _zones = {
    'EQUIPETROL': 'Equipetrol', 'URBARI': 'Urbari', 'NORTE': 'Norte',
    'LAS_PALMAS': 'Las Palmas', 'CENTRO_SAN_MARTIN': 'Centro/San Martín',
    'OTROS': 'Otros',
  };

  @override void dispose() { _scroll.dispose(); super.dispose(); }

  void _search() {
    var q = '?service=$_svc';
    if (_zone != null) q += '&zone=$_zone';
    if (_size != null) q += '&size=$_size';
    context.go('/marketplace$q');
  }

  @override
  Widget build(BuildContext context) {
    final w      = MediaQuery.of(context).size.width;
    final mobile = w < 768;

    return Scaffold(
      backgroundColor: _C.bg,
      endDrawer: mobile ? _MobileMenu(go: (r) => context.go(r)) : null,
      body: Builder(builder: (ctx) => CustomScrollView(
        controller: _scroll,
        slivers: [
          _sliverHeader(ctx, mobile),
          _sliverHero(mobile),
          SliverToBoxAdapter(child: _PainSection(scroll: _scroll, mobile: mobile)),
          SliverToBoxAdapter(child: _MidCta(onTap: _search, mobile: mobile)),
          SliverToBoxAdapter(child: _BenefitsSection(scroll: _scroll, mobile: mobile)),
          SliverToBoxAdapter(child: _TestiSection(scroll: _scroll, mobile: mobile)),
          SliverToBoxAdapter(child: _FaqSection(scroll: _scroll, mobile: mobile)),
          SliverToBoxAdapter(child: _FinalCta(mobile: mobile)),
          SliverToBoxAdapter(child: _Footer(mobile: mobile)),
        ],
      )),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────
  Widget _sliverHeader(BuildContext ctx, bool mobile) => SliverAppBar(
    backgroundColor: _C.bg,
    elevation: 0,
    scrolledUnderElevation: 0,
    pinned: true,
    toolbarHeight: 64,
    titleSpacing: 24,
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(1),
      child: Container(height: 1, color: _C.border),
    ),
    title: Image.asset('assets/images/logo-horizontal-dark.png', height: 60),
    actions: mobile
        ? [
            Builder(builder: (c) => IconButton(
              icon: const Icon(Icons.menu_rounded, color: _C.textPri, size: 26),
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
    child: Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: mobile ? 600 : 700),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A1A0A), Color(0xFF060D06), Color(0xFF0C1A08)],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            mobile ? 24 : 80, mobile ? 56 : 80,
            mobile ? 24 : 80, mobile ? 56 : 72,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Tag
              const _GreenTag('GARDEN · La plataforma líder en Bolivia')
                  .animate().fadeIn(duration: 500.ms).slideY(begin: 0.2, end: 0, duration: 500.ms, curve: Curves.easeOutCubic),
              const SizedBox(height: 24),

              // Headline
              Text(
                'Tu mascota merece lo mejor.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: mobile ? 38 : 72,
                  fontWeight: FontWeight.w900,
                  color: _C.textPri,
                  height: 1.05,
                  letterSpacing: -2.5,
                ),
              ).animate().fadeIn(delay: 150.ms, duration: 600.ms)
               .slideY(begin: 0.2, end: 0, delay: 150.ms, duration: 600.ms, curve: Curves.easeOutCubic),
              const SizedBox(height: 20),

              // Subheadline
              Text(
                mobile
                    ? 'Cuidadores verificados por IA.\nPagos asegurados con escrow blockchain.'
                    : 'Cuidadores verificados por IA. Pagos asegurados con escrow blockchain.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: mobile ? 16 : 20,
                  fontWeight: FontWeight.w400,
                  color: _C.textSec,
                  height: 1.6,
                ),
              ).animate().fadeIn(delay: 300.ms, duration: 600.ms)
               .slideY(begin: 0.2, end: 0, delay: 300.ms, duration: 600.ms, curve: Curves.easeOutCubic),
              const SizedBox(height: 36),

              // CTAs
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12, runSpacing: 12,
                children: [
                  _PrimaryBtn('Encontrar cuidador 🐾', _search, w: 230, h: 52),
                  _OutlineBtn('Cómo funciona', () {}, w: 170, h: 52),
                ],
              ).animate().fadeIn(delay: 450.ms, duration: 600.ms)
               .slideY(begin: 0.2, end: 0, delay: 450.ms, duration: 600.ms, curve: Curves.easeOutCubic),
              const SizedBox(height: 60),

              // Stats
              _StatsRow(mobile: mobile)
                  .animate().fadeIn(delay: 600.ms, duration: 600.ms),
              const SizedBox(height: 56),

              // Search bar
              _SearchBar(
                mobile: mobile, svc: _svc, zone: _zone, size: _size, zones: _zones,
                onSvcChange:  (v) => setState(() => _svc  = v),
                onZoneChange: (v) => setState(() => _zone = v),
                onSizeChange: (v) => setState(() => _size = v),
                onSearch: _search,
              ).animate().fadeIn(delay: 750.ms, duration: 600.ms)
               .slideY(begin: 0.1, end: 0, delay: 750.ms, duration: 600.ms, curve: Curves.easeOutCubic),
            ],
          ),
        ),
      ),
    ),
  );
}

// ─── Reveal on scroll ─────────────────────────────────────────────────────────
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
      _check();
      widget.scroll.addListener(_check);
    });
  }
  @override void dispose() {
    widget.scroll.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (_vis || !mounted) return;
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final pos = box.localToGlobal(Offset.zero);
    if (pos.dy < MediaQuery.of(context).size.height * 0.93) {
      widget.scroll.removeListener(_check);
      Future.delayed(widget.delay, () { if (mounted) setState(() => _vis = true); });
    }
  }

  @override Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return KeyedSubtree(
      key: _key,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 600),
        opacity: _vis ? 1.0 : 0.0,
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

// ─── Shared small widgets ─────────────────────────────────────────────────────

class _GreenTag extends StatelessWidget {
  final String label;
  const _GreenTag(this.label);
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      color: _C.primary.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(100),
      border: Border.all(color: _C.primary.withValues(alpha: 0.4)),
    ),
    child: Text(label, style: const TextStyle(
      color: _C.accent, fontWeight: FontWeight.w600, fontSize: 12, letterSpacing: 0.5)),
  );
}

class _PrimaryBtn extends StatefulWidget {
  final String label; final VoidCallback onTap;
  final double w, h;
  const _PrimaryBtn(this.label, this.onTap, {this.w = 160, this.h = 44});
  @override State<_PrimaryBtn> createState() => _PrimaryBtnState();
}
class _PrimaryBtnState extends State<_PrimaryBtn> {
  bool _hover = false;
  @override Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit:  (_) => setState(() => _hover = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: widget.w, height: widget.h,
        decoration: BoxDecoration(
          color: _hover ? _C.accent : _C.primary,
          borderRadius: BorderRadius.circular(12),
          boxShadow: _hover
              ? [BoxShadow(color: _C.primary.withValues(alpha: 0.45), blurRadius: 24, offset: const Offset(0, 8))]
              : [],
        ),
        child: Center(child: Text(widget.label,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))),
      ),
    ),
  );
}

class _OutlineBtn extends StatefulWidget {
  final String label; final VoidCallback onTap;
  final double w, h;
  const _OutlineBtn(this.label, this.onTap, {this.w = 160, this.h = 44});
  @override State<_OutlineBtn> createState() => _OutlineBtnState();
}
class _OutlineBtnState extends State<_OutlineBtn> {
  bool _hover = false;
  @override Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit:  (_) => setState(() => _hover = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: widget.w, height: widget.h,
        decoration: BoxDecoration(
          color: _hover ? _C.primary.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _hover ? _C.accent : _C.textSec.withValues(alpha: 0.35), width: 1.5),
        ),
        child: Center(child: Text(widget.label, style: TextStyle(
          color: _hover ? _C.accent : _C.textSec,
          fontWeight: FontWeight.w600, fontSize: 14))),
      ),
    ),
  );
}

class _NavLink extends StatefulWidget {
  final String label; final VoidCallback onTap;
  const _NavLink(this.label, this.onTap);
  @override State<_NavLink> createState() => _NavLinkState();
}
class _NavLinkState extends State<_NavLink> {
  bool _hover = false;
  @override Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit:  (_) => setState(() => _hover = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 150),
          style: TextStyle(
            color: _hover ? _C.accent : _C.textSec,
            fontWeight: FontWeight.w500, fontSize: 14),
          child: Text(widget.label),
        ),
      ),
    ),
  );
}

// ─── Stats ────────────────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final bool mobile;
  const _StatsRow({required this.mobile});
  @override Widget build(BuildContext context) {
    final items = [
      ('500+',   'Cuidadores verificados'),
      ('2,000+', 'Mascotas cuidadas'),
      ('4.9 ★',  'Calificación promedio'),
      ('100%',   'Pagos protegidos'),
    ];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: mobile ? 28 : 56, runSpacing: 20,
      children: items.map((e) => Column(children: [
        Text(e.$1, style: GoogleFonts.inter(
          fontSize: mobile ? 28 : 38, fontWeight: FontWeight.w900,
          color: _C.accent, letterSpacing: -1)),
        const SizedBox(height: 4),
        Text(e.$2, style: const TextStyle(color: _C.textSec, fontSize: 13)),
      ])).toList(),
    );
  }
}

// ─── Search bar hero ──────────────────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  final bool mobile;
  final String svc;
  final String? zone, size;
  final Map<String, String> zones;
  final ValueChanged<String>  onSvcChange;
  final ValueChanged<String?> onZoneChange, onSizeChange;
  final VoidCallback onSearch;
  const _SearchBar({
    required this.mobile, required this.svc, required this.zone,
    required this.size, required this.zones, required this.onSvcChange,
    required this.onZoneChange, required this.onSizeChange, required this.onSearch,
  });
  @override Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 860),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _C.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _C.border),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 48, offset: const Offset(0, 16))],
    ),
    child: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
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

class _SvcToggle extends StatelessWidget {
  final String selected; final ValueChanged<String> onChanged;
  const _SvcToggle({required this.selected, required this.onChanged});
  @override Widget build(BuildContext context) => Container(
    width: 230, height: 52,
    decoration: BoxDecoration(color: _C.surfaceEl, borderRadius: BorderRadius.circular(14), border: Border.all(color: _C.border)),
    child: Row(children: ['paseo','hospedaje'].map((s) {
      final active = selected == s;
      return Expanded(child: GestureDetector(
        onTap: () => onChanged(s),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: active ? _C.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Center(child: Text(
            s == 'paseo' ? 'Paseo 🦮' : 'Hospedaje 🏠',
            style: TextStyle(
              color: active ? Colors.white : _C.textSec,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500, fontSize: 13),
          )),
        ),
      ));
    }).toList()),
  );
}

class _DDark<T> extends StatelessWidget {
  final double w; final T? value; final String hint; final IconData icon;
  final List<DropdownMenuItem<T>> items; final ValueChanged<T?> onChanged;
  const _DDark({required this.w, required this.value, required this.hint,
    required this.icon, required this.items, required this.onChanged});
  @override Widget build(BuildContext context) => Container(
    width: w, height: 52,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(color: _C.surfaceEl, borderRadius: BorderRadius.circular(14), border: Border.all(color: _C.border)),
    child: DropdownButtonHideUnderline(child: DropdownButton<T>(
      value: value,
      hint: Text(hint, style: const TextStyle(color: _C.textSec, fontSize: 13, fontWeight: FontWeight.w500)),
      isExpanded: true,
      icon: Icon(icon, color: _C.accent, size: 18),
      dropdownColor: _C.surface,
      style: const TextStyle(color: _C.textPri, fontSize: 13, fontWeight: FontWeight.w500),
      items: items, onChanged: onChanged,
    )),
  );
}

// ─── Pain Points ──────────────────────────────────────────────────────────────
class _PainSection extends StatelessWidget {
  final ScrollController scroll; final bool mobile;
  const _PainSection({required this.scroll, required this.mobile});
  @override Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(horizontal: mobile ? 24 : 80, vertical: 96),
    child: Column(children: [
      _Reveal(scroll: scroll, child: const _GreenTag('¿Te suena familiar?')),
      const SizedBox(height: 20),
      _Reveal(
        scroll: scroll, delay: 100.ms,
        child: Text('Los problemas que resolvemos', textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: mobile ? 28 : 44, fontWeight: FontWeight.w900,
            color: _C.textPri, letterSpacing: -1.5)),
      ),
      const SizedBox(height: 56),
      Wrap(
        alignment: WrapAlignment.center, spacing: 20, runSpacing: 20,
        children: List.generate(_pains.length, (i) => _Reveal(
          scroll: scroll, delay: Duration(milliseconds: 80 * i),
          child: _PainCard(_pains[i], mobile: mobile),
        )),
      ),
    ]),
  );
}

class _PainCard extends StatefulWidget {
  final _Pain p; final bool mobile;
  const _PainCard(this.p, {required this.mobile});
  @override State<_PainCard> createState() => _PainCardState();
}
class _PainCardState extends State<_PainCard> {
  bool _h = false;
  @override Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _h = true),
    onExit:  (_) => setState(() => _h = false),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: widget.mobile ? double.infinity : 310,
      padding: const EdgeInsets.all(28),
      transform: Matrix4.translationValues(0, _h ? -5 : 0, 0),
      decoration: BoxDecoration(
        color: _h ? _C.surfaceEl : _C.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _h ? _C.primary.withValues(alpha: 0.5) : _C.border),
        boxShadow: _h ? [BoxShadow(color: _C.primary.withValues(alpha: 0.12), blurRadius: 28, offset: const Offset(0, 10))] : [],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.p.emoji, style: const TextStyle(fontSize: 38)),
        const SizedBox(height: 16),
        Text(widget.p.title, style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: _C.textPri)),
        const SizedBox(height: 8),
        Text(widget.p.desc, style: const TextStyle(color: _C.textSec, fontSize: 14, height: 1.65)),
      ]),
    ),
  );
}

// ─── Mid CTA ──────────────────────────────────────────────────────────────────
class _MidCta extends StatelessWidget {
  final VoidCallback onTap; final bool mobile;
  const _MidCta({required this.onTap, required this.mobile});
  @override Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: mobile ? 24 : 80, vertical: 16),
    child: Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: mobile ? 28 : 64, vertical: 56),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_C.primary.withValues(alpha: 0.22), _C.primary.withValues(alpha: 0.07)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _C.primary.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        Text('Únete a miles de dueños que ya confían en GARDEN',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: mobile ? 22 : 32, fontWeight: FontWeight.w800,
            color: _C.textPri, letterSpacing: -1, height: 1.2)),
        const SizedBox(height: 28),
        _PrimaryBtn('Buscar cuidadores ahora', onTap, w: 260, h: 52),
      ]),
    ),
  );
}

// ─── Benefits ─────────────────────────────────────────────────────────────────
class _BenefitsSection extends StatelessWidget {
  final ScrollController scroll; final bool mobile;
  const _BenefitsSection({required this.scroll, required this.mobile});
  @override Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: _C.surface,
    padding: EdgeInsets.symmetric(horizontal: mobile ? 24 : 80, vertical: 96),
    child: Column(children: [
      _Reveal(scroll: scroll, child: const _GreenTag('Todo lo que necesitás')),
      const SizedBox(height: 20),
      _Reveal(
        scroll: scroll, delay: 100.ms,
        child: Text('¿Por qué GARDEN?', textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: mobile ? 28 : 44, fontWeight: FontWeight.w900,
            color: _C.textPri, letterSpacing: -1.5)),
      ),
      const SizedBox(height: 56),
      Wrap(
        alignment: WrapAlignment.center, spacing: 16, runSpacing: 16,
        children: List.generate(_benes.length, (i) => _Reveal(
          scroll: scroll, delay: Duration(milliseconds: 70 * (i % 3)),
          child: _BeneCard(_benes[i], mobile: mobile),
        )),
      ),
    ]),
  );
}

class _BeneCard extends StatefulWidget {
  final _Bene b; final bool mobile;
  const _BeneCard(this.b, {required this.mobile});
  @override State<_BeneCard> createState() => _BeneCardState();
}
class _BeneCardState extends State<_BeneCard> {
  bool _h = false;
  @override Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _h = true),
    onExit:  (_) => setState(() => _h = false),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: widget.mobile ? double.infinity : 270,
      padding: const EdgeInsets.all(24),
      transform: Matrix4.translationValues(0, _h ? -4 : 0, 0),
      decoration: BoxDecoration(
        color: _h ? _C.surfaceEl : _C.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _h ? _C.primary.withValues(alpha: 0.5) : _C.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _h ? _C.primary.withValues(alpha: 0.28) : _C.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(widget.b.icon, color: _C.accent, size: 22),
        ),
        const SizedBox(height: 16),
        Text(widget.b.title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: _C.textPri)),
        const SizedBox(height: 8),
        Text(widget.b.desc, style: const TextStyle(color: _C.textSec, fontSize: 13, height: 1.65)),
      ]),
    ),
  );
}

// ─── Testimonials ─────────────────────────────────────────────────────────────
class _TestiSection extends StatelessWidget {
  final ScrollController scroll; final bool mobile;
  const _TestiSection({required this.scroll, required this.mobile});
  @override Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(horizontal: mobile ? 24 : 80, vertical: 96),
    child: Column(children: [
      _Reveal(scroll: scroll, child: const _GreenTag('Lo que dicen nuestros usuarios')),
      const SizedBox(height: 20),
      _Reveal(
        scroll: scroll, delay: 100.ms,
        child: Text('Confianza que se siente', textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: mobile ? 28 : 44, fontWeight: FontWeight.w900,
            color: _C.textPri, letterSpacing: -1.5)),
      ),
      const SizedBox(height: 56),
      Wrap(
        alignment: WrapAlignment.center, spacing: 20, runSpacing: 20,
        children: List.generate(_testis.length, (i) => _Reveal(
          scroll: scroll, delay: Duration(milliseconds: 80 * i),
          child: _TestiCard(_testis[i], mobile: mobile),
        )),
      ),
    ]),
  );
}

class _TestiCard extends StatelessWidget {
  final _Testi t; final bool mobile;
  const _TestiCard(this.t, {required this.mobile});
  @override Widget build(BuildContext context) => Container(
    width: mobile ? double.infinity : 310,
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: _C.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _C.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: List.generate(5, (_) => const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 17))),
      const SizedBox(height: 16),
      Text(t.quote, style: const TextStyle(color: _C.textPri, fontSize: 14, height: 1.75, fontStyle: FontStyle.italic)),
      const SizedBox(height: 20),
      Row(children: [
        CircleAvatar(radius: 20,
          backgroundColor: t.color.withValues(alpha: 0.25),
          child: Text(t.initials, style: TextStyle(color: t.color, fontWeight: FontWeight.w800, fontSize: 13))),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.name, style: const TextStyle(color: _C.textPri, fontWeight: FontWeight.w700, fontSize: 14)),
          Text(t.city, style: const TextStyle(color: _C.textSec, fontSize: 12)),
        ]),
      ]),
    ]),
  );
}

// ─── FAQ ──────────────────────────────────────────────────────────────────────
class _FaqSection extends StatelessWidget {
  final ScrollController scroll; final bool mobile;
  const _FaqSection({required this.scroll, required this.mobile});
  @override Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: _C.surface,
    padding: EdgeInsets.symmetric(horizontal: mobile ? 24 : 80, vertical: 96),
    child: Column(children: [
      _Reveal(scroll: scroll, child: const _GreenTag('Preguntas frecuentes')),
      const SizedBox(height: 20),
      _Reveal(
        scroll: scroll, delay: 100.ms,
        child: Text('Resolvemos tus dudas', textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: mobile ? 28 : 44, fontWeight: FontWeight.w900,
            color: _C.textPri, letterSpacing: -1.5)),
      ),
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

class _FaqTile extends StatefulWidget {
  final _Faq faq; const _FaqTile(this.faq);
  @override State<_FaqTile> createState() => _FaqTileState();
}
class _FaqTileState extends State<_FaqTile> {
  bool _open = false;
  @override Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: _open ? _C.surfaceEl : _C.bg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _open ? _C.primary.withValues(alpha: 0.4) : _C.border),
    ),
    child: Column(children: [
      GestureDetector(
        onTap: () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Expanded(child: Text(widget.faq.q,
              style: const TextStyle(color: _C.textPri, fontWeight: FontWeight.w600, fontSize: 15))),
            AnimatedRotation(
              duration: const Duration(milliseconds: 200),
              turns: _open ? 0.5 : 0,
              child: const Icon(Icons.keyboard_arrow_down_rounded, color: _C.accent, size: 22),
            ),
          ]),
        ),
      ),
      AnimatedCrossFade(
        duration: const Duration(milliseconds: 220),
        crossFadeState: _open ? CrossFadeState.showFirst : CrossFadeState.showSecond,
        firstChild: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Text(widget.faq.a, style: const TextStyle(color: _C.textSec, fontSize: 14, height: 1.7)),
        ),
        secondChild: const SizedBox.shrink(),
      ),
    ]),
  );
}

// ─── Final CTA ────────────────────────────────────────────────────────────────
class _FinalCta extends StatelessWidget {
  final bool mobile; const _FinalCta({required this.mobile});
  @override Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(horizontal: mobile ? 24 : 80, vertical: 96),
    child: Column(children: [
      Text('¿Listo para darle lo mejor?', textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: mobile ? 32 : 56, fontWeight: FontWeight.w900,
          color: _C.textPri, letterSpacing: -2, height: 1.05)),
      const SizedBox(height: 16),
      const Text('Encontrá el cuidador perfecto hoy.',
        textAlign: TextAlign.center,
        style: TextStyle(color: _C.textSec, fontSize: 18)),
      const SizedBox(height: 40),
      Wrap(alignment: WrapAlignment.center, spacing: 16, runSpacing: 12, children: [
        _PrimaryBtn('Buscar cuidadores ahora 🐾', () => context.go('/marketplace'), w: 280, h: 56),
        _OutlineBtn('Convertirse en cuidador',    () => context.go('/become-caregiver'), w: 230, h: 56),
      ]),
    ]),
  );
}

// ─── Footer ───────────────────────────────────────────────────────────────────
class _Footer extends StatelessWidget {
  final bool mobile; const _Footer({required this.mobile});
  @override Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(horizontal: mobile ? 24 : 80, vertical: 40),
    decoration: const BoxDecoration(border: Border(top: BorderSide(color: _C.border))),
    child: Column(children: [
      Image.asset('assets/images/logo-horizontal-dark.png', height: 36),
      const SizedBox(height: 16),
      const Text('© 2025 GARDEN · Santa Cruz de la Sierra, Bolivia',
        style: TextStyle(color: _C.textMut, fontSize: 13)),
      const SizedBox(height: 12),
      Wrap(alignment: WrapAlignment.center, spacing: 24, children: [
        _FootLink('Términos de uso'),
        _FootLink('Privacidad'),
        _FootLink('Contacto'),
      ]),
    ]),
  );
}

class _FootLink extends StatelessWidget {
  final String label; const _FootLink(this.label);
  @override Widget build(BuildContext context) =>
    Text(label, style: const TextStyle(color: _C.textSec, fontSize: 13));
}

// ─── Mobile menu (Drawer) ─────────────────────────────────────────────────────
class _MobileMenu extends StatelessWidget {
  final void Function(String) go;
  const _MobileMenu({required this.go});
  @override Widget build(BuildContext context) => Drawer(
    backgroundColor: _C.surface,
    child: SafeArea(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Image.asset('assets/images/logo-horizontal-dark.png', height: 40),
        const SizedBox(height: 28),
        Divider(color: _C.border),
        const SizedBox(height: 16),
        _MItem('Buscar cuidadores', Icons.search_rounded,      () { Navigator.pop(context); go('/marketplace'); }),
        _MItem('Para cuidadores',   Icons.pets_rounded,        () { Navigator.pop(context); go('/become-caregiver'); }),
        _MItem('Iniciar sesión',    Icons.login_rounded,       () { Navigator.pop(context); go('/login'); }),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () { Navigator.pop(context); go('/register'); },
          child: Container(
            width: double.infinity, height: 52,
            decoration: BoxDecoration(color: _C.primary, borderRadius: BorderRadius.circular(12)),
            child: const Center(child: Text('Registrarse',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
          ),
        ),
      ]),
    )),
  );
}

class _MItem extends StatelessWidget {
  final String label; final IconData icon; final VoidCallback onTap;
  const _MItem(this.label, this.icon, this.onTap);
  @override Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: _C.accent, size: 20),
    title: Text(label, style: const TextStyle(color: _C.textPri, fontWeight: FontWeight.w500)),
    onTap: onTap,
  );
}
