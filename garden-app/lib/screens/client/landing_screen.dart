import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

// ── App store links ───────────────────────────────────────────────────────────
const _kAppStoreUrl  = 'https://apps.apple.com/app/garden-cuidadores/id000000000';
const _kPlayStoreUrl = 'https://play.google.com/store/apps/details?id=com.garden.bolivia';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _cream     = Color(0xFFF5F2EC);
const _ink       = Color(0xFF1E2D0F);
const _inkSec    = Color(0xFF5C7238);
const _inkHint   = Color(0xFF99AC75);
const _primary   = Color(0xFF778C43);
const _primaryL  = Color(0xFF8FA353);
const _primaryD  = Color(0xFF5C6E32);
const _accent    = Color(0xFF58E262);
const _lime      = Color(0xFFD9EF9F);
const _beige     = Color(0xFFDBD0C4);
const _forest    = Color(0xFF0D1A07);
const _forestSurf= Color(0xFF162610);
const _surface   = Color(0xFFFFFFFF);
const _surfaceEl = Color(0xFFF8FBF3);

TextStyle _nunito(double size, FontWeight w, Color c, {double? ls, double? lh, bool italic = false}) =>
    GoogleFonts.nunito(fontSize: size, fontWeight: w, color: c,
        letterSpacing: ls, height: lh, fontStyle: italic ? FontStyle.italic : FontStyle.normal);

TextStyle _mono(double size, FontWeight w, Color c, {double? ls}) =>
    GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: w, color: c, letterSpacing: ls);

// ── Logo SVG (PawLeaf) ────────────────────────────────────────────────────────
class _PawLeafLogo extends StatelessWidget {
  final double size;
  final Color color;
  const _PawLeafLogo({this.size = 36, this.color = _primary});
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size, size),
    painter: _PawLeafPainter(color: color),
  );
}

class _PawLeafPainter extends CustomPainter {
  final Color color;
  const _PawLeafPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 120;
    final p = Paint()..color = color..style = PaintingStyle.fill;
    // Toe pads
    _ellipse(canvas, p, s, 30, 48, 10, 14, -25);
    _ellipse(canvas, p, s, 50, 30, 9, 13, -8);
    _ellipse(canvas, p, s, 72, 30, 9, 13, 8);
    _ellipse(canvas, p, s, 92, 48, 10, 14, 25);
    // Main pad
    final path = Path();
    path.moveTo(60 * s, 60 * s);
    path.cubicTo(42 * s, 60 * s, 30 * s, 72 * s, 30 * s, 86 * s);
    path.cubicTo(30 * s, 96 * s, 38 * s, 104 * s, 48 * s, 104 * s);
    path.cubicTo(54 * s, 104 * s, 58 * s, 101 * s, 60 * s, 97 * s);
    path.cubicTo(62 * s, 101 * s, 66 * s, 104 * s, 72 * s, 104 * s);
    path.cubicTo(82 * s, 104 * s, 90 * s, 96 * s, 90 * s, 86 * s);
    path.cubicTo(90 * s, 72 * s, 78 * s, 60 * s, 60 * s, 60 * s);
    path.close();
    canvas.drawPath(path, p);
    // Accent vein
    final ap = Paint()..color = _accent..style = PaintingStyle.stroke..strokeWidth = 2.5 * s..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(60 * s, 64 * s), Offset(60 * s, 102 * s), ap);
  }
  void _ellipse(Canvas c, Paint p, double s, double cx, double cy, double rx, double ry, double deg) {
    c.save();
    c.translate(cx * s, cy * s);
    c.rotate(deg * math.pi / 180);
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: rx * 2 * s, height: ry * 2 * s), p);
    c.restore();
  }
  @override bool shouldRepaint(_PawLeafPainter o) => o.color != color;
}

// ── Decorative paw print ─────────────────────────────────────────────────────
class _DecoPaw extends StatelessWidget {
  final double size;
  final double opacity;
  const _DecoPaw({this.size = 48, this.opacity = 0.18});
  @override
  Widget build(BuildContext context) => Opacity(
    opacity: opacity,
    child: _PawLeafLogo(size: size, color: _primary),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  MAIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});
  @override State<LandingScreen> createState() => _LandingState();
}

class _LandingState extends State<LandingScreen> {
  final _scroll = ScrollController();
  String _svc = 'PASEO';

  // Section keys for scroll-to nav
  final _keyServices    = GlobalKey();
  final _keyHowItWorks  = GlobalKey();
  final _keyTrust       = GlobalKey();

