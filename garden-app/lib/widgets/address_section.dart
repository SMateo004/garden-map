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
  final double? addressLat;
  final double? addressLng;
  final bool isApartment;
  final String purposeText;
  final void Function(AddressMapResult) onMapResult;
  final void Function(bool) onApartmentToggle;

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
    this.addressLat,
    this.addressLng,
    required this.isApartment,
    required this.purposeText,
    required this.onMapResult,
    required this.onApartmentToggle,
  });

  @override
  State<AddressSection> createState() => _AddressSectionState();
}

class _AddressSectionState extends State<AddressSection> {
  List<GardenCity> _cities = [];
  String? _selectedCityId;
  bool _loadingCities = true;

  InputDecoration _field(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
      );

  @override
  void initState() {
    super.initState();
    _loadCities();
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
  }

  @override
  Widget build(BuildContext context) {
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
                if (cityId == null) return;
                setState(() => _selectedCityId = cityId);
                widget.onZoneChanged(null); // cambiar de ciudad resetea la zona elegida
                final city = _cities.firstWhere((c) => c.id == cityId);
                widget.onCityChanged?.call(cityId, city.name);
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
              );
              if (result != null) widget.onMapResult(result);
            },
          ),
        ),
        const SizedBox(height: 16),

        // ── Campos de dirección ───────────────────────────────────
        Row(children: [
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: widget.streetController,
              style: TextStyle(color: widget.textColor),
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

        // ── Zona / Barrio — dropdown dinámico según la ciudad ─────
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
                  _loadingZones ? 'Cargando zonas...' : 'Selecciona tu zona / barrio',
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
              onChanged: widget.onZoneChanged,
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
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.garden.app',
        ),
        MarkerLayer(markers: markers),
      ],
    );
  }
}
