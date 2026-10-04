import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/design/brote.dart';
import 'package:garden_app/design/garden_booking_hero_card.dart';
import 'package:garden_app/design/garden_icons.dart';
import 'package:garden_app/design/garden_pet_avatar.dart';
import 'package:garden_app/design/garden_service.dart';
import 'package:garden_app/design/garden_status_pill.dart';
import 'package:garden_app/design/garden_story_progress.dart';
import 'package:garden_app/design/garden_trust_seals.dart';
import 'package:garden_app/narrative/booking_story.dart';
import 'package:garden_app/theme/garden_theme.dart';

// Pruebas de imagen del catálogo: una foto de referencia por componente, en
// claro y en oscuro. Si alguien cambia un color, un radio o un icono sin
// querer, la prueba falla y muestra la diferencia en test/goldens/failures.
// Las fotos viven en test/goldens/goldens/. Ver flutter_test_config.dart.

final _now = DateTime(2026, 10, 2, 10);
const _ctx = BookingStoryContext(
  petName: 'Luna',
  caregiverName: 'Andrea Rojas',
  service: GardenService.paseo,
);

/// Lienzo fijo: mismo tamaño y tema en cada corrida; sin animaciones para que
/// la foto salga del estado final.
Future<void> _shoot(WidgetTester tester, String name, Widget child, {Size size = const Size(400, 300)}) async {
  for (final dark in [false, true]) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      // Tema mínimo: gardenTheme usa google_fonts, que en pruebas intenta
      // descargar Nunito. Los componentes toman sus colores de GardenColors
      // según el brillo, así que esto alcanza para la foto.
      theme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: dark ? GardenColors.darkBackground : GardenColors.lightBackground,
      ),
      home: MediaQuery(
        data: MediaQueryData(size: size, disableAnimations: true),
        child: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: Center(child: child)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/${name}_${dark ? 'oscuro' : 'claro'}.png'),
    );
  }
}

void main() {
  testWidgets('iconos: idle y activo, con los tres servicios', (tester) async {
    const sample = [
      GIcon.inicio, GIcon.buscar, GIcon.reservas, GIcon.mascotas, GIcon.perfil, GIcon.chat,
      GIcon.billetera, GIcon.pagoProtegido, GIcon.confirmado, GIcon.esperando, GIcon.estrella, GIcon.advertencia,
      GIcon.paseo, GIcon.guarderia, GIcon.hospedaje,
    ];
    await _shoot(tester, 'iconos', Wrap(spacing: 12, runSpacing: 12, children: [
      for (final i in sample) ...[
        GardenIcon(i, size: GIconSize.lg),
        GardenIcon(i, size: GIconSize.lg, state: GIconState.active),
      ],
    ]), size: const Size(420, 200));
  });

  testWidgets('píldoras de estado', (tester) async {
    const statuses = ['PENDING_PAYMENT', 'WAITING_CAREGIVER_APPROVAL', 'CONFIRMED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'];
    await _shoot(tester, 'pildoras', Wrap(spacing: 8, runSpacing: 8, children: [
      for (final s in statuses)
        GardenStatusPill(BookingStory.of(s, _ctx, now: _now), service: GardenService.paseo),
    ]), size: const Size(420, 200));
  });

  testWidgets('avatar de mascota', (tester) async {
    await _shoot(tester, 'avatar', Row(mainAxisSize: MainAxisSize.min, children: [
      for (final s in ['IN_PROGRESS', 'CONFIRMED', 'COMPLETED'])
        Padding(
          padding: const EdgeInsets.all(8),
          child: GardenPetAvatar(
            name: 'Luna', species: 'DOG', service: GardenService.paseo,
            tone: BookingStory.of(s, _ctx, now: _now).tone,
          ),
        ),
    ]), size: const Size(320, 140));
  });

  testWidgets('sellos de confianza', (tester) async {
    await _shoot(tester, 'sellos', const GardenTrustSeals(
      identityVerified: true, backgroundChecked: false, offersWalks: true, caregiverFirstName: 'Andrea',
    ), size: const Size(420, 360));
  });

  testWidgets('progreso de la historia', (tester) async {
    await _shoot(tester, 'progreso', const GardenStoryProgress(steps: [
      StoryStepItem(GIcon.pagoProtegido, 'Pago verificado', StoryStepState.done),
      StoryStepItem(GIcon.esperando, 'Andrea acepta', StoryStepState.current, detail: 'Suele responder en menos de 1 h'),
      StoryStepItem(GIcon.paseo, 'Confirmada', StoryStepState.next),
    ]), size: const Size(420, 260));
  });

  // Sin fecha a propósito: con fecha el titular dice "mañana"/"el sábado"
  // según el día en que corre la prueba y la foto cambiaría sola.
  testWidgets('tarjeta de reserva esperando al cuidador', (tester) async {
    final booking = {
      'id': 'b1', 'status': 'WAITING_CAREGIVER_APPROVAL', 'serviceType': 'PASEO', 'petName': 'Luna',
      'caregiverName': 'Andrea Rojas',
    };
    await _shoot(tester, 'tarjeta_reserva', SingleChildScrollView(
      child: GardenBookingHeroCard(booking: booking, onAction: (_) {}, onChat: () {}),
    ), size: const Size(420, 360));
  });

  testWidgets('Brote en sus seis poses', (tester) async {
    await _shoot(tester, 'brote', Wrap(spacing: 8, runSpacing: 8, children: [
      for (final p in BrotePose.values) Brote(pose: p, size: 96),
    ]), size: const Size(420, 260));
  });
}
