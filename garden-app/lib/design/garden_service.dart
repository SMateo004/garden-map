import 'package:flutter/material.dart';

import '../theme/garden_theme.dart';

// ── IDENTIDAD DE LOS TRES SERVICIOS ────────────────────────────────────────
// Un servicio = un icono, un color y una metáfora. Reemplaza a los cuatro
// emojis distintos que cambiaban según el archivo.
//
//   Paseo      → movimiento (huellas)   · verde vivo
//   Guardería  → de día (sol)           · ámbar
//   Hospedaje  → de noche (casa y luna) · bosque
enum GardenService {
  paseo('PASEO', 'Paseo', 'Paseo de mascotas'),
  guarderia('GUARDERIA', 'Guardería', 'Guardería de día'),
  hospedaje('HOSPEDAJE', 'Hospedaje', 'Hospedaje con noche');

  const GardenService(this.apiValue, this.label, this.longLabel);

  /// Valor exacto del enum `ServiceType` de garden-api.
  final String apiValue;
  final String label;
  final String longLabel;

  /// Convierte el valor del backend. Devuelve null si no se reconoce, para que
  /// la pantalla decida qué mostrar en vez de inventar un servicio.
  static GardenService? fromApi(String? value) {
    switch (value?.toUpperCase()) {
      case 'PASEO':
      case 'WALK':
        return GardenService.paseo;
      case 'GUARDERIA':
      case 'DAYCARE':
        return GardenService.guarderia;
      case 'HOSPEDAJE':
      case 'BOARDING':
        return GardenService.hospedaje;
    }
    return null;
  }

  /// Color de marca del servicio (fondos, gráficos, tinte de mapa).
  Color get brand => switch (this) {
        GardenService.paseo     => GardenColors.accent,
        GardenService.guarderia => GardenColors.warning,
        GardenService.hospedaje => GardenColors.forest,
      };

  /// Color para trazos e iconos sobre la superficie del tema actual.
  /// El color de marca puro no tiene contraste suficiente sobre crema.
  Color ink(bool isDark) => switch (this) {
        GardenService.paseo     => isDark ? GardenColors.accent : const Color(0xFF2FA83A),
        GardenService.guarderia => isDark ? const Color(0xFFFFC24D) : const Color(0xFFC98500),
        GardenService.hospedaje => isDark ? const Color(0xFF4FD18A) : GardenColors.forest,
      };

  /// Fondo suave para tarjetas y contenedores del servicio.
  Color soft(bool isDark) => switch (this) {
        GardenService.paseo     => isDark ? const Color(0xFF173A16) : const Color(0xFFE2F7DF),
        GardenService.guarderia => isDark ? const Color(0xFF33290F) : const Color(0xFFFFF1D6),
        GardenService.hospedaje => isDark ? const Color(0xFF12301F) : const Color(0xFFDCEFE3),
      };
}
