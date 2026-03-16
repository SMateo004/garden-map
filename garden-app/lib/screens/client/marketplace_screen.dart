import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';
import '../../services/agentes_service.dart';
import '../../widgets/temporada_alta_badge.dart';

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({Key? key}) : super(key: key);

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  List<Map<String, dynamic>> _caregivers = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _selectedService = 'todos'; // 'todos', 'paseo', 'hospedaje'
  String? _selectedZone;
  int _currentPage = 1;
  bool _hasMore = true;
  String _authToken = '';
  final ScrollController _scrollController = ScrollController();

  final Map<String, String> _zoneLabels = {
    'EQUIPETROL': 'Equipetrol',
    'URBARI': 'Urbari',
    'NORTE': 'Norte',
    'LAS_PALMAS': 'Las Palmas',
    'CENTRO_SAN_MARTIN': 'Centro/San Martín',
    'OTROS': 'Otros',
  };

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !_isLoading &&
          _hasMore) {
        _loadNextPage();
      }
    });
  }

  Future<void> _loadInitialData() async {
    await _loadToken();
    await _loadCaregivers(reset: true);
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    String token = prefs.getString('access_token') ?? '';
    if (token.isEmpty) {
      token = const String.fromEnvironment('TEST_JWT', defaultValue: '');
    }
    if (mounted) {
      setState(() => _authToken = token);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCaregivers({bool reset = false}) async {
    if (reset) {
      setState(() {
        _caregivers = [];
        _currentPage = 1;
        _hasMore = true;
      });
    }
    setState(() => _isLoading = true);
    try {
      final params = <String, String>{
        'limit': '10',
        'page': _currentPage.toString(),
        if (_selectedService != 'todos') 'service': _selectedService,
        if (_selectedZone != null) 'zone': _selectedZone!,
      };
      final uri = Uri.parse(
        '${const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api')}/caregivers',
      ).replace(queryParameters: params);

      final response = await http.get(uri);
      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final list = (data['data']['caregivers'] as List).cast<Map<String, dynamic>>();
        final pagination = data['data']['pagination'];
        setState(() {
          if (reset) {
            _caregivers = list;
          } else {
            _caregivers.addAll(list);
          }
          _hasMore = _currentPage < pagination['pages'];
          _hasError = false;
        });
      } else {
        throw Exception('Error al cargar cuidadores');
      }
    } catch (e) {
      setState(() => _hasError = true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadNextPage() async {
    _currentPage++;
    await _loadCaregivers();
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedService == value;
    return GestureDetector(
      onTap: () {
        if (!isSelected) {
          setState(() => _selectedService = value);
          _loadCaregivers(reset: true);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? kPrimaryColor : kBackgroundColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : kTextSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildCaregiverCard(Map<String, dynamic> caregiver) {
    return GestureDetector(
      onTap: () => context.push('/caregiver/${caregiver['id']}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: kSurfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Imagen del cuidador
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 80,
                    height: 80,
                    child: caregiver['profilePicture'] != null
                        ? Image.network(
                            caregiver['profilePicture'],
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              color: kBackgroundColor,
                              child: const Icon(Icons.person, color: kTextSecondary, size: 40),
                            ),
                          )
                        : Container(
                            color: kBackgroundColor,
                            child: const Icon(Icons.person, color: kTextSecondary, size: 40),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                // Info del cuidador
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (caregiver['verified'] == true) ...[
                            const Icon(Icons.verified, color: kPrimaryColor, size: 16),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              '${caregiver['firstName']} ${caregiver['lastName']}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 12, color: kTextSecondary),
                          const SizedBox(width: 4),
                          Text(
                            _zoneLabels[caregiver['zone']] ?? caregiver['zone'] ?? 'Santa Cruz',
                            style: const TextStyle(fontSize: 12, color: kTextSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        children: (caregiver['services'] as List? ?? []).map((s) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: kPrimaryColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              s.toString(),
                              style: const TextStyle(fontSize: 11, color: kPrimaryColor),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.star, color: Color(0xFFFFD700), size: 14),
                          const SizedBox(width: 4),
                          Text(
                            (caregiver['rating'] as num? ?? 0).toStringAsFixed(1),
                            style: const TextStyle(fontSize: 12, color: Colors.white),
                          ),
                          if ((caregiver['reviewCount'] as int? ?? 0) > 0)
                            Text(
                              ' (${caregiver['reviewCount']})',
                              style: const TextStyle(fontSize: 12, color: kTextSecondary),
                            ),
                          const Spacer(),
                          if (caregiver['pricePerWalk30'] != null)
                            Text(
                              'Bs ${caregiver['pricePerWalk30']}/paseo',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: kPrimaryColor,
                              ),
                            )
                          else if (caregiver['pricePerDay'] != null)
                            Text(
                              'Bs ${caregiver['pricePerDay']}/noche',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: kPrimaryColor,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Badge de temporada alta
            if (caregiver['zone'] == 'EQUIPETROL') ...[
              const SizedBox(height: 12),
              TemporadaAltaBadge(
                zona: 'Equipetrol',
                porcentajeAjuste: 15,
                motivo: 'Semana Santa',
                fechaVueltaNormal: '24 de marzo',
                agentesService: AgentesService(authToken: _authToken),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: const Text('Encuentra un cuidador'),
        backgroundColor: kSurfaceColor,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.pets, color: Colors.white),
            tooltip: 'Mis mascotas',
            onPressed: () => context.push('/my-pets'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filtros
          Container(
            color: kSurfaceColor,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    _buildFilterChip('Todos', 'todos'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Paseo 🦮', 'paseo'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Hospedaje 🏠', 'hospedaje'),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedZone,
                  hint: const Text('Todas las zonas', style: TextStyle(color: kTextSecondary)),
                  dropdownColor: kSurfaceColor,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.location_on_outlined, color: kTextSecondary),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  items: _zoneLabels.entries.map((e) {
                    return DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _selectedZone = value);
                    _loadCaregivers(reset: true);
                  },
                ),
              ],
            ),
          ),
          // Lista
          Expanded(
            child: _caregivers.isEmpty && _isLoading
                ? const Center(child: CircularProgressIndicator(color: kPrimaryColor))
                : _hasError && _caregivers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.wifi_off, color: kTextSecondary, size: 48),
                            const SizedBox(height: 16),
                            const Text(
                              'No pudimos cargar los cuidadores',
                              style: TextStyle(color: kTextSecondary),
                            ),
                            TextButton(
                              onPressed: () => _loadCaregivers(reset: true),
                              child: const Text('Reintentar', style: TextStyle(color: kPrimaryColor)),
                            ),
                          ],
                        ),
                      )
                    : _caregivers.isEmpty && !_isLoading
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off, color: kTextSecondary, size: 48),
                                SizedBox(height: 16),
                                Text(
                                  'No encontramos cuidadores con estos filtros',
                                  style: TextStyle(color: kTextSecondary),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: _caregivers.length + (_hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _caregivers.length) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16),
                                    child: CircularProgressIndicator(color: kPrimaryColor),
                                  ),
                                );
                              }
                              return _buildCaregiverCard(_caregivers[index]);
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
