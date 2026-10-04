import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/theme/garden_theme.dart';

/// Configuración de las pruebas de imagen del catálogo (solo esta carpeta).
///
/// - Carga las fuentes de Phosphor: sin esto los iconos saldrían como cajas
///   y la prueba no vería un cambio de icono.
/// - El texto usa la fuente de prueba de Flutter (cajas), igual en Windows,
///   macOS y Linux. Solo el suavizado de los iconos cambia un poco entre
///   sistemas, por eso el comparador tolera hasta [_tolerance] de píxeles
///   distintos: alcanza para eso y falla ante un color, radio o icono cambiado.
///
/// Para regenerar las imágenes después de un cambio de diseño a propósito:
///   flutter test test/goldens --update-goldens
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GardenText.useGoogleFonts = false;
  for (final (family, file) in const [
    ('PhosphorRegular', 'assets/fonts/phosphor/Phosphor-Regular.ttf'),
    ('PhosphorDuotone', 'assets/fonts/phosphor/Phosphor-Duotone.ttf'),
  ]) {
    final bytes = File(file).readAsBytesSync();
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
    await loader.load();
  }
  if (goldenFileComparator is LocalFileComparator) {
    goldenFileComparator = _TolerantComparator(
      Uri.parse('${(goldenFileComparator as LocalFileComparator).basedir}golden_test.dart'),
    );
  }
  await testMain();
}

const double _tolerance = 0.015; // 1,5 % de píxeles

class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(imageBytes, await getGoldenBytes(golden));
    if (result.passed || result.diffPercent <= _tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
