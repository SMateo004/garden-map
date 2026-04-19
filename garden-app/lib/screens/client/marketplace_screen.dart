import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/notification_bell.dart';

// ── Datos geográficos de Santa Cruz de la Sierra ──────────────────────────

const LatLng _kSantaCruzCenter = LatLng(-17.775, -63.175);
const double _kDefaultZoom = 12.5;

const Map<String, String> _kZoneLabels = {
  'EQUIPETROL': 'Equipetrol',
  'URBARI': 'Urbari',
  'NORTE': 'El Norte',
  'LAS_PALMAS': 'Las Palmas',
  'CENTRO': 'Centro Primer Anillo',
  'REMANZO': 'Remanzo y Sevillas',
  'SUR': 'El Sur',
  'URUBO_NORTE': 'Urubo Norte',
  'URUBO_SUR': 'Urubo Sur',
};

const Map<String, Color> _kZoneColors = {
  'EQUIPETROL': Color(0xFF4CAF50),
  'URBARI': Color(0xFF2196F3),
  'NORTE': Color(0xFF00BCD4),
  'LAS_PALMAS': Color(0xFFFF9800),
  'CENTRO': Color(0xFFE91E63),
  'REMANZO': Color(0xFF3F51B5),
  'SUR': Color(0xFF9C27B0),
  'URUBO_NORTE': Color(0xFF00897B),
  'URUBO_SUR': Color(0xFF6D4C41),
};

const Map<String, LatLng> _kZoneCenters = {
  'EQUIPETROL': LatLng(-17.7641, -63.1958),
  'URBARI': LatLng(-17.7965, -63.1979),
  'NORTE': LatLng(-17.7630, -63.1763),
  'LAS_PALMAS': LatLng(-17.8031, -63.2074),
  'CENTRO': LatLng(-17.7911, -63.1782),
  'REMANZO': LatLng(-17.6943, -63.1576),
  'SUR': LatLng(-17.832, -63.179),
  'URUBO_NORTE': LatLng(-17.7448, -63.2251),
  'URUBO_SUR': LatLng(-17.7752, -63.2367),
};

const Map<String, double> _kZoneZooms = {
  'EQUIPETROL': 14.5,
  'URBARI': 14.5,
  'NORTE': 14.5,
  'LAS_PALMAS': 14.5,
  'CENTRO': 14.0,
  'REMANZO': 14.5,
  'SUR': 14.0,
  'URUBO_NORTE': 13.5,
  'URUBO_SUR': 13.5,
};

// Polígonos de cada zona trazados por el usuario
const Map<String, List<LatLng>> _kZonePolygons = {
  'EQUIPETROL': [
    LatLng(-17.765799, -63.205165),
    LatLng(-17.756941, -63.200993),
    LatLng(-17.752727, -63.191903),
    LatLng(-17.771688, -63.188895),
    LatLng(-17.773695, -63.191993),
  ],
  'CENTRO': [
    LatLng(-17.784393, -63.188845),
    LatLng(-17.782869, -63.172125),
    LatLng(-17.791076, -63.172763),
    LatLng(-17.797915, -63.175423),
    LatLng(-17.799130, -63.181808),
  ],
  'URBARI': [
    LatLng(-17.790265, -63.194629),
    LatLng(-17.798016, -63.193299),
    LatLng(-17.803385, -63.199577),
    LatLng(-17.794369, -63.203887),
  ],
  'LAS_PALMAS': [
    LatLng(-17.798168, -63.204758),
    LatLng(-17.804951, -63.201005),
    LatLng(-17.811313, -63.208140),
    LatLng(-17.797780, -63.215502),
  ],
  'REMANZO': [
    LatLng(-17.724889, -63.165691),
    LatLng(-17.719933, -63.180131),
    LatLng(-17.689720, -63.169008),
    LatLng(-17.711042, -63.160308),
    LatLng(-17.693484, -63.159644),
    LatLng(-17.694234, -63.159374),
    LatLng(-17.688576, -63.145079),
    LatLng(-17.680974, -63.137453),
    LatLng(-17.671336, -63.143441),
    LatLng(-17.679591, -63.153783),
    LatLng(-17.683351, -63.158864),
  ],
  'NORTE': [
    LatLng(-17.750313, -63.180868),
    LatLng(-17.774793, -63.184295),
    LatLng(-17.774496, -63.176116),
    LatLng(-17.752242, -63.163887),
  ],
  'SUR': [
    LatLng(-17.820, -63.180),
    LatLng(-17.825, -63.165),
    LatLng(-17.840, -63.170),
    LatLng(-17.845, -63.185),
    LatLng(-17.830, -63.195),
  ],
  'URUBO_NORTE': [
    LatLng(-17.763169, -63.217908),
    LatLng(-17.732469, -63.213667),
    LatLng(-17.726275, -63.231339),
    LatLng(-17.757447, -63.237418),
  ],
  'URUBO_SUR': [
    LatLng(-17.769834, -63.223280),
    LatLng(-17.785518, -63.231056),
    LatLng(-17.764516, -63.243568),
    LatLng(-17.780806, -63.248799),
  ],
};

// ── Widget principal ──────────────────────────────────────────────────────

class MarketplaceScreen extends StatefulWidget {
  final String? initialService;
  final String? initialZone;
  final String? initialSize;
  final bool isMobileShell;

  const MarketplaceScreen({
    super.key,
    this.initialService,
    this.initialZone,
    this.initialSize,
    this.isMobileShell = false,
  });

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  // ── Data ──
  List<Map<String, dynamic>> _caregivers = [];
  bool _isLoading = true;
  bool _hasError = false;
  int _currentPage = 1;
  bool _hasMore = true;

  // ── Filters (API) ──
  String _selectedService = 'todos';
  String? _selectedZone;
  int? _minExperienceYears;
  bool _filterAggressive = false;
  bool _filterPuppies = false;
  bool _filterSeniors = false;
  List<String> _selectedSizes = [];
  String _searchQuery = '';

  // ── Filters (client-side) ──
  RangeValues _priceRange = const RangeValues(0, 500);
  double _minRating = 0;
  bool _filterVerifiedOnly = false;

  // ── Sort ──
  String _sortBy = 'rating_desc';

