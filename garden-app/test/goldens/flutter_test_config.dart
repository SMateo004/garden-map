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
/// - El texto usa la fuente de prueba de Flutter (cajas), igual en todos los
///   sistemas. El suavizado de iconos y bordes sí cambia: en Linux contra
///   Windows da entre 1,5 % y 4 % de píxeles distintos.
/// - Las fotos de referencia son las de Linux, donde corre el CI, y ahí la
///   tolerancia es estricta. En Windows o macOS la prueba local es más
///   permisiva: sigue atrapando un color, un fondo o un tamaño cambiado.
///
/// Para regenerar las fotos después de un cambio de diseño a propósito, hay
/// que hacerlo en Linux: GitHub > Actions > "Actualizar fotos del catálogo" >
/// Run workflow, y commitear los PNG del artefacto en test/goldens/goldens/.
/// (`flutter test test/goldens --update-goldens` en Windows las dejaría
/// con el suavizado de Windows y el CI fallaría.)
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

// Linux (CI, referencia): 1,5 %. Otros sistemas: 6 %, por el suavizado.
final double _tolerance = Platform.isLinux ? 0.015 : 0.06;

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