  @override void dispose() { _scroll.dispose(); super.dispose(); }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _goToMarketplace() {
    HapticFeedback.lightImpact();
    context.go('/marketplace?service=${_svc.toLowerCase()}');
  }

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: 600.ms, curve: Curves.easeOutCubic);
  }

  void _showMobileSearchDialog() {
    HapticFeedback.selectionClick();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: _beige),
            boxShadow: [BoxShadow(color: const Color(0xFF1E2D0F).withValues(alpha: 0.14), blurRadius: 50, offset: const Offset(0, 18))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(color: _lime, shape: BoxShape.circle),
              child: const Icon(Icons.smartphone_rounded, color: _primaryD, size: 26),
            ),
            const SizedBox(height: 16),
            Text('¿Mejor en la app? 🐾',
              style: _nunito(18, FontWeight.w800, _ink), textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text('Garden tiene GPS en tiempo real, notificaciones y mejor experiencia para tu mascota.',
              style: _nunito(13, FontWeight.w500, _inkSec, lh: 1.5), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: _storeBtn(ctx, Icons.apple_rounded, 'App Store', _kAppStoreUrl)),
              const SizedBox(width: 10),
              Expanded(child: _storeBtn(ctx, Icons.android_rounded, 'Play Store', _kPlayStoreUrl)),
            ]),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () { Navigator.pop(ctx); _goToMarketplace(); },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Continuar en el navegador →',
                  style: _nunito(13, FontWeight.w600, _inkHint,
                    ls: 0).copyWith(decoration: TextDecoration.underline, decorationColor: _inkHint)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _storeBtn(BuildContext ctx, IconData icon, String label, String url) =>
    GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); Navigator.pop(ctx); _openUrl(url); },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: _primary, borderRadius: BorderRadius.circular(18)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: _cream, size: 16),
          const SizedBox(width: 7),
          Text(label, style: _nunito(13, FontWeight.w800, _cream)),
        ]),
      ),
    );

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final mobile = w < 860;

    return Scaffold(
      backgroundColor: _cream,
      endDrawer: mobile ? _MobileDrawer(
        onLogin:      () { Navigator.pop(context); context.go('/login'); },
        onRegister:   () { Navigator.pop(context); context.go('/register'); },
        onCaregiver:  () { Navigator.pop(context); context.go('/become-caregiver'); },
        onDownload:   () { Navigator.pop(context); _openUrl(_kAppStoreUrl); },
        onServices:   () { Navigator.pop(context); _scrollTo(_keyServices); },
        onHowItWorks: () { Navigator.pop(context); _scrollTo(_keyHowItWorks); },
        onTrust:      () { Navigator.pop(context); _scrollTo(_keyTrust); },
      ) : null,
      body: Builder(builder: (ctx) => CustomScrollView(
        controller: _scroll,
        slivers: [
          // ── Navbar
          SliverPersistentHeader(
            pinned: true,
            delegate: _NavDelegate(
              mobile: mobile,
              onOpenMenu: () => Scaffold.of(ctx).openEndDrawer(),
              onLogoTap:    () => context.go('/'),
              onServices:   () => _scrollTo(_keyServices),
              onHowItWorks: () => _scrollTo(_keyHowItWorks),
              onTrust:      () => _scrollTo(_keyTrust),
              onCaregivers: () => context.go('/become-caregiver'),
              onLogin:      () => context.go('/login'),
              onRegister:   () => context.go('/register'),
              onDownload:   () => _openUrl(_kAppStoreUrl),
            ),
          ),

          // ── Hero
          SliverToBoxAdapter(child: _HeroSection(
            mobile: mobile,
            selectedSvc: _svc,
            onSvcChange: (v) => setState(() => _svc = v),
            onSearch: mobile ? _showMobileSearchDialog : _goToMarketplace,
          )),

          // ── Services
          SliverToBoxAdapter(child: _ServicesSection(
            key: _keyServices,
            mobile: mobile,
            onTap: (svc) { setState(() => _svc = svc); _goToMarketplace(); },
          )),

          // ── How it works (dark)
          SliverToBoxAdapter(child: _HowItWorksSection(
            key: _keyHowItWorks,
            mobile: mobile,
          )),

          // ── Trust
          SliverToBoxAdapter(child: _TrustSection(
            key: _keyTrust,
            mobile: mobile,
          )),

          // ── App CTA
          SliverToBoxAdapter(child: _AppCtaSection(
            mobile: mobile,
            onAppStore:  () => _openUrl(_kAppStoreUrl),
            onPlayStore: () => _openUrl(_kPlayStoreUrl),
          )),

          // ── Footer
          SliverToBoxAdapter(child: _Footer(
            mobile: mobile,
            onLogoTap:    () => context.go('/'),
            onServices:   () => _scrollTo(_keyServices),
            onHowItWorks: () => _scrollTo(_keyHowItWorks),
            onTrust:      () => _scrollTo(_keyTrust),
            onCaregiver:  () => context.go('/become-caregiver'),
            onMarketplace:() => context.go('/marketplace'),
            onLogin:      () => context.go('/login'),
            onContact:    () => _openUrl('mailto:hola@gardenbo.com'),
          )),
        ],
      )),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  NAVBAR
// ─────────────────────────────────────────────────────────────────────────────
class _NavDelegate extends SliverPersistentHeaderDelegate {
  final bool mobile;
  final VoidCallback onOpenMenu, onLogoTap, onServices, onHowItWorks,
      onTrust, onCaregivers, onLogin, onRegister, onDownload;
  const _NavDelegate({
    required this.mobile, required this.onOpenMenu, required this.onLogoTap,
    required this.onServices, required this.onHowItWorks, required this.onTrust,
    required this.onCaregivers, required this.onLogin, required this.onRegister,
    required this.onDownload,
  });

  @override double get minExtent => 70;
  @override double get maxExtent => 70;
  @override bool shouldRebuild(_NavDelegate o) => o.mobile != mobile;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: _surface,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(children: [
              // Logo
              GestureDetector(
                onTap: onLogoTap,
                child: Row(children: [
                  _PawLeafLogo(size: 32, color: _primary),
                  const SizedBox(width: 10),
                  Text('garden', style: _nunito(22, FontWeight.w900, _ink, ls: -0.03 * 22)),
                ]),
              ),

              const Spacer(),

              if (!mobile) ...[
                _NavLink('Servicios',    onServices),
                _NavLink('Cómo funciona', onHowItWorks),
                _NavLink('Conviértete en cuidador', onCaregivers),
                const SizedBox(width: 16),
                // Iniciar sesión
                TextButton(
                  onPressed: onLogin,
                  style: TextButton.styleFrom(
                    foregroundColor: _inkSec,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  child: Text('Iniciar sesión', style: _nunito(14, FontWeight.w700, _inkSec)),
                ),
                // Registrarse
                OutlinedButton(
                  onPressed: onRegister,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _primary, width: 1.5),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  child: Text('Registrarse', style: _nunito(14, FontWeight.w800, _primary)),
                ),
                const SizedBox(width: 10),
                // Descargar app
                ElevatedButton(
                  onPressed: onDownload,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: _cream,
                    elevation: 0,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    shadowColor: _primary.withValues(alpha: 0.3),
                  ).copyWith(elevation: WidgetStateProperty.resolveWith((s) =>
                    s.contains(WidgetState.hovered) ? 4 : 0)),
                  child: Text('Descargar app', style: _nunito(14, FontWeight.w800, _cream)),
                ),
              ] else ...[
                // Mobile: just the CTA + hamburger
                ElevatedButton(
                  onPressed: onDownload,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary, foregroundColor: _cream,
                    elevation: 0, shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  child: Text('Descargar app', style: _nunito(13, FontWeight.w800, _cream)),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onOpenMenu,
                  icon: const Icon(Icons.menu_rounded, color: _ink, size: 26),
                ),
              ],
            ]),
          ),
        ),
        Divider(height: 1, color: _beige.withValues(alpha: 0.6)),
      ]),
    );
  }
}

