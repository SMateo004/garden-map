import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../design/brote.dart';
import '../../design/garden_caregiver_card.dart';
import '../../design/garden_icons.dart';
import '../../theme/garden_motion.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/garden_empty_state.dart';
import '../../services/auth_state.dart';

/// Cuidadores guardados. Usa la misma tarjeta que el marketplace (antes tenía
/// una propia, con el precio de 30 min rotulado "/ 1 hora") y el corazón de
/// la esquina quita al cuidador con opción de deshacer.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Map<String, dynamic>> _favorites = [];
  bool _isLoading = true;
  bool _failed = false;
  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites({bool silent = false}) async {
    final token = AuthState.token;
    if (token.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (!silent) {
      setState(() {
        _isLoading = true;
        _failed = false;
      });
    }
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/client/favorites'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] != true) throw Exception();
      if (mounted) {
        setState(() {
          _favorites = (data['data'] as List).cast<Map<String, dynamic>>();
          _failed = false;
        });
      }
    } catch (_) {
      // Antes un error de red mostraba "Aún no tienes favoritos".
      if (mounted && !silent) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// El endpoint alterna (agrega o quita). Devuelve si salió bien.
  Future<bool> _toggle(String caregiverId) async {
    try {
      final r = await http.post(
        Uri.parse('$_baseUrl/client/favorites/$caregiverId'),
        headers: {'Authorization': 'Bearer ${AuthState.token}'},
      );
      return r.statusCode >= 200 && r.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  String _nameOf(Map<String, dynamic> c) {
    final company = (c['companyName'] as String?)?.trim();
    if (c['isCompany'] == true && (company?.isNotEmpty ?? false)) return company!;
    return '${c['firstName'] ?? ''}'.trim().isEmpty ? 'el cuidador' : '${c['firstName']}';
  }

  /// Se quita al instante; "Deshacer" lo vuelve a guardar en su lugar.
  Future<void> _remove(Map<String, dynamic> c) async {
    HapticFeedback.mediumImpact();
    final index = _favorites.indexOf(c);
    setState(() => _favorites.remove(c));
    final ok = await _toggle(c['id'] as String);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (!ok) {
      setState(() => _favorites.insert(index.clamp(0, _favorites.length), c));
      messenger.showSnackBar(const SnackBar(content: Text('No se pudo quitar. Revisa tu conexión e intenta de nuevo.')));
      return;
    }
    messenger.showSnackBar(SnackBar(
      content: Text('Quitaste a ${_nameOf(c)} de favoritos'),
      action: SnackBarAction(
        label: 'Deshacer',
        onPressed: () async {
          if (await _toggle(c['id'] as String) && mounted) {
            setState(() => _favorites.insert(index.clamp(0, _favorites.length), c));
          }
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text('Mis favoritos', style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 20)),
        backgroundColor: bg,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        surfaceTintColor: Colors.transparent,
      ),
      body: _isLoading
          ? ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: 3,
              itemBuilder: (_, __) => const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: GardenSkeleton(width: double.infinity, height: 150, radius: GardenRadius.lg),
              ),
            )
          : _failed
              ? ListView(padding: const EdgeInsets.all(24), children: [
                  const SizedBox(height: 40),
                  GardenEmptyState(
                    type: GardenEmptyType.caregivers,
                    brote: BrotePose.oops,
                    title: 'No pudimos cargar tus favoritos',
                    subtitle: 'Revisa tu conexión e inténtalo de nuevo.',
                    ctaLabel: 'Reintentar',
                    onCta: _loadFavorites,
                  ),
                ])
              : _favorites.isEmpty
                  ? GardenEmptyState(
                      type: GardenEmptyType.caregivers,
                      title: 'Aún no tienes favoritos',
                      subtitle: 'Guarda a los cuidadores que más te gusten tocando el corazón en su perfil.',
                      ctaLabel: 'Explorar cuidadores',
                      onCta: () => context.go('/marketplace'),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _loadFavorites(silent: true),
                      color: GardenColors.primary,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 640),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                Padding(
                                  padding: const EdgeInsets.only(left: 2, bottom: 12),
                                  child: Text(
                                    _favorites.length == 1 ? '1 cuidador guardado' : '${_favorites.length} cuidadores guardados',
                                    style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                for (final c in _favorites)
                                  Padding(
                                    key: ValueKey(c['id']),
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Stack(children: [
                                      GardenCaregiverCard(
                                        caregiver: c,
                                        onTap: () async {
                                          HapticFeedback.lightImpact();
                                          await context.push('/caregiver/${c['id']}', extra: c);
                                          if (mounted) _loadFavorites(silent: true);
                                        },
                                      ),
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: _HeartButton(onTap: () => _remove(c)),
                                      ),
                                    ]),
                                  ),
                              ]),
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }
}

/// Corazón lleno para quitar de favoritos: se hunde al tocarlo.
class _HeartButton extends StatefulWidget {
  final VoidCallback onTap;
  const _HeartButton({required this.onTap});

  @override
  State<_HeartButton> createState() => _HeartButtonState();
}

class _HeartButtonState extends State<_HeartButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: 'Quitar de favoritos',
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: GardenMotion.resolve(context, GardenMotion.instant),
          scale: _down ? 0.85 : 1,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurface,
              shape: BoxShape.circle,
              border: Border.all(color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
            ),
            child: const GardenIcon(GIcon.favorito, size: GIconSize.sm, state: GIconState.active, color: GardenColors.error),
          ),
        ),
      ),
    );
  }
}
