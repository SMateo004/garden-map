import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Mapa base de Garden — el ÚNICO lugar donde se define de dónde salen los mosaicos del mapa.
///
/// Antes cada pantalla (marketplace, seguimiento GPS del paseo, ejecución del servicio, selector de dirección,
/// detalle de reserva del admin) tenía su propio `TileLayer` apuntando al proveedor CARTO. CARTO pasó a exigir
/// una clave de API y todos los mosaicos empezaron a mostrar "API KEY REQUIRED" encima del mapa, incluido el
/// seguimiento en vivo de un paseo. Con un solo componente, cambiar de proveedor es tocar este archivo.
///
/// Proveedor actual: OpenStreetMap estándar — sin clave. Su política de uso es para tráfico moderado; si Garden
/// crece (o el seguimiento GPS carga muchos mosaicos), el paso siguiente es un proveedor con clave propia
/// (MapTiler, Stadia, Mapbox…) cambiando solo [tileUrl].
///
/// Tema oscuro: OSM no tiene estilo oscuro, así que a los mosaicos se les aplica un filtro de color (invertir y
/// girar el tono 180°, el clásico de los mapas nocturnos) que conserva verdes y azules en lugar de dejar todo gris.
class GardenBaseMap {
  GardenBaseMap._();

  static const tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const userAgentPackage = 'com.garden.bolivia';

  /// Invertir + girar el tono 180° y bajar un 10 % el brillo (el mapa oscuro no debe deslumbrar).
  /// Cada fila suma 1 antes de invertir, por eso el desfase es 255 × brillo.
  static const List<double> darkMatrix = <double>[
    0.5166, -1.2870, -0.1296, 0, 229.5, //
    -0.3834, -0.3870, -0.1296, 0, 229.5, //
    -0.3834, -1.2870, 0.7704, 0, 229.5, //
    0, 0, 0, 1, 0,
  ];

  static Widget darkTileBuilder(BuildContext context, Widget tileWidget, TileImage tile) {
    return ColorFiltered(colorFilter: const ColorFilter.matrix(darkMatrix), child: tileWidget);
  }

  /// Capas base de un [FlutterMap]: mosaicos + la atribución que exige OpenStreetMap. Se usa como
  /// `children: [...GardenBaseMap.layers(isDark), ...tusCapas]`.
  static List<Widget> layers(bool isDark) => [
        TileLayer(
          urlTemplate: tileUrl,
          userAgentPackageName: userAgentPackage,
          maxNativeZoom: 19,
          tileBuilder: isDark ? darkTileBuilder : null,
        ),
        const SimpleAttributionWidget(
          source: Text('© OpenStreetMap', style: TextStyle(fontSize: 10)),
        ),
      ];
}
