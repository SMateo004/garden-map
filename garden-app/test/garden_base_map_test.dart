import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/widgets/garden_base_map.dart';

void main() {
  test('el mapa base usa OpenStreetMap, sin proveedor con clave', () {
    expect(GardenBaseMap.tileUrl, contains('openstreetmap.org'));
    expect(GardenBaseMap.tileUrl, isNot(contains('cartocdn')));
  });

  test('en tema claro no filtra los mosaicos; en oscuro sí', () {
    final light = GardenBaseMap.layers(false).whereType<TileLayer>().single;
    final dark = GardenBaseMap.layers(true).whereType<TileLayer>().single;
    expect(light.tileBuilder, isNull);
    expect(dark.tileBuilder, isNotNull);
    expect(GardenBaseMap.darkMatrix.length, 20);
  });

  test('incluye la atribución que exige OpenStreetMap', () {
    expect(GardenBaseMap.layers(false).whereType<SimpleAttributionWidget>(), hasLength(1));
  });

  test('ninguna pantalla vuelve a apuntar a CARTO (pedía API key y rompía todos los mapas)', () {
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('basemaps.cartocdn.com'))
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty, reason: 'Usa GardenBaseMap.layers(isDark) en vez de un TileLayer propio');
  });
}
