import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';
import '../../widgets/temporada_alta_badge.dart';
import '../../services/agentes_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CaregiverProfileScreen extends StatefulWidget {
  final String caregiverId;
  const CaregiverProfileScreen({Key? key, required this.caregiverId}) : super(key: key);

  @override
  State<CaregiverProfileScreen> createState() => _CaregiverProfileScreenState();
}

class _CaregiverProfileScreenState extends State<CaregiverProfileScreen> {
  Map<String, dynamic>? _caregiver;
  bool _isLoading = true;
  int _selectedPhotoIndex = 0;
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
    } catch (_) {} finally {
      if (mounted) setState(() => _isLoading = false);
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
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.verified, color: GardenColors.success, size: 14),
                                const SizedBox(width: 6),
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
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Text('⬡', style: TextStyle(color: GardenColors.polygon, fontSize: 12)),
                              const SizedBox(width: 6),
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
                                    style: TextStyle(color: GardenColors.primary, fontSize: 14, fontWeight: FontWeight.w600),
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
}
