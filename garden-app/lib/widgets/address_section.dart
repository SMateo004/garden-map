import 'package:flutter/material.dart';
import 'address_map_picker.dart';

/// Sección de dirección reutilizable: abre el mapa picker primero,
/// luego muestra los campos de texto detallados.
/// Usada en el wizard del cuidador y en el perfil del dueño de mascota.
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
  final TextEditingController zoneController;
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
    required this.zoneController,
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

        TextFormField(
          controller: zoneController,
          style: TextStyle(color: textColor),
          decoration: _field('Zona / Barrio (ej: Equipetrol)', Icons.map_outlined),
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
