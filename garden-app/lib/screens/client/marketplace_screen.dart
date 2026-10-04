import 'dart:async';
import 'dart:convert';
import '../../services/analytics_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/zones.dart';
import '../../services/zones_service.dart';
import '../../services/cities_service.dart';
import '../../design/brote.dart';
import '../../design/garden_booking_hero_card.dart';
import '../../design/garden_icons.dart';
import '../../design/garden_service.dart';
import '../../design/garden_tiles.dart';
import '../../narrative/booking_story.dart';
import '../../theme/garden_motion.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/garden_empty_state.dart';
import '../../widgets/garden_logo_loader.dart';
import '../../widgets/notification_bell.dart';
import '../../services/auth_state.dart';
import '../../utils/web_redirect.dart';
import 'nearby_vets_screen.dart';

// ── App store links (actualizar cuando estén disponibles) ────────────────────
const _kAppStoreUrl  = 'https://apps.apple.com/app/garden-cuidadores/id000000000';
const _kPlayStoreUrl = 'https://play.google.com/store/apps/details?id=com.garden.app';

// ── Defaults antes de resolver la ciudad real del usuario (_loadZones) ──────
// Santa Cruz es el fallback para guests/perfiles sin ciudad elegida — el
// centro/zoom/polígonos reales de la ciudad del usuario se cargan async y
// reemplazan estos valores vía _cityCenter/_cityZoom/_zonePolygons (state).
const _kSantaCruzCenter = kSantaCruzCenter;
const _kDefaultZoom = kZoneMapDefaultZoom;

// ── Widget principal ──────────────────────────────────────────────────────

class MarketplaceScreen extends StatefulWidget {
  final String? initialService;
  final String? initialZone;
  final String? initialSize;
  final String? initialPetType;
  final bool isMobileShell;

  const MarketplaceScreen({
    super.key,
    this.initialService,
    this.initialZone,
    this.initialSize,
    this.initialPetType,
    this.isMobileShell = false,
  });

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  // ── Data ──
  List<Map<String, dynamic>> _caregivers = [];
  List<Map<String, dynamic>> _banners = [];
  bool _isLoading = true;
  bool _hasError = false;
  int _currentPage = 1;
  bool _hasMore = true;

  // Zonas deshabilitadas temporalmente por un admin — no deben aparecer
  // como opción en el filtro ni dibujarse en el mapa.
  Set<String> _blockedZones = {};

  // Zonas de la ciudad del usuario — dinámicas desde la API (multi-ciudad),
  // en vez de los mapas hardcodeados de constants/zones.dart. Un color/nombre
  // editado desde el panel admin se refleja acá sin necesitar un release.
  Map<String, String> _zoneLabels = {};
  Map<String, Color> _zoneColors = {};
  Map<String, LatLng> _zoneCenters = {};
  final Map<String, double> _zoneZooms = {}; // zoom fijo por zona (14.0 default)
  // Polígonos por zona (mínimo 4 puntos) — vienen de la API; zonas viejas sin
  // polígono simplemente no dibujan borde, solo el marcador de _zoneCenters.
  Map<String, List<LatLng>> _zonePolygons = {};

  // ── Ciudad del usuario logueado (multi-ciudad) — el mapa/filtros del
  // marketplace se centran y llenan según SU perfil, nunca hardcodeado a
  // Santa Cruz. Guests o cuentas sin ciudad elegida caen a Santa Cruz. ──
  String? _cityId;
  String _cityName = 'Santa Cruz';
  LatLng _cityCenter = _kSantaCruzCenter;
  double _cityZoom = _kDefaultZoom;

  // ── Filters (API) ──
  String _selectedService = 'todos';
  String? _selectedZone;
  String? _selectedPetType; // 'DOGS' | 'CATS' | null (todos)
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
  int? _filterMinSimultaneous; // null=todos, 1=solo 1, 2=al menos 2, 3=al menos 3

  // ── Sort ──
  String _sortBy = 'rating_desc';

  // ── UI state ──
  bool _showFilters = true;
  bool _showMap = false;      // se activa en desktop en el primer frame
  bool _appBannerDismissed = false;
  String _authToken = '';
  String? _userName;

  // ── Reserva activa / próxima ──
  Map<String, dynamic>? _activeBooking;

  // ── Mascotas del cliente (saludo y foto de la reserva) ──
  List<Map<String, dynamic>> _clientPets = [];

  // ── Current user id (para excluir propio perfil de cuidador) ──
  String? _currentUserId;

  /// Callback that rebuilds the active filter sheet (if open).
  VoidCallback? _refreshSheet;

  // ── Controllers ──
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  Timer? _activeBookingTimer;
  final ScrollController _scrollController = ScrollController();
  final MapController _mapController = MapController();

  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  // ── Computed ──

  int get _activeFilterCount {
    int n = 0;
    if (_selectedService != 'todos') n++;
    if (_selectedZone != null) n++;
    if (_selectedPetType != null) n++;
    if (_searchQuery.isNotEmpty) n++;
    if (_minExperienceYears != null) n++;
    if (_filterAggressive) n++;
    if (_filterPuppies) n++;
    if (_filterSeniors) n++;
    if (_selectedSizes.isNotEmpty) n++;
    if (_minRating > 0) n++;
    if (_filterVerifiedOnly) n++;
    if (_priceRange.start > 0 || _priceRange.end < 500) n++;
    if (_filterMinSimultaneous != null) n++;
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
                ? (c['pricePerWalk30'] ?? c['pricePerWalk60'] ?? 0)
                : _selectedService == 'guarderia'
                    ? (c['pricePerGuarderia'] ?? c['pricePerWalk60'] ?? 0)
                    : (c['pricePerWalk30'] ?? c['pricePerWalk60'] ?? c['pricePerDay'] ?? 0)) as num;
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

    // Simultaneous pets filter (client-side) — usa la capacidad del servicio
    // que el cliente tiene seleccionado, no el campo maxPets legado (que
    // muchos perfiles ya migrados dejan en null, excluyéndolos aunque su
    // capacidad real para ese servicio sí cumpla el filtro).
    if (_filterMinSimultaneous != null) {
      list = list.where((c) {
        final legacy = (c['maxPets'] as num?)?.toInt() ?? 1;
        int forService(String key) => (c[key] as num?)?.toInt() ?? legacy;
        if (_selectedService == 'paseo') return forService('maxPetsPaseo') >= _filterMinSimultaneous!;
        if (_selectedService == 'hospedaje') return forService('maxPetsHospedaje') >= _filterMinSimultaneous!;
        if (_selectedService == 'guarderia') return forService('maxPetsGuarderia') >= _filterMinSimultaneous!;
        // 'todos' — cumple si CUALQUIER servicio que ofrece alcanza el mínimo.
        return forService('maxPetsPaseo') >= _filterMinSimultaneous! ||
            forService('maxPetsHospedaje') >= _filterMinSimultaneous! ||
            forService('maxPetsGuarderia') >= _filterMinSimultaneous!;
      }).toList();
    }

