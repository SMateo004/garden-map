import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Mapa base de Garden — el ÚNICO lugar donde se define de dónde salen los mosaicos y cómo se ven.
/// Todas las pantallas lo usan con `children: [...GardenBaseMap.layers(isDark), ...tusCapas]`.
///
/// Estilo (octubre 2026): las calles tienen que leerse, en gris plomo y blanco (sin el verde de antes;
/// el verde queda para lo de Garden que va encima: zonas, recorridos, marcadores).
/// - Claro: el mapa de calles de Esri ("World Street Map", trae los nombres de casi todas las calles)
///   recoloreado en dos pasos: el suelo crema pasa a gris muy claro #ECEDEB, las calles quedan blancas,
///   las avenidas en gris medio y el texto en gris grafito (no negro); casi sin color.
///   Antes (suelo #E2E4E2, texto casi negro) el mapa se veía pesado.
/// - Oscuro: el lienzo gris oscuro de Esri en carbón neutro, calles en gris plomo y su capa de nombres
///   en claro.
///
/// Antes (blanco y verde sobre el lienzo gris claro) la matriz de calles solo pintaba los píxeles 100 %
/// blancos: las calles finas y los bordes (241–254) quedaban transparentes, y el lienzo casi no trae
/// nombres de calles en zoom de barrio.
///
/// Historia de proveedores (para no repetir errores):
/// - CARTO: pasó a exigir clave y los mosaicos mostraban "API KEY REQUIRED".
/// - OpenStreetMap (tile.openstreetmap.org): bloquea las apps hechas con flutter_map y en la web devolvía
///   mosaicos "403 Access blocked"; además su política no admite el tráfico de una app.
/// - Esri (server.arcgisonline.com): responde sin clave y con CORS abierto (necesario en la web),
///   verificado para World_Street_Map y los lienzos. Para tráfico grande Esri pide una cuenta de ArcGIS
///   Location Platform (tiene nivel gratuito): el token se pasa con `--dart-define=MAP_TILE_TOKEN=...`.
class GardenBaseMap {
  GardenBaseMap._();

  static const _token = String.fromEnvironment('MAP_TILE_TOKEN');
  static const _root = 'https://server.arcgisonline.com/ArcGIS/rest/services';
  static const _street = '$_root/World_Street_Map/MapServer/tile/{z}/{y}/{x}';
  static const _darkBase = '$_root/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}';
  static const _darkLabels = '$_root/Canvas/World_Dark_Gray_Reference/MapServer/tile/{z}/{y}/{x}';

  static String _withToken(String url) => _token.isEmpty ? url : '$url?token=$_token';

  static String tileUrl(bool isDark) => _withToken(isDark ? _darkBase : _street);
  static String get darkLabelsUrl => _withToken(_darkLabels);

  static const userAgentPackage = 'com.garden.bolivia';

  /// Niveles con mosaicos propios; más cerca, flutter_map amplía el último nivel.
  static const streetMaxNativeZoom = 19;
  static const canvasMaxNativeZoom = 16;

  static const attribution = 'Esri, HERE, Garmin, USGS, © OpenStreetMap';

  // ── Matrices de color ─────────────────────────────────────────────────────────────────────────
  // Cada fila: R, G, B, A, desfase (0–255). L = 0.2126R + 0.7152G + 0.0722B. Cada matriz lleva L de
  // forma lineal entre dos colores y suma una parte del croma original (k).

  /// Claro, paso 1 sobre World Street Map: estira los tonos (suelo crema L≈242 → gris claro, blanco →
  /// blanco, todo lo oscuro → negro); 5 % del croma original (parques apenas verdosos).
  static const List<double> lightStreetMatrix = <double>[
    0.5138274, 1.560345, 0.1575181, 0, -314.0810686, //
    0.4498863, 1.5634462, 0.1527836, 0, -297.3596036, //
    0.4948525, 1.6647155, 0.2180543, 0, -351.2937063, //
    0, 0, 0, 1, 0,
  ];

  /// Claro, paso 2: aclara todo hacia arriba — el negro pasa a gris grafito #585C5A y el blanco sigue
  /// blanco, así el suelo queda en #ECEDEB. Va aparte porque una sola matriz no puede aclarar los
  /// tonos oscuros sin oscurecer el suelo (el paso 1 recorta en 0 y este levanta desde ahí).
  static const List<double> lightInkMatrix = <double>[
    0.654902, 0, 0, 0, 88, //
    0, 0.6392157, 0, 0, 92, //
    0, 0, 0.6470588, 0, 90, //
    0, 0, 0, 1, 0,
  ];

  /// Oscuro sobre el lienzo gris oscuro: suelo (L≈71) → gris carbón #1C1E1D, calles (L≈102) → gris plomo
  /// #5C615E (las avenidas, más claras, quedan más claras todavía).
  static const List<double> darkBaseMatrix = <double>[
    0.4389161, 1.476542, 0.1490581, 0, -118.5806, //
    0.4594903, 1.545755, 0.1560452, 0, -123.4516, //
    0.4457742, 1.499613, 0.1513871, 0, -119.871, //
    0, 0, 0, 1, 0,
  ];

  /// Nombres del lienzo oscuro: texto claro (L≈230) → #DEE1DD; halo (L≈40) → carbón. Conserva la
  /// transparencia de la capa.
  static const List<double> darkLabelsMatrix = <double>[
    0.2170758, 0.7302568, 0.07372, 0, -12.8421, //
    0.2181947, 0.7340211, 0.0741, 0, -11.0526, //
    0.2148379, 0.7227284, 0.07296, 0, -11.4211, //
    0, 0, 0, 1, 0,
  ];

  static TileBuilder _tinted(List<double> matrix, [List<double>? then]) => (context, tileWidget, tile) {
        final first = ColorFiltered(colorFilter: ColorFilter.matrix(matrix), child: tileWidget);
        return then == null ? first : ColorFiltered(colorFilter: ColorFilter.matrix(then), child: first);
      };

  /// Fondo de la vista mientras cargan los mosaicos (el mismo suelo, sin parpadeo blanco ni gris).
  static Color background(bool isDark) => isDark ? const Color(0xFF1C1E1D) : const Color(0xFFECEDEB);

  /// Capas base de un [FlutterMap]: mosaicos (+ nombres en oscuro) y la atribución que exigen los datos.
  static List<Widget> layers(bool isDark) => [
        TileLayer(
          urlTemplate: tileUrl(isDark),
          userAgentPackageName: userAgentPackage,
          maxNativeZoom: isDark ? canvasMaxNativeZoom : streetMaxNativeZoom,
          tileBuilder: isDark ? _tinted(darkBaseMatrix) : _tinted(lightStreetMatrix, lightInkMatrix),
        ),
        // El mapa de calles ya trae los nombres; el lienzo oscuro los tiene en una capa aparte.
        if (isDark)
          TileLayer(
            urlTemplate: darkLabelsUrl,
            userAgentPackageName: userAgentPackage,
            maxNativeZoom: canvasMaxNativeZoom,
            tileBuilder: _tinted(darkLabelsMatrix),
          ),
        const SimpleAttributionWidget(
          source: Text(attribution, style: TextStyle(fontSize: 10)),
        ),
      ];
}
