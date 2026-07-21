import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/cities_service.dart';
import '../services/zones_service.dart';
import 'address_map_picker.dart';

/// Sección de dirección reutilizable: abre el mapa picker primero,
/// luego muestra los campos de texto detallados y un selector de
/// ciudad + zona. Usada en el wizard del cuidador y en el registro
/// del dueño de mascota.
class AddressSection extends StatefulWidget {
  final bool isDark;
  final Color textColor;
  final Color subtextColor;
  final Color borderColor;
  final Color surfaceEl;
  final TextEditingController streetController;
  final TextEditingController numberController;
  final TextEditingController apartmentController;
  final TextEditingController condominioController;
  final TextEditingController referenceController;
  // Zona como dropdown — reemplaza zoneController. `selectedZone` guarda el
  // `key` de la zona (ej. "EQUIPETROL"), igual que antes.
  final String? selectedZone;
  final void Function(String?) onZoneChanged;
  // Ciudad — nuevo (multi-ciudad). Opcional: si no se maneja desde afuera,
  // el widget la gestiona solo (default Santa Cruz) sin romper pantallas
  // que todavía no la usan.
  final String? initialCityId;
  final void Function(String cityId, String cityName)? onCityChanged;
  /// Se llama cuando el usuario cambia de ciudad — el padre debe limpiar
  /// addressLat/Lng/street/número/dpto/condominio/referencia (la ubicación
  /// exacta ya no es válida para la ciudad nueva, hay que volver a marcarla).
  final VoidCallback? onCityChangeReset;
  final double? addressLat;
  final double? addressLng;
  final bool isApartment;
  final String purposeText;
  final void Function(AddressMapResult) onMapResult;
  final void Function(bool) onApartmentToggle;
  /// Opcional — se llama en cada tecla de calle/número/etc. para que un padre
  /// que gatea un botón "Guardar" con un valor derivado de estos controllers
  /// (ej. MyDataScreen) se entere y se reconstruya. Los demás usuarios de este
  /// widget no lo necesitan porque ya validan solo al tocar su propio botón.
  final VoidCallback? onFieldsChanged;
  /// Se llama con `true` cuando el pin cae fuera de todos los polígonos de
  /// zona conocidos (Garden todavía no cubre esa zona — caso excepcional, se
  /// permite continuar sin zona) y con `false` cuando el pin sí matchea una
  /// zona o vuelve a quedar indeterminado (sin pin, cambio de ciudad, etc).
  /// El padre lo usa para no exigir "selecciona tu zona" en el caso
  /// excepcional confirmado.
  final ValueChanged<bool>? onZoneCoverageResolved;
  /// Cuando es true (solo el registro de dueño de mascota lo usa hoy), las
  /// sub-secciones internas (calle/número, zona+dpto+referencia) aparecen
  /// recién cuando la anterior está completa, en vez de mostrarse todas de
  /// una — mismo espíritu de revelado progresivo que el resto del formulario
  /// de registro. El resto de los usuarios de este widget (wizard de
  /// cuidador, Mis Datos) no lo pasan y mantienen el comportamiento actual.
  final bool progressive;

  const AddressSection({
    super.key,
    required this.isDark,
    required this.textColor,
    required this.subtextColor,
    required this.borderColor,
    required this.surfaceEl,
    required this.streetController,
    required this.numberController,
    required this.apartmentController,
    required this.condominioController,
    required this.referenceController,
    required this.selectedZone,
    required this.onZoneChanged,
    this.initialCityId,
    this.onCityChanged,
    this.onCityChangeReset,
    this.addressLat,
    this.addressLng,
    required this.isApartment,
    required this.purposeText,
    required this.onMapResult,
    required this.onApartmentToggle,
    this.onFieldsChanged,
    this.onZoneCoverageResolved,
    this.progressive = false,
  });

  @override
  State<AddressSection> createState() => _AddressSectionState();
}

class _AddressSectionState extends State<AddressSection> {
  List<GardenCity> _cities = [];
  String? _selectedCityId;
  bool _loadingCities = true;

