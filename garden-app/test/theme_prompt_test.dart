import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/design/garden_theme_prompt.dart';
import 'package:garden_app/theme/garden_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "¿Claro u oscuro?" de la primera vez: solo al abrir la app por primera vez
/// con el teléfono en modo oscuro, una sola vez, y la respuesta queda guardada.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GardenText.useGoogleFonts = false);
  tearDown(() => ThemeNotifier.debugSystemBrightness = null);

  Future<ThemeNotifier> abrirApp({required Brightness sistema}) async {
    ThemeNotifier.debugSystemBrightness = sistema;
    final n = ThemeNotifier();
    await n.init();
    return n;
  }

  group('cuándo se pregunta', () {
    test('primera apertura en modo oscuro: pregunta; elegir claro lo guarda y no vuelve a preguntar', () async {
      SharedPreferences.setMockInitialValues({});
      final n = await abrirApp(sistema: Brightness.dark);
      expect(n.shouldAskOnFirstLaunch, isTrue);
      expect(n.isDark, isTrue);

      await n.answerFirstLaunchPrompt(GardenThemeMode.light);
      expect(n.mode, GardenThemeMode.light);
      expect(n.isDark, isFalse);
      expect(n.shouldAskOnFirstLaunch, isFalse);

      // Siguiente apertura (mismas prefs, teléfono sigue oscuro).
      final otra = await abrirApp(sistema: Brightness.dark);
      expect(otra.shouldAskOnFirstLaunch, isFalse);
      expect(otra.isDark, isFalse);
    });

    test('elegir mantener oscuro queda como apariencia oscura aunque el teléfono cambie', () async {
      SharedPreferences.setMockInitialValues({});
      final n = await abrirApp(sistema: Brightness.dark);
      await n.answerFirstLaunchPrompt(GardenThemeMode.dark);
      final otra = await abrirApp(sistema: Brightness.light);
      expect(otra.mode, GardenThemeMode.dark);
      expect(otra.isDark, isTrue);
      expect(otra.shouldAskOnFirstLaunch, isFalse);
    });

    test('primera apertura en modo claro: no pregunta, ni después si el teléfono pasa a oscuro', () async {
      SharedPreferences.setMockInitialValues({});
      final n = await abrirApp(sistema: Brightness.light);
      expect(n.shouldAskOnFirstLaunch, isFalse);
      final despues = await abrirApp(sistema: Brightness.dark);
      expect(despues.shouldAskOnFirstLaunch, isFalse);
    });

    test('si ya había una apariencia elegida, no pregunta', () async {
      SharedPreferences.setMockInitialValues({'garden_theme_mode': 'light'});
      final n = await abrirApp(sistema: Brightness.dark);
      expect(n.shouldAskOnFirstLaunch, isFalse);
    });
  });

  testWidgets('la ventana ofrece claro y oscuro, y no se cierra tocando afuera', (tester) async {
    GardenThemeMode? elegido;
    await tester.pumpWidget(MaterialApp(
      theme: gardenTheme(dark: true),
      home: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async => elegido = await GardenThemePrompt.show(context),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('¿Cómo prefieres ver GARDEN?'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5)); // afuera de la ventana
    await tester.pumpAndSettle();
    expect(find.text('¿Cómo prefieres ver GARDEN?'), findsOneWidget);

    await tester.tap(find.text('Ver en modo claro'));
    await tester.pumpAndSettle();
    expect(elegido, GardenThemeMode.light);
    expect(find.text('¿Cómo prefieres ver GARDEN?'), findsNothing);
  });

  testWidgets('cabe en un teléfono angosto (360 dp)', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: gardenTheme(dark: true),
      home: Scaffold(body: GardenThemePrompt(onChoose: (_) {})),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Mantener modo oscuro'), findsOneWidget);
  });
}
