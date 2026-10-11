import 'dart:io';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/widgets/garden_base_map.dart';

/// Aplica una matriz 4x5 de ColorFilter a un color gris (r = g = b = v), como hace el motor.
List<int> _apply(List<double> m, int v, {int a = 255}) {
  final out = <int>[];
  for (var row = 0; row < 3; row++) {
    final x = m[row * 5] * v + m[row * 5 + 1] * v + m[row * 5 + 2] * v + m[row * 5 + 3] * a + m[row * 5 + 4];
    out.add(x.clamp(0, 255).round());
  }
  return out;
}

void main() {
  test('mosaicos sin clave y con CORS: ni CARTO (pide clave) ni OpenStreetMap (bloquea flutter_map)', () {
    expect(GardenBaseMap.tileUrl, contains('World_Light_Gray_Base'));
    expect(GardenBaseMap.labelsUrl, contains('World_Light_Gray_Reference'));
    for (final url in [GardenBaseMap.tileUrl, GardenBaseMap.labelsUrl]) {
      expect(url, isNot(contains('cartocdn')));
      expect(url, isNot(contains('openstreetmap.org')));
    }
  });

  test('estilo claro: suelo blanco puro, calles verde Garden', () {
    expect(_apply(GardenBaseMap.lightBaseMatrix, 239), [255, 255, 255]); // suelo del lienzo gris
    expect(_apply(GardenBaseMap.lightBaseMatrix, 237), [255, 255, 255]);
    final street = _apply(GardenBaseMap.lightBaseMatrix, 255);
    expect(street, [173, 186, 142]); // #ADBA8E: verde Garden suavizado
  });

  test('nombres: texto en verde Garden, halo blanco', () {
    expect(_apply(GardenBaseMap.lightLabelsMatrix, 51), [119, 140, 67]); // #778C43
    expect(_apply(GardenBaseMap.lightLabelsMatrix, 255), [255, 255, 255]);
  });

  test('estilo oscuro: suelo fondo bosque, calles verde Garden', () {
    final ground = _apply(GardenBaseMap.darkBaseMatrix, 239);
    expect(ground.every((c) => c < 20), isTrue);
    expect(_apply(GardenBaseMap.darkBaseMatrix, 255), [119, 140, 67]);
  });

  test('cada capa lleva su filtro y está la atribución', () {
    for (final dark in [false, true]) {
      final layers = GardenBaseMap.layers(dark);
      final tiles = layers.whereType<TileLayer>().toList();
      expect(tiles, hasLength(2));
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