  // ── Auto-completado + bloqueo de zona por polígono ──────────────────────
  // Si la ubicación exacta que el usuario marcó en el mapa cae dentro del
  // polígono de una zona (cargado por el admin), la zona se llena sola y se
  // bloquea — evita que alguien elija a mano una zona distinta de donde
  // realmente está su pin (fraude de zona). Zonas sin polígono todavía
  // cargado no bloquean nada — el usuario sigue eligiendo a mano.
  List<GardenZone> _zonesForMatch = [];
  bool _zoneLocked = false;
  // true cuando ya se cargaron las zonas de la ciudad y el pin confirmado no
  // cae en ninguna — a diferencia de _zoneLocked==false "normal" (todavía no
  // hay pin, o las zonas ni cargaron), este es un resultado definitivo.
  bool _zoneNoMatch = false;
  bool _loadingZonesForMatch = true;

  InputDecoration _field(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
      );

  @override
  void initState() {
    super.initState();
    _loadCities();
    // Modo progresivo: la sub-sección de zona depende de que calle/avenida
    // ya tenga texto — sin este listener, el widget no se repinta solo con
    // el controller cambiando (el padre sí lo hace vía onFieldsChanged, pero
    // esa reconstrucción es de afuera hacia adentro, no alcanza para que
    // ESTE widget decida mostrar u ocultar su propia sub-sección).
    if (widget.progressive) {
      widget.streetController.addListener(_onProgressiveFieldChanged);
    }
  }