    // Sort
    list.sort((a, b) {
      switch (_sortBy) {
        case 'price_asc':
          num _resolvePrice(Map<String, dynamic> c, num fallback) {
            if (_selectedService == 'hospedaje') return (c['pricePerDay'] ?? fallback) as num;
            if (_selectedService == 'paseo') return (c['pricePerWalk30'] ?? c['pricePerWalk60'] ?? fallback) as num;
            if (_selectedService == 'guarderia') return (c['pricePerGuarderia'] ?? c['pricePerWalk60'] ?? fallback) as num;
            return (c['pricePerWalk30'] ?? c['pricePerWalk60'] ?? c['pricePerDay'] ?? fallback) as num;
          }
          final pa = _resolvePrice(a, 999);
          final pb = _resolvePrice(b, 999);
          return pa.compareTo(pb);
        case 'price_desc':
          num _resolvePrice2(Map<String, dynamic> c) {
            if (_selectedService == 'hospedaje') return (c['pricePerDay'] ?? 0) as num;
            if (_selectedService == 'paseo') return (c['pricePerWalk30'] ?? c['pricePerWalk60'] ?? 0) as num;
            if (_selectedService == 'guarderia') return (c['pricePerGuarderia'] ?? c['pricePerWalk60'] ?? 0) as num;
            return (c['pricePerWalk30'] ?? c['pricePerWalk60'] ?? c['pricePerDay'] ?? 0) as num;
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
    if (widget.initialPetType != null) _selectedPetType = widget.initialPetType!.toUpperCase();

    _loadInitialData();
    _loadBanners();
    // Un invitado que inicia sesión sin salir de /marketplace (push a
    // /login → go de vuelta) reutiliza este mismo State — initState no
    // vuelve a correr, así que sin esto se quedaba en modo invitado hasta
    // refrescar el navegador a mano. Ver doc de loginSuccessNotifier.
    loginSuccessNotifier.addListener(_loadInitialData);
    ZonesService.getBlockedZones().then((blocked) {
      if (!mounted) return;
      setState(() {
        _blockedZones = blocked;
        // Si la zona ya elegida (ej. desde un link/preset) se bloqueó
        // mientras tanto, la limpiamos para no dejar un filtro "fantasma"
        // aplicado a una zona que ya no existe en la UI.
        if (_selectedZone != null && blocked.contains(_selectedZone)) {
          _selectedZone = null;
        }
      });
    });
    if (kIsWeb) _checkOnboarding();
    // Abrir mapa por defecto en desktop web
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final w = MediaQuery.of(context).size.width;
      if (kIsWeb && w >= 700 && !_showMap) {
        setState(() => _showMap = true);
      }
    });
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
          !_isLoading && _hasMore) {
        _loadNextPage();
      }
    });
  }

  @override
  void dispose() {
    loginSuccessNotifier.removeListener(_loadInitialData);
    _searchController.dispose();
    _searchDebounce?.cancel();
    _activeBookingTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Data loading ──

  Future<void> _loadBanners() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/banners'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && mounted) {
          setState(() => _banners = List<Map<String, dynamic>>.from(data['data'] as List? ?? []));
        }
      }
    } catch (_) {}
  }

  /// Resuelve la ciudad del usuario logueado (via /auth/me) y carga sus
  /// zonas — el marketplace nunca asume Santa Cruz salvo que el usuario no
  /// tenga ciudad elegida en su perfil (o sea un guest sin sesión).
  Future<void> _loadZones() async {
    try {
      String? profileCityId;
      String? profileZoneKey;
      final token = AuthState.token;
      if (token.isNotEmpty) {
        try {
          final res = await http.get(
            Uri.parse('$_baseUrl/auth/me'),
            headers: {'Authorization': 'Bearer $token'},
          );
          final data = jsonDecode(res.body);
          if (data['success'] == true) {
            final profile = data['data'] as Map<String, dynamic>;
            profileCityId = profile['cityId'] as String?;
            profileZoneKey = profile['addressZone'] as String?;
          }
        } catch (_) {}
      }
      // Autocompleta el filtro de zona con la del cliente — mismo criterio de
      // coherencia que la ciudad y el tipo de mascota (puede cambiarlo
      // manualmente después). Solo si no vino ya explícito desde un link
      // (initialZone) ni fue tocado a mano antes de que esto resuelva.
      if (widget.initialZone == null && _selectedZone == null && profileZoneKey != null && mounted) {
        setState(() => _selectedZone = profileZoneKey);
      }

      final cities = await CitiesService.getCities();
      final resolvedCity = (profileCityId != null
              ? cities.where((c) => c.id == profileCityId).firstOrNull
              : null) ??
          cities.where((c) => c.slug == 'santa-cruz').firstOrNull;
      if (resolvedCity == null) return;

      final zones = await CitiesService.getZones(resolvedCity.id);
      if (!mounted) return;
      setState(() {
        _cityId = resolvedCity.id;
        _cityName = resolvedCity.name;
        _cityCenter = LatLng(resolvedCity.centerLat, resolvedCity.centerLng);
        _cityZoom = resolvedCity.defaultZoom;
        _zoneLabels = {for (final z in zones) z.key: z.label};
        _zoneColors = {for (final z in zones) z.key: z.color};
        _zoneCenters = {for (final z in zones) z.key: LatLng(z.lat, z.lng)};
        _zoneZooms
          ..clear()
          ..addEntries(zones.map((z) => MapEntry(z.key, 14.0)));
        _zonePolygons = {
          for (final z in zones)
            if (z.points != null && z.points!.length >= 4) z.key: z.points!,
        };
      });
    } catch (_) {
      // Sin conexión — se mantienen los mapas vacíos hasta el próximo intento;
      // el resto de la UI ya tolera _zoneLabels/_zoneColors vacíos (fallback
      // a GardenColors.primary y a la key cruda como label).
    }
  }

  /// Autocompleta el filtro de tipo de mascota según las mascotas del cliente
  /// (mismo criterio de coherencia que _loadZones usa para la ubicación): si
  /// tiene solo perros o solo gatos, se preselecciona ese tipo; si tiene
  /// ambos o ninguno, se deja en "Todos" (null). Nunca pisa un valor ya
  /// explícito (ej. venir de un link con initialPetType) ni un guest sin
  /// sesión.
  /// Carga las mascotas del cliente (para el saludo y la foto en la tarjeta
  /// de la reserva) y, si todas son de la misma especie, preselecciona ese
  /// filtro.
  Future<void> _autoSelectPetTypeFromClientPets() async {
    final token = AuthState.token;
    if (token.isEmpty) return;
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/client/pets'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body);
      if (data['success'] != true) return;
      final pets = (data['data'] as List? ?? []).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _clientPets = pets);
      final types = pets.map((p) => p['animalType']?.toString()).whereType<String>().toSet();
      if (widget.initialPetType == null && types.length == 1 && mounted) {
        setState(() => _selectedPetType = types.first);
      }
    } catch (_) {
      // Sin conexión o error — se mantiene el default "Todos", no es crítico.
    }
  }

  Future<void> _loadInitialData() async {
    await _loadToken();
    // Resolver la ciudad ANTES de pedir cuidadores — si no, la primera carga
    // se hace sin cityId y el backend cae al default (Santa Cruz), mostrando
    // por un instante (o directamente, si el usuario no scrollea) cuidadores
    // de la ciudad equivocada para alguien en Cochabamba.
    await _loadZones();
    await _autoSelectPetTypeFromClientPets();
    await Future.wait([_loadCaregivers(reset: true), _loadActiveBooking()]);
    _activeBookingTimer?.cancel();
    _activeBookingTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) _loadActiveBooking();
    });
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
      final found = pickHeroBooking(bookings, now: DateTime.now());
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
    String token = AuthState.token;
    if (token.isEmpty) token = const String.fromEnvironment('TEST_JWT', defaultValue: '');
    if (mounted) {
      setState(() {
        _authToken = token;
        _userName = prefs.getString('user_name');
        _currentUserId = prefs.getString('user_id');
      });
    }
  }

  /// Preferencias del usuario para analítica: solo valores de catálogo
  /// (servicio, zona, tamaño…), nunca el texto de búsqueda.
  void _trackFilters() {
    final a = Analytics.instance;
    if (_selectedService != 'todos') a.filter('service', _selectedService);
    if (_selectedZone != null) a.filter('zone', _selectedZone!.toLowerCase());
    if (_selectedPetType != null) a.filter('pet_type', _selectedPetType!);
    for (final s in _selectedSizes) {
      a.filter('size', s);
    }
    if (_searchQuery.isNotEmpty) a.filter('search', 'used');
    if (_filterVerifiedOnly) a.filter('verified_only', 'on');
    if (_filterAggressive) a.filter('aggressive', 'on');
    if (_filterPuppies) a.filter('puppies', 'on');
    if (_filterSeniors) a.filter('seniors', 'on');
    if (_minRating > 0) a.filter('min_rating', _minRating);
    if (_sortBy != 'rating_desc') a.filter('sort', _sortBy);
  }

  Future<void> _loadCaregivers({bool reset = false}) async {
    if (reset) setState(() { _caregivers = []; _currentPage = 1; _hasMore = true; });
    setState(() => _isLoading = true);
    if (reset) _trackFilters();

    final params = <String, String>{
      'limit': '20',
      'page': _currentPage.toString(),
      if (_selectedService != 'todos') 'service': _selectedService,
      // El marketplace siempre filtra por ciudad (nunca mezcla cuidadores de
      // ciudades distintas) — "Todas las zonas" solo deja el filtro de zona
      // vacío, cityId sigue mandándose siempre.
      if (_cityId != null) 'cityId': _cityId!,
      if (_selectedZone != null) 'zone': _selectedZone!.toLowerCase(),
      if (_selectedPetType != null) 'petType': _selectedPetType!,
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

    // Hasta 3 intentos con timeout generoso (cold start del servidor puede tardar)
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await http.get(uri).timeout(const Duration(seconds: 25));
        final data = jsonDecode(response.body);
        if (response.statusCode == 200 && data['success'] == true) {
          var list = (data['data']['caregivers'] as List).cast<Map<String, dynamic>>();
          if (_currentUserId != null && _currentUserId!.isNotEmpty) {
            list = list.where((c) => c['userId'] != _currentUserId).toList();
          }
          final pagination = data['data']['pagination'];
          if (mounted) setState(() {
            if (reset) {
              _caregivers = list;
            } else {
              _caregivers.addAll(list);
            }
            _hasMore = _currentPage < pagination['pages'];
            _hasError = false;
            _isLoading = false;
          });
          return; // éxito
        }
      } catch (_) {
        if (attempt < 2) await Future.delayed(const Duration(seconds: 1));
      }
    }
    // Agotó los 3 intentos
    if (mounted) setState(() => _hasError = true);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadNextPage() async {
    _currentPage++;
    await _loadCaregivers();
  }

  void _clearAllFilters() {
    setState(() {
      _selectedService = 'todos';
      _selectedZone = null;
      _selectedPetType = null;
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
      _filterMinSimultaneous = null;
    });
    _loadCaregivers(reset: true);
  }

  void _selectZone(String? zone) {
    HapticFeedback.selectionClick();
    setState(() => _selectedZone = zone);
    _refreshSheet?.call();
    _loadCaregivers(reset: true);
    if (zone != null && _showMap) {
      final center = _zoneCenters[zone];
      final zoom = _zoneZooms[zone] ?? 14.0;
      if (center != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _mapController.move(center, zoom));
      }
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _getGreeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Buenos días';
    if (h < 19) return 'Buenas tardes';
    return 'Buenas noches';
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
          // _buildAppBar solo cuando el Marketplace corre standalone (sin WebShellScreen)
          if (widget.isMobileShell) _buildAppBar(theme, isDark, surface, border),
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
  // Solo el saludo queda fijo. La reserva protagonista, la búsqueda, los
  // servicios y los accesos scrollean junto con la lista para que en un
  // teléfono chico los cuidadores no queden escondidos debajo del encabezado.
  Widget _buildMobileLayout(ThemeData theme, bool isDark, Color bg, Color surface, Color border) {
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    final header = <Widget>[
      if (kIsWeb) _buildMobileAppBanner(bg, border, textColor, subtextColor, isDark),
      if (_activeBooking != null) ...[
        _buildActiveBookingCard(),
        const SizedBox(height: 14),
      ],
      _buildMobileSearchRow(theme, isDark, surface, border, textColor, subtextColor),
      const SizedBox(height: 12),
      _buildServiceTiles(),
      const SizedBox(height: 14),
      _buildShortcuts(),
      const SizedBox(height: 18),
      Text(
        _listTitle,
        style: GardenText.h4.copyWith(color: textColor, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 10),
    ];

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildGreeting(textColor, subtextColor),
            Expanded(child: _buildCaregiverList(theme, isDark, header: header)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.small(
        backgroundColor: GardenColors.primary,
        tooltip: 'Ver mapa',
        onPressed: () {
          HapticFeedback.selectionClick();
          _showMobileMapSheet(isDark);
        },
        child: const GardenIcon(GIcon.mapa, color: Colors.white, size: GIconSize.md),
      ),
    );
  }

  // ── Saludo: la persona y su mascota ──────────────────────────────────────
  Widget _buildGreeting(Color textColor, Color subtextColor) {
    final firstName = _userName?.split(' ').first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          const Brote(pose: BrotePose.hola, size: 46),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  firstName == null ? _getGreeting() : '${_getGreeting()}, $firstName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GardenText.bodySmall.copyWith(color: subtextColor, fontWeight: FontWeight.w700),
                ),
                Text(
                  _petQuestion,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GardenText.headingLarge.copyWith(color: textColor, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          if (_authToken.isNotEmpty) NotificationBell(token: _authToken, baseUrl: _baseUrl),
        ],
      ),
    );
  }

  List<String> get _petNames => _clientPets
      .map((p) => (p['name'] as String?)?.trim() ?? '')
      .where((n) => n.isNotEmpty)
      .toList();

  String get _petQuestion {
    final names = _petNames;
    if (names.isEmpty) return '¿Qué necesita tu mascota hoy?';
    if (names.length == 1) return '¿Qué hace ${names.first} hoy?';
    if (names.length == 2) return '¿Qué hacen ${names[0]} y ${names[1]} hoy?';
    return '¿Qué hacen tus mascotas hoy?';
  }

  String get _listTitle {
    final names = _petNames;
    final forWho = names.length == 1 ? 'para ${names.first}' : 'de confianza';
    return 'Cuidadores $forWho en $_cityName';
  }

  // ── Reserva protagonista ─────────────────────────────────────────────────
  Widget _buildActiveBookingCard() {
    final b = _activeBooking!;
    final id = b['id'] as String;
    final pet = _clientPets.where((p) => p['id'] == b['petId']).firstOrNull;
    final status = b['status'] as String?;
    final disputed = b['hasDisputePending'] == true;

    void openService() => context.push('/service/$id', extra: {'role': 'CLIENT', 'token': _authToken});
    void openChat() => context.push('/chat/$id', extra: {
          'otherPersonName': b['caregiverName'] ?? 'Cuidador',
          'otherPersonPhoto': b['caregiverPhoto'],
        });
    final opensService = status == 'IN_PROGRESS' || status == 'CONFIRMED' || status == 'COMPLETED';

    return GardenBookingHeroCard(
      booking: b,
      petPhotoUrl: pet?['photoUrl'] as String?,
      petSpecies: pet?['animalType'] as String?,
      onTap: opensService ? openService : () => context.push('/my-bookings'),
      onChat: status == 'COMPLETED' ? null : openChat,
      onAction: (action) {
        switch (action) {
          case StoryAction.viewMap:
          case StoryAction.viewNotes:
            openService();
          case StoryAction.chat:
            openChat();
          case StoryAction.pay:
            context.push('/payment/$id');
          case StoryAction.viewMeet:
            context.push('/meet-and-greet/$id', extra: {'role': 'CLIENT'});
          case StoryAction.chooseOtherTime:
            context.push('/slot-conflict/$id', extra: {
              'serviceType': b['serviceType'],
              'caregiverId': b['caregiverId'],
            });
          case StoryAction.viewDetail:
            if (disputed) {
              context.push('/dispute/$id', extra: {'role': 'CLIENT'});
            } else {
              openService();
            }
          case StoryAction.bookAgain:
            context.push('/caregiver/${b['caregiverId']}');
          case StoryAction.rate:
          case StoryAction.respond:
          case StoryAction.sendPhoto:
          case StoryAction.findAnother:
            context.push('/my-bookings');
        }
      },
    );
  }

  // ── Búsqueda + filtros ───────────────────────────────────────────────────
  Widget _buildMobileSearchRow(ThemeData theme, bool isDark, Color surface, Color border,
      Color textColor, Color subtextColor) {
    final hasFilters = _activeFilterCount > 0;
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: border),
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: textColor, fontSize: 14),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Busca un cuidador por nombre',
                hintStyle: TextStyle(color: subtextColor, fontSize: 14),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 6),
                  child: GardenIcon(GIcon.buscar, color: subtextColor),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 38),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
        Semantics(
          button: true,
          label: hasFilters ? 'Filtros, $_activeFilterCount activos' : 'Filtros',
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _showMobileFilterSheet(theme, isDark, surface, border);
            },
            child: AnimatedContainer(
              duration: GardenMotion.resolve(context, GardenMotion.quick),
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: hasFilters ? GardenColors.primary.withValues(alpha: 0.15) : surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: hasFilters ? GardenColors.primary : border),
              ),
              child: Stack(
                children: [
                  Center(
                    child: GardenIcon(
                      GIcon.filtros,
                      state: hasFilters ? GIconState.active : GIconState.idle,
                    ),
                  ),
                  if (hasFilters)
                    Positioned(
                      top: 5,
                      right: 5,
                      child: Container(
                        width: 15,
                        height: 15,
                        decoration: const BoxDecoration(color: GardenColors.primary, shape: BoxShape.circle),
                        child: Center(
                          child: Text('$_activeFilterCount',
                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Servicios como mosaicos (día → noche) ────────────────────────────────
  Widget _buildServiceTiles() {
    const options = <(String, GardenService?)>[
      ('todos', null),
      ('paseo', GardenService.paseo),
      ('guarderia', GardenService.guarderia),
      ('hospedaje', GardenService.hospedaje),
    ];
    return Row(
      children: [
        for (var k = 0; k < options.length; k++) ...[
          if (k > 0) const SizedBox(width: 8),
          Expanded(
            child: GardenServiceTile(
              service: options[k].$2,
              selected: _selectedService == options[k].$1,
              onTap: () {
                if (_selectedService == options[k].$1) return;
                setState(() => _selectedService = options[k].$1);
                _loadCaregivers(reset: true);
              },
            ),
          ),
        ],
      ],
    );
  }

  // ── Accesos rápidos ──────────────────────────────────────────────────────
  Widget _buildShortcuts() {
    final items = <(GIcon, String, VoidCallback)>[
      (GIcon.veterinaria, 'Veterinarias cerca',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NearbyVetsScreen()))),
      (GIcon.favorito, 'Favoritos', () => context.push('/favorites')),
      (GIcon.repetir, 'Reservas fijas', () => context.push('/recurring-bookings')),
      (GIcon.regalo, 'Invita y gana', () => context.push('/referral')),
      (GIcon.ayuda, 'Ayuda', () => context.push('/help-center')),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (icon, label, onTap) in items) GardenShortcut(icon: icon, label: label, onTap: onTap),
        ],
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildMobileAppBanner(Color bg, Color border, Color textColor, Color subtextColor, bool isDark) {
    if (_appBannerDismissed) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            GardenColors.primary.withValues(alpha: 0.08),
            GardenColors.primary.withValues(alpha: 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GardenColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: GardenColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const GardenIcon(GIcon.dispositivo, size: GIconSize.sm, color: GardenColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '¡Mejor experiencia en la app!',
                  style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              // Área de toque real de 44x44 aunque el ícono se vea chico —
              // un GestureDetector pegado al ícono de 18px era casi imposible
              // de acertar con el dedo en mobile-web.
              IconButton(
                onPressed: () => setState(() => _appBannerDismissed = true),
                icon: GardenIcon(GIcon.cerrar, size: GIconSize.sm, color: subtextColor),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                splashRadius: 20,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Descarga GARDEN para una experiencia completa con notificaciones, GPS y más.',
            style: TextStyle(color: subtextColor, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _storeBtn(
                  icon: GIcon.marcaApple,
                  label: 'App Store',
                  onTap: () => _openUrl(_kAppStoreUrl),
                  isDark: isDark),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _storeBtn(
                  icon: GIcon.marcaAndroid,
                  label: 'Play Store',
                  onTap: () => _openUrl(_kPlayStoreUrl),
                  isDark: isDark),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _storeBtn({required GIcon icon, required String label, required VoidCallback onTap, required bool isDark}) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: GardenColors.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GardenIcon(icon, size: GIconSize.xs, color: Colors.white),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );

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
      builder: (sheetContext) => SizedBox(
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
                  // El botón "X" del panel debe cerrar ESTE modal — un
                  // setState() en la pantalla de fondo no lo hace, ya que el
                  // bottom sheet es una ruta aparte manejada por Navigator.
                  onClose: () => Navigator.pop(sheetContext),
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
      height: 64,
      color: surface,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  // Logo → siempre vuelve al landing de React
                  GestureDetector(
                    onTap: () => redirectToReactLanding(),
                    child: Image.asset('assets/images/logo-horizontal.png', height: 52),
                  ),
                  const SizedBox(width: 8),
                  Text('·', style: TextStyle(color: subtextColor, fontSize: 16)),
                  const SizedBox(width: 8),
                  Text('Cuidadores en $_cityName', style: TextStyle(color: subtextColor, fontSize: 13)),
                  const Spacer(),
                  if (_authToken.isNotEmpty) ...[
                    NotificationBell(token: _authToken, baseUrl: _baseUrl),
                    _appBarBtn(GIcon.lista, 'Mis reservas', () => context.push('/my-bookings'), textColor),
                    _appBarBtn(GIcon.huella, 'Mis mascotas', () => context.push('/my-pets'), textColor),
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
                          const GardenIcon(GIcon.perfil, size: GIconSize.sm, color: GardenColors.primary),
                          const SizedBox(width: 6),
                          Text(_userName?.split(' ').first ?? 'Perfil',
                              style: const TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                        ]),
                      ),
                    ),
                  ] else ...[
                    TextButton(
                      onPressed: () => context.go('/about'),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                      child: Text('¿Quiénes somos?',
                          style: TextStyle(color: subtextColor, fontWeight: FontWeight.w500, fontSize: 13)),
                    ),
                    TextButton(
                      onPressed: () => context.go('/register'),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                      child: const Text('Ser cuidador',
                          style: TextStyle(color: GardenColors.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                    TextButton(
                      onPressed: () => context.go('/login'),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                      child: Text('Iniciar sesión',
                          style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GardenButton(label: 'Registrarse', width: 130, height: 40, onPressed: () => context.go('/register')),
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

  Widget _appBarBtn(GIcon icon, String tooltip, VoidCallback onTap, Color color) => IconButton(
        icon: GardenIcon(icon, size: GIconSize.md, color: color),
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
            icon: GIcon.filtros,
            label: _showFilters ? 'Ocultar filtros' : 'Filtros',
            badge: _activeFilterCount,
            active: _showFilters,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _showFilters = !_showFilters);
            },
            textColor: textColor),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GardenIcon(GIcon.filtros, size: GIconSize.sm, color: textColor),
                  const SizedBox(width: 6),
                  Text(_sortLabel(_sortBy), style: TextStyle(fontSize: 13, color: textColor, fontWeight: FontWeight.w500)),
                  const SizedBox(width: 4),
                  GardenIcon(GIcon.desplegar, size: GIconSize.sm, color: textColor),
                ],
              ),
            ),
            itemBuilder: (_) => [
              _sortMenuItem('rating_desc', 'Mejor valorados', GIcon.estrella),
              _sortMenuItem('price_asc', 'Precio: menor a mayor', GIcon.arriba),
              _sortMenuItem('price_desc', 'Precio: mayor a menor', GIcon.abajo),
              _sortMenuItem('experience', 'Más experiencia', GIcon.destacado),
            ],
          ),
          const SizedBox(width: 10),

          // Toggle map button
          _toolbarToggleBtn(
            icon: GIcon.mapa,
            label: _showMap ? 'Cerrar mapa' : 'Ver mapa',
            badge: 0,
            active: _showMap,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _showMap = !_showMap);
              if (!_showMap) return;
              // Animate to selected zone if any
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_selectedZone != null && _zoneCenters[_selectedZone] != null) {
                  _mapController.move(_zoneCenters[_selectedZone]!, _zoneZooms[_selectedZone] ?? 14.0);
                } else {
                  _mapController.move(_cityCenter, _cityZoom);
                }
              });
            },
            textColor: textColor),
        ],
      ),
    );
  }

  Widget _toolbarToggleBtn({
    required GIcon icon,
    required String label,
    required int badge,
    required bool active,
    required VoidCallback onTap,
    required Color textColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? GardenColors.primary.withValues(alpha: 0.1) : Colors.transparent,
          border: Border.all(color: active ? GardenColors.primary.withValues(alpha: 0.5) : GardenColors.darkBorder.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GardenIcon(icon, size: GIconSize.sm, color: active ? GardenColors.primary : textColor),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, color: active ? GardenColors.primary : textColor, fontWeight: FontWeight.w600)),
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

  PopupMenuItem<String> _sortMenuItem(String value, String label, GIcon icon) => PopupMenuItem(
        value: value,
        child: Row(children: [
          GardenIcon(icon, size: GIconSize.sm, color: GardenColors.primary),
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
                const GardenIcon(GIcon.filtros, size: GIconSize.sm, color: GardenColors.primary),
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
                  // Chips de ancho natural + scroll horizontal en vez de
                  // Expanded a partes iguales: con 4 opciones de largo muy
                  // distinto ("Todos" vs "Hospedaje 🏠"), forzar el mismo
                  // ancho partía el texto en dos líneas. Así siempre quedan
                  // en una sola línea, tanto en el sidebar web como en mobile.
                  _sectionTitle('Tipo de servicio', textColor),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _serviceChip('Todos', 'todos', textColor),
                        const SizedBox(width: 8),
                        _serviceChip('Paseo', 'paseo', textColor),
                        const SizedBox(width: 8),
                        _serviceChip('Hospedaje', 'hospedaje', textColor),
                        const SizedBox(width: 8),
                        _serviceChip('Guardería', 'guarderia', textColor),
                      ],
                    ),
                  ),
                  _divider(border),

                  // ── Tipo de mascota ──
                  _sectionTitle('Tipo de mascota', textColor),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _petTypeChip(null, 'Todos', textColor),
                        const SizedBox(width: 8),
                        _petTypeChip('DOGS', 'Perro', textColor),
                        const SizedBox(width: 8),
                        _petTypeChip('CATS', 'Gato', textColor),
                      ],
                    ),
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
                      prefixIcon: const GardenIcon(GIcon.buscar, size: GIconSize.sm, color: GardenColors.primary),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: GardenIcon(GIcon.cerrar, size: GIconSize.sm, color: subtextColor),
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
                        GardenIcon(GIcon.web, size: GIconSize.xs, color: _selectedZone == null ? GardenColors.primary : subtextColor),
                        const SizedBox(width: 8),
                        Text('Todas las zonas',
                            style: TextStyle(
                              color: _selectedZone == null ? GardenColors.primary : textColor,
                              fontWeight: _selectedZone == null ? FontWeight.w700 : FontWeight.w500,
                              fontSize: 13,
                            )),
                        if (_selectedZone == null) ...[
                          const Spacer(),
                          const GardenIcon(GIcon.hecho, size: GIconSize.xs, color: GardenColors.primary),
                        ],
                      ]),
                    ),
                  ),
                  // Zone pills — las zonas que un admin deshabilitó no se
                  // muestran como opción de filtro.
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: _zoneLabels.entries.where((e) => !_blockedZones.contains(e.key)).map((e) {
                      final isSelected = _selectedZone == e.key;
                      final color = _zoneColors[e.key] ?? GardenColors.primary;
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
                      _sizeChip('SMALL', 'Pequeño', textColor),
                      _sizeChip('MEDIUM', 'Mediano', textColor),
                      _sizeChip('LARGE', 'Grande', textColor),
                      _sizeChip('GIANT', 'Gigante', textColor),
                    ],
                  ),
                  _divider(border),

                  // ── Políticas ──
                  _sectionTitle('Políticas de aceptación', textColor),
                  const SizedBox(height: 4),
                  _filterSwitch('Acepta perros agresivos', GIcon.advertencia, _filterAggressive, (v) {
                    setState(() => _filterAggressive = v);
                    _refreshSheet?.call();
                    _loadCaregivers(reset: true);
                  }, textColor, subtextColor),
                  _filterSwitch('Acepta cachorros', GIcon.cachorro, _filterPuppies, (v) {
                    setState(() => _filterPuppies = v);
                    _refreshSheet?.call();
                    _loadCaregivers(reset: true);
                  }, textColor, subtextColor),
                  _filterSwitch('Acepta perros seniors', GIcon.salud, _filterSeniors, (v) {
                    setState(() => _filterSeniors = v);
                    _refreshSheet?.call();
                    _loadCaregivers(reset: true);
                  }, textColor, subtextColor),
                  _divider(border),

                  // ── Mascotas simultáneas ──
                  _sectionTitle('Mascotas simultáneas', textColor),
                  const SizedBox(height: 4),
                  Text('Cuidadores que aceptan cuántas mascotas a la vez',
                      style: TextStyle(color: subtextColor, fontSize: 11)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: [
                      _simultaneousChip(null, 'Cualquiera', textColor),
                      _simultaneousChip(1, 'Solo 1', textColor),
                      _simultaneousChip(2, 'Mín. 2', textColor),
                      _simultaneousChip(3, '3 mascotas', textColor),
                    ],
                  ),
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
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedService = value);
        _refreshSheet?.call();
        _loadCaregivers(reset: true);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? GardenColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? GardenColors.primary : GardenColors.darkBorder.withValues(alpha: 0.3)),
        ),
        child: Text(label,
            softWrap: false,
            style: TextStyle(
              color: selected ? Colors.white : textColor,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 12,
            )),
      ),
    );
  }

  Widget _petTypeChip(String? val, String label, Color textColor) {
    final selected = _selectedPetType == val;
    return GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedPetType = val);
          _refreshSheet?.call();
          _loadCaregivers(reset: true);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? GardenColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? GardenColors.primary : GardenColors.darkBorder.withValues(alpha: 0.3)),
          ),
          child: Text(label,
              softWrap: false,
              style: TextStyle(
                color: selected ? Colors.white : textColor,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12,
              )),
        ),
    );
  }

  Widget _expChip(int? val, String label, Color textColor) {
    final selected = _minExperienceYears == val;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
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
        HapticFeedback.selectionClick();
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
        HapticFeedback.selectionClick();
        setState(() => _minRating = selected ? 0 : val);
        _refreshSheet?.call();
      },
      child: _smallChip(label, selected, textColor),
    );
  }

  Widget _simultaneousChip(int? val, String label, Color textColor) {
    final selected = _filterMinSimultaneous == val;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _filterMinSimultaneous = selected ? null : val);
        _refreshSheet?.call();
      },
      child: _smallChip(label, selected, textColor),
    );
  }

  Widget _smallChip(String label, bool selected, Color textColor) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? GardenColors.primary.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? GardenColors.primary : GardenColors.darkBorder.withValues(alpha: 0.3)),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? GardenColors.primary : textColor,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 12,
            )),
      );

  Widget _filterSwitch(String label, GIcon icon, bool value, Function(bool) onChanged,
      Color textColor, Color subtextColor) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          GardenIcon(icon, size: GIconSize.sm, color: value ? GardenColors.primary : subtextColor),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(color: textColor, fontSize: 12))),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: value,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                onChanged(v);
              },
              activeColor: GardenColors.primary,
            ),
          ),
        ]),
      );

  // ── Caregiver List ────────────────────────────────────────────────────────

  /// [header]: widgets que scrollean arriba de la lista (layout móvil).
  Widget _buildCaregiverList(ThemeData theme, bool isDark, {List<Widget> header = const []}) {
    final displayed = _displayCaregivers;
    final pad = header.isEmpty
        ? const EdgeInsets.all(GardenSpacing.lg)
        : const EdgeInsets.fromLTRB(16, 4, 16, 96);

    // Estado vacío o error debajo del encabezado, sin perder el encabezado.
    Widget withHeader(Widget state) => header.isEmpty
        ? state
        : ListView(padding: pad, children: [...header, SizedBox(height: 320, child: state)]);

    // Skeleton cards que calcan el layout final de la tarjeta de cuidador —
    // se percibe mucho más premium que un spinner genérico en una pantalla
    // tan cargada de listas como el marketplace.
    if (_isLoading && _caregivers.isEmpty) {
      return ListView(
        padding: pad,
        children: [...header, for (var k = 0; k < 5; k++) _buildCaregiverCardSkeleton(isDark)],
      );
    }
    if (_hasError && _caregivers.isEmpty) {
      return withHeader(GardenEmptyState(
        type: GardenEmptyType.generic,
        brote: BrotePose.oops,
        title: 'No pudimos conectar',
        subtitle: 'Revisa tu conexión a internet e intenta de nuevo. Tus filtros quedaron guardados.',
        ctaLabel: 'Reintentar',
        onCta: () => _loadCaregivers(reset: true),
      ));
    }
    if (displayed.isEmpty && !_isLoading) {
      return withHeader(GardenEmptyState(
        type: GardenEmptyType.caregivers,
        title: 'Sin cuidadores disponibles',
        subtitle: _activeFilterCount > 0
            ? 'Ningún cuidador coincide con tus filtros. Prueba ampliar la zona o quitar algún filtro.'
            : 'No hay cuidadores disponibles en este momento. Vuelve a intentar en un rato.',
        ctaLabel: _activeFilterCount > 0 ? 'Limpiar filtros' : null,
        onCta: _activeFilterCount > 0 ? _clearAllFilters : null,
      ));
    }

    // Construir lista combinada: cuidadores + banners intercalados por position
    // Cada elemento es {'type': 'caregiver'|'banner', 'data': {...}}
    final List<Map<String, dynamic>> items = [];
    for (int i = 0; i <= displayed.length; i++) {
      // Insertar banners cuya posición == i (antes del cuidador i)
      for (final b in _banners) {
        final pos = (b['position'] as int? ?? 0).clamp(0, displayed.length);
        if (pos == i) items.add({'type': 'banner', 'data': b});
      }
      if (i < displayed.length) {
        items.add({'type': 'caregiver', 'data': displayed[i]});
      }
    }

    return RefreshIndicator(
      color: GardenColors.primary,
      onRefresh: () => _loadCaregivers(reset: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: pad,
        // Siempre scrolleable para que el pull-to-refresh funcione incluso
        // con pocos resultados que no llenan la pantalla.
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: header.length + items.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index < header.length) return header[index];
          final i = index - header.length;
          if (i == items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: GardenLogoLoader(size: 120),
            );
          }
          final item = items[i];
          // Entrada escalonada sutil — no gratuita: duración corta y delay
          // acotado para que no se sienta lenta ni en listas largas.
          final delayMs = (i.clamp(0, 6) * 40);
          Widget card = item['type'] == 'banner'
              ? _buildBannerCard(item['data'] as Map<String, dynamic>)
              : _buildCaregiverCard(item['data'] as Map<String, dynamic>);
          return card
              .animate()
              .fadeIn(duration: GardenMotion.quick, delay: delayMs.ms)
              .slideY(begin: 0.04, end: 0, duration: GardenMotion.quick, curve: GardenMotion.enter);
        },
      ),
    );
  }

  /// Skeleton que calca el layout de [_buildCaregiverCard] mientras carga.
  Widget _buildCaregiverCardSkeleton(bool isDark) {
    final cardBg = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    return Container(
      margin: const EdgeInsets.only(bottom: GardenSpacing.md),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: GardenRadius.lg_,
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const GardenSkeleton(width: 58, height: 58, radius: 29),
          const SizedBox(width: GardenSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const GardenSkeleton(width: 130, height: 14),
                const SizedBox(height: GardenSpacing.sm),
                const GardenSkeleton(width: 90, height: 11),
                const SizedBox(height: GardenSpacing.sm + 2),
                GardenSkeleton(width: 100, height: 18, radius: GardenRadius.full),
              ],
            ),
          ),
          const SizedBox(width: GardenSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const GardenSkeleton(width: 50, height: 14),
              const SizedBox(height: GardenSpacing.sm),
              GardenSkeleton(width: 70, height: 28, radius: GardenRadius.full),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBannerCard(Map<String, dynamic> banner) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final imageUrl = banner['imageUrl'] as String?;
    final title = banner['title'] as String? ?? '';
    final subtitle = banner['subtitle'] as String?;
    final buttonText = banner['buttonText'] as String?;
    final actionType = banner['actionType'] as String? ?? 'none';
    final actionValue = banner['actionValue'] as String?;

    // Rutas internas permitidas para banners (whitelist de seguridad)
    const _allowedRoutes = {
      '/marketplace', '/my-bookings-tab', '/my-pets-tab',
      '/service-selector', '/profile', '/wallet',
    };

    Future<void> handleTap() async {
      if (actionType == 'url' && actionValue != null) {
        final uri = Uri.tryParse(actionValue);
        // Solo URLs con esquema http/https permitidas
        if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } else if (actionType == 'screen' && actionValue != null) {
        if (_allowedRoutes.contains(actionValue)) {
          context.push(actionValue);
        }
      }
    }

    return GardenPressable(
      pressedScale: 0.97,
      onTap: actionType != 'none'
          ? () {
              HapticFeedback.selectionClick();
              handleTap();
            }
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        height: 180, // mismo alto que tarjeta de cuidador
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isDark ? GardenColors.darkSurface : GardenColors.lightSurface,
          image: imageUrl != null && imageUrl.isNotEmpty
              ? DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover)
              : null,
          boxShadow: GardenShadows.card,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.15),
                Colors.black.withValues(alpha: 0.65),
              ],
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  shadows: [Shadow(color: Colors.black38, blurRadius: 4)],
                )),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 13,
                    height: 1.4,
                  )),
              ],
              if (buttonText != null && buttonText.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: GardenColors.primary,
                    borderRadius: BorderRadius.circular(GardenRadius.full),
                  ),
                  child: Text(buttonText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    )),
                ),
              ],
            ],
          ),
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
    final zoneColor = _zoneColors[caregiver['zone']] ?? GardenColors.primary;

    final rating = (caregiver['rating'] as num? ?? 0).toStringAsFixed(1);
    final reviewCount = caregiver['reviewCount'] as int? ?? 0;
    final firstName = caregiver['firstName'] as String? ?? '';
    final lastName = caregiver['lastName'] as String? ?? '';
    final isCompany = caregiver['isCompany'] == true;
    final companyName = caregiver['companyName'] as String?;
    final displayName = (isCompany && (companyName?.isNotEmpty ?? false))
        ? companyName!
        : '$firstName $lastName';
    final zone = _zoneLabels[caregiver['zone']] ?? caregiver['zone'] ?? '';
    final expYears = caregiver['experienceYears'] as int?;
    final allServices = (caregiver['services'] as List? ?? []);
    final services = allServices.take(3).toList();
    // Set de servicios realmente habilitados (servicesOffered) — un precio
    // guardado en la BD (ej. Guardería pre-rellenada con el precio de Paseo)
    // no implica que el cuidador ofrezca ese servicio hoy.
    final servicesSet = allServices.map((s) => s.toString()).toSet();

    // Precios a mostrar: (monto, unidad, servicio). Solo si el servicio está
    // habilitado Y el precio > 0. El servicio se dibuja con su icono propio.
    final List<(String, String, GardenService)> prices = [];
    final priceDay = caregiver['pricePerDay'];
    final priceWalk60 = caregiver['pricePerWalk60'];
    final priceWalk30 = caregiver['pricePerWalk30'];
    final bool hasDayPrice = servicesSet.contains('HOSPEDAJE') && priceDay != null && (priceDay as num) > 0;
    final bool hasWalk60Price = servicesSet.contains('PASEO') && priceWalk60 != null && (priceWalk60 as num) > 0;
    final bool hasWalk30Price = servicesSet.contains('PASEO') && priceWalk30 != null && (priceWalk30 as num) > 0;

    final priceGuarderia = caregiver['pricePerGuarderia'];
    final bool hasGuarderiaPrice = servicesSet.contains('GUARDERIA') && priceGuarderia != null && (priceGuarderia as num) > 0;

    final walk = ('Bs $priceWalk30', '30 min', GardenService.paseo);
    final day = ('Bs $priceGuarderia', '/hora', GardenService.guarderia);
    final night = ('Bs $priceDay', '/noche', GardenService.hospedaje);
    if (_selectedService == 'hospedaje') {
      if (hasDayPrice) prices.add(night);
    } else if (_selectedService == 'paseo') {
      if (hasWalk30Price) prices.add(walk);
    } else if (_selectedService == 'guarderia') {
      if (hasGuarderiaPrice) prices.add(day);
    } else {
      // 'todos' — solo los servicios que el cuidador ofrece de verdad
      if (hasWalk30Price) prices.add(walk);
      if (hasGuarderiaPrice) prices.add(day);
      if (hasDayPrice) prices.add(night);
    }

    return GardenPressable(
      pressedScale: 0.97,
      onTap: () {
        HapticFeedback.lightImpact();
        if (!AuthState.hasSession) {
          context.push('/login', extra: {
            'returnTo': '/caregiver/${caregiver['id']}',
            'caregiverData': caregiver,
          });
        } else {
          context.push('/caregiver/${caregiver['id']}', extra: caregiver);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isVerified ? GardenColors.primary.withValues(alpha: 0.3) : borderColor),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.06), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
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
                      child: Hero(
                        tag: 'caregiver-${caregiver['id']}',
                        child: GardenAvatar(
                        imageUrl: caregiver['profilePicture'] as String?,
                        size: 58,
                        initials: (isCompany && (companyName?.isNotEmpty ?? false))
                            ? companyName![0]
                            : '${firstName.isNotEmpty ? firstName[0] : "C"}${lastName.isNotEmpty ? lastName[0] : ""}',
                        ),
                      ),
                    ),
                    if (isVerified)
                      Positioned(
                        bottom: 0, right: 0,
                        child: Container(
                          width: 18, height: 18,
                          decoration: const BoxDecoration(color: GardenColors.primary, shape: BoxShape.circle),
                          child: const GardenIcon(GIcon.verificado,
                              size: GIconSize.xs, color: Colors.white, state: GIconState.active,
                              semanticLabel: 'Verificado'),
                        ),
                      ),
                  ]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayName,
                            maxLines: 1,
                            style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 3),
                        // Calificación, zona y experiencia como grupos: si no
                        // entran en una línea, bajan enteros (sin "·" colgando).
                        Wrap(spacing: 10, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            const GardenIcon(GIcon.estrella,
                                color: GardenColors.star, size: GIconSize.xs, state: GIconState.active),
                            const SizedBox(width: 2),
                            Text(reviewCount > 0 ? rating : 'Nuevo',
                                style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w700)),
                            if (reviewCount > 0) ...[
                              const SizedBox(width: 2),
                              Text('($reviewCount)', style: TextStyle(color: subtextColor, fontSize: 10)),
                            ],
                          ]),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              width: 7, height: 7,
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(color: zoneColor, shape: BoxShape.circle),
                            ),
                            Text(zone, style: TextStyle(color: subtextColor, fontSize: 11)),
                          ]),
                          if (expYears != null)
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              const GardenIcon(GIcon.antecedentes, size: GIconSize.xs, color: GardenColors.primary),
                              const SizedBox(width: 2),
                              Text('$expYears+ años',
                                  style: const TextStyle(color: GardenColors.primary, fontSize: 10, fontWeight: FontWeight.w600)),
                            ]),
                        ]),
                        if (services.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              for (final svc in services
                                  .map((s) => GardenService.fromApi(s.toString()))
                                  .whereType<GardenService>())
                                Container(
                                  padding: const EdgeInsets.fromLTRB(5, 2, 8, 2),
                                  decoration: BoxDecoration(
                                    color: svc.soft(isDark),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    GardenIcon(GIcon.forService(svc), size: GIconSize.sm, state: GIconState.active),
                                    const SizedBox(width: 3),
                                    Text(svc.label,
                                        style: TextStyle(color: svc.ink(isDark), fontSize: 10, fontWeight: FontWeight.w700)),
                                  ]),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (prices.isNotEmpty) ...[
                        ...prices.map((p) => Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(p.$1,
                                style: GardenText.metadata.copyWith(
                                    color: GardenColors.primary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13)),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              if (prices.length > 1) ...[
                                GardenIcon(GIcon.forService(p.$3), size: GIconSize.xs, state: GIconState.active),
                                const SizedBox(width: 3),
                              ],
                              Text(p.$2, style: TextStyle(color: subtextColor, fontSize: 10)),
                            ]),
                            if (prices.length > 1 && p != prices.last) const SizedBox(height: 4),
                          ],
                        )),
                        const SizedBox(height: 8),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: GardenColors.primary,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: GardenColors.primary.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text('Reservar',
                            style: GardenText.metadata.copyWith(
                                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
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

  // ── Map Panel ─────────────────────────────────────────────────────────────

  Widget _buildMapPanel(ThemeData theme, bool isDark, Color surface, Color border, {VoidCallback? onClose}) {
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;

    // Las zonas deshabilitadas por un admin desaparecen del mapa — ni su
    // polígono ni su marcador se dibujan mientras estén bloqueadas.
    final polygons = _zonePolygons.entries.where((e) => !_blockedZones.contains(e.key)).map((e) {
      final color = _zoneColors[e.key] ?? GardenColors.primary;
      final isSelected = _selectedZone == e.key;
      return Polygon(
        points: e.value,
        color: color.withValues(alpha: isSelected ? 0.35 : 0.15),
        borderColor: color.withValues(alpha: isSelected ? 0.9 : 0.5),
        borderStrokeWidth: isSelected ? 2.5 : 1.5,
      );
    }).toList();

    final markers = _zoneCenters.entries.where((e) => !_blockedZones.contains(e.key)).map((e) {
      final color = _zoneColors[e.key] ?? GardenColors.primary;
      final label = _zoneLabels[e.key] ?? e.key;
      final isSelected = _selectedZone == e.key;
      // Count caregivers in this zone
      final count = _caregivers.where((c) => c['zone'] == e.key).length;

      return Marker(
        point: e.value,
        width: 120,
        height: 40,
        child: GardenPressable(
          pressedScale: 0.88,
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
                const GardenIcon(GIcon.mapa, size: GIconSize.sm, color: GardenColors.primary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Mapa · $_cityName',
                    style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const Spacer(),
                // Zoom out button
                if (_selectedZone != null)
                  GestureDetector(
                    onTap: () {
                      _selectZone(null);
                      _mapController.move(_cityCenter, _cityZoom);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: GardenColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: GardenColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        GardenIcon(GIcon.ampliar, size: GIconSize.xs, color: GardenColors.primary),
                        SizedBox(width: 4),
                        Text('Vista general', style: TextStyle(color: GardenColors.primary, fontSize: 10, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                const SizedBox(width: 4),
                IconButton(
                  icon: GardenIcon(GIcon.cerrar, size: GIconSize.sm, color: subtextColor),
                  onPressed: onClose ?? () => setState(() => _showMap = false),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: 'Cerrar mapa',
                ),
              ],
            ),
          ),
          Container(height: 1, color: border),

          // Zone legend — misma exclusión de zonas bloqueadas
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: _zoneLabels.entries.where((e) => !_blockedZones.contains(e.key)).map((e) {
                final color = _zoneColors[e.key] ?? GardenColors.primary;
                final isSelected = _selectedZone == e.key;
                return GestureDetector(
                  onTap: () {
                    _selectZone(isSelected ? null : e.key);
                    if (!isSelected) {
                      final c = _zoneCenters[e.key];
                      final z = _zoneZooms[e.key] ?? 14.0;
                      if (c != null) _mapController.move(c, z);
                    } else {
                      _mapController.move(_cityCenter, _cityZoom);
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
                initialCenter: _cityCenter,
                initialZoom: _cityZoom,
                minZoom: 10,
                maxZoom: 17,
                onTap: (_, __) {
                  // Deselect zone on empty map tap
                  if (_selectedZone != null) setState(() => _selectedZone = null);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: isDark
                      ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                      : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.garden.bolivia',
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
