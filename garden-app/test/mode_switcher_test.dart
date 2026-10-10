import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/design/garden_icons.dart';
import 'package:garden_app/design/garden_mode_switcher.dart';
import 'package:garden_app/services/auth_state.dart';
import 'package:garden_app/services/work_mode.dart';
import 'package:garden_app/theme/garden_theme.dart';

const _options = [
  GardenModeOption(
    mode: GardenMode.owner,
    title: 'Dueño',
    subtitle: 'de mascota',
    description: 'Descripción dueño',
    icon: GIcon.mascotas,
  ),
  GardenModeOption(
    mode: GardenMode.independent,
    title: 'Cuidador',
    subtitle: 'por mi cuenta',
    description: 'Descripción cuidador',
    icon: GIcon.perfil,
  ),
  GardenModeOption(
    mode: GardenMode.staff,
    title: 'Equipo',
    subtitle: 'Patitas',
    description: 'Descripción equipo',
    icon: GIcon.equipo,
  ),
];

Widget _host(Widget child) => MaterialApp(
      theme: gardenTheme(dark: false),
      home: Scaffold(body: Center(child: SizedBox(width: 360, child: child))),
    );

void main() {
  group('GardenModeSwitcher', () {
    testWidgets('muestra la descripción del modo actual y cambia al elegir otro', (tester) async {
      GardenMode? picked;
      await tester.pumpWidget(_host(GardenModeSwitcher(
        initiallyExpanded: true,
        options: _options,
        current: GardenMode.staff,
        onSelect: (m) => picked = m,
      )));
      expect(find.text('Descripción equipo'), findsOneWidget);
      expect(find.text('Descripción dueño'), findsNothing);

      await tester.tap(find.text('Dueño'));
      expect(picked, GardenMode.owner);
    });

    testWidgets('tocar el modo actual no dispara nada', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_host(GardenModeSwitcher(
        initiallyExpanded: true,
        options: _options,
        current: GardenMode.independent,
        onSelect: (_) => calls++,
      )));
      await tester.tap(find.text('Cuidador'));
      expect(calls, 0);
    });

    testWidgets('mientras cambia muestra el indicador e ignora más toques', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_host(GardenModeSwitcher(
        initiallyExpanded: true,
        options: _options,
        current: GardenMode.owner,
        switching: GardenMode.staff,
        onSelect: (_) => calls++,
      )));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Cuidador'));
      expect(calls, 0);
    });

    testWidgets('el fondo del selector se desliza a la opción elegida', (tester) async {
      Widget build(GardenMode current) => _host(GardenModeSwitcher(
            initiallyExpanded: true,
            options: _options,
            current: current,
            bare: true,
            onSelect: (_) {},
          ));
      await tester.pumpWidget(build(GardenMode.owner));
      double left() => tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned)).left!;
      expect(left(), 0);

      await tester.pumpWidget(build(GardenMode.staff));
      // A mitad de la animación todavía no llegó (se desliza, no salta)...
      await tester.pump(const Duration(milliseconds: 100));
      expect(left(), greaterThan(0));
      // ...y al terminar queda en el tercer segmento (ancho 360 → 2 × 120).
      await tester.pumpAndSettle();
      expect(left(), closeTo(240, 0.5));
    });

    testWidgets('con "reducir movimiento" el fondo salta directo', (tester) async {
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _host(GardenModeSwitcher(initiallyExpanded: true, options: _options, current: GardenMode.owner, bare: true, onSelect: (_) {})),
      ));
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _host(GardenModeSwitcher(initiallyExpanded: true, options: _options, current: GardenMode.staff, bare: true, onSelect: (_) {})),
      ));
      await tester.pump();
      expect(tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned)).left, closeTo(240, 0.5));
    });

    testWidgets('las acciones "agregar" aparecen y responden', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_host(GardenModeSwitcher(
        initiallyExpanded: true,
        options: _options.sublist(0, 2),
        current: GardenMode.owner,
        onSelect: (_) {},
        addActions: [GardenModeAddAction(label: 'Unirme a un equipo', onTap: () => tapped = true)],
      )));
      await tester.tap(find.text('Unirme a un equipo'));
      expect(tapped, isTrue);
    });
  

    group('plegado por defecto (barra delgada)', () {
      Widget barra({GardenMode current = GardenMode.owner, ValueChanged<GardenMode>? onSelect, GardenMode? switching}) =>
          _host(GardenModeSwitcher(
            options: _options,
            current: current,
            switching: switching,
            onSelect: onSelect ?? (_) {},
            addActions: [GardenModeAddAction(label: 'Unirme a un equipo', onTap: () {})],
            footer: const Text('Salir del equipo'),
          ));

      testWidgets('solo muestra en qué perfil estás: nada de opciones ni extras', (tester) async {
        await tester.pumpWidget(barra());
        expect(find.textContaining('Usando Garden como'), findsOneWidget);
        expect(find.textContaining('Dueño'), findsOneWidget); // el nombre del perfil actual, no el selector
        expect(find.text('Cuidador'), findsNothing);
        expect(find.text('Equipo'), findsNothing);
        expect(find.text('Descripción dueño'), findsNothing);
        expect(find.text('Unirme a un equipo'), findsNothing);
        expect(find.text('Salir del equipo'), findsNothing);
      });

      testWidgets('es delgada (no ocupa más que una fila)', (tester) async {
        await tester.pumpWidget(barra());
        expect(tester.getSize(find.byType(GardenModeSwitcher)).height, lessThanOrEqualTo(48));
      });

      testWidgets('tocar la barra despliega las opciones ahí mismo, sin ventanas emergentes', (tester) async {
        await tester.pumpWidget(barra());
        await tester.tap(find.textContaining('Usando Garden como'));
        await tester.pumpAndSettle();
        expect(find.text('Cuidador'), findsOneWidget);
        expect(find.text('Equipo'), findsOneWidget);
        expect(find.text('Descripción dueño'), findsOneWidget);
        expect(find.text('Unirme a un equipo'), findsOneWidget);
        expect(find.text('Salir del equipo'), findsOneWidget);
        expect(find.byType(Dialog), findsNothing);
        expect(find.byType(BottomSheet), findsNothing);
      });

      testWidgets('tocarla otra vez la vuelve a plegar', (tester) async {
        await tester.pumpWidget(barra());
        await tester.tap(find.textContaining('Usando Garden como'));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Usando Garden como'));
        await tester.pumpAndSettle();
        expect(find.text('Cuidador'), findsNothing);
      });

      testWidgets('deslizar hacia abajo despliega y hacia arriba pliega', (tester) async {
        await tester.pumpWidget(barra());
        await tester.fling(find.textContaining('Usando Garden como'), const Offset(0, 120), 1200);
        await tester.pumpAndSettle();
        expect(find.text('Cuidador'), findsOneWidget);

        await tester.fling(find.textContaining('Usando Garden como'), const Offset(0, -120), 1200);
        await tester.pumpAndSettle();
        expect(find.text('Cuidador'), findsNothing);
      });

      testWidgets('desplegada, elegir otro perfil funciona igual que antes', (tester) async {
        GardenMode? picked;
        await tester.pumpWidget(barra(onSelect: (m) => picked = m));
        await tester.tap(find.textContaining('Usando Garden como'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cuidador'));
        expect(picked, GardenMode.independent);
      });

      testWidgets('mientras cambia de perfil queda desplegada aunque no se haya tocado', (tester) async {
        await tester.pumpWidget(barra(switching: GardenMode.staff));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });

      testWidgets('con "reducir movimiento" también se despliega y se pliega', (tester) async {
        await tester.pumpWidget(MediaQuery(data: const MediaQueryData(disableAnimations: true), child: barra()));
        expect(find.text('Cuidador'), findsNothing);
        await tester.tap(find.textContaining('Usando Garden como'));
        await tester.pump();
        expect(find.text('Cuidador'), findsOneWidget);
        await tester.tap(find.textContaining('Usando Garden como'));
        await tester.pump();
        expect(find.text('Cuidador'), findsNothing);
      });

      testWidgets('es accesible: se anuncia como botón desplegable con el perfil actual', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(barra(current: GardenMode.independent));
        expect(
          find.bySemanticsLabel(RegExp('Cambiar de perfil. Estás usando Garden como Cuidador')),
          findsOneWidget,
        );
        handle.dispose();
      });
    });
  });

  group('WorkMode', () {
    void setAccount({String role = '', String activeRole = '', bool staff = false, bool own = false, bool staffMode = true}) {
      AuthState.updateRole(role: role, activeRole: activeRole);
      AuthState.updateStaffInfo(isCaregiverStaff: staff, hasOwnProfile: own, companyName: staff ? 'Patitas' : '');
      // ignore: invalid_use_of_visible_for_testing_member
      AuthState.debugSetStaffMode(staffMode);
    }

    test('dueño de mascota: solo un modo', () {
      setAccount(role: 'CLIENT');
      expect(WorkMode.available, [GardenMode.owner]);
      expect(WorkMode.current, GardenMode.owner);
    });

    test('cuidador sin equipo: dueño + cuidador', () {
      setAccount(role: 'CAREGIVER');
      expect(WorkMode.available, [GardenMode.owner, GardenMode.independent]);
      expect(WorkMode.current, GardenMode.independent);
    });

    test('solo empleado: dueño + equipo (no hay modo independiente)', () {
      setAccount(role: 'CAREGIVER', staff: true);
      expect(WorkMode.available, [GardenMode.owner, GardenMode.staff]);
      expect(WorkMode.current, GardenMode.staff);
    });

    test('empleado con perfil propio: los tres, y el modo guardado manda', () {
      setAccount(role: 'CAREGIVER', staff: true, own: true, staffMode: false);
      expect(WorkMode.available, [GardenMode.owner, GardenMode.independent, GardenMode.staff]);
      expect(WorkMode.current, GardenMode.independent);

      setAccount(role: 'CAREGIVER', staff: true, own: true, staffMode: true);
      expect(WorkMode.current, GardenMode.staff);
    });

    test('actuando como dueño, el modo actual es dueño aunque sea empleado', () {
      setAccount(role: 'CAREGIVER', activeRole: 'CLIENT', staff: true, own: true);
      expect(WorkMode.current, GardenMode.owner);
    });

    test('las opciones llevan el nombre de la empresa y "Mi empresa" para el dueño', () {
      setAccount(role: 'CAREGIVER', staff: true);
      final staff = WorkMode.options().firstWhere((o) => o.mode == GardenMode.staff);
      expect(staff.subtitle, 'Patitas');
      expect(staff.description, contains('Patitas'));

      setAccount(role: 'CAREGIVER');
      final company = WorkMode.options(isCompany: true).firstWhere((o) => o.mode == GardenMode.independent);
      expect(company.title, 'Mi empresa');
    });
  });
}
