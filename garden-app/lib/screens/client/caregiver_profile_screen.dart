import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/garden_empty_state.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';
import '../../widgets/temporada_alta_badge.dart';
import '../../services/agentes_service.dart';
import '../../widgets/garden_logo_loader.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CaregiverProfileScreen extends StatefulWidget {
  final String caregiverId;
  final Map<String, dynamic>? initialData;

  const CaregiverProfileScreen({
    super.key,
    required this.caregiverId,
    this.initialData,
  });

  @override
  State<CaregiverProfileScreen> createState() => _CaregiverProfileScreenState();
}

class _CaregiverProfileScreenState extends State<CaregiverProfileScreen> {
  Map<String, dynamic>? _caregiver;
  bool _isLoading = true;
  bool _loadError = false;
  List<dynamic> _clientPets = [];
  String _authToken = '';
  int _selectedPhotoIndex = 0;
  bool _showAllReviews = false;
  bool _isFavorite = false;
  bool _isTogglingFavorite = false;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _caregiver = widget.initialData;
      _isLoading = false;
    }
    _loadAll();
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token') ?? '';
    if (mounted) setState(() => _authToken = token);
    await Future.wait([
      _fetchCaregiver(),
      if (token.isNotEmpty) _fetchClientPets(token),
    ]);
    if (mounted) setState(() => _isLoading = false);
    if (token.isNotEmpty) _fetchFavoriteStatus(token);
  }

  Future<void> _fetchCaregiver() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await http
            .get(Uri.parse('$_baseUrl/caregivers/${widget.caregiverId}'))
            .timeout(const Duration(seconds: 10));
        final data = jsonDecode(response.body);
        if (response.statusCode == 404) {
          if (mounted && _caregiver == null) setState(() => _loadError = true);
          return;
        }
        if (data['success'] == true && mounted) {
          setState(() { _caregiver = data['data']; _loadError = false; });
          return;
        }
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }
    if (mounted && _caregiver == null) setState(() => _loadError = true);
  }

  Future<void> _fetchClientPets(String token) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/client/pets'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 8));
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        setState(() => _clientPets = data['data'] as List? ?? []);
      }
    } catch (_) {}
  }

  Future<void> _fetchFavoriteStatus(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/client/my-profile'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 8));
      final data = jsonDecode(response.body);
      if (data['success'] == true && mounted) {
        final favorites = (data['data']['favoriteCaregiverIds'] as List?)?.cast<String>() ?? [];
        setState(() => _isFavorite = favorites.contains(widget.caregiverId));
      }
    } catch (_) {}
  }

  Future<void> _toggleFavorite() async {
    final token = _authToken;
    if (token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sesión para guardar favoritos'), backgroundColor: GardenColors.primary, duration: Duration(seconds: 2)),
      );
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      context.push('/login');
      return;
    }
    setState(() => _isTogglingFavorite = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/client/favorites/${widget.caregiverId}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true && mounted) {
        setState(() => _isFavorite = data['data']['isFavorite'] == true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isFavorite ? 'Agregado a favoritos' : 'Eliminado de favoritos'),
          backgroundColor: _isFavorite ? GardenColors.success : GardenColors.darkSurface,
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _isTogglingFavorite = false);
    }
  }

  void _openPhotoViewer(List<String> photos, int initialIndex) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _PhotoLightbox(photos: photos, initialIndex: initialIndex),
    );
  }

  void _onReserve() {
    final token = _authToken;
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sesión para hacer una reserva'), backgroundColor: GardenColors.primary, duration: Duration(seconds: 2)),
      );
      Future.delayed(const Duration(seconds: 1), () { if (context.mounted) context.push('/login'); });
      return;
    }
    if (_clientPets.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Primero agrega una mascota'),
          content: const Text('Necesitas registrar al menos una mascota para hacer una reserva.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            TextButton(
              onPressed: () { Navigator.pop(ctx); context.push('/my-pets'); },
              child: const Text('Agregar mascota', style: TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      return;
    }

    final pricePerWalk60Raw = _caregiver!['pricePerWalk60'];
    final pricePerWalk30Raw = _caregiver!['pricePerWalk30'];
    final pricePerDayRaw = _caregiver!['pricePerDay'];
    final pricePerDay = (pricePerDayRaw != null && (pricePerDayRaw as num) > 0) ? pricePerDayRaw : null;
    final pricePerWalk60 = (pricePerWalk60Raw != null && (pricePerWalk60Raw as num) > 0) ? pricePerWalk60Raw : null;
    final pricePerWalk30 = (pricePerWalk30Raw != null && (pricePerWalk30Raw as num) > 0) ? pricePerWalk30Raw : null;
    final offersHospedaje = pricePerDay != null;
    final offersPaseo = pricePerWalk30 != null || pricePerWalk60 != null;
    final walkDisplayPrice = pricePerWalk30 ?? pricePerWalk60;
    final walkDisplayUnit = pricePerWalk30 != null ? '30 min' : 'hora';
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;

    final bookingExtra = {'caregiver': _caregiver, 'pets': _clientPets, 'token': token};

    if (offersHospedaje && offersPaseo) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) => Container(
          decoration: BoxDecoration(color: surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Text('¿Qué servicio necesitas?', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              _ServiceOption(icon: Icons.home_outlined, label: 'Hospedaje', sublabel: 'Bs $pricePerDay/noche', onTap: () { Navigator.pop(sheetCtx); context.push('/booking/${widget.caregiverId}', extra: {...bookingExtra, 'serviceType': 'HOSPEDAJE'}); }),
              const SizedBox(height: 12),
              _ServiceOption(icon: Icons.directions_walk, label: 'Paseo', sublabel: 'Bs $walkDisplayPrice/$walkDisplayUnit', onTap: () { Navigator.pop(sheetCtx); context.push('/booking/${widget.caregiverId}', extra: {...bookingExtra, 'serviceType': 'PASEO'}); }),
            ],
          ),
        ),
      );
    } else {
      // Single service — detect which one it is
      final singleService = offersHospedaje ? 'HOSPEDAJE' : 'PASEO';
      context.push('/booking/${widget.caregiverId}', extra: {...bookingExtra, 'serviceType': singleService});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    if (_isLoading && _caregiver == null) {
      return Scaffold(backgroundColor: bg, body: GardenLogoLoader(bgColor: bg));
    }
    if (_loadError && _caregiver == null) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(backgroundColor: surface, leading: IconButton(icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 18), onPressed: () => context.pop())),
        body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.wifi_off_rounded, size: 52, color: subtextColor),
            const SizedBox(height: 16),
            Text('No se pudo cargar', style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Verifica tu conexión e intenta de nuevo', style: TextStyle(color: subtextColor, fontSize: 13)),
            const SizedBox(height: 24),
            GardenButton(label: 'Reintentar', width: 140, onPressed: () { setState(() { _loadError = false; _isLoading = true; }); _loadAll(); }),
          ]),
        ),
      );
    }

    final photos = (_caregiver!['photos'] as List?)?.cast<String>() ?? [];
    final services = (_caregiver!['services'] as List?)?.cast<String>() ?? [];
    final name = '${_caregiver!['firstName']} ${_caregiver!['lastName']}';
    final rating = (_caregiver!['rating'] as num? ?? 0).toStringAsFixed(1);
    final reviewCount = _caregiver!['reviewCount'] as int? ?? 0;
    final zone = _caregiver!['zone'] as String? ?? '';
    final bio = _caregiver!['bio'] as String? ?? '';
    final bioDetail = _caregiver!['bioDetail'] as String? ?? '';
    final verified = _caregiver!['verified'] == true;
    final pricePerWalk60Raw = _caregiver!['pricePerWalk60'];
    final pricePerWalk30Raw = _caregiver!['pricePerWalk30'];
    final pricePerDayRaw = _caregiver!['pricePerDay'];
    final pricePerWalk60 = (pricePerWalk60Raw != null && (pricePerWalk60Raw as num) > 0) ? pricePerWalk60Raw : null;
    final pricePerWalk30 = (pricePerWalk30Raw != null && (pricePerWalk30Raw as num) > 0) ? pricePerWalk30Raw : null;
    final pricePerDay = (pricePerDayRaw != null && (pricePerDayRaw as num) > 0) ? pricePerDayRaw : null;
    final offersHospedaje = pricePerDay != null;
    final offersPaseo = pricePerWalk30 != null || pricePerWalk60 != null;
    final walkDisplayPrice = pricePerWalk30 ?? pricePerWalk60;
    final walkDisplayUnit = pricePerWalk30 != null ? '30 min' : 'hora';
    final priceDisplay = offersPaseo ? 'Bs $walkDisplayPrice/$walkDisplayUnit' : offersHospedaje ? 'Bs $pricePerDay/noche' : 'Consultar';

    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 900;
      if (isWide) {
        return _buildWideLayout(
          context: context, isDark: isDark, bg: bg, surface: surface,
          textColor: textColor, subtextColor: subtextColor, borderColor: borderColor,
          photos: photos, services: services, name: name, rating: rating,
          reviewCount: reviewCount, zone: zone, bio: bio, bioDetail: bioDetail,
          verified: verified, pricePerWalk60: pricePerWalk60, pricePerWalk30: pricePerWalk30, pricePerDay: pricePerDay,
          offersHospedaje: offersHospedaje, offersPaseo: offersPaseo, priceDisplay: priceDisplay,
        );
      }
      return _buildNarrowLayout(
        context: context, isDark: isDark, bg: bg, surface: surface,
        textColor: textColor, subtextColor: subtextColor, borderColor: borderColor,
        photos: photos, services: services, name: name, rating: rating,
        reviewCount: reviewCount, zone: zone, bio: bio, bioDetail: bioDetail,
        verified: verified, pricePerWalk60: pricePerWalk60, pricePerWalk30: pricePerWalk30, pricePerDay: pricePerDay,
        offersHospedaje: offersHospedaje, offersPaseo: offersPaseo, priceDisplay: priceDisplay,
      );
    });
  }

  // ─────────────────────── WIDE LAYOUT (WEB) ───────────────────────────────

  Widget _buildWideLayout({
    required BuildContext context,
    required bool isDark, required Color bg, required Color surface,
    required Color textColor, required Color subtextColor, required Color borderColor,
    required List<String> photos, required List<String> services, required String name,
    required String rating, required int reviewCount, required String zone,
    required String bio, required String bioDetail, required bool verified,
    required dynamic pricePerWalk60, required dynamic pricePerWalk30, required dynamic pricePerDay,
    required bool offersHospedaje, required bool offersPaseo, required String priceDisplay,
  }) {
    final cardBg = isDark ? GardenColors.darkSurfaceElevated : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── Barra superior ──────────────────────────────────
            Container(
              height: 60,
              color: surface,
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Row(children: [
                      Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: textColor),
                      const SizedBox(width: 8),
                      Text('Volver al marketplace', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _toggleFavorite,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _isFavorite ? GardenColors.error.withValues(alpha: 0.1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _isFavorite ? GardenColors.error.withValues(alpha: 0.4) : borderColor),
                      ),
                      child: Row(children: [
                        _isTogglingFavorite
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: GardenColors.error))
                            : Icon(_isFavorite ? Icons.favorite : Icons.favorite_border, size: 16, color: _isFavorite ? GardenColors.error : subtextColor),
                        const SizedBox(width: 6),
                        Text(_isFavorite ? 'Guardado' : 'Guardar', style: TextStyle(color: _isFavorite ? GardenColors.error : subtextColor, fontSize: 13, fontWeight: FontWeight.w500)),
                      ]),
                    ),
                  ),
                ],
              ),
            ),

            // ── Cuerpo principal: 2 columnas ────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Columna izquierda (contenido) ─────────────
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Nombre, zona, rating
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GardenAvatar(
                              imageUrl: _caregiver!['profilePicture'] as String?,
                              size: 72,
                              initials: '${_caregiver!['firstName']?[0] ?? ''}${_caregiver!['lastName']?[0] ?? ''}',
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: TextStyle(color: textColor, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                                  const SizedBox(height: 6),
                                  Row(children: [
                                    _zoneChip(zone, subtextColor, borderColor, surface),
                                    const SizedBox(width: 12),
                                    Icon(Icons.star_rounded, color: GardenColors.star, size: 18),
                                    const SizedBox(width: 4),
                                    Text(rating, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w800)),
                                    const SizedBox(width: 4),
                                    if (reviewCount > 0) Text('($reviewCount reseñas)', style: TextStyle(color: subtextColor, fontSize: 13)),
                                  ]),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Badges
                        Wrap(
                          spacing: 8, runSpacing: 8,
                          children: [
                            if (verified) _verifiedBadge(),
                            _polygonBadge(),
                            if (_caregiver!['zone'] == 'EQUIPETROL')
                              TemporadaAltaBadge(zona: 'Equipetrol', porcentajeAjuste: 15, motivo: 'Semana Santa', fechaVueltaNormal: '24 de marzo', agentesService: AgentesService(authToken: '')),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildTrustBadges(subtextColor),
                        const SizedBox(height: 32),

                        Divider(color: borderColor),
                        const SizedBox(height: 28),

                        // Bio
                        Text('Sobre ${_caregiver!['firstName']}', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 12),
                        if (bio.isNotEmpty) Text(bio, style: TextStyle(color: subtextColor, fontSize: 15, height: 1.7)),
                        if (bioDetail.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(bioDetail, style: TextStyle(color: subtextColor, fontSize: 15, height: 1.7)),
                        ],
                        const SizedBox(height: 32),

                        // Experiencia
                        if (_caregiver!['experienceYears'] != null) ...[
                          Divider(color: borderColor),
                          const SizedBox(height: 28),
                          Text('Experiencia', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: GardenColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: GardenColors.primary.withValues(alpha: 0.25)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.workspace_premium_outlined, color: GardenColors.primary, size: 16),
                              const SizedBox(width: 8),
                              Text('${_caregiver!['experienceYears']} años de experiencia', style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w600, fontSize: 14)),
                            ]),
                          ),
                          if ((_caregiver!['experienceDescription'] as String? ?? '').isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text(_caregiver!['experienceDescription'] as String, style: TextStyle(color: subtextColor, fontSize: 15, height: 1.7)),
                          ],
                        ],

                        // Por qué cuidador / Qué lo diferencia
                        if ((_caregiver!['whyCaregiver'] as String? ?? '').isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _infoCard('¿Por qué soy cuidador?', _caregiver!['whyCaregiver'] as String, Icons.favorite_outline, GardenColors.error, surface, textColor, subtextColor, borderColor),
                        ],
                        if ((_caregiver!['whatDiffers'] as String? ?? '').isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _infoCard('¿Qué me diferencia?', _caregiver!['whatDiffers'] as String, Icons.star_outline_rounded, GardenColors.star, surface, textColor, subtextColor, borderColor),
                        ],

                        const SizedBox(height: 32),
                        Divider(color: borderColor),
                        const SizedBox(height: 28),

                        // Políticas de mascotas
                        Text('Políticas de cuidado', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 14),
                        if ((_caregiver!['sizesAccepted'] as List? ?? []).isNotEmpty) ...[
                          Text('Tamaños aceptados', style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8, runSpacing: 6,
                            children: {
                              'PEQUEÑO': '🐾 Pequeño',
                              'MEDIANO': '🐕 Mediano',
                              'GRANDE': '🦮 Grande',
                              'GIGANTE': '🐘 Gigante',
                            }.entries
                              .where((e) => (_caregiver!['sizesAccepted'] as List).contains(e.key))
                              .map((e) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: GardenColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: GardenColors.success.withValues(alpha: 0.3))),
                                child: Text(e.value, style: const TextStyle(color: GardenColors.success, fontSize: 12, fontWeight: FontWeight.w500)),
                              )).toList(),
                          ),
                          const SizedBox(height: 14),
                        ],
                        Wrap(
                          spacing: 8, runSpacing: 8,
                          children: [
                            _policyChip('Cachorros', _caregiver!['acceptPuppies'] == true),
                            _policyChip('Mascotas seniors', _caregiver!['acceptSeniors'] == true),
                            _policyChip('Mascotas agresivas', _caregiver!['acceptAggressive'] == true),
                          ],
                        ),
                        if ((_caregiver!['handleAnxious'] as String? ?? '').isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _infoCard('Mascotas con ansiedad', _caregiver!['handleAnxious'] as String, Icons.psychology_outlined, GardenColors.warning, surface, textColor, subtextColor, borderColor),
                        ],
                        if ((_caregiver!['emergencyResponse'] as String? ?? '').isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _infoCard('Protocolo de emergencias', _caregiver!['emergencyResponse'] as String, Icons.emergency_outlined, GardenColors.error, surface, textColor, subtextColor, borderColor),
                        ],

                        // Mi espacio (solo hospedaje)
                        if (offersHospedaje && (_caregiver!['homeType'] != null || _caregiver!['hasYard'] == true)) ...[
                          const SizedBox(height: 32),
                          Divider(color: borderColor),
                          const SizedBox(height: 28),
                          Text('Mi espacio', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 12),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            if (_caregiver!['homeType'] != null) _spaceChip(_homeTypeLabel(_caregiver!['homeType'] as String), Icons.home_outlined),
                            if (_caregiver!['hasYard'] == true) _spaceChip('Tiene jardín/patio', Icons.grass_outlined),
                          ]),
                        ],

                        // Fotos (con label condicional)
                        if (photos.isNotEmpty) ...[
                          const SizedBox(height: 32),
                          Divider(color: borderColor),
                          const SizedBox(height: 28),
                          Text(offersHospedaje ? 'Fotos del espacio' : 'Fotos del paseador',
                            style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 14),
                          _buildPhotoGrid(photos, borderColor),
                        ],

                        // Reseñas
                        const SizedBox(height: 32),
                        Divider(color: borderColor),
                        const SizedBox(height: 28),
                        _buildReviewsSection(textColor, subtextColor, surface, borderColor),
                        const SizedBox(height: 60),
                      ],
                    ),
                  ),

                  const SizedBox(width: 40),

                  // ── Columna derecha (tarjeta de reserva) ──────
                  SizedBox(
                    width: 360,
                    child: Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: borderColor),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08), blurRadius: 24, offset: const Offset(0, 8))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Servicios y precios
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                                child: Text('Servicios disponibles', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                              ),
                              const SizedBox(height: 12),
                              ...services.map((s) {
                                final isWalk = s == 'PASEO';
                                final price = isWalk ? (pricePerWalk30 ?? pricePerWalk60) : pricePerDay;
                                final unit = isWalk ? (pricePerWalk30 != null ? '/ 30 min' : '/ hora') : '/ noche';
                                return Container(
                                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: GardenColors.primary.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: GardenColors.primary.withValues(alpha: 0.2)),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(isWalk ? '🦮' : '🏠', style: const TextStyle(fontSize: 24)),
                                      const SizedBox(width: 12),
                                      Expanded(child: Text(isWalk ? 'Paseo' : 'Hospedaje', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700))),
                                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                        Text('Bs ${price ?? '—'}', style: const TextStyle(color: GardenColors.primary, fontSize: 18, fontWeight: FontWeight.w800)),
                                        Text(unit, style: TextStyle(color: subtextColor, fontSize: 11)),
                                      ]),
                                    ],
                                  ),
                                );
                              }),
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                                child: SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: GardenColors.primary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      elevation: 0,
                                    ),
                                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                                    label: const Text('Reservar ahora', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                    onPressed: _onReserve,
                                  ),
                                ),
                              ),
                              Divider(height: 1, color: borderColor),
                              // Zona
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(children: [
                                  Icon(Icons.location_on_outlined, size: 16, color: subtextColor),
                                  const SizedBox(width: 8),
                                  Text(_zoneLabel(zone), style: TextStyle(color: subtextColor, fontSize: 13)),
                                ]),
                              ),
                              Divider(height: 1, color: borderColor),
                              // Rating
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(children: [
                                  const Icon(Icons.star_rounded, color: GardenColors.star, size: 16),
                                  const SizedBox(width: 8),
                                  Text('$rating de 5', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w700)),
                                  const SizedBox(width: 4),
                                  if (reviewCount > 0) Text('· $reviewCount reseñas', style: TextStyle(color: subtextColor, fontSize: 12)),
                                ]),
                              ),
                              if (verified) ...[
                                Divider(height: 1, color: borderColor),
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(children: [
                                    const Icon(Icons.verified, color: GardenColors.success, size: 16),
                                    const SizedBox(width: 8),
                                    const Text('Verificado por IA', style: TextStyle(color: GardenColors.success, fontSize: 13, fontWeight: FontWeight.w600)),
                                  ]),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────── NARROW LAYOUT (MOBILE) ──────────────────────────

  Widget _buildNarrowLayout({
    required BuildContext context,
    required bool isDark, required Color bg, required Color surface,
    required Color textColor, required Color subtextColor, required Color borderColor,
    required List<String> photos, required List<String> services, required String name,
    required String rating, required int reviewCount, required String zone,
    required String bio, required String bioDetail, required bool verified,
    required dynamic pricePerWalk60, required dynamic pricePerWalk30, required dynamic pricePerDay,
    required bool offersHospedaje, required bool offersPaseo, required String priceDisplay,
  }) {
    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // Hero foto
              SliverToBoxAdapter(
                child: Stack(
                  children: [
                    SizedBox(
                      width: double.infinity, height: 320,
                      child: photos.isNotEmpty
                          ? GestureDetector(
                              onTap: () => _openPhotoViewer(photos, _selectedPhotoIndex),
                              child: Image.network(fixImageUrl(photos[_selectedPhotoIndex]), fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(color: GardenColors.primary.withValues(alpha: 0.1), child: const Icon(Icons.pets, size: 80, color: GardenColors.primary))),
                            )
                          : Container(color: GardenColors.primary.withValues(alpha: 0.1), child: const Icon(Icons.pets, size: 80, color: GardenColors.primary)),
                    ),
                    Positioned(bottom: 0, left: 0, right: 0,
                      child: Container(height: 120, decoration: BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, bg.withValues(alpha: 0.95)]),
                      ))),
                    Positioned(top: 48, left: 16,
                      child: GestureDetector(onTap: () => context.pop(),
                        child: Container(width: 40, height: 40, decoration: BoxDecoration(color: surface.withValues(alpha: 0.9), shape: BoxShape.circle, boxShadow: GardenShadows.card),
                          child: Icon(Icons.arrow_back, color: textColor, size: 20)))),
                    Positioned(top: 48, right: 16,
                      child: GestureDetector(onTap: _toggleFavorite,
                        child: Container(width: 40, height: 40, decoration: BoxDecoration(color: surface.withValues(alpha: 0.9), shape: BoxShape.circle, boxShadow: GardenShadows.card),
                          child: _isTogglingFavorite
                              ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: GardenColors.primary))
                              : Icon(_isFavorite ? Icons.favorite : Icons.favorite_border, color: _isFavorite ? GardenColors.error : textColor, size: 20)))),
                    if (photos.length > 1)
                      Positioned(bottom: 16, right: 16,
                        child: Row(children: photos.asMap().entries.map((e) {
                          final sel = e.key == _selectedPhotoIndex;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedPhotoIndex = e.key),
                            child: Container(margin: const EdgeInsets.only(left: 6), width: sel ? 32 : 24, height: sel ? 32 : 24,
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: sel ? GardenColors.primary : Colors.white.withValues(alpha: 0.5), width: sel ? 2 : 1)),
                              child: ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(fixImageUrl(e.value), fit: BoxFit.cover))),
                          );
                        }).toList())),
                  ],
                ),
              ),
              // Contenido
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Nombre + rating
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        GardenAvatar(imageUrl: _caregiver!['profilePicture'] as String?, size: 64, initials: '${_caregiver!['firstName']?[0] ?? ''}${_caregiver!['lastName']?[0] ?? ''}'),
                        const SizedBox(width: 16),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(name, style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                              const SizedBox(height: 4),
                              _zoneChip(zone, subtextColor, borderColor, surface),
                            ])),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Row(children: [
                                const Icon(Icons.star_rounded, color: GardenColors.star, size: 18),
                                const SizedBox(width: 4),
                                Text(rating, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w800)),
                              ]),
                              if (reviewCount > 0) Text('$reviewCount reseñas', style: TextStyle(color: subtextColor, fontSize: 11)),
                            ]),
                          ]),
                        ])),
                      ]),
                      const SizedBox(height: 16),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        if (verified) _verifiedBadge(),
                        _polygonBadge(),
                        if (_caregiver!['zone'] == 'EQUIPETROL')
                          TemporadaAltaBadge(zona: 'Equipetrol', porcentajeAjuste: 15, motivo: 'Semana Santa', fechaVueltaNormal: '24 de marzo', agentesService: AgentesService(authToken: '')),
                      ]),
                      const SizedBox(height: 16),
                      _buildTrustBadges(subtextColor),
                      const SizedBox(height: 24),
                      Divider(color: borderColor),
                      const SizedBox(height: 20),
                      // Servicios
                      Text('Servicios', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      Row(children: services.map((s) {
                        final isWalk = s == 'PASEO';
                        return Expanded(child: Container(
                          margin: EdgeInsets.only(right: services.last != s ? 12 : 0),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(isWalk ? '🦮' : '🏠', style: const TextStyle(fontSize: 28)),
                            const SizedBox(height: 8),
                            Text(isWalk ? 'Paseo' : 'Hospedaje', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            if (isWalk)
                              Text('Bs ${pricePerWalk30 ?? pricePerWalk60 ?? '—'} / ${pricePerWalk30 != null ? '30 min' : '1 hora'}', style: const TextStyle(color: GardenColors.primary, fontSize: 13, fontWeight: FontWeight.w600))
                            else
                              Text('Bs ${pricePerDay ?? '—'} / noche', style: const TextStyle(color: GardenColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                          ]),
                        ));
                      }).toList()),
                      const SizedBox(height: 24),
                      Divider(color: borderColor),
                      const SizedBox(height: 20),
                      // Bio
                      Text('Sobre ${_caregiver!['firstName']}', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      if (bio.isNotEmpty) Text(bio, style: TextStyle(color: subtextColor, fontSize: 15, height: 1.6)),
                      if (bioDetail.isNotEmpty) ...[const SizedBox(height: 10), Text(bioDetail, style: TextStyle(color: subtextColor, fontSize: 15, height: 1.6))],
                      const SizedBox(height: 24),
                      // Experiencia
                      if (_caregiver!['experienceYears'] != null) ...[
                        Divider(color: borderColor), const SizedBox(height: 20),
                        Text('Experiencia', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(color: GardenColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: GardenColors.primary.withValues(alpha: 0.3))),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.workspace_premium_outlined, color: GardenColors.primary, size: 16),
                            const SizedBox(width: 6),
                            Text('${_caregiver!['experienceYears']} años de experiencia', style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                          ]),
                        ),
                        if ((_caregiver!['experienceDescription'] as String? ?? '').isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(_caregiver!['experienceDescription'] as String, style: TextStyle(color: subtextColor, fontSize: 14, height: 1.6)),
                        ],
                      ],
                      if ((_caregiver!['whyCaregiver'] as String? ?? '').isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _infoCard('¿Por qué soy cuidador?', _caregiver!['whyCaregiver'] as String, Icons.favorite_outline, GardenColors.error, surface, textColor, subtextColor, borderColor),
                      ],
                      if ((_caregiver!['whatDiffers'] as String? ?? '').isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _infoCard('¿Qué me diferencia?', _caregiver!['whatDiffers'] as String, Icons.star_outline_rounded, GardenColors.star, surface, textColor, subtextColor, borderColor),
                      ],
                      Divider(color: borderColor), const SizedBox(height: 20),
                      Text('Políticas de cuidado', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      if ((_caregiver!['sizesAccepted'] as List? ?? []).isNotEmpty) ...[
                        Text('Tamaños aceptados', style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 6, children: {
                          'PEQUEÑO': '🐾 Pequeño', 'MEDIANO': '🐕 Mediano', 'GRANDE': '🦮 Grande', 'GIGANTE': '🐘 Gigante',
                        }.entries.where((e) => (_caregiver!['sizesAccepted'] as List).contains(e.key)).map((e) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: GardenColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: GardenColors.success.withValues(alpha: 0.3))),
                          child: Text(e.value, style: const TextStyle(color: GardenColors.success, fontSize: 12, fontWeight: FontWeight.w500)),
                        )).toList()),
                        const SizedBox(height: 16),
                      ],
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        _policyChip('Cachorros', _caregiver!['acceptPuppies'] == true),
                        _policyChip('Mascotas seniors', _caregiver!['acceptSeniors'] == true),
                        _policyChip('Mascotas agresivas', _caregiver!['acceptAggressive'] == true),
                      ]),
                      if ((_caregiver!['handleAnxious'] as String? ?? '').isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _infoCard('Mascotas con ansiedad', _caregiver!['handleAnxious'] as String, Icons.psychology_outlined, GardenColors.warning, surface, textColor, subtextColor, borderColor),
                      ],
                      if ((_caregiver!['emergencyResponse'] as String? ?? '').isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _infoCard('Protocolo de emergencias', _caregiver!['emergencyResponse'] as String, Icons.emergency_outlined, GardenColors.error, surface, textColor, subtextColor, borderColor),
                      ],
                      if (offersHospedaje && (_caregiver!['homeType'] != null || _caregiver!['hasYard'] == true)) ...[
                        Divider(color: borderColor), const SizedBox(height: 20),
                        Text('Mi espacio', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          if (_caregiver!['homeType'] != null) _spaceChip(_homeTypeLabel(_caregiver!['homeType'] as String), Icons.home_outlined),
                          if (_caregiver!['hasYard'] == true) _spaceChip('Tiene jardín/patio', Icons.grass_outlined),
                        ]),
                      ],
                      const SizedBox(height: 24),
                      if (photos.isNotEmpty) ...[
                        Divider(color: borderColor), const SizedBox(height: 20),
                        Text(offersHospedaje ? 'Fotos del espacio' : 'Fotos del paseador',
                          style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 110,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: photos.length,
                            itemBuilder: (_, index) => GestureDetector(
                              onTap: () => _openPhotoViewer(photos, index),
                              child: Container(
                                margin: const EdgeInsets.only(right: 10),
                                width: 130,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _selectedPhotoIndex == index ? GardenColors.primary : borderColor, width: _selectedPhotoIndex == index ? 2 : 1),
                                ),
                                child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(fixImageUrl(photos[index]), fit: BoxFit.cover)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Divider(color: borderColor),
                        const SizedBox(height: 20),
                      ],
                      Divider(color: borderColor), const SizedBox(height: 20),
                      _buildReviewsSection(textColor, subtextColor, surface, borderColor),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Botón sticky abajo (solo mobile)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: BoxDecoration(
                color: bg,
                border: Border(top: BorderSide(color: borderColor, width: 1)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08), blurRadius: 20, offset: const Offset(0, -4))],
              ),
              child: Row(children: [
                // Solo muestra precio si ofrece UN solo servicio
                if (!(offersHospedaje && offersPaseo)) ...[
                  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(priceDisplay, style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
                    Text('precio por servicio', style: TextStyle(color: subtextColor, fontSize: 12)),
                  ]),
                  const SizedBox(width: 20),
                ],
                Expanded(child: GardenButton(label: 'Reservar ahora', icon: Icons.calendar_today_outlined, onPressed: _onReserve)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────── SHARED HELPERS ───────────────────────────────────

  Widget _buildPhotoGrid(List<String> photos, Color borderColor) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
      itemCount: photos.length,
      itemBuilder: (_, index) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
        onTap: () => _openPhotoViewer(photos, index),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(fit: StackFit.expand, children: [
              Image.network(fixImageUrl(photos[index]), fit: BoxFit.cover),
              // Hover overlay con ícono de zoom
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _openPhotoViewer(photos, index),
                  hoverColor: Colors.black.withValues(alpha: 0.2),
                  child: const Align(alignment: Alignment.center, child: Icon(Icons.zoom_in, color: Colors.transparent, size: 28)),
                ),
              ),
            ]),
          ),
        )),
      ),
    );
  }

  Widget _zoneChip(String zone, Color subtextColor, Color borderColor, Color surface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: borderColor)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.location_on_outlined, size: 12, color: subtextColor),
        const SizedBox(width: 4),
        Text(_zoneLabel(zone), style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  String _zoneLabel(String zone) {
    const labels = {
      'EQUIPETROL': 'Equipetrol',
      'URBARI': 'Urbari',
      'NORTE': 'Norte',
      'LAS_PALMAS': 'Las Palmas',
      'CENTRO': 'Centro',
      'CENTRO_SAN_MARTIN': 'Centro / San Martín',
      'REMANZO': 'Remanzo',
      'SUR': 'Sur',
      'URUBO_NORTE': 'Urubo Norte',
      'URUBO_SUR': 'Urubo Sur',
      'OTROS': 'Otros',
    };
    return labels[zone] ?? zone.replaceAll('_', ' ');
  }

  Widget _verifiedBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: GardenColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: GardenColors.success.withValues(alpha: 0.4))),
    child: const Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.verified, color: GardenColors.success, size: 14),
      SizedBox(width: 6),
      Text('Verificado por IA', style: TextStyle(color: GardenColors.success, fontSize: 12, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _polygonBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: GardenColors.polygon.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: GardenColors.polygon.withValues(alpha: 0.4))),
    child: const Row(mainAxisSize: MainAxisSize.min, children: [
      Text('⬡', style: TextStyle(color: GardenColors.polygon, fontSize: 12)),
      SizedBox(width: 6),
      Text('Polygon Amoy', style: TextStyle(color: GardenColors.polygon, fontSize: 12, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _buildTrustBadges(Color subtextColor) {
    if (_caregiver == null) return const SizedBox.shrink();
    final ratingNum = (_caregiver!['rating'] as num? ?? 0).toDouble();
    final reviewCount = _caregiver!['reviewCount'] as int? ?? 0;
    final verified = _caregiver!['verified'] == true;
    final experienceYears = _caregiver!['experienceYears'] as int? ?? 0;
    final sizesAccepted = (_caregiver!['sizesAccepted'] as List? ?? []);
    final hasYard = _caregiver!['hasYard'] == true;
    final acceptPuppies = _caregiver!['acceptPuppies'] == true;
    final acceptSeniors = _caregiver!['acceptSeniors'] == true;

    final badges = <Map<String, dynamic>>[];
    if (reviewCount >= 10) badges.add({'icon': '🏆', 'label': '${reviewCount}+ reseñas', 'color': GardenColors.star});
    if (ratingNum >= 4.8) badges.add({'icon': '⭐', 'label': 'Top rated', 'color': GardenColors.star});
    if (verified) badges.add({'icon': '✓', 'label': 'Verificado IA', 'color': GardenColors.success});
    if (experienceYears >= 3) badges.add({'icon': '🎖️', 'label': '$experienceYears años exp.', 'color': GardenColors.secondary});
    if (sizesAccepted.length >= 4) badges.add({'icon': '🐘', 'label': 'Todos los tamaños', 'color': GardenColors.primary});
    if (hasYard) badges.add({'icon': '🌿', 'label': 'Tiene jardín', 'color': GardenColors.success});
    if (acceptPuppies && acceptSeniors) badges.add({'icon': '🐾', 'label': 'Cachorros y seniors', 'color': GardenColors.primary});
    if (badges.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: badges.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final b = badges[i];
          final color = b['color'] as Color;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.30))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(b['icon'] as String, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 5),
              Text(b['label'] as String, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          );
        },
      ),
    );
  }

  Widget _buildReviewsSection(Color textColor, Color subtextColor, Color surface, Color borderColor) {
    final reviews = (_caregiver!['reviews'] as List?) ?? [];
    final rating = (_caregiver!['rating'] as num? ?? 0).toDouble();
    final reviewCount = _caregiver!['reviewCount'] as int? ?? 0;
    final firstName = _caregiver!['firstName'] as String? ?? 'este cuidador';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text('Lo que dicen los dueños', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (reviewCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: GardenColors.star.withValues(alpha: 0.12), borderRadius: GardenRadius.full_, border: Border.all(color: GardenColors.star.withValues(alpha: 0.3))),
              child: Text('$reviewCount reseñas', style: const TextStyle(color: GardenColors.star, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
        ]),
        if (reviewCount > 0) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(color: GardenColors.star.withValues(alpha: 0.06), borderRadius: GardenRadius.lg_, border: Border.all(color: GardenColors.star.withValues(alpha: 0.2))),
            child: Row(children: [
              Text(rating.toStringAsFixed(1), style: const TextStyle(color: GardenColors.star, fontSize: 48, fontWeight: FontWeight.w800, height: 1, letterSpacing: -1)),
              const SizedBox(width: 16),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: List.generate(5, (i) {
                  final filled = i < rating.floor();
                  final half = !filled && i < rating;
                  return Icon(half ? Icons.star_half_rounded : (filled ? Icons.star_rounded : Icons.star_outline_rounded), color: GardenColors.star, size: 22);
                })),
                const SizedBox(height: 4),
                Text('Calificación promedio', style: TextStyle(color: subtextColor, fontSize: 12)),
                Text('Basado en $reviewCount ${reviewCount == 1 ? "reseña" : "reseñas"}', style: TextStyle(color: subtextColor, fontSize: 11)),
              ]),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        if (reviews.isEmpty)
          GardenEmptyState(type: GardenEmptyType.reviews, title: 'Sin reseñas todavía', subtitle: 'Sé el primero en reservar con $firstName y dejar una opinión.', compact: true)
        else ...[
          ...() {
            final visible = _showAllReviews ? reviews : reviews.take(5).toList();
            return visible.map((r) => _buildReviewCard(r, textColor, subtextColor, surface, borderColor));
          }(),
          if (reviews.length > 5) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _showAllReviews = !_showAllReviews),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: surface, borderRadius: GardenRadius.md_, border: Border.all(color: borderColor)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(_showAllReviews ? 'Mostrar menos' : 'Ver todas las reseñas (${reviews.length})', style: const TextStyle(color: GardenColors.primary, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  Icon(_showAllReviews ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: GardenColors.primary, size: 18),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  Widget _buildReviewCard(dynamic r, Color textColor, Color subtextColor, Color surface, Color borderColor) {
    final clientName = r['clientName'] as String? ?? 'Anónimo';
    final initial = clientName.isNotEmpty ? clientName[0].toUpperCase() : '?';
    final rating = (r['rating'] as num? ?? 0).toInt();
    final comment = r['comment'] as String?;
    final petName = r['petName'] as String?;
    final serviceType = r['serviceType'] as String?;
    final createdAt = r['createdAt'] != null ? _formatDate(r['createdAt'].toString()) : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: surface, borderRadius: GardenRadius.lg_, border: Border.all(color: borderColor)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: GardenColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle, border: Border.all(color: GardenColors.primary.withValues(alpha: 0.25))),
            child: Center(child: Text(initial, style: const TextStyle(color: GardenColors.primary, fontSize: 16, fontWeight: FontWeight.w700))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(clientName, style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 2),
            Row(children: [
              ...List.generate(5, (i) => Icon(i < rating ? Icons.star_rounded : Icons.star_outline_rounded, color: GardenColors.star, size: 13)),
              const SizedBox(width: 8),
              Text(createdAt, style: TextStyle(color: subtextColor, fontSize: 11)),
            ]),
          ])),
        ]),
        if (petName != null || serviceType != null) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, children: [
            if (petName != null) _reviewChip('🐾 $petName', subtextColor, borderColor, surface),
            if (serviceType != null) _reviewChip(serviceType == 'PASEO' ? '🦮 Paseo' : '🏠 Hospedaje', subtextColor, borderColor, surface),
          ]),
        ],
        if (comment != null && comment.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('"$comment"', style: TextStyle(color: subtextColor, fontSize: 14, height: 1.55, fontStyle: FontStyle.italic)),
        ],
      ]),
    );
  }

  Widget _reviewChip(String label, Color subtextColor, Color borderColor, Color surface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: surface, borderRadius: GardenRadius.full_, border: Border.all(color: borderColor)),
      child: Text(label, style: TextStyle(color: subtextColor, fontSize: 11)),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) { return iso.length >= 10 ? iso.substring(0, 10) : iso; }
  }

  Widget _infoCard(String title, String content, IconData icon, Color color, Color surface, Color textColor, Color subtextColor, Color borderColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 4),
          Text(content, style: TextStyle(color: subtextColor, fontSize: 13, height: 1.5)),
        ])),
      ]),
    );
  }

  Widget _policyChip(String label, bool accepted) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: accepted ? GardenColors.success.withValues(alpha: 0.1) : GardenColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accepted ? GardenColors.success.withValues(alpha: 0.3) : GardenColors.error.withValues(alpha: 0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(accepted ? Icons.check_circle_outline : Icons.cancel_outlined, size: 13, color: accepted ? GardenColors.success : GardenColors.error),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: accepted ? GardenColors.success : GardenColors.error, fontSize: 12, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _spaceChip(String label, IconData icon) {
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: borderColor)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: subtextColor),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: subtextColor, fontSize: 12)),
      ]),
    );
  }

  String _homeTypeLabel(String type) {
    const labels = {'CASA': '🏠 Casa', 'APARTAMENTO': '🏢 Apartamento', 'APARTMENT': '🏢 Apartamento', 'HOUSE': '🏠 Casa', 'FINCA': '🌾 Finca', 'LOCAL': '🏪 Local'};
    return labels[type] ?? type;
  }
}

