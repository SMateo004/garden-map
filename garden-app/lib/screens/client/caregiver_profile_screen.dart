import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/garden_empty_state.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';
import '../../widgets/temporada_alta_badge.dart';
import '../../services/agentes_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CaregiverProfileScreen extends StatefulWidget {
  final String caregiverId;
  const CaregiverProfileScreen({super.key, required this.caregiverId});

  @override
  State<CaregiverProfileScreen> createState() => _CaregiverProfileScreenState();
}

class _CaregiverProfileScreenState extends State<CaregiverProfileScreen> {
  Map<String, dynamic>? _caregiver;
  bool _isLoading = true;
  int _selectedPhotoIndex = 0;
  bool _showAllReviews = false;
  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api');

  @override
  void initState() {
    super.initState();
    _loadCaregiver();
  }

  Future<void> _loadCaregiver() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/caregivers/${widget.caregiverId}'));
      final data = jsonDecode(response.body);
      if (data['success'] == true) setState(() => _caregiver = data['data']);
      await _loadFavoriteStatus();
    } catch (_) {} finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isFavorite = false;
  bool _isTogglingFavorite = false;

  Future<void> _loadFavoriteStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      if (token.isEmpty) return;

      final response = await http.get(
        Uri.parse('$_baseUrl/client/my-profile'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final favorites = (data['data']['favoriteCaregiverIds'] as List?)?.cast<String>() ?? [];
        if (mounted) {
          setState(() {
            _isFavorite = favorites.contains(widget.caregiverId);
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _toggleFavorite() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token') ?? '';
    if (token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inicia sesión para guardar favoritos'),
          backgroundColor: GardenColors.primary,
          duration: Duration(seconds: 2),
        ),
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
      if (data['success'] == true) {
        if (mounted) {
          setState(() {
            _isFavorite = data['data']['isFavorite'] == true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_isFavorite ? 'Agregado a favoritos' : 'Eliminado de favoritos'),
              backgroundColor: _isFavorite ? GardenColors.success : GardenColors.darkSurface,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _isTogglingFavorite = false);
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

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bg,
        body: const Center(child: CircularProgressIndicator(color: GardenColors.primary)),
      );
    }

    if (_caregiver == null) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(backgroundColor: surface),
        body: Center(child: Text('Cuidador no encontrado', style: TextStyle(color: textColor))),
      );
    }

    final photos = (_caregiver!['photos'] as List?)?.cast<String>() ?? [];
    final services = (_caregiver!['services'] as List?)?.cast<String>() ?? [];
    final name = '${_caregiver!['firstName']} ${_caregiver!['lastName']}';
    final rating = (_caregiver!['rating'] as num? ?? 0).toStringAsFixed(1);
    final reviewCount = _caregiver!['reviewCount'] as int? ?? 0;
    final zone = _caregiver!['zone'] as String? ?? '';
    final bio = _caregiver!['bio'] as String? ?? '';
    final verified = _caregiver!['verified'] == true;
    final pricePerWalk = _caregiver!['pricePerWalk30'];
    final pricePerDay = _caregiver!['pricePerDay'];
    final priceDisplay = pricePerWalk != null ? 'Bs $pricePerWalk/paseo' : pricePerDay != null ? 'Bs $pricePerDay/noche' : 'Consultar';

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          // Contenido scrollable
          CustomScrollView(
            slivers: [
              // ── GALERÍA DE FOTOS ────────────────────────────
              SliverToBoxAdapter(
                child: Stack(
                  children: [
                    // Foto principal
                    SizedBox(
                      width: double.infinity,
                      height: 320,
                      child: photos.isNotEmpty
                          ? Image.network(
                              photos[_selectedPhotoIndex],
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: GardenColors.primary.withOpacity(0.1),
                                child: const Icon(Icons.pets, size: 80, color: GardenColors.primary),
                              ),
                            )
                          : Container(
                              color: GardenColors.primary.withOpacity(0.1),
                              child: const Icon(Icons.pets, size: 80, color: GardenColors.primary),
                            ),
                    ),
                    // Gradiente inferior sobre la foto
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: Container(
                        height: 120,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, bg.withOpacity(0.95)],
                          ),
                        ),
                      ),
                    ),
                    // Botón atrás
                    Positioned(
                      top: 48, left: 16,
                      child: GestureDetector(
                        onTap: () => context.pop(),
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: surface.withOpacity(0.9),
                            shape: BoxShape.circle,
                            boxShadow: GardenShadows.card,
                          ),
                          child: Icon(Icons.arrow_back, color: textColor, size: 20),
                        ),
                      ),
                    ),
                    // Botón favorito
                    Positioned(
                      top: 48, right: 16,
                      child: GestureDetector(
                        onTap: () => _toggleFavorite(),
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: surface.withOpacity(0.9),
                            shape: BoxShape.circle,
                            boxShadow: GardenShadows.card,
                          ),
                          child: _isTogglingFavorite 
                              ? const Padding(
                                  padding: EdgeInsets.all(12), 
                                  child: CircularProgressIndicator(strokeWidth: 2, color: GardenColors.primary)
                                )
                              : Icon(
                                  _isFavorite ? Icons.favorite : Icons.favorite_border, 
                                  color: _isFavorite ? GardenColors.error : textColor, 
                                  size: 20
                                ),
                        ),
                      ),
                    ),
                    // Miniaturas de fotos
                    if (photos.length > 1)
                      Positioned(
                        bottom: 16, right: 16,
                        child: Row(
                          children: photos.asMap().entries.map((e) {
                            final selected = e.key == _selectedPhotoIndex;
                            return GestureDetector(
                              onTap: () => setState(() => _selectedPhotoIndex = e.key),
                              child: Container(
                                margin: const EdgeInsets.only(left: 6),
                                width: selected ? 32 : 24,
                                height: selected ? 32 : 24,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: selected ? GardenColors.primary : Colors.white.withOpacity(0.5),
                                    width: selected ? 2 : 1,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.network(e.value, fit: BoxFit.cover),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),

              // ── INFO PRINCIPAL ──────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Nombre y rating
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Avatar del cuidador
                          GardenAvatar(
                            imageUrl: _caregiver!['profilePicture'] as String?,
                            size: 64,
                            initials: '${_caregiver!['firstName']?[0] ?? ''}${_caregiver!['lastName']?[0] ?? ''}',
                          ),
                          const SizedBox(width: 16),
                          // Nombre, zona y rating
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(name, style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(Icons.location_on_outlined, size: 13, color: subtextColor),
                                              const SizedBox(width: 3),
                                              Text(zone, style: TextStyle(color: subtextColor, fontSize: 13)),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.star_rounded, color: GardenColors.star, size: 18),
                                            const SizedBox(width: 4),
                                            Text(rating, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w800)),
                                          ],
                                        ),
                                        if (reviewCount > 0)
                                          Text('$reviewCount reseñas', style: TextStyle(color: subtextColor, fontSize: 11)),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Badges verificado + blockchain
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: [
                          if (verified)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: GardenColors.success.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: GardenColors.success.withOpacity(0.4)),
                              ),
                              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.verified, color: GardenColors.success, size: 14),
                                SizedBox(width: 6),
                                Text('Verificado por IA', style: TextStyle(color: GardenColors.success, fontSize: 12, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: GardenColors.polygon.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: GardenColors.polygon.withOpacity(0.4)),
                            ),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Text('⬡', style: TextStyle(color: GardenColors.polygon, fontSize: 12)),
                              SizedBox(width: 6),
                              Text('Polygon Amoy', style: TextStyle(color: GardenColors.polygon, fontSize: 12, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                          if (_caregiver!['zone'] == 'EQUIPETROL')
                            TemporadaAltaBadge(
                              zona: 'Equipetrol', porcentajeAjuste: 15,
                              motivo: 'Semana Santa', fechaVueltaNormal: '24 de marzo',
                              agentesService: AgentesService(authToken: ''),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── TRUST BADGES ─────────────────────────
                      _buildTrustBadges(subtextColor),
                      const SizedBox(height: 24),

                      // Divisor
                      Divider(color: borderColor),
                      const SizedBox(height: 20),

                      // Servicios
                      Text('Servicios', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      Row(
                        children: services.map((s) {
                          final isWalk = s == 'PASEO';
                          return Expanded(
                            child: Container(
                              margin: EdgeInsets.only(right: services.last != s ? 12 : 0),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(isWalk ? '🦮' : '🏠', style: const TextStyle(fontSize: 28)),
                                  const SizedBox(height: 8),
                                  Text(isWalk ? 'Paseo' : 'Hospedaje',
                                    style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text(
                                    isWalk
                                      ? 'Bs ${pricePerWalk ?? '—'} / 30 min'
                                      : 'Bs ${pricePerDay ?? '—'} / noche',
                                    style: const TextStyle(color: GardenColors.primary, fontSize: 14, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),

                      Divider(color: borderColor),
                      const SizedBox(height: 20),

                      // Bio
                      Text('Sobre ${_caregiver!['firstName']}',
                        style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      Text(bio, style: TextStyle(color: subtextColor, fontSize: 15, height: 1.6)),
                      const SizedBox(height: 24),

                      // ── EXPERIENCIA Y PERFIL PROFESIONAL ──
                      if (_caregiver!['experienceYears'] != null) ...[
                        Divider(color: borderColor),
                        const SizedBox(height: 20),
                        Text('Experiencia', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: GardenColors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: GardenColors.primary.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.workspace_premium_outlined, color: GardenColors.primary, size: 16),
                                  const SizedBox(width: 6),
                                  Text('${_caregiver!['experienceYears']} años de experiencia',
                                    style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (_caregiver!['experienceDescription'] != null && (_caregiver!['experienceDescription'] as String).isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(_caregiver!['experienceDescription'] as String,
                            style: TextStyle(color: subtextColor, fontSize: 14, height: 1.6)),
                        ],
                      ],

                      // ── POR QUÉ SER CUIDADOR ──
                      if (_caregiver!['whyCaregiver'] != null && (_caregiver!['whyCaregiver'] as String).isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _infoCard('¿Por qué soy cuidador?', _caregiver!['whyCaregiver'] as String, Icons.favorite_outline, GardenColors.error, surface, textColor, subtextColor, borderColor),
                      ],

                      // ── QUÉ LO DIFERENCIA ──
                      if (_caregiver!['whatDiffers'] != null && (_caregiver!['whatDiffers'] as String).isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _infoCard('¿Qué me diferencia?', _caregiver!['whatDiffers'] as String, Icons.star_outline_rounded, GardenColors.star, surface, textColor, subtextColor, borderColor),
                      ],

                      // ── POLÍTICAS DE MASCOTAS ──
                      Divider(color: borderColor),
                      const SizedBox(height: 20),
                      Text('Políticas de cuidado', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),

                      // Tamaños aceptados
                      if ((_caregiver!['sizesAccepted'] as List? ?? []).isNotEmpty) ...[
                        Text('Tamaños aceptados', style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
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
                              decoration: BoxDecoration(
                                color: GardenColors.success.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: GardenColors.success.withOpacity(0.3)),
                              ),
                              child: Text(e.value, style: const TextStyle(color: GardenColors.success, fontSize: 12, fontWeight: FontWeight.w500)),
                            )).toList(),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Acepta/No acepta
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: [
                          _policyChip('Cachorros', _caregiver!['acceptPuppies'] == true),
                          _policyChip('Mascotas seniors', _caregiver!['acceptSeniors'] == true),
                          _policyChip('Mascotas agresivas', _caregiver!['acceptAggressive'] == true),
                        ],
                      ),

                      // ── SITUACIONES ESPECIALES ──
                      if (_caregiver!['handleAnxious'] != null && (_caregiver!['handleAnxious'] as String).isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _infoCard('Mascotas con ansiedad', _caregiver!['handleAnxious'] as String, Icons.psychology_outlined, GardenColors.warning, surface, textColor, subtextColor, borderColor),
                      ],
                      if (_caregiver!['emergencyResponse'] != null && (_caregiver!['emergencyResponse'] as String).isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _infoCard('Protocolo de emergencias', _caregiver!['emergencyResponse'] as String, Icons.emergency_outlined, GardenColors.error, surface, textColor, subtextColor, borderColor),
                      ],

                      // ── MI ESPACIO ──
                      if (_caregiver!['homeType'] != null || _caregiver!['hasYard'] == true) ...[
                        Divider(color: borderColor),
                        const SizedBox(height: 20),
                        Text('Mi espacio', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8, runSpacing: 8,
                          children: [
                            if (_caregiver!['homeType'] != null)
                              _spaceChip(_homeTypeLabel(_caregiver!['homeType'] as String), Icons.home_outlined),
                            if (_caregiver!['hasYard'] == true)
                              _spaceChip('Tiene jardín/patio', Icons.grass_outlined),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),

                      Divider(color: borderColor),
                      const SizedBox(height: 20),

                      // Fotos del espacio
                      if (photos.isNotEmpty) ...[
                        Text('Fotos del espacio',
                          style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 120,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: photos.length,
                            itemBuilder: (context, index) => GestureDetector(
                              onTap: () => setState(() => _selectedPhotoIndex = index),
                              child: Container(
                                margin: const EdgeInsets.only(right: 10),
                                width: 140,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _selectedPhotoIndex == index ? GardenColors.primary : borderColor,
                                    width: _selectedPhotoIndex == index ? 2 : 1,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(photos[index], fit: BoxFit.cover),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Divider(color: borderColor),
                        const SizedBox(height: 20),
                      ],

                      // ── SECCIÓN RESEÑAS ─────────────────────
                      Divider(color: borderColor),
                      const SizedBox(height: 20),
                      _buildReviewsSection(textColor, subtextColor, surface, borderColor),

                      // Espacio para el botón sticky
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── BOTÓN RESERVAR STICKY ───────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: BoxDecoration(
                color: bg,
                border: Border(top: BorderSide(color: borderColor, width: 1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Precio
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(priceDisplay,
                        style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
                      Text('precio por servicio',
                        style: TextStyle(color: subtextColor, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(width: 20),
                  // Botón reservar
                  Expanded(
                    child: GardenButton(
                      label: 'Reservar ahora',
                      icon: Icons.calendar_today_outlined,
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        final token = prefs.getString('access_token') ?? '';
                        if (token.isEmpty) {
                          // No hay sesión, ir al login
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Inicia sesión para hacer una reserva'),
                              backgroundColor: GardenColors.primary,
                              duration: Duration(seconds: 2),
                            ),
                          );
                          await Future.delayed(const Duration(seconds: 1));
                          if (!mounted) return;
                          context.push('/login');
                        } else {
                          context.push('/booking/${widget.caregiverId}');
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── SECCIÓN DE RESEÑAS COMPLETA ─────────────────────────────────────────
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
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.30)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(b['icon'] as String, style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 5),
                Text(b['label'] as String,
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
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
        // ── Encabezado ──────────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Lo que dicen los dueños',
              style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            if (reviewCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: GardenColors.star.withValues(alpha: 0.12),
                  borderRadius: GardenRadius.full_,
                  border: Border.all(color: GardenColors.star.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '$reviewCount reseñas',
                  style: const TextStyle(color: GardenColors.star, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),

        // ── Calificación promedio grande ─────────────────────────
        if (reviewCount > 0) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: GardenColors.star.withValues(alpha: 0.06),
              borderRadius: GardenRadius.lg_,
              border: Border.all(color: GardenColors.star.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                // Número grande
                Text(
                  rating.toStringAsFixed(1),
                  style: const TextStyle(
                    color: GardenColors.star,
                    fontSize: 48,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Estrellas
                    Row(
                      children: List.generate(5, (i) {
                        final filled = i < rating.floor();
                        final half = !filled && i < rating;
                        return Icon(
                          half ? Icons.star_half_rounded : (filled ? Icons.star_rounded : Icons.star_outline_rounded),
                          color: GardenColors.star,
                          size: 22,
                        );
                      }),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Calificación promedio',
                      style: TextStyle(color: subtextColor, fontSize: 12),
                    ),
                    Text(
                      'Basado en $reviewCount ${reviewCount == 1 ? "reseña" : "reseñas"}',
                      style: TextStyle(color: subtextColor, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),

        // ── Lista de reseñas o estado vacío ─────────────────────
        if (reviews.isEmpty)
          GardenEmptyState(
            type: GardenEmptyType.reviews,
            title: 'Sin reseñas todavía',
            subtitle: 'Sé el primero en reservar con $firstName y dejar una opinión.',
            compact: true,
          )
        else ...[
          // Reseñas visibles (máx 5)
          ...() {
            final visible = _showAllReviews ? reviews : reviews.take(5).toList();
            return visible.map((r) => _buildReviewCard(r, textColor, subtextColor, surface, borderColor));
          }(),

          // Botón "Ver todas" si hay más de 5
          if (reviews.length > 5) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _showAllReviews = !_showAllReviews),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: GardenRadius.md_,
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _showAllReviews
                          ? 'Mostrar menos'
                          : 'Ver todas las reseñas (${reviews.length})',
                      style: TextStyle(
                        color: GardenColors.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      _showAllReviews ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: GardenColors.primary,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Divider(color: borderColor),
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  Widget _buildReviewCard(
    dynamic r,
    Color textColor,
    Color subtextColor,
    Color surface,
    Color borderColor,
  ) {
    final clientName = r['clientName'] as String? ?? 'Anónimo';
    final initial = clientName.isNotEmpty ? clientName[0].toUpperCase() : '?';
    final rating = (r['rating'] as num? ?? 0).toInt();
    final comment = r['comment'] as String?;
    final petName = r['petName'] as String?;
    final serviceType = r['serviceType'] as String?;
    final createdAt = r['createdAt'] != null
        ? _formatDate(r['createdAt'].toString())
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: GardenRadius.lg_,
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cabecera: avatar + nombre + fecha + rating ─────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar con inicial
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: GardenColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: GardenColors.primary.withValues(alpha: 0.25)),
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: GardenColors.primary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clientName,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        // Estrellas pequeñas
                        ...List.generate(5, (i) => Icon(
                          i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: GardenColors.star,
                          size: 13,
                        )),
                        const SizedBox(width: 8),
                        Text(
                          createdAt,
                          style: TextStyle(color: subtextColor, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Chips: mascota + tipo de servicio ──────────────────
          if (petName != null || serviceType != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [
                if (petName != null)
                  _reviewChip('🐾 $petName', subtextColor, borderColor, surface),
                if (serviceType != null)
                  _reviewChip(
                    serviceType == 'PASEO' ? '🦮 Paseo' : '🏠 Hospedaje',
                    subtextColor,
                    borderColor,
                    surface,
                  ),
              ],
            ),
          ],

          // ── Comentario ──────────────────────────────────────────
          if (comment != null && comment.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '"$comment"',
              style: TextStyle(
                color: subtextColor,
                fontSize: 14,
                height: 1.55,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _reviewChip(String label, Color subtextColor, Color borderColor, Color surface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: GardenRadius.full_,
        border: Border.all(color: borderColor),
      ),
      child: Text(label, style: TextStyle(color: subtextColor, fontSize: 11)),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return iso.length >= 10 ? iso.substring(0, 10) : iso;
    }
  }

  Widget _infoCard(String title, String content, IconData icon, Color color, Color surface, Color textColor, Color subtextColor, Color borderColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 4),
                Text(content, style: TextStyle(color: subtextColor, fontSize: 13, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _policyChip(String label, bool accepted) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: accepted ? GardenColors.success.withOpacity(0.1) : GardenColors.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accepted ? GardenColors.success.withOpacity(0.3) : GardenColors.error.withOpacity(0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(accepted ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: 13, color: accepted ? GardenColors.success : GardenColors.error),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(
            color: accepted ? GardenColors.success : GardenColors.error,
            fontSize: 12, fontWeight: FontWeight.w500,
          )),
        ],
      ),
    );
  }

  Widget _spaceChip(String label, IconData icon) {
    // Usamos el themeNotifier para obtener el tema actual
    final isDark = themeNotifier.isDark;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: subtextColor),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: subtextColor, fontSize: 12)),
        ],
      ),
    );
  }

  String _homeTypeLabel(String type) {
    const labels = {
      'CASA': '🏠 Casa',
      'APARTAMENTO': '🏢 Apartamento',
      'APARTMENT': '🏢 Apartamento',
      'FINCA': '🌾 Finca',
      'LOCAL': '🏪 Local',
    };
    return labels[type] ?? type;
  }
}