class _NavLink extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _NavLink(this.label, this.onTap);
  @override State<_NavLink> createState() => _NavLinkState();
}
class _NavLinkState extends State<_NavLink> {
  bool _hov = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hov = true),
    onExit:  (_) => setState(() => _hov = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(widget.label,
          style: _nunito(14, FontWeight.w700, _hov ? _primary : _inkSec)),
      ),
    ),
  );
}

// Mobile drawer
class _MobileDrawer extends StatelessWidget {
  final VoidCallback onLogin, onRegister, onCaregiver, onDownload,
      onServices, onHowItWorks, onTrust;
  const _MobileDrawer({
    required this.onLogin, required this.onRegister, required this.onCaregiver,
    required this.onDownload, required this.onServices,
    required this.onHowItWorks, required this.onTrust,
  });
  @override
  Widget build(BuildContext context) => Drawer(
    backgroundColor: _surface,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _PawLeafLogo(size: 28), const SizedBox(width: 8),
            Text('garden', style: _nunito(20, FontWeight.w900, _ink)),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: _ink)),
          ]),
          const SizedBox(height: 32),
          _DrawerLink('Servicios',    onServices),
          _DrawerLink('Cómo funciona', onHowItWorks),
          _DrawerLink('Conviértete en cuidador', onCaregiver),
          const SizedBox(height: 24),
          const Divider(color: _beige),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: OutlinedButton(
            onPressed: onLogin,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _beige, width: 1.5),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text('Iniciar sesión', style: _nunito(15, FontWeight.w800, _ink)),
          )),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: onRegister,
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary, foregroundColor: _cream,
              elevation: 0, shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text('Registrarse', style: _nunito(15, FontWeight.w800, _cream)),
          )),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: TextButton(
            onPressed: onCaregiver,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text('Conviértete en cuidador →',
              style: _nunito(14, FontWeight.w700, _primary)),
          )),
        ]),
      ),
    ),
  );
}

