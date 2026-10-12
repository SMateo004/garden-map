import 'dart:io';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/widgets/garden_base_map.dart';

/// Aplica la matriz a un color RGB cualquiera (no solo grises).
List<int> _applyRgb(List<double> m, List<int> c) => [
      for (var row = 0; row < 3; row++)
        (m[row * 5] * c[0] + m[row * 5 + 1] * c[1] + m[row * 5 + 2] * c[2] + m[row * 5 + 4]).clamp(0, 255).round(),
    ];

int _lum(List<int> c) => (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]).round();

void main() {
  test('mosaicos sin clave y con CORS: ni CARTO (pide clave) ni OpenStreetMap (bloquea flutter_map)', () {
    expect(GardenBaseMap.tileUrl(false), contains('World_Street_Map'));
    expect(GardenBaseMap.tileUrl(true), contains('World_Dark_Gray_Base'));
    expect(GardenBaseMap.darkLabelsUrl, contains('World_Dark_Gray_Reference'));
    for (final url in [GardenBaseMap.tileUrl(false), GardenBaseMap.tileUrl(true), GardenBaseMap.darkLabelsUrl]) {
      expect(url, contains('server.arcgisonline.com'));
      expect(url, isNot(contains('cartocdn')));
      expect(url, isNot(contains('openstreetmap.org')));
    }
  });

  test('claro: suelo gris claro, calles blancas y nombres en gris grafito (no negro)', () {
    List<int> m(List<int> c) => _applyRgb(GardenBaseMap.lightInkMatrix, _applyRgb(GardenBaseMap.lightStreetMatrix, c));
    final ground = m([247, 244, 213]); // suelo crema del mapa de calles
    // Gris neutro: sin tinte verde ni crema.
    expect((ground[0] - ground[1]).abs() <= 6 && (ground[1] - ground[2]).abs() <= 6, isTrue, reason: 'suelo $ground');
    expect(m([255, 255, 255]), [255, 255, 255]); // calle
    expect(_lum(ground), greaterThan(230)); // gris claro, no plomo
    final ink = _lum(m([80, 80, 80]));
    expect(ink, inInclusiveRange(70, 110)); // texto gris grafito: se lee, pero sin negro
    // Las calles (blancas en el mapa de calles, también las finas) contrastan con el suelo gris;
    // antes, sobre el lienzo gris, las finas (241–254) quedaban transparentes.
    expect(255 - _lum(ground), greaterThan(15));
  });

  test('oscuro: suelo carbón, calles gris plomo más claras y nombres claros', () {
    final ground = _applyRgb(GardenBaseMap.darkBaseMatrix, [71, 71, 71]);
    final road = _applyRgb(GardenBaseMap.darkBaseMatrix, [102, 102, 102]);
    expect(ground, [28, 30, 29]); // #1C1E1D
    expect(_lum(road) - _lum(ground), greaterThan(50));
    expect(_lum(_applyRgb(GardenBaseMap.darkLabelsMatrix, [230, 230, 230])), greaterThan(200));
  });

  test('cada capa lleva su filtro y está la atribución', () {
    for (final dark in [false, true]) {
      final layers = GardenBaseMap.layers(dark);
      final tiles = layers.whereType<TileLayer>().toList();
      expect(tiles, hasLength(dark ? 2 : 1)); // oscuro: base + nombres; claro: el mapa de calles ya los trae
      expect(tiles.every((t) => t.tileBuilder != null), isTrue);
      expect(layers.whereType<SimpleAttributionWidget>(), hasLength(1));
    }
  });

  test('ninguna pantalla define su propio TileLayer (todas usan GardenBaseMap)', () {
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('garden_base_map.dart'))
        .where((f) {
          final src = f.readAsStringSync();
          return src.contains('TileLayer(') || src.contains('basemaps.cartocdn.com') || src.contains('tile.openstreetmap.org');
        })
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty, reason: 'Usa GardenBaseMap.layers(isDark) en vez de un TileLayer propio');
  });
}
