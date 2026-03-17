import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';
import '../../services/agentes_service.dart';
import '../../widgets/temporada_alta_badge.dart';
import '../../theme/garden_theme.dart';

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
    final theme = Theme.of(context);
    
    return GestureDetector(
      onTap: () {
        if (!isSelected) {
          setState(() => _selectedService = value);
          _loadCaregivers(reset: true);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? GardenColors.primary : theme.colorScheme.surfaceVariant,
          borderRadius: GardenRadius.full_,
          boxShadow: isSelected ? GardenShadows.primary : null,
          border: Border.all(
            color: isSelected ? GardenColors.primary : theme.colorScheme.outline.withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GardenText.labelLarge.copyWith(
            color: isSelected ? Colors.white : theme.colorScheme.onSurface,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildCaregiverCard(Map<String, dynamic> caregiver) {
    final theme = Theme.of(context);
    final isVerified = caregiver['verified'] == true;
    
    return GardenCard(
      margin: const EdgeInsets.only(bottom: 20),
      padding: EdgeInsets.zero,
      onTap: () => context.push('/caregiver/${caregiver['id']}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sección superior: Imagen y Resumen rápido
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar grande con sombra
                Container(
                  decoration: BoxDecoration(
                    borderRadius: GardenRadius.lg_,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Hero(
                    tag: 'avatar-${caregiver['id']}',
                    child: GardenAvatar(
                      imageUrl: caregiver['profilePicture'],
                      size: 90,
                      initials: '${caregiver['firstName']} ${caregiver['lastName']}',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Información principal
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${caregiver['firstName']} ${caregiver['lastName']}',
                              style: GardenText.headingLarge.copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isVerified)
                            Icon(Icons.verified, color: GardenColors.secondary, size: 20),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.location_on, size: 14, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                          const SizedBox(width: 4),
                          Text(
                            _zoneLabels[caregiver['zone']] ?? caregiver['zone'] ?? 'Santa Cruz',
                            style: GardenText.bodySmall.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Rating
                      Row(
                        children: [
                          const Icon(Icons.star, color: GardenColors.star, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            (caregiver['rating'] as num? ?? 0).toStringAsFixed(1),
                            style: GardenText.labelLarge.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if ((caregiver['reviewCount'] as int? ?? 0) > 0)
                            Text(
                              ' (${caregiver['reviewCount']} reseñas)',
                              style: GardenText.caption.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.5),
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
          
          // Línea divisoria sutil
          Divider(height: 1, color: theme.colorScheme.outline.withOpacity(0.1)),
          
          // Sección inferior: Servicios y Precio
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Servicios como Badges
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: (caregiver['services'] as List? ?? []).take(2).map((s) {
                      return GardenBadge(
                        text: s.toString(),
                        color: GardenColors.secondary,
                        fontSize: 10,
                      );
                    }).toList(),
                  ),
                ),
                // Precio destacado
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (caregiver['pricePerWalk30'] != null) ...[
                      Text(
                        'Bs ${caregiver['pricePerWalk30']}',
                        style: GardenText.price.copyWith(color: GardenColors.primary),
                      ),
                      Text('por paseo', style: GardenText.caption),
                    ] else if (caregiver['pricePerDay'] != null) ...[
                      Text(
                        'Bs ${caregiver['pricePerDay']}',
                        style: GardenText.price.copyWith(color: GardenColors.primary),
                      ),
                      Text('por noche', style: GardenText.caption),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Blockchain Verification (si aplica)
          if (isVerified)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              decoration: BoxDecoration(
                color: GardenColors.polygon.withOpacity(0.08),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(GardenRadius.lg),
                  bottomRight: Radius.circular(GardenRadius.lg),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.link, size: 12, color: GardenColors.polygon),
                  const SizedBox(width: 6),
                  Text(
                    'Verificado en Polygon Blockchain',
                    style: GardenText.caption.copyWith(
                      color: GardenColors.polygon,
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          
          // Badge de temporada alta
          if (caregiver['zone'] == 'EQUIPETROL')
            Padding(
              padding: const EdgeInsets.all(12),
              child: TemporadaAltaBadge(
                zona: 'Equipetrol',
                porcentajeAjuste: 15,
                motivo: 'Semana Santa',
                fechaVueltaNormal: '24 de marzo',
                agentesService: AgentesService(authToken: _authToken),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 5,
      itemBuilder: (context, _) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: GardenCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const GardenSkeleton(width: 80, height: 80, radius: GardenRadius.lg),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    GardenSkeleton(width: 150, height: 18),
                    SizedBox(height: 8),
                    GardenSkeleton(width: 100, height: 14),
                    SizedBox(height: 12),
                    GardenSkeleton(width: 200, height: 14),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Header Moderno estilo Airbnb/Rover
          SliverAppBar(
            expandedHeight: 140,
            floating: true,
            pinned: true,
            elevation: 0,
            backgroundColor: theme.colorScheme.surface,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: isDark 
                      ? [GardenColors.darkSurface, theme.scaffoldBackgroundColor]
                      : [GardenColors.primary.withOpacity(0.05), theme.scaffoldBackgroundColor],
                  ),
                ),
              ),
              titlePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Busca el cuidador ideal',
                      style: GardenText.headingLarge.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  // Botón de Toggle de Tema (para testear)
                  IconButton(
                    icon: Icon(
                      isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                      color: GardenColors.primary,
                      size: 20,
                    ),
                    onPressed: () => themeNotifier.toggle(),
                  ),
                ],
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  icon: Icon(Icons.list_alt_rounded, color: theme.colorScheme.onSurface),
                  onPressed: () => context.push('/my-bookings'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: IconButton(
                  icon: Icon(Icons.pets_rounded, color: theme.colorScheme.onSurface),
                  onPressed: () => context.push('/my-pets'),
                ),
              ),
            ],
          ),

          // Filtros
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Chips de servicio
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('Todos', 'todos'),
                        const SizedBox(width: 8),
                        _buildFilterChip('Paseo 🦮', 'paseo'),
                        const SizedBox(width: 8),
                        _buildFilterChip('Hospedaje 🏠', 'hospedaje'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Selector de zona con nuevo estilo
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                      borderRadius: GardenRadius.md_,
                      border: Border.all(color: theme.colorScheme.outline.withOpacity(0.3)),
                    ),
                    child: DropdownButtonFormField<String>(
                      value: _selectedZone,
                      dropdownColor: theme.colorScheme.surface,
                      icon: Icon(Icons.keyboard_arrow_down_rounded, color: GardenColors.primary),
                      decoration: InputDecoration(
                        hintText: 'Todas las zonas',
                        hintStyle: GardenText.bodyMedium.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.4)),
                        prefixIcon: Icon(Icons.location_on_rounded, color: GardenColors.primary, size: 20),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      items: _zoneLabels.entries.map((e) {
                        return DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value, style: GardenText.bodyMedium),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() => _selectedZone = value);
                        _loadCaregivers(reset: true);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Lista de resultados
          if (_isLoading && _caregivers.isEmpty)
            SliverFillRemaining(child: _buildLoadingSkeleton())
          else if (_hasError && _caregivers.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline_rounded, color: GardenColors.error, size: 60),
                    const SizedBox(height: 20),
                    Text('Ops! Algo salió mal', style: GardenText.headingMedium),
                    const SizedBox(height: 8),
                    Text('No pudimos conectar con los cuidadores', style: GardenText.bodySmall),
                    const SizedBox(height: 20),
                    GardenButton(
                      label: 'Reintentar',
                      onPressed: () => _loadCaregivers(reset: true),
                      width: 160,
                    ),
                  ],
                ),
              ),
            )
          else if (_caregivers.isEmpty && !_isLoading)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.search_off_rounded, color: theme.colorScheme.onSurface.withOpacity(0.2), size: 80),
                    const SizedBox(height: 20),
                    Text('Sin resultados', style: GardenText.headingMedium),
                    const SizedBox(height: 8),
                    Text('Intenta cambiar los filtros de búsqueda', style: GardenText.bodySmall),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == _caregivers.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator(color: GardenColors.primary)),
                      );
                    }
                    return _buildCaregiverCard(_caregivers[index]);
                  },
                  childCount: _caregivers.length + (_hasMore ? 1 : 0),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