class _DrawerLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DrawerLink(this.label, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(label, style: _nunito(17, FontWeight.w700, _ink)),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  HERO SECTION
// ─────────────────────────────────────────────────────────────────────────────
class _HeroSection extends StatelessWidget {
  final bool mobile;
  final String selectedSvc;
  final ValueChanged<String> onSvcChange;
  final VoidCallback onSearch;
  const _HeroSection({required this.mobile, required this.selectedSvc,
      required this.onSvcChange, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _cream,
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: mobile ? 24 : MediaQuery.of(context).size.width * 0.05,
        vertical: mobile ? 64 : 100,
      ),
      child: Stack(children: [
        // Decorative paws
        if (!mobile) ...[
          Positioned(top: 0,   left: 20,  child: const _DecoPaw(size: 52, opacity: 0.22)),
          Positioned(top: 60,  right: 80, child: const _DecoPaw(size: 38, opacity: 0.15)),
          Positioned(bottom: 80, left: 60, child: const _DecoPaw(size: 44, opacity: 0.18)),
          Positioned(bottom: 20, right: 40, child: const _DecoPaw(size: 58, opacity: 0.20))
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(begin: 0, end: -18, duration: 3000.ms, curve: Curves.easeInOut),
        ],

        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(children: [
              // Availability badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _beige),
                  boxShadow: [BoxShadow(color: const Color(0xFF1E2D0F).withValues(alpha: 0.06),
                    blurRadius: 16, offset: const Offset(0, 4))],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8,
                    decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Text('Ya disponible en Santa Cruz de la Sierra',
                    style: _nunito(14, FontWeight.w700, _ink)),
                ]),
              ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.2, end: 0),

              const SizedBox(height: 32),

              // H1
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(children: [
                  TextSpan(text: 'Cuidamos a quien\nvos más ',
                    style: _nunito(mobile ? 44 : 72, FontWeight.w900, _ink, ls: -0.045 * 72, lh: 0.98)),
                  TextSpan(text: 'querés',
                    style: _nunito(mobile ? 44 : 72, FontWeight.w900, _primary, ls: -0.045 * 72, lh: 0.98, italic: true)),
                  TextSpan(text: '.',
                    style: _nunito(mobile ? 44 : 72, FontWeight.w900, _ink, ls: -0.045 * 72, lh: 0.98)),
                ]),
              ).animate().fadeIn(delay: 100.ms, duration: 600.ms).slideY(begin: 0.15, end: 0),

              const SizedBox(height: 24),

              // Subtitle
              Text(
                'Paseadores, cuidadores y hospedaje para tu mascota\n— ',
                style: _nunito(mobile ? 16 : 19, FontWeight.w500, _inkSec, lh: 1.5),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 200.ms, duration: 600.ms),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(children: [
                  TextSpan(text: 'verificados',
                    style: _nunito(mobile ? 16 : 19, FontWeight.w800, _ink)),
                  TextSpan(text: ', cerca de tu casa y con pago protegido.',
                    style: _nunito(mobile ? 16 : 19, FontWeight.w500, _inkSec, lh: 1.5)),
                ]),
              ).animate().fadeIn(delay: 200.ms, duration: 600.ms),

              const SizedBox(height: 40),

              // Search bar
              _SearchBar(
                mobile: mobile,
                selectedSvc: selectedSvc,
                onSvcChange: onSvcChange,
                onSearch: onSearch,
              ).animate().fadeIn(delay: 300.ms, duration: 600.ms).slideY(begin: 0.1, end: 0),

              const SizedBox(height: 28),

              // Trust badges
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 28, runSpacing: 12,
                children: [
                  _TrustBadge(Icons.shield_outlined, 'Identidad verificada'),
                  _TrustBadge(Icons.lock_outline_rounded, 'Pago protegido'),
                  _TrustBadge(Icons.pets_rounded, '+500 mascotas felices'),
                ],
              ).animate().fadeIn(delay: 400.ms, duration: 600.ms),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _TrustBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _TrustBadge(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 16, color: _inkSec),
    const SizedBox(width: 6),
    Text(label, style: _nunito(14, FontWeight.w600, _inkSec)),
  ]);
}

// Search bar
class _SearchBar extends StatefulWidget {
  final bool mobile;
  final String selectedSvc;
  final ValueChanged<String> onSvcChange;
  final VoidCallback onSearch;
  const _SearchBar({required this.mobile, required this.selectedSvc,
      required this.onSvcChange, required this.onSearch});
  @override State<_SearchBar> createState() => _SearchBarState();
}
class _SearchBarState extends State<_SearchBar> {
  bool _svcOpen = false;
  static const _services = {'PASEO': 'Paseo', 'HOSPEDAJE': 'Hospedaje', 'GUARDERIA': 'Guardería', 'VISITA': 'Visita'};

  @override
  Widget build(BuildContext context) {
    if (widget.mobile) {
      return GestureDetector(
        onTap: widget.onSearch,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: _surface, borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _beige),
            boxShadow: [BoxShadow(color: const Color(0xFF1E2D0F).withValues(alpha: 0.10),
              blurRadius: 30, offset: const Offset(0, 8))],
          ),
          child: Row(children: [
            const Icon(Icons.search_rounded, color: _primary),
            const SizedBox(width: 12),
            Text('Buscar cuidadores...', style: _nunito(15, FontWeight.w600, _inkHint)),
          ]),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: _surface, borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _beige),
        boxShadow: [BoxShadow(color: const Color(0xFF1E2D0F).withValues(alpha: 0.10),
          blurRadius: 30, offset: const Offset(0, 8))],
      ),
      padding: const EdgeInsets.all(6),
      child: Row(children: [
        // SERVICIO
        Expanded(child: _SvcSegment(
          label: 'SERVICIO',
          value: _services[widget.selectedSvc] ?? 'Elegí un servicio',
          isOpen: _svcOpen,
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _svcOpen = !_svcOpen);
          },
          dropdown: _svcOpen ? _SvcDropdown(
            selected: widget.selectedSvc,
            onSelect: (v) {
              HapticFeedback.selectionClick();
              widget.onSvcChange(v);
              setState(() => _svcOpen = false);
            },
          ) : null,
        )),
        _divider(),
        // DÓNDE
        Expanded(child: _Segment(label: 'DÓNDE', placeholder: 'Tu zona en SCZ')),
        _divider(),
        // CUÁNDO
        Expanded(child: _Segment(label: 'CUÁNDO', placeholder: 'Agregá fecha')),
        _divider(),
        // MASCOTA
        Expanded(child: _Segment(label: 'MASCOTA', placeholder: '¿Quién va?')),
        const SizedBox(width: 8),
        // Buscar
        ElevatedButton.icon(
          onPressed: widget.onSearch,
          icon: const Icon(Icons.search_rounded, size: 18),
          label: Text('Buscar', style: _nunito(15, FontWeight.w800, _cream)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _primary, foregroundColor: _cream, elevation: 0,
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            shadowColor: _primary.withValues(alpha: 0.3),
          ).copyWith(elevation: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.hovered) ? 4 : 0)),
        ),
      ]),
    );
  }

  Widget _divider() => Container(width: 1, height: 36, color: _beige.withValues(alpha: 0.8));
}

