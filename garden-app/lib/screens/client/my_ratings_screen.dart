import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';
import '../../services/auth_state.dart';
import '../../widgets/garden_empty_state.dart';
import '../../widgets/garden_loading_indicator.dart';
import '../../design/brote.dart';
import '../../design/garden_caregiver_card.dart';
import '../../design/garden_ratings.dart';
import '../../design/garden_service.dart';

/// Mis calificaciones (dueño): primero lo que falta calificar —con el plazo,
/// porque pasado ese tiempo el pago se libera solo y ya no se puede—, después
/// el resumen y las reseñas escritas con la respuesta del cuidador.
class MyRatingsScreen extends StatefulWidget {
  const MyRatingsScreen({super.key});
  @override
  State<MyRatingsScreen> createState() => _MyRatingsScreenState();
}

class _MyRatingsScreenState extends State<MyRatingsScreen> {
  List<Map<String, dynamic>> _reviews = [];
  List<Map<String, dynamic>> _pending = [];
  bool _isLoading = true;
  bool _failed = false;

  /// Horas para calificar tras el servicio (setting público
  /// autoReleasePaymentHoras, igual que en Mis reservas).
  int _autoReleaseHoras = 24;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final headers = {'Authorization': 'Bearer ${AuthState.token}'};
    var failed = false;
    List<Map<String, dynamic>> reviews = _reviews;
    List<Map<String, dynamic>> pending = _pending;
    await Future.wait([
      () async {
        try {
          final res = await http.get(Uri.parse('$_baseUrl/client/my-reviews'), headers: headers);
          final data = jsonDecode(res.body);
          if (data['success'] == true) {
            reviews = (data['data'] as List).cast<Map<String, dynamic>>();
          } else {
            failed = true;
          }
        } catch (_) {
          // Antes un error de red mostraba "Aún no has calificado ningún
          // servicio", como si no hubiera reseñas.
          failed = true;
        }
      }(),
      () async {
        try {
          final res = await http.get(Uri.parse('$_baseUrl/bookings/my'), headers: headers);
          final data = jsonDecode(res.body);
          if (data['success'] == true && data['data'] is List) {
            // Mismo criterio que el botón "Calificar experiencia" de Mis reservas.
            pending = (data['data'] as List)
                .cast<Map<String, dynamic>>()
                .where((b) => b['status'] == 'COMPLETED' && b['ownerRated'] != true && b['ownerRating'] == null)
                .toList();
          }
        } catch (_) {}
      }(),
      () async {
        try {
          final res = await http.get(Uri.parse('$_baseUrl/settings'));
          final d = (jsonDecode(res.body) as Map<String, dynamic>)['data'] as Map<String, dynamic>?;
          final h = (d?['autoReleasePaymentHoras'] as num?)?.toInt();
          if (h != null && h > 0) _autoReleaseHoras = h;
        } catch (_) {}
      }(),
    ]);
    if (!mounted) return;
    setState(() {
      _reviews = reviews;
      _pending = pending;
      _failed = failed && reviews.isEmpty;
      _isLoading = false;
    });
  }

  DateTime? _deadline(Map<String, dynamic> b) {
    final ended = DateTime.tryParse(b['serviceEndedAt'] as String? ?? '');
    return ended?.add(Duration(hours: _autoReleaseHoras)).toLocal();
  }

  /// La única forma de calificar: la encuesta del resumen del servicio
  /// (maneja la disputa si es < 3 y la propina si es ≥ 3).
  Future<void> _rate(Map<String, dynamic> b) async {
    await context.push('/service/${b['id']}', extra: {'role': 'CLIENT', 'token': AuthState.token});
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeNotifier,
      builder: (context, _) {
        final isDark = themeNotifier.isDark;
        final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
        final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            title: const Text('Mis calificaciones'),
            backgroundColor: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
            foregroundColor: textColor,
            elevation: 0,
          ),
          body: _isLoading
              ? const Center(child: GardenLoadingIndicator(color: GardenColors.primary))
              : RefreshIndicator(
                  color: GardenColors.primary,
                  onRefresh: _load,
                  child: _body(isDark),
                ),
        );
      },
    );
  }

  Widget _body(bool isDark) {
    final sub = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    if (_failed && _pending.isEmpty) {
      return ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 40),
        GardenEmptyState(
          type: GardenEmptyType.reviews,
          brote: BrotePose.oops,
          title: 'No pudimos cargar tus calificaciones',
          subtitle: 'Revisa tu conexión e inténtalo de nuevo.',
          ctaLabel: 'Reintentar',
          onCta: () {
            setState(() => _isLoading = true);
            _load();
          },
        ),
      ]);
    }
    if (_reviews.isEmpty && _pending.isEmpty) {
      return ListView(padding: const EdgeInsets.all(24), children: const [
        SizedBox(height: 40),
        GardenEmptyState(
          type: GardenEmptyType.reviews,
          brote: BrotePose.esperando,
          title: 'Aún no calificaste ningún servicio',
          subtitle: 'Cuando termine un servicio, podrás contar cómo te fue. Tu reseña ayuda a otros dueños a elegir.',
        ),
      ]);
    }

    final avg = _reviews.isEmpty
        ? 0.0
        : _reviews.map((r) => (r['rating'] as num?)?.toDouble() ?? 0).reduce((a, b) => a + b) / _reviews.length;
    final answered = _reviews.where((r) => (r['caregiverResponse'] as String?)?.isNotEmpty == true).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_pending.isNotEmpty) ...[
                GardenRatingsSectionTitle(
                  _pending.length == 1 ? 'Te falta calificar 1 servicio' : 'Tienes ${_pending.length} servicios por calificar',
                ),
                for (final b in _pending)
                  GardenPendingRatingCard(
                    caregiverName: b['caregiverName'] as String? ?? 'Tu cuidador',
                    caregiverPhoto: b['caregiverPhoto'] as String?,
                    petName: b['petName'] as String?,
                    service: GardenService.fromApi(b['serviceType'] as String?),
                    deadline: _deadline(b),
                    onRate: () => _rate(b),
                  ),
                const SizedBox(height: 14),
              ],
              if (_reviews.isNotEmpty) ...[
                GardenStatTiles(
                  highlightFirst: true,
                  tiles: [
                    (avg.toStringAsFixed(1).replaceAll('.', ','), 'nota promedio'),
                    ('${_reviews.length}', _reviews.length == 1 ? 'reseña' : 'reseñas'),
                    ('$answered', 'con respuesta'),
                  ],
                ),
                const SizedBox(height: 20),
                const GardenRatingsSectionTitle('Lo que escribiste'),
                for (final r in _reviews) _reviewCard(r),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Tus reseñas aparecerán aquí después de calificar.',
                      textAlign: TextAlign.center, style: TextStyle(color: sub, fontSize: 13)),
                ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _reviewCard(Map<String, dynamic> r) {
    final caregiver = r['caregiver'] as Map<String, dynamic>?;
    final u = caregiver?['user'] as Map<String, dynamic>?;
    final name = u != null ? '${u['firstName'] ?? ''} ${u['lastName'] ?? ''}'.trim() : 'Cuidador';
    final caregiverId = caregiver?['id'] as String?;
    return GardenReviewCard(
      caregiverName: name.isEmpty ? 'Cuidador' : name,
      caregiverPhoto: caregiver?['profilePhoto'] as String?,
      rating: (r['rating'] as num?)?.toInt() ?? 0,
      comment: r['comment'] as String?,
      service: GardenService.fromApi(r['serviceType'] as String?),
      date: DateTime.tryParse(r['createdAt'] as String? ?? '')?.toLocal(),
      response: r['caregiverResponse'] as String?,
      onOpenCaregiver: caregiverId == null ? null : () => context.push('/caregiver/$caregiverId'),
    );
  }
}
