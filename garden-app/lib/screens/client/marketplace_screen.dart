import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';
import '../../theme/garden_theme.dart';

class MarketplaceScreen extends StatefulWidget {
  final String? initialService;
  final String? initialZone;
  final String? initialSize;

  const MarketplaceScreen({
    super.key,
    this.initialService,
    this.initialZone,
    this.initialSize,
  });

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
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
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
    _checkOnboarding();
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

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool('onboarding_completed') ?? false;
    if (!completed && mounted) {
      context.go('/client-welcome');
    }
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
    _searchController.dispose();
    _searchDebounce?.cancel();
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
        if (_searchQuery.isNotEmpty) 'search': _searchQuery,
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
          color: isSelected ? GardenColors.primary : theme.colorScheme.surfaceContainerHighest,
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
      child: const Text(
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
    final cardBg = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final rating = (caregiver['rating'] as num? ?? 0).toStringAsFixed(1);
    final reviewCount = caregiver['reviewCount'] as int? ?? 0;
    final firstName = caregiver['firstName'] as String? ?? '';
    final lastName = caregiver['lastName'] as String? ?? '';
    final zone = _zoneLabels[caregiver['zone']] ?? caregiver['zone'] ?? '';
    final expYears = caregiver['experienceYears'] as int?;
    final services = (caregiver['services'] as List? ?? []).take(2).toList();

    // Precio principal
    String? priceLabel;
    String? priceUnit;
    if (caregiver['pricePerWalk30'] != null) {
      priceLabel = 'Bs ${caregiver['pricePerWalk30']}';
      priceUnit = '/paseo';
    } else if (caregiver['pricePerDay'] != null) {
      priceLabel = 'Bs ${caregiver['pricePerDay']}';
      priceUnit = '/noche';
    }

    return GestureDetector(
      onTap: () => context.push('/caregiver/${caregiver['id']}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isVerified
                ? GardenColors.primary.withValues(alpha: 0.25)
                : borderColor,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── Fila principal ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar con ring de verificación
                  Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isVerified
                                ? GardenColors.primary.withValues(alpha: 0.6)
                                : borderColor,
                            width: isVerified ? 2 : 1.5,
                          ),
                        ),
                        child: GardenAvatar(
                          imageUrl: caregiver['profilePicture'] as String?,
                          size: 54,
                          initials: '${firstName.isNotEmpty ? firstName[0] : "C"}${lastName.isNotEmpty ? lastName[0] : ""}',
                        ),
                      ),
                      if (isVerified)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(
                              color: GardenColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.verified_rounded, size: 12, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),

                  // Info central
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Nombre + rating en misma fila
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                '$firstName $lastName',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded, color: GardenColors.star, size: 14),
                                const SizedBox(width: 2),
                                Text(
                                  rating,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (reviewCount > 0) ...[
                                  const SizedBox(width: 2),
                                  Text(
                                    '($reviewCount)',
                                    style: TextStyle(color: subtextColor, fontSize: 11),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // Zona + experiencia
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined, size: 11, color: subtextColor),
                            const SizedBox(width: 3),
                            Text(zone, style: TextStyle(color: subtextColor, fontSize: 12)),
                            if (expYears != null) ...[
                              Text('  ·  ', style: TextStyle(color: subtextColor, fontSize: 12)),
                              Icon(Icons.workspace_premium_outlined, size: 11, color: GardenColors.primary),
                              const SizedBox(width: 3),
                              Text(
                                '$expYears+ años',
                                style: const TextStyle(color: GardenColors.primary, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Badges de servicios
                        if (services.isNotEmpty)
                          Wrap(
                            spacing: 5,
                            children: services.map((s) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: GardenColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                s.toString(),
                                style: const TextStyle(
                                  color: GardenColors.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )).toList(),
                          ),
                      ],
                    ),
                  ),

                  // Precio (columna derecha)
                  if (priceLabel != null) ...[
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          priceLabel,
                          style: const TextStyle(
                            color: GardenColors.primary,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          priceUnit!,
                          style: TextStyle(color: subtextColor, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // ── Footer verificación / temporada alta ──────────────
            if (isVerified || caregiver['zone'] == 'EQUIPETROL')
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: isVerified
                      ? GardenColors.polygon.withValues(alpha: 0.07)
                      : GardenColors.warning.withValues(alpha: 0.07),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    if (isVerified) ...[
                      const Icon(Icons.link_rounded, size: 12, color: GardenColors.polygon),
                      const SizedBox(width: 5),
                      Text(
                        'Verificado en Polygon Blockchain',
                        style: TextStyle(
                          color: GardenColors.polygon,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ] else ...[
                      Icon(Icons.trending_up_rounded, size: 12, color: GardenColors.warning),
                      const SizedBox(width: 5),
                      Text(
                        'Zona con alta demanda · Semana Santa',
                        style: TextStyle(
                          color: GardenColors.warning,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 5,
      itemBuilder: (context, _) => const Padding(
        padding: EdgeInsets.only(bottom: 20),
        child: GardenCard(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              GardenSkeleton(width: 80, height: 80, radius: GardenRadius.lg),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                  const SizedBox(height: 12),
                  // Buscador por nombre
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Buscar cuidador por nombre...',
                      hintStyle: GardenText.bodyMedium.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                      prefixIcon: const Icon(Icons.search_rounded, color: GardenColors.primary, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.close_rounded, color: theme.colorScheme.onSurface.withValues(alpha: 0.5), size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                                _loadCaregivers(reset: true);
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      border: OutlineInputBorder(
                        borderRadius: GardenRadius.md_,
                        borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: GardenRadius.md_,
                        borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: GardenRadius.md_,
                        borderSide: const BorderSide(color: GardenColors.primary, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: (value) {
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(const Duration(milliseconds: 500), () {
                        setState(() => _searchQuery = value.trim());
                        _loadCaregivers(reset: true);
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  // Selector de zona con nuevo estilo
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                      borderRadius: GardenRadius.md_,
                      border: Border.all(color: theme.colorScheme.outline.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedZone,
                            dropdownColor: theme.colorScheme.surface,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: GardenColors.primary),
                            decoration: InputDecoration(
                              hintText: 'Todas las zonas',
                              hintStyle: GardenText.bodyMedium.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.4)),
                              prefixIcon: const Icon(Icons.location_on_rounded, color: GardenColors.primary, size: 20),
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
                            icon: const Icon(Icons.tune_rounded, color: GardenColors.primary),
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
                    const Icon(Icons.error_outline_rounded, color: GardenColors.error, size: 60),
                    const SizedBox(height: 20),
                    const Text('Ops! Algo salió mal', style: GardenText.headingMedium),
                    const SizedBox(height: 8),
                    const Text('No pudimos conectar con los cuidadores', style: GardenText.bodySmall),
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
                    const Text('Sin resultados', style: GardenText.headingMedium),
                    const SizedBox(height: 8),
                    const Text('Intenta cambiar los filtros de búsqueda', style: GardenText.bodySmall),
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
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
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
                          if (val) {
                            _selectedSizes.add(size);
                          } else {
                            _selectedSizes.remove(size);
                          }
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
