import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../main.dart';

class CaregiverProfileScreen extends StatefulWidget {
  final String caregiverId;
  const CaregiverProfileScreen({Key? key, required this.caregiverId}) : super(key: key);

  @override
  State<CaregiverProfileScreen> createState() => _CaregiverProfileScreenState();
}

class _CaregiverProfileScreenState extends State<CaregiverProfileScreen> {
  Map<String, dynamic>? _caregiver;
  bool _isLoading = true;

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api');

  @override
  void initState() {
    super.initState();
    _loadCaregiver();
  }

  Future<void> _loadCaregiver() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/caregivers/${widget.caregiverId}'),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _caregiver = data['data']);
      }
    } catch (e) {
      // silencioso
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: kBackgroundColor,
        body: Center(child: CircularProgressIndicator(color: kPrimaryColor)),
      );
    }

    if (_caregiver == null) {
      return Scaffold(
        backgroundColor: kBackgroundColor,
        appBar: AppBar(backgroundColor: kSurfaceColor, title: const Text('Cuidador no encontrado')),
        body: const Center(child: Text('Error al cargar cuidador', style: TextStyle(color: Colors.white))),
      );
    }

    final photos = (_caregiver!['photos'] as List?)?.cast<String>() ?? [];
    final firstPhoto = photos.isNotEmpty ? photos.first : null;
    final services = (_caregiver!['services'] as List?)?.cast<String>() ?? [];

    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: kSurfaceColor,
            flexibleSpace: FlexibleSpaceBar(
              background: firstPhoto != null
                  ? Image.network(firstPhoto, fit: BoxFit.cover)
                  : Container(color: kSurfaceColor),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sección 1 — Header del cuidador
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: SizedBox(
                          width: 60,
                          height: 60,
                          child: _caregiver!['profilePicture'] != null
                              ? Image.network(
                                  _caregiver!['profilePicture'],
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  color: kBackgroundColor,
                                  child: const Icon(Icons.person, color: kTextSecondary, size: 30),
                                ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_caregiver!['firstName']} ${_caregiver!['lastName']}',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.location_on, size: 14, color: kTextSecondary),
                                const SizedBox(width: 4),
                                Text(
                                  _caregiver!['zone'] ?? 'Ubicación no especificada',
                                  style: const TextStyle(fontSize: 13, color: kTextSecondary),
                                ),
                              ],
                            ),
                            if (_caregiver!['verified'] == true) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: const [
                                  Icon(Icons.verified, color: kPrimaryColor, size: 14),
                                  SizedBox(width: 4),
                                  Text(
                                    'Verificado por GARDEN IA',
                                    style: TextStyle(fontSize: 12, color: kPrimaryColor),
                                  ),
                                ],
                              ),
                              // Badge blockchain
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8247E5).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF8247E5).withOpacity(0.4)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Text('⬡', style: TextStyle(fontSize: 10, color: Color(0xFF8247E5))),
                                    SizedBox(width: 4),
                                    Text('Polygon Amoy',
                                      style: TextStyle(fontSize: 10, color: Color(0xFF8247E5))),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Sección 2 — Rating y precio
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.star, color: Color(0xFFFFD700), size: 18),
                          const SizedBox(width: 4),
                          Text(
                            (_caregiver!['rating'] as num? ?? 0).toStringAsFixed(1),
                            style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          if ((_caregiver!['reviewCount'] as int? ?? 0) > 0)
                            Text(
                              ' (${_caregiver!['reviewCount']})',
                              style: const TextStyle(fontSize: 14, color: kTextSecondary),
                            ),
                        ],
                      ),
                      if (_caregiver!['pricePerWalk30'] != null)
                        Text(
                          'Bs ${_caregiver!['pricePerWalk30']}/paseo',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kPrimaryColor),
                        )
                      else if (_caregiver!['pricePerDay'] != null)
                        Text(
                          'Bs ${_caregiver!['pricePerDay']}/noche',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kPrimaryColor),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Sección 3 — Servicios
                  const Text('Servicios', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: services.map((s) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: kPrimaryColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          s.toString(),
                          style: const TextStyle(fontSize: 14, color: kPrimaryColor),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // Sección 4 — Bio
                  const Text('Sobre mí', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
                  const SizedBox(height: 12),
                  Text(
                    _caregiver!['bio'] ?? 'Sin descripción.',
                    style: const TextStyle(color: kTextSecondary, fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 24),

                  // Sección 5 — Fotos
                  if (photos.isNotEmpty) ...[
                    const Text('Fotos del espacio', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: photos.length,
                        itemBuilder: (context, index) {
                          return Container(
                            margin: const EdgeInsets.only(right: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                photos[index],
                                width: 120,
                                height: 100,
                                fit: BoxFit.cover,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Sección 6 — Botón de reservar
                  const SizedBox(height: 32),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 56),
                      backgroundColor: kPrimaryColor,
                    ),
                    onPressed: () {
                      context.push('/booking/${widget.caregiverId}');
                    },
                    child: const Text('Reservar ahora', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
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