  // ── UI state ──
  bool _showFilters = true;
  bool _showMap = false;
  String _authToken = '';
  String? _userName;

  // ── Reserva activa / próxima ──
  Map<String, dynamic>? _activeBooking;

  /// Callback that rebuilds the active filter sheet (if open).
  VoidCallback? _refreshSheet;

  // ── Controllers ──
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  final ScrollController _scrollController = ScrollController();
  final MapController _mapController = MapController();

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://garden-api-1ldd.onrender.com/api');

  // ── Computed ──

  int get _activeFilterCount {
    int n = 0;
    if (_selectedService != 'todos') n++;
    if (_selectedZone != null) n++;
    if (_searchQuery.isNotEmpty) n++;
    if (_minExperienceYears != null) n++;
    if (_filterAggressive) n++;
    if (_filterPuppies) n++;
    if (_filterSeniors) n++;
    if (_selectedSizes.isNotEmpty) n++;
    if (_minRating > 0) n++;
    if (_filterVerifiedOnly) n++;
    if (_priceRange.start > 0 || _priceRange.end < 500) n++;
    return n;
  }

  List<Map<String, dynamic>> get _displayCaregivers {
    var list = List<Map<String, dynamic>>.from(_caregivers);

    // Price range (client-side)
    if (_priceRange.start > 0 || _priceRange.end < 500) {
      list = list.where((c) {
        final price = (_selectedService == 'hospedaje'
            ? (c['pricePerDay'] ?? 0)
            : _selectedService == 'paseo'
                ? (c['pricePerWalk60'] ?? c['pricePerWalk30'] ?? 0)
                : (c['pricePerWalk60'] ?? c['pricePerWalk30'] ?? c['pricePerDay'] ?? 0)) as num;
        return price >= _priceRange.start && (price <= _priceRange.end || _priceRange.end >= 500);
      }).toList();
    }

    // Min rating (client-side)
    if (_minRating > 0) {
      list = list.where((c) => (c['rating'] as num? ?? 0) >= _minRating).toList();
    }

    // Verified only (client-side)
    if (_filterVerifiedOnly) {
      list = list.where((c) => c['verified'] == true).toList();
    }

    // Sort
    list.sort((a, b) {
      switch (_sortBy) {
        case 'price_asc':
          num _resolvePrice(Map<String, dynamic> c, num fallback) {
            if (_selectedService == 'hospedaje') return (c['pricePerDay'] ?? fallback) as num;
            if (_selectedService == 'paseo') return (c['pricePerWalk60'] ?? c['pricePerWalk30'] ?? fallback) as num;
            return (c['pricePerWalk60'] ?? c['pricePerWalk30'] ?? c['pricePerDay'] ?? fallback) as num;
          }
          final pa = _resolvePrice(a, 999);
          final pb = _resolvePrice(b, 999);
          return pa.compareTo(pb);
        case 'price_desc':
          num _resolvePrice2(Map<String, dynamic> c) {
            if (_selectedService == 'hospedaje') return (c['pricePerDay'] ?? 0) as num;
            if (_selectedService == 'paseo') return (c['pricePerWalk60'] ?? c['pricePerWalk30'] ?? 0) as num;
            return (c['pricePerWalk60'] ?? c['pricePerWalk30'] ?? c['pricePerDay'] ?? 0) as num;
          }
          final pa = _resolvePrice2(a);
          final pb = _resolvePrice2(b);
          return pb.compareTo(pa);
        case 'experience':
          return ((b['experienceYears'] as int? ?? 0)).compareTo((a['experienceYears'] as int? ?? 0));
        default: // rating_desc
          return ((b['rating'] as num? ?? 0)).compareTo((a['rating'] as num? ?? 0));
      }
    });

    return list;
  }

  // ── Lifecycle ──