class _Segment extends StatelessWidget {
  final String label, placeholder;
  const _Segment({required this.label, required this.placeholder});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: _mono(11, FontWeight.w600, _inkHint, ls: 0.16)),
      const SizedBox(height: 3),
      Text(placeholder, style: _nunito(15, FontWeight.w700, _ink)),
    ]),
  );
}

class _SvcSegment extends StatelessWidget {
  final String label, value;
  final bool isOpen;
  final VoidCallback onTap;
  final Widget? dropdown;
  const _SvcSegment({required this.label, required this.value,
      required this.isOpen, required this.onTap, this.dropdown});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Stack(clipBehavior: Clip.none, children: [
      AnimatedContainer(
        duration: 200.ms,
        decoration: BoxDecoration(
          color: isOpen ? _surfaceEl : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: _mono(11, FontWeight.w600, _inkHint, ls: 0.16)),
          const SizedBox(height: 3),
          Text(value, style: _nunito(15, FontWeight.w700, _ink)),
        ]),
      ),
      if (dropdown != null)
        Positioned(top: 68, left: 0, child: dropdown!),
    ]),
  );
}

class _SvcDropdown extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  static const _opts = {
    'PASEO': ('Paseo', Icons.directions_walk_rounded),
    'HOSPEDAJE': ('Hospedaje', Icons.home_rounded),
    'GUARDERIA': ('Guardería de día', Icons.wb_sunny_rounded),
    'VISITA': ('Visita a domicilio', Icons.house_rounded),
  };
  const _SvcDropdown({required this.selected, required this.onSelect});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Container(
      width: 220,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _surface, borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _beige),
        boxShadow: [BoxShadow(color: const Color(0xFF1E2D0F).withValues(alpha: 0.14),
          blurRadius: 50, offset: const Offset(0, 18))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _opts.entries.map((e) {
          final active = e.key == selected;
          return GestureDetector(
            onTap: () => onSelect(e.key),
            child: AnimatedContainer(
              duration: 150.ms,
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: active ? _lime : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                Container(
                  width: 32, height: 32, decoration: BoxDecoration(
                    color: active ? _primary : _surfaceEl,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(e.value.$2, size: 16, color: active ? _cream : _inkSec),
                ),
                const SizedBox(width: 10),
                Text(e.value.$1, style: _nunito(14, active ? FontWeight.w800 : FontWeight.w600,
                  active ? _primaryD : _ink)),
              ]),
            ),
          );
        }).toList(),
      ),
    ),
  ).animate().scale(begin: const Offset(0.98, 0.98), end: const Offset(1, 1), duration: 150.ms)
   .fadeIn(duration: 150.ms);
}

// ─────────────────────────────────────────────────────────────────────────────
//  SERVICES SECTION
// ─────────────────────────────────────────────────────────────────────────────
class _ServicesSection extends StatelessWidget {
  final bool mobile;
  final ValueChanged<String> onTap;
  const _ServicesSection({super.key, required this.mobile, required this.onTap});

  static const _cards = [
    ('PASEO',      Icons.directions_walk_rounded, 'Paseo',
     'Salidas con seguimiento GPS. Cuidadores verificados y reseñados por otras familias.'),
    ('HOSPEDAJE',  Icons.home_rounded,            'Hospedaje',
     'En casa del cuidador. Cuidadores verificados y reseñados por otras familias.'),
    ('GUARDERIA',  Icons.wb_sunny_rounded,        'Guardería de día',
     'Mientras trabajás. Cuidadores verificados y reseñados por otras familias.'),
    ('VISITA',     Icons.house_rounded,           'Visita a domicilio',
     'En tu propia casa. Cuidadores verificados y reseñados por otras familias.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _cream,
      padding: EdgeInsets.symmetric(
        horizontal: mobile ? 24 : MediaQuery.of(context).size.width * 0.05,
        vertical: mobile ? 64 : 100,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1320),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('SERVICIOS', style: _mono(13, FontWeight.w600, _primary, ls: 0.16)),
          const SizedBox(height: 14),
          Text('Todo lo que tu mascota\nnecesita, en un solo jardín.',
            style: _nunito(mobile ? 34 : 52, FontWeight.w900, _ink, ls: -0.035 * 52, lh: 1.04)),
          const SizedBox(height: 48),
          if (mobile)
            Column(children: _cards.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _ServiceCard(svc: c.$1, icon: c.$2, title: c.$3, desc: c.$4,
                onTap: () => onTap(c.$1)),
            )).toList())
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _cards.map((c) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: _ServiceCard(svc: c.$1, icon: c.$2, title: c.$3, desc: c.$4,
                    onTap: () => onTap(c.$1)),
                ),
              )).toList(),
            ),
        ]),
      ),
    );
  }
}

