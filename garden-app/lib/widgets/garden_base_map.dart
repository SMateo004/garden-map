import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Mapa base de Garden — el ÚNICO lugar donde se define de dónde salen los mosaicos y cómo se ven.
/// Todas las pantallas lo usan con `children: [...GardenBaseMap.layers(isDark), ...tusCapas]`.
///
/// Estilo: minimalista, blanco puro y el verde de Garden. Se parte del mapa base gris claro de Esri
/// ("Light Gray Canvas", diseñado justamente como lienzo neutro) y se recolorea con una matriz de color:
/// el suelo (gris ≈239) queda blanco puro y las calles (blancas, 255) pasan a verde salvia de Garden. Los
/// nombres de calles/barrios van en una capa aparte (transparente) que se tiñe con el verde de la marca.
/// En tema oscuro, la misma idea sobre el fondo bosque de la app.
///
/// Historia de proveedores (para no repetir errores):
/// - CARTO: pasó a exigir clave y los mosaicos mostraban "API KEY REQUIRED".
/// - OpenStreetMap (tile.openstreetmap.org): bloquea las apps hechas con flutter_map y en la web devolvía
///   mosaicos "403 Access blocked"; además su política no admite el tráfico de una app.
/// - Esri Light Gray Canvas: responde sin clave y con CORS (necesario en la web). Para tráfico grande Esri
///   pide una cuenta de ArcGIS Location Platform (tiene nivel gratuito): el token se pasa con
///   `--dart-define=MAP_TILE_TOKEN=...` y se agrega solo a las URLs.
class GardenBaseMap {
  GardenBaseMap._();

  static const _token = String.fromEnvironment('MAP_TILE_TOKEN');
  static const _base =
      'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}';
  static const _labels =
      'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Reference/MapServer/tile/{z}/{y}/{x}';

  static String get tileUrl => _token.isEmpty ? _base : '$_base?token=$_token';
  static String get labelsUrl => _token.isEmpty ? _labels : '$_labels?token=$_token';

  static const userAgentPackage = 'com.garden.bolivia';

  /// Nivel máximo con mosaicos propios del lienzo gris; más cerca, flutter_map amplía el último nivel.
  static const maxNativeZoom = 16;

  static const attribution = 'Esri, HERE, Garmin, © OpenStreetMap';

  // ── Matrices de color ─────────────────────────────────────────────────────────────────────────
  // Cada fila: R, G, B, A, desfase (0–255). L = 0.2126R + 0.7152G + 0.0722B.
  // Base clara: t = (L − 241) / 14 → suelo (≈239) blanco puro, calles (255) verde salvia #ADBA8E
  // (el verde de Garden #778C43 al 60 % sobre blanco: se lee como calle sin ensuciar el mapa).
  static const List<double> lightBaseMatrix = <double>[
    -1.2452, -4.1890, -0.4229, 0, 1666.6, //
    -1.0478, -3.5249, -0.3558, 0, 1442.8, //
    -1.7160, -5.7727, -0.5828, 0, 2200.2, //
    0, 0, 0, 1, 0,
  ];

  /// Nombres: texto gris (51) → verde Garden #778C43, halo blanco → blanco. Conserva la transparencia.
  static const List<double> lightLabelsMatrix = <double>[
    0.1417, 0.4768, 0.0481, 0, 85.0, //
    0.1198, 0.4032, 0.0407, 0, 111.25, //
    0.1959, 0.6591, 0.0665, 0, 20.0, //
    0, 0, 0, 1, 0,
  ];

  /// Base oscura: suelo → fondo bosque #0D1A07, calles → verde Garden #778C43.
  static const List<double> darkBaseMatrix = <double>[
    1.6097, 5.4151, 0.5467, 0, -1811.7, //
    1.7312, 5.8238, 0.5879, 0, -1936.4, //
    0.9111, 3.0651, 0.3094, 0, -1025.9, //
    0, 0, 0, 1, 0,
  ];

  /// Nombres en oscuro: texto → salvia claro #BECCA0, halo → fondo bosque.
  static const List<double> darkLabelsMatrix = <double>[
    -0.1845, -0.6205, -0.0626, 0, 234.25, //
    -0.1855, -0.6240, -0.0630, 0, 248.5, //
    -0.1595, -0.5364, -0.0542, 0, 198.25, //
    0, 0, 0, 1, 0,
  ];

  static TileBuilder _tinted(List<double> matrix) =>
      (context, tileWidget, tile) => ColorFiltered(colorFilter: ColorFilter.matrix(matrix), child: tileWidget);

  /// Fondo de la vista mientras cargan los mosaicos (evita el parpadeo gris de flutter_map).
  static Color background(bool isDark) => isDark ? const Color(0xFF0D1A07) : Colors.white;

  /// Capas base de un [FlutterMap]: mosaicos + nombres + la atribución que exigen los datos.
  static List<Widget> layers(bool isDark) => [
        TileLayer(
          urlTemplate: tileUrl,
          userAgentPackageName: userAgentPackage,
          maxNativeZoom: maxNativeZoom,
          tileBuilder: _tinted(isDark ? darkBaseMatrix : lightBaseMatrix),
        ),
        TileLayer(
          urlTemplate: labelsUrl,
          userAgentPackageName: userAgentPackage,
          maxNativeZoom: maxNativeZoom,
          tileBuilder: _tinted(isDark ? darkLabelsMatrix : lightLabelsMatrix),
        ),
        const SimpleAttributionWidget(
          source: Text(attribution, style: TextStyle(fontSize: 10)),
        ),
      ];
}
