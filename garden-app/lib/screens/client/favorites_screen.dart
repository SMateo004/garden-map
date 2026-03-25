import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<dynamic> _favorites = [];
  bool _isLoading = true;
  String _token = '';
  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api');

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token') ?? '';

    if (token.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    setState(() {
      _token = token;
      _isLoading = true;
    });

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/client/favorites'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true && mounted) {
        setState(() => _favorites = data['data'] as List);
      }
    } catch (e) {
      debugPrint('Error loading favorites: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _removeFavorite(String caregiverId) async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/client/favorites/$caregiverId'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      await _loadFavorites();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(
          'Mis Favoritos',
          style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 20),
        ),
        backgroundColor: bg,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        surfaceTintColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
          : _favorites.isEmpty
              ? _buildEmptyState(textColor, subtextColor)
              : RefreshIndicator(
                  onRefresh: _loadFavorites,
                  color: GardenColors.primary,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: _favorites.length,
                    itemBuilder: (context, index) {
                      final c = _favorites[index];
                      return _buildFavoriteCard(c, surface, textColor, subtextColor, borderColor);
                    },
                  ),
                ),
    );
  }

  Widget _buildFavoriteCard(
    Map<String, dynamic> c,
    Color surface,
    Color textColor,
    Color subtextColor,
    Color borderColor,
  ) {
    final rating = (c['rating'] as num? ?? 0).toStringAsFixed(1);
    final reviewCount = c['reviewCount'] ?? 0;
    final firstName = c['firstName'] ?? '';
    final lastName = c['lastName'] ?? '';
    final zone = c['zone'] ?? '';
    final pricePerWalk = c['pricePerWalk30'];
    final pricePerDay = c['pricePerDay'];
    final verified = c['verified'] == true;
    final profilePicture = c['profilePicture'] as String?;

    return GestureDetector(
      onTap: () => context.push('/caregiver/${c['id']}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: GardenShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Foto
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 8,
                    child: profilePicture != null && profilePicture.isNotEmpty
                        ? Image.network(
                            profilePicture,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _photoPlaceholder(),
                          )
                        : _photoPlaceholder(),
                  ),
                  // Botón quitar de favoritos (esquina superior derecha sobre la foto)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: GestureDetector(
                      onTap: () => _removeFavorite(c['id']),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.45),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.favorite, color: Colors.red, size: 18),
                      ),
                    ),
                  ),
                  // Badge verificado sobre foto
                  if (verified)
                    Positioned(
                      bottom: 10,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: GardenColors.success.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.verified, color: Colors.white, size: 12),
                            SizedBox(width: 4),
                            Text('Verificado', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Info
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$firstName $lastName',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(Icons.location_on_outlined, size: 12, color: subtextColor),
                                const SizedBox(width: 3),
                                Text(zone, style: TextStyle(color: subtextColor, fontSize: 12)),
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
                              const Icon(Icons.star_rounded, color: GardenColors.star, size: 15),
                              const SizedBox(width: 3),
                              Text(rating, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                            ],
                          ),
                          if (reviewCount > 0)
                            Text('$reviewCount reseñas', style: TextStyle(color: subtextColor, fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        pricePerWalk != null
                            ? 'Bs $pricePerWalk / paseo'
                            : pricePerDay != null
                                ? 'Bs $pricePerDay / noche'
                                : 'Consultar precio',
                        style: const TextStyle(
                          color: GardenColors.primary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => context.push('/booking/${c['id']}'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: GardenColors.primary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Reservar',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoPlaceholder() {
    return Container(
      color: GardenColors.primary.withOpacity(0.1),
      child: const Center(child: Icon(Icons.pets, size: 40, color: GardenColors.primary)),
    );
  }

  Widget _buildEmptyState(Color textColor, Color subtextColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: GardenColors.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.favorite_border, size: 48, color: GardenColors.primary),
            ),
            const SizedBox(height: 24),
            Text(
              'Aún no tienes favoritos',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: textColor),
            ),
            const SizedBox(height: 10),
            Text(
              'Guarda a los cuidadores que más te gusten\ntocando el ❤️ en su perfil para encontrarlos\nfácilmente en tu próxima reserva.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subtextColor, fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 36),
            GardenButton(
              label: 'Explorar cuidadores',
              icon: Icons.search,
              onPressed: () => context.go('/marketplace'),
            ),
          ],
        ),
      ),
    );
  }
}