class _ServiceCard extends StatefulWidget {
  final String svc, title, desc;
  final IconData icon;
  final VoidCallback onTap;
  const _ServiceCard({required this.svc, required this.icon, required this.title,
      required this.desc, required this.onTap});
  @override State<_ServiceCard> createState() => _ServiceCardState();
}
class _ServiceCardState extends State<_ServiceCard> {
  bool _hov = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hov = true),
    onExit:  (_) => setState(() => _hov = false),
    child: GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: 300.ms,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: _hov ? _primary.withValues(alpha: 0.4) : _beige),
          boxShadow: _hov ? [BoxShadow(color: const Color(0xFF1E2D0F).withValues(alpha: 0.12),
              blurRadius: 40, offset: const Offset(0, 14))] : [],
        ),
        transform: _hov ? (Matrix4.identity()..translate(0.0, -8.0)) : Matrix4.identity(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(color: _lime, borderRadius: BorderRadius.circular(18)),
            child: Icon(widget.icon, color: _primaryD, size: 28),
          ),
          const SizedBox(height: 20),
          Text(widget.title, style: _nunito(20, FontWeight.w800, _ink, ls: -0.02 * 20)),
          const SizedBox(height: 10),
          Text(widget.desc, style: _nunito(14, FontWeight.w500, _inkSec, lh: 1.5)),
          const SizedBox(height: 20),
          Text('Buscar ahora →', style: _nunito(14, FontWeight.w800, _primary)),
        ]),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  HOW IT WORKS (dark section)
// ─────────────────────────────────────────────────────────────────────────────
class _HowItWorksSection extends StatelessWidget {
  final bool mobile;
  const _HowItWorksSection({super.key, required this.mobile});

  static const _steps = [
    (Icons.search_rounded,           '01', 'Buscá',
     'Elegí servicio, zona y fecha. Te mostramos solo cuidadores verificados cerca tuyo.'),
    (Icons.pets_rounded,             '02', 'Conocé',
     'Mirá perfiles, reseñas reales y respondé tus dudas por chat antes de reservar.'),
    (Icons.shield_outlined,          '03', 'Reservá',
     'Pagás por QR y el dinero queda protegido hasta confirmar que todo salió bien.'),
    (Icons.wb_sunny_rounded,         '04', 'Relajate',
     'Recibí fotos y seguimiento en tiempo real. Tu mascota en las mejores manos.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _forest,
      padding: EdgeInsets.symmetric(
        horizontal: mobile ? 24 : MediaQuery.of(context).size.width * 0.05,
        vertical: mobile ? 64 : 100,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1320),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('CÓMO FUNCIONA', style: _mono(13, FontWeight.w600, _primaryL, ls: 0.16)),
          const SizedBox(height: 14),
          Text('Cuatro pasos entre vos\ny la tranquilidad.',
            style: _nunito(mobile ? 34 : 52, FontWeight.w900, const Color(0xFFF0F7E8), ls: -0.035 * 52, lh: 1.04)),
          const SizedBox(height: 48),
          if (mobile)
            Column(children: _steps.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _StepCard(icon: s.$1, num: s.$2, title: s.$3, desc: s.$4),
            )).toList())
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _steps.map((s) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: _StepCard(icon: s.$1, num: s.$2, title: s.$3, desc: s.$4),
                ),
              )).toList(),
            ),
        ]),
      ),
    );
  }
}

class _StepCard extends StatefulWidget {
  final IconData icon;
  final String num, title, desc;
  const _StepCard({required this.icon, required this.num, required this.title, required this.desc});
  @override State<_StepCard> createState() => _StepCardState();
}
class _StepCardState extends State<_StepCard> {
  bool _hov = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hov = true),
    onExit:  (_) => setState(() => _hov = false),
    child: AnimatedContainer(
      duration: 300.ms,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _hov ? _forestSurf.withValues(alpha: 0.9) : _forestSurf,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF334D24).withValues(alpha: _hov ? 1.0 : 0.6)),
      ),
      transform: _hov ? (Matrix4.identity()..translate(0.0, -8.0)) : Matrix4.identity(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: _primary.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(widget.icon, color: _primaryL, size: 24),
          ),
          Text(widget.num, style: _nunito(36, FontWeight.w900,
            const Color(0xFF334D24), ls: -0.02)),
        ]),
        const SizedBox(height: 20),
        Text(widget.title,
          style: _nunito(18, FontWeight.w800, const Color(0xFFF0F7E8), ls: -0.01 * 18)),
        const SizedBox(height: 8),
        Text(widget.desc,
          style: _nunito(14, FontWeight.w500, const Color(0xFF8CAB6A), lh: 1.5)),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  TRUST SECTION
