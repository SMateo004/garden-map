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
        child: _host(GardenModeSwitcher(options: _options, current: GardenMode.owner, bare: true, onSelect: (_) {})),
      ));
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _host(GardenModeSwitcher(options: _options, current: GardenMode.staff, bare: true, onSelect: (_) {})),
      ));
      await tester.pump();
      expect(tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned)).left, closeTo(240, 0.5));
    });

    testWidgets('las acciones "agregar" aparecen y responden', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_host(GardenModeSwitcher(
        options: _options.sublist(0, 2),
        current: GardenMode.owner,
        onSelect: (_) {},
        addActions: [GardenModeAddAction(label: 'Unirme a un equipo', onTap: () => tapped = true)],
      )));
      await tester.tap(find.text('Unirme a un equipo'));
      expect(tapped, isTrue);
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