  void _onProgressiveFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (widget.progressive) {
      widget.streetController.removeListener(_onProgressiveFieldChanged);
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(AddressSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pinChanged = widget.addressLat != oldWidget.addressLat || widget.addressLng != oldWidget.addressLng;
    if (pinChanged && widget.addressLat != null && widget.addressLng != null) {
      _matchZoneByPoint(LatLng(widget.addressLat!, widget.addressLng!));
    }
  }

  Future<void> _loadCities() async {
    final cities = await CitiesService.getCities();
    if (!mounted) return;
    setState(() {
      _cities = cities;
      _loadingCities = false;
      _selectedCityId = widget.initialCityId ??
          (cities.isNotEmpty
              ? cities.firstWhere((c) => c.slug == 'santa-cruz', orElse: () => cities.first).id
              : null);
    });
    // Si el default (o initialCityId) ya resuelve una ciudad válida, avisarle
    // al padre aunque el usuario nunca haya tocado el dropdown — si no, el
    // padre nunca se entera de la ciudad y el perfil se guarda con
    // cityId null, invisible en el marketplace aunque la UI muestre la
    // ciudad correcta seleccionada.
    if (_selectedCityId != null) {
      final selected = cities.where((c) => c.id == _selectedCityId).firstOrNull;
      if (selected != null) widget.onCityChanged?.call(selected.id, selected.name);
    }
    if (_selectedCityId != null) await _loadZonesForMatch(_selectedCityId!);
    // Si ya había un pin cargado (ej. editando un perfil existente), corre
    // el match apenas se conocen las zonas de la ciudad.
    if (widget.addressLat != null && widget.addressLng != null) {
      _matchZoneByPoint(LatLng(widget.addressLat!, widget.addressLng!));
    }
  }

  Future<void> _loadZonesForMatch(String cityId) async {
    final zones = await CitiesService.getZones(cityId);
    if (mounted) setState(() {
      _zonesForMatch = zones;
      _loadingZonesForMatch = false;
    });
  }

  /// Ray casting estándar — true si [point] cae dentro de [polygon].
  bool _pointInPolygon(LatLng point, List<LatLng> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].longitude, yi = polygon[i].latitude;
      final xj = polygon[j].longitude, yj = polygon[j].latitude;
      final intersect = ((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  void _matchZoneByPoint(LatLng point) {
    for (final zone in _zonesForMatch) {
      final points = zone.points;
      if (points == null || points.length < 4) continue;
      if (_pointInPolygon(point, points)) {
        // _matchZoneByPoint corre sincrónicamente dentro de didUpdateWidget,
        // que a su vez se dispara en medio del build del padre (ej. justo al
        // volver del selector de mapa). Llamar a widget.onZoneChanged aquí
        // dispara un setState() en el padre mientras todavía se está
        // reconstruyendo — "setState() or markNeedsBuild() called during
        // build". Se difiere al próximo frame para evitarlo.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _zoneLocked = true;
            _zoneNoMatch = false;
          });
          if (widget.selectedZone != zone.key) widget.onZoneChanged(zone.key);
          widget.onZoneCoverageResolved?.call(false);
        });
        return;
      }
    }
    // El pin no cae en ningún polígono conocido. Si las zonas de la ciudad ya
    // cargaron, es un resultado definitivo: Garden todavía no cubre ese
    // punto — se bloquea la selección manual (en vez de dejarla abierta,
    // como antes) y se avisa al padre para que permita continuar sin zona.
    final zonesLoaded = _zonesForMatch.isNotEmpty || !_loadingZonesForMatch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _zoneLocked = false;
        _zoneNoMatch = zonesLoaded;
      });
      if (zonesLoaded) {
        if (widget.selectedZone != null) widget.onZoneChanged(null);
        widget.onZoneCoverageResolved?.call(true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedCity = _cities.where((c) => c.id == _selectedCityId).firstOrNull;
    final bool hasPin = widget.addressLat != null && widget.addressLng != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Aviso de privacidad ───────────────────────────────────
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF16a34a).withAlpha(20),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF16a34a).withAlpha(50)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: Color(0xFF16a34a), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.purposeText,
                  style: TextStyle(fontSize: 12, color: widget.subtextColor),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── Ciudad ─────────────────────────────────────────────────
        Text('Ciudad', style: TextStyle(color: widget.textColor, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: widget.surfaceEl,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: widget.borderColor),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedCityId,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              dropdownColor: widget.isDark ? const Color(0xFF1E1E2E) : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              hint: _loadingCities
                  ? Text('Cargando ciudades...', style: TextStyle(color: widget.subtextColor, fontSize: 14))
                  : Text('Selecciona tu ciudad', style: TextStyle(color: widget.subtextColor, fontSize: 14)),
              items: _cities
                  .map((c) => DropdownMenuItem(
                        value: c.id,
                        child: Row(children: [
                          const Icon(Icons.location_city_rounded, size: 18, color: Color(0xFF16a34a)),
                          const SizedBox(width: 10),
                          Text(c.name, style: TextStyle(color: widget.textColor, fontSize: 14)),
                        ]),
                      ))
                  .toList(),
              onChanged: (cityId) {
                if (cityId == null || cityId == _selectedCityId) return;
                setState(() {
                  _selectedCityId = cityId;
                  _zoneLocked = false;
                  _zoneNoMatch = false;
                  _loadingZonesForMatch = true;
                  _zonesForMatch = [];
                });
                widget.onZoneChanged(null); // cambiar de ciudad resetea la zona elegida
                widget.onZoneCoverageResolved?.call(false);
                _loadZonesForMatch(cityId);
                final city = _cities.firstWhere((c) => c.id == cityId);
                widget.onCityChanged?.call(cityId, city.name);
                // La ubicación exacta marcada en el mapa pertenecía a la
                // ciudad anterior — hay que volver a marcarla para la nueva
                // ciudad (evita, ej., decir que vivís en Cochabamba con un
                // pin que en realidad quedó puesto en Santa Cruz).
                widget.onCityChangeReset?.call();
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Botón abrir mapa ──────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: Icon(
              hasPin ? Icons.edit_location_alt : Icons.add_location_alt_outlined,
              color: hasPin ? const Color(0xFF16a34a) : null,
            ),
            label: Text(
              hasPin
                  ? '📍 Ubicación confirmada — toca para ajustar'
                  : 'Abrir mapa y confirmar ubicación',
              style: TextStyle(
                color: hasPin ? const Color(0xFF16a34a) : null,
                fontWeight: hasPin ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side: BorderSide(
                color: hasPin ? const Color(0xFF16a34a) : Colors.grey.shade400,
              ),
            ),
            onPressed: () async {
              final result = await showAddressMapPicker(
                context,
                initialLat: widget.addressLat,
                initialLng: widget.addressLng,
                purpose: widget.purposeText,
                cityLat: selectedCity?.centerLat ?? -17.775,
                cityLng: selectedCity?.centerLng ?? -63.175,
                cityName: selectedCity?.name ?? 'tu ciudad',
              );
              if (result != null) widget.onMapResult(result);
            },
          ),
        ),
        const SizedBox(height: 16),

        // ── Campos de dirección ───────────────────────────────────
        // En modo progresivo, calle/avenida recién aparece una vez hay pin
        // confirmado — evita mostrar todo el bloque de dirección de una.
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: (!widget.progressive || hasPin)
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: widget.streetController,
                          style: TextStyle(color: widget.textColor),
                          onChanged: (_) => widget.onFieldsChanged?.call(),
                          decoration: _field('Calle / Avenida', Icons.signpost_outlined),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: widget.numberController,
                          style: TextStyle(color: widget.textColor),
                          decoration: _field('N° casa', Icons.tag),
                          keyboardType: TextInputType.text,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                  ],
                )
              : const SizedBox.shrink(),
        ),

        // ── Zona / Barrio + departamento + referencia ─────────────
        // En modo progresivo, recién aparece cuando ya se escribió la calle.
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: (!widget.progressive || (hasPin && widget.streetController.text.trim().isNotEmpty))
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_selectedCityId != null)
                      _ZoneDropdownWithMap(
                        key: ValueKey(_selectedCityId),
                        isDark: widget.isDark,
                        textColor: widget.textColor,
                        subtextColor: widget.subtextColor,
                        borderColor: widget.borderColor,
                        surfaceEl: widget.surfaceEl,
                        cityId: _selectedCityId!,
                        selectedZone: widget.selectedZone,
                        onZoneChanged: widget.onZoneChanged,
                        locked: _zoneLocked || _zoneNoMatch,
                        noMatchHint: _zoneNoMatch,
                      ),
                    if (_zoneLocked)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(children: [
                          Icon(Icons.lock_outline_rounded, size: 14, color: widget.subtextColor),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Zona detectada automáticamente según tu ubicación exacta — no se puede cambiar a mano.',
                              style: TextStyle(color: widget.subtextColor, fontSize: 11.5),
                            ),
                          ),
                        ]),
                      ),
                    if (_zoneNoMatch)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(children: [
                          Icon(Icons.schedule_rounded, size: 14, color: widget.subtextColor),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Todavía no llegamos a tu zona — puedes crear tu cuenta igual, y te avisaremos apenas esté disponible para reservar.',
                              style: TextStyle(color: widget.subtextColor, fontSize: 11.5),
                            ),
                          ),
                        ]),
                      ),

                    const SizedBox(height: 12),

                    // Checkbox departamento
                    GestureDetector(
                      onTap: () => widget.onApartmentToggle(!widget.isApartment),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: widget.isApartment ? const Color(0xFF16a34a) : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: widget.isApartment ? const Color(0xFF16a34a) : Colors.grey.shade400,
                                width: 2,
                              ),
                            ),
                            child: widget.isApartment
                                ? const Icon(Icons.check, color: Colors.white, size: 14)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Vivo en departamento / edificio',
                            style: TextStyle(color: widget.textColor, fontSize: 14),
                          ),
                        ],
                      ),
                    ),

                    if (widget.isApartment) ...[
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: TextFormField(
                            controller: widget.apartmentController,
                            style: TextStyle(color: widget.textColor),
                            decoration: _field('Número de dpto.', Icons.meeting_room_outlined),
                            keyboardType: TextInputType.text,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: widget.condominioController,
                            style: TextStyle(color: widget.textColor),
                            decoration: _field('Nombre del condominio', Icons.apartment_outlined),
                          ),
                        ),
                      ]),
                    ],

                    const SizedBox(height: 12),
                    TextFormField(
                      controller: widget.referenceController,
                      style: TextStyle(color: widget.textColor),
                      decoration: _field(
                        'Referencia (ej: frente al parque, casa verde)',
                        Icons.place_outlined,
                      ),
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ── Dropdown de zona + mapa referencial desplegable ───────────────────────────

class _ZoneDropdownWithMap extends StatefulWidget {
  final bool isDark;
  final Color textColor;
  final Color subtextColor;
  final Color borderColor;
  final Color surfaceEl;
  final String cityId;
  final String? selectedZone;
  final void Function(String?) onZoneChanged;
  final bool locked;
  final bool noMatchHint;

  const _ZoneDropdownWithMap({
    super.key,
    required this.isDark,
    required this.textColor,
    required this.subtextColor,
    required this.borderColor,
    required this.surfaceEl,
    required this.cityId,
    required this.selectedZone,
    required this.onZoneChanged,
    this.locked = false,
    this.noMatchHint = false,
  });

  @override
  State<_ZoneDropdownWithMap> createState() => _ZoneDropdownWithMapState();
}

class _ZoneDropdownWithMapState extends State<_ZoneDropdownWithMap> {
  bool _showMap = false;
  final MapController _mapController = MapController();
  Set<String> _blockedZones = {};
  List<GardenZone> _zones = [];
  bool _loadingZones = true;

  @override
  void initState() {
    super.initState();
    ZonesService.getBlockedZones().then((blocked) {
      if (mounted) setState(() => _blockedZones = blocked);
    });
    _loadZones();
  }

  Future<void> _loadZones() async {
    final zones = await CitiesService.getZones(widget.cityId);
    if (!mounted) return;
    setState(() {
      _zones = zones;
      _loadingZones = false;
    });
  }

  @override
  void didUpdateWidget(_ZoneDropdownWithMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_showMap && widget.selectedZone != oldWidget.selectedZone && widget.selectedZone != null) {
      final zone = _zones.where((z) => z.key == widget.selectedZone).firstOrNull;
      if (zone != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mapController.move(LatLng(zone.lat, zone.lng), 14.5);
        });
      }
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  GardenZone? get _selected =>
      widget.selectedZone == null ? null : _zones.where((z) => z.key == widget.selectedZone).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final zoneColor = _selected?.color ?? Colors.grey.shade400;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Dropdown ─────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: widget.surfaceEl,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _selected != null ? zoneColor : widget.borderColor,
              width: _selected != null ? 1.5 : 1.0,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: widget.selectedZone,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              dropdownColor: widget.isDark ? const Color(0xFF1E1E2E) : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              hint: Row(children: [
                Icon(Icons.map_outlined, color: widget.subtextColor, size: 20),
                const SizedBox(width: 10),
                Text(
                  _loadingZones
                      ? 'Cargando zonas...'
                      : (widget.noMatchHint ? 'Sin zona disponible por ahora' : 'Selecciona tu zona / barrio'),
                  style: TextStyle(color: widget.subtextColor, fontSize: 14),
                ),
              ]),
              items: _zones.map((z) {
                final blocked = _blockedZones.contains(z.key);
                final color = blocked ? Colors.grey.shade400 : z.color;
                return DropdownMenuItem(
                  value: z.key,
                  // Zonas bloqueadas por el admin no se pueden elegir — se
                  // muestran en gris con una etiqueta clara en vez de
                  // desaparecer, para que el usuario entienda por qué no
                  // está disponible en lugar de pensar que es un error.
                  enabled: !blocked,
                  child: Row(children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Text(z.label,
                        style: TextStyle(
                          color: blocked ? Colors.grey.shade400 : widget.textColor,
                          fontSize: 14,
                        )),
                    if (blocked) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('No disponible',
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 10, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ]),
                );
              }).toList(),
              selectedItemBuilder: (_) => _zones.map((z) {
                return Row(children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: z.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Text(z.label,
                      style: TextStyle(color: widget.textColor, fontSize: 14, fontWeight: FontWeight.w600)),
                ]);
              }).toList(),
              onChanged: widget.locked ? null : widget.onZoneChanged,
            ),
          ),
        ),

        // ── Botón mostrar/ocultar mapa referencial ────────────────
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => setState(() => _showMap = !_showMap),
          child: Row(children: [
            Icon(
              _showMap ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              color: widget.subtextColor,
              size: 18,
            ),
            const SizedBox(width: 4),
            Text(
              _showMap ? 'Ocultar mapa de zonas' : '¿No sé a qué zona pertenezco? Ver mapa',
              style: TextStyle(
                color: const Color(0xFF2196F3),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ]),
        ),

        // ── Mapa referencial (desplegable) ────────────────────────
        if (_showMap && _zones.isNotEmpty) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 260,
              child: _ZoneReferenceMap(
                zones: _zones,
                selectedZone: widget.selectedZone,
                surfaceEl: widget.surfaceEl,
                mapController: _mapController,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Mapa referencial con un marcador por zona (sin polígonos — cada zona
// nueva se define solo con un punto central, elegible desde el panel admin) ──

class _ZoneReferenceMap extends StatelessWidget {
  final List<GardenZone> zones;
  final String? selectedZone;
  final Color surfaceEl;
  final MapController mapController;

  const _ZoneReferenceMap({
    required this.zones,
    required this.selectedZone,
    required this.surfaceEl,
    required this.mapController,
  });

  @override
  Widget build(BuildContext context) {
    final markers = zones.map((z) {
      final isSelected = selectedZone == z.key;
      return Marker(
        point: LatLng(z.lat, z.lng),
        width: 110,
        height: 28,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: isSelected ? z.color : surfaceEl,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: z.color, width: isSelected ? 0 : 1.5),
            boxShadow: [
              BoxShadow(color: z.color.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 1)),
            ],
          ),
          child: Text(
            z.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : z.color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }).toList();

    final center = zones.isNotEmpty ? LatLng(zones.first.lat, zones.first.lng) : const LatLng(-17.775, -63.175);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 12.5,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: isDark
              ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
              : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.garden.bolivia',
        ),
        MarkerLayer(markers: markers),
      ],
    );
  }
}