  @override
  void initState() {
    super.initState();
    if (widget.initialService != null) _selectedService = widget.initialService!;
    if (widget.initialZone != null) _selectedZone = widget.initialZone;
    if (widget.initialSize != null) _selectedSizes = [widget.initialSize!];

    _loadInitialData();
    if (kIsWeb) _checkOnboarding();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
          !_isLoading && _hasMore) {
        _loadNextPage();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Data loading ──

  Future<void> _loadInitialData() async {
    await _loadToken();
    await Future.wait([_loadCaregivers(reset: true), _loadActiveBooking()]);
  }



  Future<void> _loadActiveBooking() async {
    if (_authToken.isEmpty) return;
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/bookings/my?limit=5&page=1'),
        headers: {'Authorization': 'Bearer $_authToken'},
      );
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body);
      if (data['success'] != true) return;
      final bookings = (data['data'] as List).cast<Map<String, dynamic>>();
      // Prioridad: IN_PROGRESS > CONFIRMED > WAITING_CAREGIVER_APPROVAL
      // Desaparece solo cuando tiene ownerRating (fue calificado)
      const activeStatuses = ['IN_PROGRESS', 'CONFIRMED', 'WAITING_CAREGIVER_APPROVAL'];
      Map<String, dynamic>? found;
      for (final s in activeStatuses) {
        found = bookings.where((b) =>
          b['status'] == s && b['ownerRating'] == null
        ).firstOrNull;
        if (found != null) break;
      }
      if (mounted) setState(() => _activeBooking = found);
    } catch (_) {}
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? '';
    final seen = userId.isNotEmpty ? (prefs.getBool('welcome_seen_$userId') ?? false) : true;
    if (!seen && mounted) context.go('/client-welcome');
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    String token = prefs.getString('access_token') ?? '';
    if (token.isEmpty) token = const String.fromEnvironment('TEST_JWT', defaultValue: '');
    if (mounted) {
      setState(() {
        _authToken = token;
        _userName = prefs.getString('user_name');
      });
    }
  }

  Future<void> _loadCaregivers({bool reset = false}) async {
    if (reset) setState(() { _caregivers = []; _currentPage = 1; _hasMore = true; });
    setState(() => _isLoading = true);
    try {
      final params = <String, String>{
        'limit': '20',
        'page': _currentPage.toString(),
        if (_selectedService != 'todos') 'service': _selectedService,
        if (_selectedZone != null) 'zone': _selectedZone!.toLowerCase(),
        if (_minExperienceYears != null && _minExperienceYears! > 0) 'experienceYears': _minExperienceYears.toString(),
        if (_filterAggressive) 'acceptAggressive': 'true',
        if (_filterPuppies) 'acceptPuppies': 'true',
        if (_filterSeniors) 'acceptSeniors': 'true',
        if (_selectedSizes.isNotEmpty) 'sizesAccepted': _selectedSizes.join(','),
        if (_searchQuery.isNotEmpty) 'search': _searchQuery,
        if (_filterVerifiedOnly) 'verified': 'true',
        if (_minRating > 0) 'minRating': _minRating.toString(),
      };
      final uri = Uri.parse('$_baseUrl/caregivers').replace(queryParameters: params);
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
        throw Exception('Error');
      }
    } catch (_) {
      setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadNextPage() async {
    _currentPage++;
    await _loadCaregivers();
  }

  void _clearAllFilters() {
    setState(() {
      _selectedService = 'todos';
      _selectedZone = null;
      _searchQuery = '';
      _searchController.clear();
      _minExperienceYears = null;
      _filterAggressive = false;
      _filterPuppies = false;
      _filterSeniors = false;
      _selectedSizes = [];
      _priceRange = const RangeValues(0, 500);
      _minRating = 0;
      _filterVerifiedOnly = false;
    });
    _loadCaregivers(reset: true);
  }

  void _selectZone(String? zone) {
    setState(() => _selectedZone = zone);
    _refreshSheet?.call();
    _loadCaregivers(reset: true);
    if (zone != null && _showMap) {
      final center = _kZoneCenters[zone];
      final zoom = _kZoneZooms[zone] ?? 14.0;
      if (center != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _mapController.move(center, zoom));
      }
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _getGreeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Buenos días,';
    if (h < 19) return 'Buenas tardes,';
    return 'Buenas noches,';
  }

  String _formatBookingTime(Map<String, dynamic> b) {
    // Paseo: mostrar hora específica si está disponible
    final startTime = b['startTime'] as String?;
    if (startTime != null && startTime.isNotEmpty) {
      try {
        final parts = startTime.split(':');
        final h = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        final period = h >= 12 ? 'pm' : 'am';
        final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
        final mStr = m.toString().padLeft(2, '0');
        return '$h12:$mStr $period';
      } catch (_) {}
    }
    // Fallback: timeSlot
    final slot = b['timeSlot'] as String?;
    if (slot == 'MANANA') return 'por la mañana';
    if (slot == 'TARDE') return 'por la tarde';
    if (slot == 'NOCHE') return 'por la noche';
    return '';
  }

  Widget _buildActiveBookingBanner() {
    final b = _activeBooking;
    if (b == null) return const SizedBox.shrink();

    final status = b['status'] as String;
    final isInProgress = status == 'IN_PROGRESS';
    final isPaseo = b['serviceType'] == 'PASEO';
    final petName = b['petName'] as String? ?? 'tu mascota';
    final caregiverName = (b['caregiverName'] as String? ?? 'el cuidador').split(' ').first;
    final duration = b['duration'] as int?;
    final timeStr = _formatBookingTime(b);

    // Texto principal y sublabel según estado
    String mainText;
    String subText;
    IconData actionIcon;

    if (isInProgress) {
      mainText = isPaseo
          ? '$petName está de paseo 🐕'
          : '$petName está con $caregiverName';
      subText = 'con $caregiverName${duration != null ? ' · $duration min' : ''}';
      actionIcon = Icons.play_circle_fill_rounded;
    } else if (status == 'CONFIRMED') {
      final walkDate = b['walkDate'] as String?;
      String fechaStr = '';
      if (walkDate != null) {
        try {
          final d = DateTime.parse(walkDate);
          const months = ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'];
          fechaStr = '${d.day} ${months[d.month - 1]}';
        } catch (_) {}
      }
      mainText = isPaseo
          ? '$petName pasea${timeStr.isNotEmpty ? ' a las $timeStr' : ''}'
          : '$petName se queda con $caregiverName';
      subText = 'con $caregiverName${fechaStr.isNotEmpty ? ' · $fechaStr' : ''}${duration != null && isPaseo ? ' · $duration min' : ''}';
      actionIcon = Icons.calendar_today_rounded;
    } else {
      mainText = 'Reserva pendiente de confirmación';
      subText = 'con $caregiverName · $petName';
      actionIcon = Icons.hourglass_top_rounded;
    }

    return GestureDetector(
      onTap: () => context.push('/my-bookings'),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: GardenColors.primary,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isInProgress ? 'EN CURSO' : 'PRÓXIMA SESIÓN',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mainText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subText,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(actionIcon, color: Colors.white, size: 24),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final border = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    final isMobile = !kIsWeb || MediaQuery.of(context).size.width < 700;

    if (isMobile) {
      return _buildMobileLayout(theme, isDark, bg, surface, border);
    }

    // ── Layout WEB ────────────────────────────────────────────────────────
    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          _buildAppBar(theme, isDark, surface, border),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Left: Filter panel ──
                ClipRect(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeInOut,
                    width: _showFilters ? 300.0 : 0.0,
                    child: SizedBox(
                      width: 300,
                      child: _buildFilterPanel(theme, isDark, surface, border),
                    ),
                  ),
                ),
                Container(width: 1, color: border),

                // ── Center: List ──
                Expanded(
                  child: Column(
                    children: [
                      _buildToolbar(theme, isDark, surface, border),
                      Container(height: 1, color: border),
                      Expanded(child: _buildCaregiverList(theme, isDark)),
                    ],
                  ),
                ),

                // ── Right: Map ──
                ClipRect(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeInOut,
                    width: _showMap ? 420.0 : 0.0,
                    child: SizedBox(
                      width: 420,
                      child: _buildMapPanel(theme, isDark, surface, border),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Layout MÓVIL ──────────────────────────────────────────────────────────
  Widget _buildMobileLayout(ThemeData theme, bool isDark, Color bg, Color surface, Color border) {
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── AppBar móvil ───────────────────────────────────────────
            Container(
              height: 56,
              color: surface,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {},
                    child: const Text('GARDEN',
                        style: TextStyle(color: GardenColors.primary, fontSize: 20, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 6),
                  Text('·', style: TextStyle(color: subtextColor, fontSize: 18)),
                  const SizedBox(width: 6),
                  Text('Santa Cruz', style: TextStyle(color: subtextColor, fontSize: 13)),
                  const Spacer(),
                  if (_authToken.isNotEmpty)
                    NotificationBell(token: _authToken, baseUrl: _baseUrl),
                  IconButton(
                    icon: Icon(
                      isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                      color: subtextColor, size: 20,
                    ),
                    onPressed: () => themeNotifier.toggle(),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: border),

            // ── Saludo ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_getGreeting(),
                            style: GardenText.metadata.copyWith(color: subtextColor)),
                        const SizedBox(height: 2),
                        RichText(
                          text: TextSpan(children: [
                            TextSpan(
                              text: _userName?.split(' ').first ?? 'tú',
                              style: GardenText.h3.copyWith(
                                  color: textColor, fontWeight: FontWeight.w900),
                            ),
                            const TextSpan(text: ' 🌿',
                                style: TextStyle(fontSize: 22)),
                          ]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ── Banner reserva activa / próxima ───────────────────────
            _buildActiveBookingBanner(),
            if (_activeBooking != null) const SizedBox(height: 8),

            // ── Barra de búsqueda ──────────────────────────────────────
            Container(
              color: Colors.transparent,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: border),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(color: textColor, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Buscar cuidador...',
                          hintStyle: TextStyle(color: subtextColor, fontSize: 14),
                          prefixIcon: Icon(Icons.search, color: subtextColor, size: 18),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (v) {
                          _searchDebounce?.cancel();
                          _searchDebounce = Timer(const Duration(milliseconds: 400), () {
                            setState(() => _searchQuery = v.trim());
                            _loadCaregivers(reset: true);
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Botón filtros
                  GestureDetector(
                    onTap: () => _showMobileFilterSheet(theme, isDark, surface, border),
                    child: Container(
                      height: 40, width: 40,
                      decoration: BoxDecoration(
                        color: _activeFilterCount > 0
                            ? GardenColors.primary.withValues(alpha: 0.15)
                            : bg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _activeFilterCount > 0 ? GardenColors.primary : border,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Center(child: Icon(Icons.tune_rounded,
                              color: _activeFilterCount > 0 ? GardenColors.primary : subtextColor,
                              size: 20)),
                          if (_activeFilterCount > 0)
                            Positioned(
                              top: 4, right: 4,
                              child: Container(
                                width: 14, height: 14,
                                decoration: const BoxDecoration(color: GardenColors.primary, shape: BoxShape.circle),
                                child: Center(child: Text('$_activeFilterCount',
                                    style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800))),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Chips de servicio ──────────────────────────────────────
            Container(
              color: surface,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                children: [
                  _mobileServiceChip('todos', 'Todos', isDark, subtextColor),
                  const SizedBox(width: 8),
                  _mobileServiceChip('paseo', '🦮 Paseo', isDark, subtextColor),
                  const SizedBox(width: 8),
                  _mobileServiceChip('hospedaje', '🏠 Hospedaje', isDark, subtextColor),
                ],
              ),
            ),
            Container(height: 1, color: border),

            // ── Lista de cuidadores ────────────────────────────────────
            Expanded(child: _buildCaregiverList(theme, isDark)),
          ],
        ),
      ),
      // FAB: mapa
      floatingActionButton: FloatingActionButton.small(
        backgroundColor: GardenColors.primary,
        onPressed: () => _showMobileMapSheet(isDark),
        child: const Icon(Icons.map_outlined, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _mobileServiceChip(String value, String label, bool isDark, Color subtextColor) {
    final isSelected = _selectedService == value;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedService = value);
        _loadCaregivers(reset: true);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? GardenColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? GardenColors.primary : (isDark ? GardenColors.darkBorder : GardenColors.lightBorder),
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: isSelected ? Colors.white : subtextColor,
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            )),
      ),
    );
  }

  void _showMobileFilterSheet(ThemeData theme, bool isDark, Color surface, Color border) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          _refreshSheet = () => setSheetState(() {});
          return GlassBox(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Reutilizamos el panel de filtros existente
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.65,
                child: _buildFilterPanel(theme, isDark, surface, border),
              ),
              GardenButton(
                label: 'Aplicar filtros',
                onPressed: () {
                  Navigator.pop(context);
                  _loadCaregivers(reset: true);
                },
              ),
            ],
          ),
        ),
          );
        },
      ),
    ).whenComplete(() => _refreshSheet = null);
  }

  void _showMobileMapSheet(bool isDark) {
    final theme = Theme.of(context);
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: GlassBox(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: isDark ? GardenColors.darkBorder : GardenColors.lightBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: _buildMapPanel(
                  theme, isDark, surface,
                  isDark ? GardenColors.darkBorder : GardenColors.lightBorder,
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  Widget _buildAppBar(ThemeData theme, bool isDark, Color surface, Color border) {
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    return Container(
      height: 60,
      color: surface,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  // Logo
                  GestureDetector(
                    onTap: () => context.go('/marketplace'),
                    child: const Text('GARDEN',
                        style: TextStyle(color: GardenColors.primary, fontSize: 20, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 6),
                  Text('·', style: TextStyle(color: subtextColor, fontSize: 18)),
                  const SizedBox(width: 6),
                  Text('Cuidadores en Santa Cruz', style: TextStyle(color: subtextColor, fontSize: 13)),
                  const Spacer(),
                  if (_authToken.isNotEmpty) ...[
                    NotificationBell(token: _authToken, baseUrl: _baseUrl),
                    _appBarBtn(Icons.list_alt_rounded, 'Mis reservas', () => context.push('/my-bookings'), textColor),
                    _appBarBtn(Icons.pets_rounded, 'Mis mascotas', () => context.push('/my-pets'), textColor),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => context.push('/profile'),
                      child: Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          border: Border.all(color: GardenColors.primary.withValues(alpha: 0.4)),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(children: [
                          const Icon(Icons.account_circle_outlined, size: 18, color: GardenColors.primary),
                          const SizedBox(width: 6),
                          Text(_userName?.split(' ').first ?? 'Perfil',
                              style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                        ]),
                      ),
                    ),
                  ] else ...[
                    TextButton(
                      onPressed: () => context.go('/register'),
                      child: const Text('Ser cuidador',
                          style: TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                    TextButton(
                      onPressed: () => context.go('/login'),
                      child: Text('Iniciar sesión',
                          style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: GardenButton(label: 'Registrarse', width: 110, onPressed: () => context.go('/register')),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Container(height: 1, color: border),
        ],
      ),
    );
  }

  Widget _appBarBtn(IconData icon, String tooltip, VoidCallback onTap, Color color) => IconButton(
        icon: Icon(icon, color: color, size: 20),
        onPressed: onTap,
        tooltip: tooltip,
      );

  // ── Toolbar ───────────────────────────────────────────────────────────────

  Widget _buildToolbar(ThemeData theme, bool isDark, Color surface, Color border) {
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final displayed = _displayCaregivers.length;

    return Container(
      height: 52,
      color: surface,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Toggle filters button
          _toolbarToggleBtn(
            icon: Icons.tune_rounded,
            label: _showFilters ? 'Ocultar filtros' : 'Filtros',
            badge: _activeFilterCount,
            active: _showFilters,
            onTap: () => setState(() => _showFilters = !_showFilters),
            textColor: textColor,
          ),
          const SizedBox(width: 12),

          // Result count
          Text(
            _isLoading && _caregivers.isEmpty
                ? 'Buscando...'
                : '$displayed cuidador${displayed != 1 ? 'es' : ''}',
            style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w500),
          ),

          const Spacer(),

          // Sort dropdown
          PopupMenuButton<String>(
            initialValue: _sortBy,
            onSelected: (v) => setState(() => _sortBy = v),
            tooltip: 'Ordenar',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sort_rounded, size: 16, color: textColor),
                  const SizedBox(width: 6),
                  Text(_sortLabel(_sortBy), style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w500)),
                  const SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: textColor),
                ],
              ),
            ),
            itemBuilder: (_) => [
              _sortMenuItem('rating_desc', 'Mejor valorados', Icons.star_rounded),
              _sortMenuItem('price_asc', 'Precio: menor a mayor', Icons.arrow_upward_rounded),
              _sortMenuItem('price_desc', 'Precio: mayor a menor', Icons.arrow_downward_rounded),
              _sortMenuItem('experience', 'Más experiencia', Icons.workspace_premium_outlined),
            ],
          ),
          const SizedBox(width: 10),

          // Toggle map button
          _toolbarToggleBtn(
            icon: Icons.map_outlined,
            label: _showMap ? 'Cerrar mapa' : 'Ver mapa',
            badge: 0,
            active: _showMap,
            onTap: () {
              setState(() => _showMap = !_showMap);
              if (!_showMap) return;
              // Animate to selected zone if any
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_selectedZone != null && _kZoneCenters[_selectedZone] != null) {
                  _mapController.move(_kZoneCenters[_selectedZone]!, _kZoneZooms[_selectedZone] ?? 14.0);
                } else {
                  _mapController.move(_kSantaCruzCenter, _kDefaultZoom);
                }
              });
            },
            textColor: textColor,
          ),
        ],
      ),
    );
  }

  Widget _toolbarToggleBtn({
    required IconData icon,
    required String label,
    required int badge,
    required bool active,
    required VoidCallback onTap,
    required Color textColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? GardenColors.primary.withValues(alpha: 0.1) : Colors.transparent,
          border: Border.all(color: active ? GardenColors.primary.withValues(alpha: 0.5) : GardenColors.darkBorder.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: active ? GardenColors.primary : textColor),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, color: active ? GardenColors.primary : textColor, fontWeight: FontWeight.w600)),
            if (badge > 0) ...[
              const SizedBox(width: 6),
              Container(
                width: 18, height: 18,
                decoration: const BoxDecoration(color: GardenColors.primary, shape: BoxShape.circle),
                child: Center(child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800))),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _sortLabel(String key) {
    switch (key) {
      case 'price_asc': return 'Precio ↑';
      case 'price_desc': return 'Precio ↓';
      case 'experience': return 'Experiencia';
      default: return 'Valoración';
    }
  }

  PopupMenuItem<String> _sortMenuItem(String value, String label, IconData icon) => PopupMenuItem(
        value: value,
        child: Row(children: [
          Icon(icon, size: 16, color: GardenColors.primary),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 13)),
        ]),
      );

  // ── Filter Panel ──────────────────────────────────────────────────────────

  Widget _buildFilterPanel(ThemeData theme, bool isDark, Color surface, Color border) {
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surfaceEl = isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated;

    return Container(
      color: surface,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                const Icon(Icons.tune_rounded, size: 18, color: GardenColors.primary),
                const SizedBox(width: 8),
                Text('Filtros', style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 16)),
                if (_activeFilterCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: GardenColors.primary, borderRadius: BorderRadius.circular(10)),
                    child: Text('$_activeFilterCount', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ],
                const Spacer(),
                if (_activeFilterCount > 0)
                  GestureDetector(
                    onTap: _clearAllFilters,
                    child: const Text('Limpiar todo',
                        style: TextStyle(color: GardenColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
          Container(height: 1, color: border),

          // Scrollable filter sections
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // ── Tipo de servicio ──
                  _sectionTitle('Tipo de servicio', textColor),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _serviceChip('Todos', 'todos', textColor),
                      const SizedBox(width: 6),
                      _serviceChip('Paseo 🦮', 'paseo', textColor),
                      const SizedBox(width: 6),
                      _serviceChip('Hospedaje 🏠', 'hospedaje', textColor),
                    ],
                  ),
                  _divider(border),

                  // ── Buscar ──
                  _sectionTitle('Buscar por nombre', textColor),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchController,
                    style: TextStyle(color: textColor, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Nombre del cuidador...',
                      hintStyle: TextStyle(color: subtextColor, fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded, color: GardenColors.primary, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.close_rounded, size: 16, color: subtextColor),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                                _loadCaregivers(reset: true);
                              })
                          : null,
                      filled: true, fillColor: surfaceEl,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: GardenColors.primary, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (v) {
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(const Duration(milliseconds: 450), () {
                        setState(() => _searchQuery = v.trim());
                        _loadCaregivers(reset: true);
                      });
                    },
                  ),
                  _divider(border),

                  // ── Zona ──
                  _sectionTitle('Zona', textColor),
                  const SizedBox(height: 4),
                  Text('Selecciona una zona para encontrar cuidadores cercanos',
                      style: TextStyle(color: subtextColor, fontSize: 11)),
                  const SizedBox(height: 10),
                  // "Todas" pill
                  GestureDetector(
                    onTap: () => _selectZone(null),
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _selectedZone == null
                            ? GardenColors.primary.withValues(alpha: 0.12)
                            : surfaceEl,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _selectedZone == null ? GardenColors.primary : border,
                          width: _selectedZone == null ? 1.5 : 1,
                        ),
                      ),
                      child: Row(children: [
                        Icon(Icons.public_rounded, size: 14,
                            color: _selectedZone == null ? GardenColors.primary : subtextColor),
                        const SizedBox(width: 8),
                        Text('Todas las zonas',
                            style: TextStyle(
                              color: _selectedZone == null ? GardenColors.primary : textColor,
                              fontWeight: _selectedZone == null ? FontWeight.w700 : FontWeight.w500,
                              fontSize: 13,
                            )),
                        if (_selectedZone == null) ...[
                          const Spacer(),
                          const Icon(Icons.check_rounded, size: 14, color: GardenColors.primary),
                        ],
                      ]),
                    ),
                  ),
                  // Zone pills
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: _kZoneLabels.entries.map((e) {
                      final isSelected = _selectedZone == e.key;
                      final color = _kZoneColors[e.key] ?? GardenColors.primary;
                      return GestureDetector(
                        onTap: () => _selectZone(isSelected ? null : e.key),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: isSelected ? color.withValues(alpha: 0.15) : surfaceEl,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? color : border,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8, height: 8,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(e.value,
                                  style: TextStyle(
                                    color: isSelected ? color : textColor,
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  )),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  _divider(border),

                  // ── Precio ──
                  _sectionTitle('Precio por servicio', textColor),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Bs ${_priceRange.start.toInt()}', style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                      Text(_priceRange.end >= 500 ? 'Bs 500+' : 'Bs ${_priceRange.end.toInt()}',
                          style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: GardenColors.primary,
                      inactiveTrackColor: GardenColors.primary.withValues(alpha: 0.2),
                      thumbColor: GardenColors.primary,
                      overlayColor: GardenColors.primary.withValues(alpha: 0.1),
                      trackHeight: 3,
                    ),
                    child: RangeSlider(
                      values: _priceRange,
                      min: 0, max: 500, divisions: 50,
                      labels: RangeLabels(
                        'Bs ${_priceRange.start.toInt()}',
                        _priceRange.end >= 500 ? 'Bs 500+' : 'Bs ${_priceRange.end.toInt()}',
                      ),
                      onChanged: (v) {
                        setState(() => _priceRange = v);
                        _refreshSheet?.call();
                      },
                      onChangeEnd: (_) => setState(() {}),
                    ),
                  ),
                  _divider(border),

                  // ── Experiencia ──
                  _sectionTitle('Experiencia mínima', textColor),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: [
                      _expChip(null, 'Sin mínimo', textColor),
                      _expChip(1, '1+ año', textColor),
                      _expChip(2, '2+ años', textColor),
                      _expChip(3, '3+ años', textColor),
                      _expChip(5, '5+ años', textColor),
                    ],
                  ),
                  _divider(border),

                  // ── Tamaño de mascota ──
                  _sectionTitle('Tamaño de mascota', textColor),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: [
                      _sizeChip('PEQUEÑO', 'Pequeño 🐾', textColor),
                      _sizeChip('MEDIANO', 'Mediano 🐕', textColor),
                      _sizeChip('GRANDE', 'Grande 🐕‍🦺', textColor),
                      _sizeChip('GIGANTE', 'Gigante 🦮', textColor),
                    ],
                  ),
                  _divider(border),

                  // ── Políticas ──
                  _sectionTitle('Políticas de aceptación', textColor),
                  const SizedBox(height: 4),
                  _filterSwitch('Acepta perros agresivos', Icons.warning_amber_rounded, _filterAggressive, (v) {
                    setState(() => _filterAggressive = v);
                    _refreshSheet?.call();
                    _loadCaregivers(reset: true);
                  }, textColor, subtextColor),
                  _filterSwitch('Acepta cachorros', Icons.child_care_rounded, _filterPuppies, (v) {
                    setState(() => _filterPuppies = v);
                    _refreshSheet?.call();
                    _loadCaregivers(reset: true);
                  }, textColor, subtextColor),
                  _filterSwitch('Acepta perros seniors', Icons.elderly_rounded, _filterSeniors, (v) {
                    setState(() => _filterSeniors = v);
                    _refreshSheet?.call();
                    _loadCaregivers(reset: true);
                  }, textColor, subtextColor),
                  _divider(border),

                  // ── Calificación ──
                  _sectionTitle('Calificación mínima', textColor),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: [
                      _ratingChip(0, 'Cualquiera', textColor),
                      _ratingChip(3, '3+ ⭐', textColor),
                      _ratingChip(4, '4+ ⭐', textColor),
                      _ratingChip(4.5, '4.5+ ⭐', textColor),
                    ],
                  ),
                  _divider(border),

                  // ── Verificación ──
                  _sectionTitle('Verificación', textColor),
                  const SizedBox(height: 4),
                  _filterSwitch(
                    'Solo verificados blockchain',
                    Icons.link_rounded,
                    _filterVerifiedOnly,
                    (v) {
                      setState(() => _filterVerifiedOnly = v);
                      _refreshSheet?.call();
                    },
                    textColor, subtextColor,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, Color textColor) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13)),
      );

  Widget _divider(Color border) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Divider(height: 1, thickness: 1, color: border),
      );

  Widget _serviceChip(String label, String value, Color textColor) {
    final selected = _selectedService == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedService = value);
          _refreshSheet?.call();
          _loadCaregivers(reset: true);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? GardenColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? GardenColors.primary : GardenColors.darkBorder.withValues(alpha: 0.3)),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                  color: selected ? Colors.white : textColor,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 11,
                )),
          ),
        ),
      ),
    );
  }

  Widget _expChip(int? val, String label, Color textColor) {
    final selected = _minExperienceYears == val;
    return GestureDetector(
      onTap: () {
        setState(() => _minExperienceYears = selected ? null : val);
        _refreshSheet?.call();
        _loadCaregivers(reset: true);
      },
      child: _smallChip(label, selected, textColor),
    );
  }

  Widget _sizeChip(String val, String label, Color textColor) {
    final selected = _selectedSizes.contains(val);
    return GestureDetector(
      onTap: () {
        setState(() => selected ? _selectedSizes.remove(val) : _selectedSizes.add(val));
        _refreshSheet?.call();
        _loadCaregivers(reset: true);
      },
      child: _smallChip(label, selected, textColor),
    );
  }

  Widget _ratingChip(double val, String label, Color textColor) {
    final selected = _minRating == val;
    return GestureDetector(
      onTap: () {
        setState(() => _minRating = selected ? 0 : val);
        _refreshSheet?.call();
      },
      child: _smallChip(label, selected, textColor),
    );
  }

  Widget _smallChip(String label, bool selected, Color textColor) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? GardenColors.primary.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? GardenColors.primary : GardenColors.darkBorder.withValues(alpha: 0.3)),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? GardenColors.primary : textColor,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              fontSize: 12,
            )),
      );

  Widget _filterSwitch(String label, IconData icon, bool value, Function(bool) onChanged,
      Color textColor, Color subtextColor) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Icon(icon, size: 16, color: value ? GardenColors.primary : subtextColor),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(color: textColor, fontSize: 12))),
          Transform.scale(
            scale: 0.8,
            child: Switch(value: value, onChanged: onChanged, activeColor: GardenColors.primary),
          ),
        ]),
      );

  // ── Caregiver List ────────────────────────────────────────────────────────

  Widget _buildCaregiverList(ThemeData theme, bool isDark) {
    final displayed = _displayCaregivers;

    if (_isLoading && _caregivers.isEmpty) return _buildLoadingSkeleton();
    if (_hasError && _caregivers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, color: GardenColors.error, size: 50),
            const SizedBox(height: 16),
            Text('No pudimos conectar', style: GardenText.headingMedium),
            const SizedBox(height: 20),
            GardenButton(label: 'Reintentar', onPressed: () => _loadCaregivers(reset: true), width: 140),
          ],
        ),
      );
    }
    if (displayed.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2), size: 70),
            const SizedBox(height: 16),
            Text('Sin resultados', style: GardenText.headingMedium),
            const SizedBox(height: 8),
            Text('Intenta cambiar los filtros', style: GardenText.bodySmall),
            if (_activeFilterCount > 0) ...[
              const SizedBox(height: 20),
              GardenButton(label: 'Limpiar filtros', onPressed: _clearAllFilters, width: 160),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: displayed.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == displayed.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: GardenColors.primary, strokeWidth: 2)),
          );
        }
        return _buildCaregiverCard(displayed[i]);
      },
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
    final zoneColor = _kZoneColors[caregiver['zone']] ?? GardenColors.primary;

    final rating = (caregiver['rating'] as num? ?? 0).toStringAsFixed(1);
    final reviewCount = caregiver['reviewCount'] as int? ?? 0;
    final firstName = caregiver['firstName'] as String? ?? '';
    final lastName = caregiver['lastName'] as String? ?? '';
    final zone = _kZoneLabels[caregiver['zone']] ?? caregiver['zone'] ?? '';
    final expYears = caregiver['experienceYears'] as int?;
    final services = (caregiver['services'] as List? ?? []).take(2).toList();

    String? priceLabel, priceUnit;
    if (_selectedService == 'hospedaje') {
      if (caregiver['pricePerDay'] != null) {
        priceLabel = 'Bs ${caregiver['pricePerDay']}'; priceUnit = '/noche';
      }
    } else if (_selectedService == 'paseo') {
      if (caregiver['pricePerWalk60'] != null) {
        priceLabel = 'Bs ${caregiver['pricePerWalk60']}'; priceUnit = '1 hora';
      } else if (caregiver['pricePerWalk30'] != null) {
        priceLabel = 'Bs ${caregiver['pricePerWalk30']}'; priceUnit = '1 hora';
      }
    } else {
      // 'todos' — mostrar paseo si tiene, si no hospedaje
      if (caregiver['pricePerWalk60'] != null) {
        priceLabel = 'Bs ${caregiver['pricePerWalk60']}'; priceUnit = '1 hora';
      } else if (caregiver['pricePerWalk30'] != null) {
        priceLabel = 'Bs ${caregiver['pricePerWalk30']}'; priceUnit = '1 hora';
      } else if (caregiver['pricePerDay'] != null) {
        priceLabel = 'Bs ${caregiver['pricePerDay']}'; priceUnit = '/noche';
      }
    }

    return GestureDetector(
      onTap: () => context.push('/caregiver/${caregiver['id']}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isVerified ? GardenColors.primary.withValues(alpha: 0.3) : borderColor),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: isVerified ? GardenColors.primary.withValues(alpha: 0.6) : borderColor,
                            width: isVerified ? 2 : 1.5),
                      ),
                      child: GardenAvatar(
                        imageUrl: caregiver['profilePicture'] as String?,
                        size: 50,
                        initials: '${firstName.isNotEmpty ? firstName[0] : "C"}${lastName.isNotEmpty ? lastName[0] : ""}',
                      ),
                    ),
                    if (isVerified)
                      Positioned(
                        bottom: 0, right: 0,
                        child: Container(
                          width: 16, height: 16,
                          decoration: const BoxDecoration(color: GardenColors.primary, shape: BoxShape.circle),
                          child: const Icon(Icons.verified_rounded, size: 10, color: Colors.white),
                        ),
                      ),
                  ]),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text('$firstName $lastName',
                                style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.star_rounded, color: GardenColors.star, size: 13),
                          const SizedBox(width: 2),
                          Text(rating, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w700)),
                          if (reviewCount > 0) ...[
                            const SizedBox(width: 2),
                            Text('($reviewCount)', style: TextStyle(color: subtextColor, fontSize: 10)),
                          ],
                        ]),
                        const SizedBox(height: 3),
                        Row(children: [
                          Container(
                            width: 7, height: 7,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(color: zoneColor, shape: BoxShape.circle),
                          ),
                          Text(zone, style: TextStyle(color: subtextColor, fontSize: 11)),
                          if (expYears != null) ...[
                            Text('  ·  ', style: TextStyle(color: subtextColor, fontSize: 11)),
                            const Icon(Icons.workspace_premium_outlined, size: 10, color: GardenColors.primary),
                            const SizedBox(width: 2),
                            Text('$expYears+ años',
                                style: const TextStyle(color: GardenColors.primary, fontSize: 10, fontWeight: FontWeight.w600)),
                          ],
                        ]),
                        if (services.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 4,
                            children: services.map((s) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: GardenColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(s.toString(),
                                  style: const TextStyle(color: GardenColors.primary, fontSize: 9, fontWeight: FontWeight.w600)),
                            )).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (priceLabel != null) ...[
                        Text(priceLabel,
                            style: GardenText.metadata.copyWith(
                                color: GardenColors.primary,
                                fontWeight: FontWeight.w900,
                                fontSize: 14)),
                        Text(priceUnit!,
                            style: TextStyle(color: subtextColor, fontSize: 10)),
                        const SizedBox(height: 8),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: GardenColors.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('Reservar',
                            style: GardenText.metadata.copyWith(
                                color: Colors.white, fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isVerified)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: GardenColors.polygon.withValues(alpha: 0.07),
                  borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14)),
                ),
                child: const Row(children: [
                  Icon(Icons.link_rounded, size: 11, color: GardenColors.polygon),
                  SizedBox(width: 5),
                  Text('Verificado en Polygon Blockchain',
                      style: TextStyle(color: GardenColors.polygon, fontSize: 10, fontWeight: FontWeight.w600)),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton() => ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 6,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: GardenCard(
            padding: EdgeInsets.all(14),
            child: Row(children: [
              GardenSkeleton(width: 50, height: 50, radius: GardenRadius.lg),
              SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                GardenSkeleton(width: 140, height: 14),
                SizedBox(height: 6),
                GardenSkeleton(width: 90, height: 12),
                SizedBox(height: 8),
                GardenSkeleton(width: 180, height: 12),
              ])),
            ]),
          ),
        ),
      );

  // ── Map Panel ─────────────────────────────────────────────────────────────

  Widget _buildMapPanel(ThemeData theme, bool isDark, Color surface, Color border) {
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    final polygons = _kZonePolygons.entries.map((e) {
      final color = _kZoneColors[e.key] ?? GardenColors.primary;
      final isSelected = _selectedZone == e.key;
      return Polygon(
        points: e.value,
        color: color.withValues(alpha: isSelected ? 0.35 : 0.15),
        borderColor: color.withValues(alpha: isSelected ? 0.9 : 0.5),
        borderStrokeWidth: isSelected ? 2.5 : 1.5,
      );
    }).toList();

    final markers = _kZoneCenters.entries.map((e) {
      final color = _kZoneColors[e.key] ?? GardenColors.primary;
      final label = _kZoneLabels[e.key] ?? e.key;
      final isSelected = _selectedZone == e.key;
      // Count caregivers in this zone
      final count = _caregivers.where((c) => c['zone'] == e.key).length;

      return Marker(
        point: e.value,
        width: 120,
        height: 40,
        child: GestureDetector(
          onTap: () => _selectZone(_selectedZone == e.key ? null : e.key),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected ? color : surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color, width: isSelected ? 0 : 1.5),
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2))],
                ),
                child: Text(
                  count > 0 ? '$label ($count)' : label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();

    return Container(
      color: surface,
      child: Column(
        children: [
          // Map header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                const Icon(Icons.map_rounded, size: 16, color: GardenColors.primary),
                const SizedBox(width: 8),
                Text('Mapa · Santa Cruz', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
                const Spacer(),
                // Zoom out button
                if (_selectedZone != null)
                  GestureDetector(
                    onTap: () {
                      _selectZone(null);
                      _mapController.move(_kSantaCruzCenter, _kDefaultZoom);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: GardenColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: GardenColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.zoom_out_map_rounded, size: 12, color: GardenColors.primary),
                        SizedBox(width: 4),
                        Text('Vista general', style: TextStyle(color: GardenColors.primary, fontSize: 10, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 18, color: subtextColor),
                  onPressed: () => setState(() => _showMap = false),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: 'Cerrar mapa',
                ),
              ],
            ),
          ),
          Container(height: 1, color: border),

          // Zone legend
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: _kZoneLabels.entries.map((e) {
                final color = _kZoneColors[e.key] ?? GardenColors.primary;
                final isSelected = _selectedZone == e.key;
                return GestureDetector(
                  onTap: () {
                    _selectZone(isSelected ? null : e.key);
                    if (!isSelected) {
                      final c = _kZoneCenters[e.key];
                      final z = _kZoneZooms[e.key] ?? 14.0;
                      if (c != null) _mapController.move(c, z);
                    } else {
                      _mapController.move(_kSantaCruzCenter, _kDefaultZoom);
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: isSelected ? color : color.withValues(alpha: 0.4)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      Text(e.value,
                          style: TextStyle(
                            color: isSelected ? color : subtextColor,
                            fontSize: 10,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          )),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
          Container(height: 1, color: border),

          // Flutter Map
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _kSantaCruzCenter,
                initialZoom: _kDefaultZoom,
                minZoom: 10,
                maxZoom: 17,
                onTap: (_, __) {
                  // Deselect zone on empty map tap
                  if (_selectedZone != null) setState(() => _selectedZone = null);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.garden.app',
                  tileBuilder: isDark ? _darkTileBuilder : null,
                ),
                PolygonLayer(polygons: polygons),
                MarkerLayer(markers: markers),
              ],
            ),
          ),

          // Map attribution
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: surface,
            child: Text('© OpenStreetMap contributors · Zonas son aproximadas',
                style: TextStyle(color: subtextColor, fontSize: 9)),
          ),
        ],
      ),
    );
  }

  // Dark tile tint for night mode
  Widget _darkTileBuilder(BuildContext context, Widget tileWidget, TileImage tile) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        -0.2126, -0.7152, -0.0722, 0, 255,
        -0.2126, -0.7152, -0.0722, 0, 255,
        -0.2126, -0.7152, -0.0722, 0, 255,
        0, 0, 0, 1, 0,
      ]),
      child: tileWidget,
    );
  }
}
