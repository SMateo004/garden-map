import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../constants/zones.dart';
import 'address_map_picker.dart';

/// Sección de dirección reutilizable: abre el mapa picker primero,
/// luego muestra los campos de texto detallados y un selector de zona.
/// Usada en el wizard del cuidador y en el registro del dueño de mascota.
class AddressSection extends StatelessWidget {
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
  // Zona como dropdown — reemplaza zoneController
  final String? selectedZone;
  final void Function(String?) onZoneChanged;
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
    this.addressLat,
    this.addressLng,
    required this.isApartment,
    required this.purposeText,
    required this.onMapResult,
    required this.onApartmentToggle,
  });

  InputDecoration _field(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
      );

  @override
  Widget build(BuildContext context) {
    final bool hasPin = addressLat != null && addressLng != null;

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
                  purposeText,
                  style: TextStyle(fontSize: 12, color: subtextColor),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

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
                initialLat: addressLat,
                initialLng: addressLng,
                purpose: purposeText,
              );
              if (result != null) onMapResult(result);
            },
          ),
        ),
        const SizedBox(height: 16),

        // ── Campos de dirección ───────────────────────────────────
        Row(children: [
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: streetController,
              style: TextStyle(color: textColor),
              decoration: _field('Calle / Avenida', Icons.signpost_outlined),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: numberController,
              style: TextStyle(color: textColor),
              decoration: _field('N° casa', Icons.tag),
              keyboardType: TextInputType.text,
            ),
          ),
        ]),
        const SizedBox(height: 12),

        // ── Zona / Barrio — dropdown ──────────────────────────────
        _ZoneDropdownWithMap(
          isDark: isDark,
          textColor: textColor,
          subtextColor: subtextColor,
          borderColor: borderColor,
          surfaceEl: surfaceEl,
          selectedZone: selectedZone,
          onZoneChanged: onZoneChanged,
        ),

        const SizedBox(height: 12),

        // Checkbox departamento
        GestureDetector(
          onTap: () => onApartmentToggle(!isApartment),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: isApartment ? const Color(0xFF16a34a) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isApartment ? const Color(0xFF16a34a) : Colors.grey.shade400,
                    width: 2,
                  ),
                ),
                child: isApartment
                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                    : null,
              ),
              const SizedBox(width: 10),
              Text(
                'Vivo en departamento / edificio',
                style: TextStyle(color: textColor, fontSize: 14),
              ),
            ],
          ),
        ),

        if (isApartment) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: apartmentController,
                style: TextStyle(color: textColor),
                decoration: _field('Número de dpto.', Icons.meeting_room_outlined),
                keyboardType: TextInputType.text,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: condominioController,
                style: TextStyle(color: textColor),
                decoration: _field('Nombre del condominio', Icons.apartment_outlined),
              ),
            ),
          ]),
        ],

        const SizedBox(height: 12),
        TextFormField(
          controller: referenceController,
          style: TextStyle(color: textColor),
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
  final String? selectedZone;
  final void Function(String?) onZoneChanged;

  const _ZoneDropdownWithMap({
    required this.isDark,
    required this.textColor,
    required this.subtextColor,
    required this.borderColor,
    required this.surfaceEl,
    required this.selectedZone,
    required this.onZoneChanged,
  });

  @override
  State<_ZoneDropdownWithMap> createState() => _ZoneDropdownWithMapState();
}

class _ZoneDropdownWithMapState extends State<_ZoneDropdownWithMap> {
  bool _showMap = false;
  final MapController _mapController = MapController();

  @override
  void didUpdateWidget(_ZoneDropdownWithMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Cuando cambia la zona seleccionada, mover el mapa a esa zona
    if (_showMap && widget.selectedZone != oldWidget.selectedZone && widget.selectedZone != null) {
      final center = kZoneCenters[widget.selectedZone];
      final zoom = kZoneZooms[widget.selectedZone] ?? kZoneMapDefaultZoom;
      if (center != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mapController.move(center, zoom);
        });
      }
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zoneColor = widget.selectedZone != null
        ? (kZoneColors[widget.selectedZone] ?? const Color(0xFF16a34a))
        : Colors.grey.shade400;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Dropdown ─────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: widget.surfaceEl,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.selectedZone != null ? zoneColor : widget.borderColor,
              width: widget.selectedZone != null ? 1.5 : 1.0,
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
                Text('Selecciona tu zona / barrio',
                    style: TextStyle(color: widget.subtextColor, fontSize: 14)),
              ]),
              items: kZoneLabels.entries.map((e) {
                final color = kZoneColors[e.key] ?? const Color(0xFF16a34a);
                return DropdownMenuItem(
                  value: e.key,
                  child: Row(children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(e.value,
                        style: TextStyle(color: widget.textColor, fontSize: 14)),
                  ]),
                );
              }).toList(),
              selectedItemBuilder: (_) => kZoneLabels.entries.map((e) {
                final color = kZoneColors[e.key] ?? const Color(0xFF16a34a);
                return Row(children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Text(e.value,
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
        if (_showMap) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 260,
              child: _ZoneReferenceMap(
                isDark: widget.isDark,
                selectedZone: widget.selectedZone,
                surfaceEl: widget.surfaceEl,
                textColor: widget.textColor,
                mapController: _mapController,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Mapa referencial estático con polígonos de zonas ─────────────────────────

class _ZoneReferenceMap extends StatelessWidget {
  final bool isDark;
  final String? selectedZone;
  final Color surfaceEl;
  final Color textColor;
  final MapController mapController;

  const _ZoneReferenceMap({
    required this.isDark,
    required this.selectedZone,
    required this.surfaceEl,
    required this.textColor,
    required this.mapController,
  });

  @override
  Widget build(BuildContext context) {
    final polygons = kZonePolygons.entries.map((e) {
      final color = kZoneColors[e.key] ?? const Color(0xFF4CAF50);
      final isSelected = selectedZone == e.key;
      return Polygon(
        points: e.value,
        color: color.withValues(alpha: isSelected ? 0.35 : 0.15),
        borderColor: color.withValues(alpha: isSelected ? 0.9 : 0.5),
        borderStrokeWidth: isSelected ? 2.5 : 1.5,
      );
    }).toList();

    final markers = kZoneCenters.entries.map((e) {
      final color = kZoneColors[e.key] ?? const Color(0xFF4CAF50);
      final label = kZoneLabels[e.key] ?? e.key;
      final isSelected = selectedZone == e.key;
      return Marker(
        point: e.value,
        width: 110,
        height: 28,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: isSelected ? color : surfaceEl,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color, width: isSelected ? 0 : 1.5),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 1)),
            ],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }).toList();

    return FlutterMap(
      mapController: mapController,
      options: const MapOptions(
        initialCenter: kSantaCruzCenter,
        initialZoom: kZoneMapDefaultZoom,
        // Permite pan y zoom pero no rotación
        interactionOptions: InteractionOptions(
          flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.garden.app',
        ),
        PolygonLayer(polygons: polygons),
        MarkerLayer(markers: markers),
      ],
    );
  }
}
