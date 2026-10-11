import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Mapa base de Garden — el ÚNICO lugar donde se define de dónde salen los mosaicos y cómo se ven.
/// Todas las pantallas lo usan con `children: [...GardenBaseMap.layers(isDark), ...tusCapas]`.
///
/// Estilo: minimalista, blanco puro y el verde de Garden. Se parte del mapa base gris claro de Esri
/// ("Light Gray Canvas", diseñado justamente como lienzo neutro) y se recolorea con matrices de color: el
/// campo queda blanco puro, la ciudad en un salvia muy suave, las calles en verde Garden y los nombres de
/// calles/barrios (capa aparte, transparente) en el verde de la marca. En tema oscuro, la misma idea sobre
/// el fondo bosque de la app.
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
  // Cada fila: R, G, B, A, desfase (0–255). L = 0.2126R + 0.7152G + 0.0722B. El lienzo gris trae:
  // campo ≈239, mancha urbana ≈232 (zoom bajo), calles 255 (solo desde zoom ~11) y agua/límites más
  // oscuros. Una sola matriz no puede pintar a la vez "más claro" y "más oscuro" que el campo, así que
  // el mismo mosaico se dibuja dos veces: el SUELO y, encima, solo las CALLES (con transparencia).

  /// Suelo claro: campo (239) blanco puro; ciudad (232) salvia muy suave #E7EADD; agua y ríos en salvia.
  static const List<double> lightGroundMatrix = <double>[
    0.7289, 2.4521, 0.2475, 0, -564.4, //
    0.6378, 2.1456, 0.2166, 0, -462.0, //
    1.0326, 3.4738, 0.3507, 0, -905.9, //
    0, 0, 0, 1, 0,
  ];

  /// Calles claras: color fijo verde Garden suavizado #92A369; opacas donde L = 255 y transparentes
  /// bajo 250 (el resto del mosaico no se dibuja en esta capa).
  static const List<double> lightRoadsMatrix = <double>[
    0, 0, 0, 0, 146, //
    0, 0, 0, 0, 163, //
    0, 0, 0, 0, 105, //
    10.8426, 36.4752, 3.6822, 0, -12750,
  ];

  /// Suelo oscuro: campo → fondo bosque #0D1A07, ciudad → superficie bosque #162610.
  static const List<double> darkGroundMatrix = <double>[
    -0.2733, -0.9195, -0.0928, 0, 320.3, //
    -0.3645, -1.2261, -0.1238, 0, 435.7, //
    -0.2733, -0.9195, -0.0928, 0, 314.3, //
    0, 0, 0, 1, 0,
  ];

  /// Calles oscuras: verde Garden #778C43, misma transparencia que en claro.
  static const List<double> darkRoadsMatrix = <double>[
    0, 0, 0, 0, 119, //
    0, 0, 0, 0, 140, //
    0, 0, 0, 0, 67, //
    10.8426, 36.4752, 3.6822, 0, -12750,
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
          tileBuilder: _tinted(isDark ? darkGroundMatrix : lightGroundMatrix),
        ),
        // Mismos mosaicos (el navegador/la caché los reutiliza): solo las calles, en verde.
        TileLayer(
          urlTemplate: tileUrl,
          userAgentPackageName: userAgentPackage,
          maxNativeZoom: maxNativeZoom,
          tileBuilder: _tinted(isDark ? darkRoadsMatrix : lightRoadsMatrix),
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
