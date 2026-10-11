import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/design/garden_photo_tile.dart';
import 'package:garden_app/theme/garden_theme.dart';
import 'package:garden_app/utils/photo_picker.dart';

void main() {
  final photos = [for (var i = 0; i < 3; i++) (bytes: Uint8List(1), name: 'p$i.jpg')];

  Future<BuildContext> host(WidgetTester t) async {
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(
      theme: gardenTheme(),
      home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })),
    ));
    return ctx;
  }

  testWidgets('sube todas en orden y resume', (t) async {
    final ctx = await host(t);
    final order = <String>[];
    final ok = await GardenPhotoPicker.uploadAll(ctx, photos, (p) async => order.add(p.name));
    await t.pump();
    expect(ok, 3);
    expect(order, ['p0.jpg', 'p1.jpg', 'p2.jpg']);
    expect(find.text('Listo: 3 fotos agregadas.'), findsOneWidget);
  });

  testWidgets('si una falla sigue con las demás y dice cuál fue el problema', (t) async {
    final ctx = await host(t);
    final ok = await GardenPhotoPicker.uploadAll(ctx, photos, (p) async {
      if (p.name == 'p1.jpg') throw Exception('La foto pesa demasiado.');
    });
    await t.pump();
    expect(ok, 2);
    expect(find.text('2 de 3 fotos agregadas. Una no se pudo subir: La foto pesa demasiado.'), findsOneWidget);
  });

  testWidgets('sin lugar no abre la galería y lo avisa', (t) async {
    final ctx = await host(t);
    final picked = await GardenPhotoPicker.pick(ctx, remaining: 0);
    await t.pump();
    expect(picked, isEmpty);
    expect(find.textContaining('Ya tienes el máximo'), findsOneWidget);
  });

  testWidgets('el cuadro de agregar dice cuántas quedan y cuándo sube', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: gardenTheme(),
      home: Scaffold(
        body: Row(children: [
          GardenAddPhotoTile(size: 90, remaining: 4, onTap: () {}),
          GardenAddPhotoTile(size: 90, remaining: 1, onTap: () {}),
          GardenAddPhotoTile(size: 90, remaining: 2, uploading: true, onTap: () {}),
        ]),
      ),
    ));
    await t.pump();
    expect(find.text('quedan 4'), findsOneWidget);
    expect(find.text('queda 1'), findsOneWidget);
    expect(find.text('Subiendo…'), findsOneWidget);
  });
}