// ─────────────────────────────────────────────────────────────────────────────
class _TrustSection extends StatelessWidget {
  final bool mobile;
  const _TrustSection({super.key, required this.mobile});

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CONFIANZA', style: _mono(13, FontWeight.w600, _primary, ls: 0.16)),
        const SizedBox(height: 14),
        RichText(text: TextSpan(children: [
          TextSpan(text: 'No es buena onda.\nEs ',
            style: _nunito(mobile ? 34 : 52, FontWeight.w900, _ink, ls: -0.035 * 52, lh: 1.04)),
          TextSpan(text: 'verificación real',
            style: _nunito(mobile ? 34 : 52, FontWeight.w900, _primary, ls: -0.035 * 52, lh: 1.04, italic: true)),
          TextSpan(text: '.',
            style: _nunito(mobile ? 34 : 52, FontWeight.w900, _ink, ls: -0.035 * 52, lh: 1.04)),
        ])),
        const SizedBox(height: 24),
        Text(
          'Cada cuidador pasa por verificación de identidad con IA y queda registrado de forma permanente. Tu pago queda protegido hasta que confirmás que todo salió bien.',
          style: _nunito(16, FontWeight.w500, _inkSec, lh: 1.5),
        ),
        const SizedBox(height: 32),
        _CheckItem('Identidad verificada', 'Reconocimiento facial + carnet, registro inmutable.'),
        const SizedBox(height: 16),
        _CheckItem('Pago protegido', 'El dinero se libera solo al completar el servicio.'),
        const SizedBox(height: 16),
        _CheckItem('Reseñas reales', 'Solo quien reservó y completó puede calificar.'),
      ],
    );

    final stats = Column(children: [
      Row(children: [
        Expanded(child: _StatCard('+500', 'mascotas cuidadas', bg: _surface, textColor: _ink, subtextColor: _inkSec)),
        const SizedBox(width: 16),
        Expanded(child: _StatCard('100%', 'identidades verificadas', bg: _primaryD, textColor: _surfaceEl, subtextColor: _lime)),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: _StatCard('4.9★', 'calificación promedio', bg: _lime, textColor: _primaryD, subtextColor: _primaryD)),
        const SizedBox(width: 16),
        Expanded(child: _StatCard('24h', 'soporte para vos', bg: _forest, textColor: const Color(0xFFF0F7E8), subtextColor: const Color(0xFF8CAB6A))),
      ]),
    ]);

    return Container(
      color: _cream,
      padding: EdgeInsets.symmetric(
        horizontal: mobile ? 24 : MediaQuery.of(context).size.width * 0.05,
        vertical: mobile ? 64 : 100,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1320),
        child: mobile
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [content, const SizedBox(height: 48), stats])
          : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(child: content),
              const SizedBox(width: 80),
              SizedBox(width: 420, child: stats),
            ]),
      ),
    );
  }
}

class _CheckItem extends StatelessWidget {
  final String title, subtitle;
  const _CheckItem(this.title, this.subtitle);
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(
      width: 28, height: 28,
      decoration: BoxDecoration(color: _lime, borderRadius: BorderRadius.circular(8)),
      child: const Icon(Icons.check_rounded, color: _primaryD, size: 16),
    ),
    const SizedBox(width: 14),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: _nunito(15, FontWeight.w800, _ink)),
      const SizedBox(height: 2),
      Text(subtitle, style: _nunito(13, FontWeight.w500, _inkSec)),
    ])),
  ]);
}

