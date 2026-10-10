import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/screens/caregiver/camera_overlay_screen.dart';
import 'package:garden_app/theme/garden_theme.dart';

void main() {
  testWidgets('mientras abre la cámara muestra el marco con los consejos', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: gardenTheme(),
      home: const CameraOverlayScreen(frameShape: CameraFrameShape.rectangle, title: 'CI — Anverso', hint: 'Coloca el carnet'),
    ));
    await t.pump();
    expect(find.text('Todo el carnet dentro'), findsOneWidget);
    expect(find.text('Sin reflejos'), findsOneWidget);
    await t.pump(const Duration(seconds: 11)); // deja vencer el límite
  });

  testWidgets('si la cámara no responde, ofrece reintentar en vez de girar para siempre', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: gardenTheme(),
      home: const CameraOverlayScreen(frameShape: CameraFrameShape.oval, title: 'Selfie', hint: 'Tu cara dentro del óvalo'),
    ));
    await t.pump(const Duration(seconds: 11));
    await t.pump();
    expect(find.text('La cámara no está disponible'), findsOneWidget);
    expect(find.text('Intentar de nuevo'), findsOneWidget);
    expect(find.text('Volver'), findsOneWidget);
  });
}