// ── Lightbox para ver fotos en pantalla completa ─────────────────────────────

class _PhotoLightbox extends StatefulWidget {
  final List<String> photos;
  final int initialIndex;
  const _PhotoLightbox({required this.photos, required this.initialIndex});

  @override
  State<_PhotoLightbox> createState() => _PhotoLightboxState();
}

class _PhotoLightboxState extends State<_PhotoLightbox> {
  late int _index;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          // Fondo oscuro
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(color: Colors.black87),
          ),
          // Foto con swipe
          PageView.builder(
            controller: _pageController,
            itemCount: widget.photos.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 60),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    fixImageUrl(widget.photos[i]),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 80),
                  ),
                ),
              ),
            ),
          ),
          // Botón cerrar
          Positioned(
            top: 20, right: 20,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
                child: const Icon(Icons.close, color: Colors.white, size: 20),
              ),
            ),
          ),
          // Flecha izquierda
          if (_index > 0)
            Positioned(
              left: 16, top: 0, bottom: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () { _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); },
                  child: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
                    child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ),
          // Flecha derecha
          if (_index < widget.photos.length - 1)
            Positioned(
              right: 16, top: 0, bottom: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () { _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); },
                  child: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
                    child: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ),
          // Contador de fotos
          Positioned(
            bottom: 24, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                child: Text('${_index + 1} / ${widget.photos.length}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helper widget for service selector bottom sheet ──────────────────────────

class _ServiceOption extends StatelessWidget {
  const _ServiceOption({required this.icon, required this.label, required this.sublabel, required this.onTap});
  final IconData icon;
  final String label;
  final String sublabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAF8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: GardenColors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: GardenColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(icon, color: GardenColors.primary, size: 22)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1A1A1A), fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(sublabel, style: const TextStyle(color: GardenColors.primary, fontSize: 14, fontWeight: FontWeight.w600)),
          ])),
          Icon(Icons.arrow_forward_ios, size: 16, color: GardenColors.primary.withValues(alpha: 0.7)),
        ]),
      ),
    );
  }
}