class _StatCard extends StatelessWidget {
  final String value, label;
  final Color bg, textColor, subtextColor;
  const _StatCard(this.value, this.label, {required this.bg, required this.textColor, required this.subtextColor});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(26)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: _nunito(40, FontWeight.w900, textColor, ls: -0.03 * 40)),
      const SizedBox(height: 6),
      Text(label, style: _nunito(13, FontWeight.w600, subtextColor)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  APP CTA SECTION
// ─────────────────────────────────────────────────────────────────────────────
class _AppCtaSection extends StatelessWidget {
  final bool mobile;
  final VoidCallback onAppStore, onPlayStore;
  const _AppCtaSection({required this.mobile, required this.onAppStore, required this.onPlayStore});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _cream,
      padding: EdgeInsets.symmetric(
        horizontal: mobile ? 24 : MediaQuery.of(context).size.width * 0.05,
        vertical: 32,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1320),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: mobile ? 32 : 64, vertical: 56),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [_primary, _primaryD],
            ),
            borderRadius: BorderRadius.circular(34),
          ),
          child: Stack(children: [
            // Decorative paws background
            Positioned(left: -20, top: -10,
              child: const _DecoPaw(size: 120, opacity: 0.12)),
            Positioned(right: -10, bottom: -20,
              child: const _DecoPaw(size: 160, opacity: 0.10)),
            // Content
            Column(children: [
              Text('Llevá Garden en tu bolsillo.',
                style: _nunito(mobile ? 30 : 44, FontWeight.w900, _cream, ls: -0.03 * 44),
                textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Text('Buscá, reservá y seguí a tu mascota en tiempo real.\nGratis en iOS y Android.',
                style: _nunito(16, FontWeight.w500, _cream.withValues(alpha: 0.85), lh: 1.5),
                textAlign: TextAlign.center),
              const SizedBox(height: 36),
              Wrap(alignment: WrapAlignment.center, spacing: 16, runSpacing: 12, children: [
                _StoreButton(
                  topText: 'Download on',
                  mainText: 'App Store',
                  icon: Icons.apple_rounded,
                  onTap: onAppStore,
                ),
                _StoreButton(
                  topText: 'GET IT ON',
                  mainText: 'Google Play',
                  icon: Icons.play_arrow_rounded,
                  onTap: onPlayStore,
                ),
              ]),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _StoreButton extends StatefulWidget {
  final String topText, mainText;
  final IconData icon;
  final VoidCallback onTap;
  const _StoreButton({required this.topText, required this.mainText,
      required this.icon, required this.onTap});
  @override State<_StoreButton> createState() => _StoreButtonState();
}
class _StoreButtonState extends State<_StoreButton> {
  bool _hov = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hov = true),
    onExit:  (_) => setState(() => _hov = false),
    child: GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: 200.ms,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          color: _hov ? const Color(0xFF1A2B10) : const Color(0xFF0D1A07),
          borderRadius: BorderRadius.circular(18),
        ),
        transform: _hov ? (Matrix4.identity()..translate(0.0, -3.0)) : Matrix4.identity(),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(widget.icon, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.topText, style: _mono(10, FontWeight.w500, Colors.white.withValues(alpha: 0.7), ls: 0.04)),
            Text(widget.mainText, style: _nunito(17, FontWeight.w800, Colors.white)),
          ]),
        ]),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  FOOTER
// ─────────────────────────────────────────────────────────────────────────────
class _Footer extends StatelessWidget {
  final bool mobile;
  final VoidCallback onLogoTap, onServices, onHowItWorks, onTrust,
      onCaregiver, onMarketplace, onLogin, onContact;
  const _Footer({required this.mobile, required this.onLogoTap,
      required this.onServices, required this.onHowItWorks, required this.onTrust,
      required this.onCaregiver, required this.onMarketplace,
      required this.onLogin, required this.onContact});

  @override
  Widget build(BuildContext context) {
    final links1 = [
      ('Servicios',     onServices),
      ('Cómo funciona', onHowItWorks),
      ('Descargar app', onLogoTap),
    ];
    final links2 = [
      ('Sobre Garden',              onLogoTap),
      ('Conviértete en cuidador',  onCaregiver),
      ('Contacto',                  onContact),
      ('Trabajá con nosotros',      onCaregiver),
    ];

    return Container(
      color: _forest,
      padding: EdgeInsets.symmetric(
        horizontal: mobile ? 24 : MediaQuery.of(context).size.width * 0.05,
        vertical: mobile ? 48 : 64,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1320),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Main footer row
          if (mobile) ...[
            _footerBrand(),
            const SizedBox(height: 40),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _footerCol('PRODUCTO', links1)),
              Expanded(child: _footerCol('EMPRESA', links2)),
            ]),
          ] else
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 2, child: _footerBrand()),
              const SizedBox(width: 80),
              Expanded(child: _footerCol('PRODUCTO', links1)),
              const SizedBox(width: 48),
              Expanded(child: _footerCol('EMPRESA', links2)),
            ]),

          const SizedBox(height: 48),
          Divider(color: const Color(0xFF334D24).withValues(alpha: 0.5)),
          const SizedBox(height: 24),
          Row(children: [
            Text('GARDEN · Santa Cruz de la Sierra · www.gardenbo.com',
              style: _mono(12, FontWeight.w500, const Color(0xFF506038))),
            const Spacer(),
            Text('© 2026 Garden',
              style: _mono(12, FontWeight.w500, const Color(0xFF506038))),
          ]),
        ]),
      ),
    );
  }

  Widget _footerBrand() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    GestureDetector(
      onTap: onLogoTap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _PawLeafLogo(size: 32, color: _primaryL),
        const SizedBox(width: 10),
        Text('garden', style: _nunito(20, FontWeight.w900, const Color(0xFFF0F7E8), ls: -0.03 * 20)),
      ]),
    ),
    const SizedBox(height: 16),
    Text('El primer marketplace verificado de servicios\npara mascotas en Bolivia.',
      style: _nunito(14, FontWeight.w500, const Color(0xFF8CAB6A), lh: 1.5)),
  ]);

  Widget _footerCol(String title, List<(String, VoidCallback)> links) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: _mono(12, FontWeight.w600, _primary, ls: 0.12)),
      const SizedBox(height: 20),
      ...links.map((l) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GestureDetector(
          onTap: l.$2,
          child: Text(l.$1,
            style: _nunito(14, FontWeight.w600, const Color(0xFF8CAB6A))),
        ),
      )),
    ],
  );
}
