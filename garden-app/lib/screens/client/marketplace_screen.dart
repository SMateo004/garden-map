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
  final String? initialService;
  final String? initialZone;
  final String? initialSize;

  const MarketplaceScreen({
    Key? key,
    this.initialService,
    this.initialZone,
    this.initialSize,
  }) : super(key: key);

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
  
  // Filtros Avanzados
  int? _minExperienceYears;
  bool _filterAggressive = false;
  bool _filterPuppies = false;
  bool _filterSeniors = false;
  List<String> _selectedSizes = [];
  String _authToken = '';
  String? _userPhoto;
  String? _userName;
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
    if (widget.initialService != null) {
      _selectedService = widget.initialService!;
    }
    if (widget.initialZone != null) {
      _selectedZone = widget.initialZone;
    }
    if (widget.initialSize != null) {
      _selectedSizes = [widget.initialSize!];
    }
    
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
      setState(() {
        _authToken = token;
        _userPhoto = prefs.getString('user_photo');
        _userName = prefs.getString('user_name');
      });
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
        if (_selectedZone != null) 'zone': _selectedZone!.toLowerCase(),
        if (_minExperienceYears != null) 'experienceYears': _minExperienceYears.toString(),
        if (_filterAggressive) 'acceptAggressive': 'true',
        if (_filterPuppies) 'acceptPuppies': 'true',
        if (_filterSeniors) 'acceptSeniors': 'true',
        if (_selectedSizes.isNotEmpty) 'sizesAccepted': _selectedSizes.join(','),
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

  Widget _buildAuthButton() {
    final theme = Theme.of(context);
    if (_authToken.isNotEmpty) {
      return IconButton(
        icon: const Icon(Icons.account_circle_outlined),
        onPressed: () => context.push('/profile'),
        tooltip: 'Mi perfil',
      );
    }
    return TextButton(
      onPressed: () => context.push('/login'),
      child: Text(
        'Iniciar sesión', 
        style: TextStyle(
          color: GardenColors.primary, 
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildCaregiverCard(Map<String, dynamic> caregiver) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isVerified = caregiver['verified'] == true;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return GardenCard(
      margin: const EdgeInsets.only(bottom: 20),
      padding: EdgeInsets.zero,
      onTap: () => context.push('/caregiver/${caregiver['id']}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Foto Grande (con Hero)
          Hero(
            tag: 'photo-${caregiver['id']}',
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(GardenRadius.lg),
                topRight: Radius.circular(GardenRadius.lg),
              ),
              child: Image.network(
                caregiver['profilePicture'] ?? '',
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 180,
                  color: GardenColors.primary.withOpacity(0.1),
                  child: const Icon(Icons.pets, size: 40, color: GardenColors.primary),
                ),
              ),
            ),
          ),
          
          // Sección de Info (Snippet del usuario)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                GardenAvatar(
                  imageUrl: caregiver['profilePicture'] as String?,
                  size: 44,
                  initials: '${(caregiver['firstName'] as String? ?? 'C')[0]}${(caregiver['lastName'] as String? ?? '')[0]}',
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${caregiver['firstName']} ${caregiver['lastName']}',
                        style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        children: [
                          if (caregiver['experienceYears'] != null) ...[
                            Icon(Icons.badge_outlined, size: 12, color: GardenColors.primary),
                            const SizedBox(width: 4),
                            Text(
                              '${caregiver['experienceYears']}+ años exp.',
                              style: TextStyle(color: GardenColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Icon(Icons.location_on_outlined, size: 12, color: subtextColor),
                          const SizedBox(width: 3),
                          Text(
                            _zoneLabels[caregiver['zone']] ?? caregiver['zone'] ?? '',
                            style: TextStyle(color: subtextColor, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, color: GardenColors.star, size: 15),
                    const SizedBox(width: 3),
                    Text(
                      (caregiver['rating'] as num? ?? 0).toStringAsFixed(1),
                      style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
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
                ],
              ),
            ),
            actions: [
              _buildAuthButton(),
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
                    child: Row(
                      children: [
                        Expanded(
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
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: IconButton(
                            icon: Icon(Icons.tune_rounded, color: GardenColors.primary),
                            onPressed: _showFiltersBottomSheet,
                            tooltip: 'Filtros avanzados',
                          ),
                        ),
                      ],
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

  void _showFiltersBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;
          final textColor = isDark ? Colors.white : Colors.black87;
          
          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: BoxDecoration(
              color: isDark ? GardenColors.darkSurface : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Filtros avanzados',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
                    TextButton(
                      onPressed: () {
                        setSheetState(() {
                          _minExperienceYears = null;
                          _filterAggressive = false;
                          _filterPuppies = false;
                          _filterSeniors = false;
                          _selectedSizes = [];
                        });
                        setState(() {});
                      },
                      child: const Text('Limpiar', style: TextStyle(color: GardenColors.primary)),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Años de experiencia
                Text('Años de experiencia mín.', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [0, 1, 2, 3, 5].map((years) {
                    final selected = _minExperienceYears == years;
                    return ChoiceChip(
                      label: Text(years == 0 ? 'Sin min' : '$years+'),
                      selected: selected,
                      onSelected: (val) {
                        setSheetState(() => _minExperienceYears = val ? years : null);
                        setState(() {});
                      },
                      selectedColor: GardenColors.primary.withOpacity(0.2),
                      checkmarkColor: GardenColors.primary,
                      labelStyle: TextStyle(color: selected ? GardenColors.primary : textColor),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // Políticas
                Text('Políticas de aceptación', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                _filterSwitch('Acepta agresivos', _filterAggressive, (v) {
                  setSheetState(() => _filterAggressive = v);
                  setState(() {});
                }),
                _filterSwitch('Acepta cachorros', _filterPuppies, (v) {
                  setSheetState(() => _filterPuppies = v);
                  setState(() {});
                }),
                _filterSwitch('Acepta seniors', _filterSeniors, (v) {
                  setSheetState(() => _filterSeniors = v);
                  setState(() {});
                }),

                const SizedBox(height: 24),
                
                // Tamaños
                Text('Tamaños aceptados', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: ['PEQUEÑO', 'MEDIANO', 'GRANDE', 'GIGANTE'].map((size) {
                    final selected = _selectedSizes.contains(size);
                    return FilterChip(
                      label: Text(size),
                      selected: selected,
                      onSelected: (val) {
                        setSheetState(() {
                          if (val) _selectedSizes.add(size);
                          else _selectedSizes.remove(size);
                        });
                        setState(() {});
                      },
                      selectedColor: GardenColors.primary.withOpacity(0.2),
                    );
                  }).toList(),
                ),

                const Spacer(),
                GardenButton(
                  label: 'Aplicar filtros',
                  onPressed: () {
                    Navigator.pop(context);
                    _loadCaregivers(reset: true);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _filterSwitch(String label, bool value, Function(bool) onChanged) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        const Spacer(),
        Switch(value: value, onChanged: onChanged, activeColor: GardenColors.primary),
      ],
    );
  }
}
