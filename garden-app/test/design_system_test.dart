import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/design/brote.dart';
import 'package:garden_app/design/garden_booking_hero_card.dart';
import 'package:garden_app/design/garden_live_hero.dart';
import 'package:garden_app/design/garden_story_progress.dart';
import 'package:garden_app/design/garden_trust_seals.dart';
import 'package:garden_app/design/garden_icons.dart';
import 'package:garden_app/design/garden_pet_avatar.dart';
import 'package:garden_app/design/garden_service.dart';
import 'package:garden_app/design/garden_status_pill.dart';
import 'package:garden_app/narrative/booking_story.dart';
import 'package:garden_app/narrative/chat_event.dart';
import 'package:garden_app/narrative/service_moments.dart';

void main() {
  final now = DateTime(2026, 10, 2, 10); // viernes
  final ctx = BookingStoryContext(
    petName: 'Luna',
    caregiverName: 'Andrea Rojas',
    service: GardenService.paseo,
    start: DateTime(2026, 10, 3, 9),
  );

  group('BookingStory', () {
    test('cubre todos los estados del backend sin caer al genérico', () {
      for (final s in BookingStatus.values) {
        final story = BookingStory.of(s.apiValue, ctx, now: now);
        expect(story.status, s, reason: s.apiValue);
        expect(story.ownerHeadline, isNot(contains('Reserva de')), reason: s.apiValue);
      }
    });

    test('usa el nombre de la mascota y el primer nombre del cuidador', () {
      final story = BookingStory.of('CONFIRMED', ctx, now: now);
      expect(story.ownerHeadline, '¡Listo! Andrea pasea a Luna mañana a las 9:00.');
      expect(story.caregiverHeadline, 'Mañana a las 9:00 paseas a Luna. Revisa sus notas.');
    });

    test('sin nombres cae a textos neutros', () {
      final story = BookingStory.of('IN_PROGRESS', const BookingStoryContext(), now: now);
      expect(story.ownerHeadline, 'tu mascota está con tu cuidador.');
      expect(story.isLive, isTrue);
    });

    test('la gramática cambia según el servicio', () {
      String owner(GardenService s) => BookingStory.of(
            'IN_PROGRESS',
            BookingStoryContext(petName: 'Luna', caregiverName: 'Andrea', service: s),
            now: now,
          ).ownerHeadline;
      expect(owner(GardenService.paseo), 'Luna está paseando con Andrea.');
      expect(owner(GardenService.guarderia), 'Luna está pasando el día con Andrea.');
      expect(owner(GardenService.hospedaje), 'Luna se está quedando con Andrea.');
    });

    test('una disputa abierta tapa el estado y no usa exclamaciones', () {
      final story = BookingStory.of(
        'COMPLETED',
        const BookingStoryContext(petName: 'Luna', disputed: true),
        now: now,
      );
      expect(story.tone, StoryTone.alert);
      expect(story.ownerHeadline, isNot(contains('!')));
    });

    test('dinero, cancelaciones y rechazos no llevan exclamaciones', () {
      for (final s in ['PENDING_PAYMENT', 'PAYMENT_PENDING_APPROVAL', 'CANCELLED', 'REJECTED_BY_CAREGIVER']) {
        final story = BookingStory.of(s, ctx, now: now);
        expect(story.ownerHeadline, isNot(contains('!')), reason: s);
        expect(story.caregiverHeadline, isNot(contains('!')), reason: s);
      }
    });

    test('completado: califica si falta, si no ofrece repetir', () {
      expect(BookingStory.of('COMPLETED', ctx, now: now).ownerNext?.action, StoryAction.rate);
      const rated = BookingStoryContext(petName: 'Luna', caregiverName: 'Andrea', rated: true);
      expect(BookingStory.of('COMPLETED', rated, now: now).ownerNext?.action, StoryAction.bookAgain);
    });

    test('whenLabel en lenguaje natural', () {
      expect(BookingStory.whenLabel(DateTime(2026, 10, 2, 15, 30), now: now), 'hoy a las 15:30');
      expect(BookingStory.whenLabel(DateTime(2026, 10, 3, 1), now: now), 'mañana a la 1:00');
      expect(BookingStory.whenLabel(DateTime(2026, 10, 4, 9), now: now), 'el domingo a las 9:00');
      expect(BookingStory.whenLabel(DateTime(2026, 11, 14, 9), now: now), 'el 14/11 a las 9:00');
    });
  });

  group('Reserva protagonista', () {
    Map<String, dynamic> bk(String status, {String? date, String? time, Map<String, dynamic> extra = const {}}) =>
        {'id': status, 'status': status, 'walkDate': date, 'startTime': time, ...extra};

    test('lo en vivo gana sobre todo lo demás', () {
      final picked = pickHeroBooking([
        bk('CONFIRMED', date: '2026-10-03', time: '09:00'),
        bk('WAITING_CAREGIVER_APPROVAL'),
        bk('IN_PROGRESS'),
      ], now: now);
      expect(picked?['status'], 'IN_PROGRESS');
    });

    test('una confirmada deja de mostrarse 3 h después de su hora', () {
      final b = bk('CONFIRMED', date: '2026-10-02', time: '06:00');
      expect(pickHeroBooking([b], now: DateTime(2026, 10, 2, 8, 59)), isNotNull);
      expect(pickHeroBooking([b], now: DateTime(2026, 10, 2, 9, 1)), isNull);
    });

    test('terminada sin calificar se muestra 3 días; calificada o vieja no', () {
      final ended = now.subtract(const Duration(hours: 5)).toUtc().toIso8601String();
      final old = now.subtract(const Duration(days: 4)).toUtc().toIso8601String();
      expect(pickHeroBooking([bk('COMPLETED', extra: {'serviceEndedAt': ended})], now: now), isNotNull);
      expect(pickHeroBooking([bk('COMPLETED', extra: {'serviceEndedAt': ended, 'ownerRated': true})], now: now), isNull);
      expect(pickHeroBooking([bk('COMPLETED', extra: {'serviceEndedAt': old})], now: now), isNull);
    });

    test('pagos pendientes no aparecen (suelen ser QR abandonados)', () {
      expect(pickHeroBooking([bk('PENDING_PAYMENT')], now: now), isNull);
    });

    test('lee la reserva del backend', () {
      final c = BookingStoryContext.fromBooking({
        'petName': 'Luna', 'caregiverName': 'Andrea Rojas', 'serviceType': 'HOSPEDAJE',
        'startDate': '2026-10-05', 'ownerRating': 5, 'hasDisputePending': false,
      });
      expect(c.service, GardenService.hospedaje);
      expect(c.start, DateTime(2026, 10, 5));
      expect(c.rated, isTrue);
      expect(c.caregiver, 'Andrea');
    });

    test('tiempo transcurrido corto', () {
      expect(BookingStory.elapsedLabel(now.subtract(const Duration(seconds: 20)), now: now), 'recién');
      expect(BookingStory.elapsedLabel(now.subtract(const Duration(minutes: 23)), now: now), '23 min');
      expect(BookingStory.elapsedLabel(now.subtract(const Duration(minutes: 65)), now: now), '1 h 05 min');
      expect(BookingStory.elapsedLabel(now.subtract(const Duration(hours: 50)), now: now), '2 días');
    });
  });

  group('Cuidador', () {
    Map<String, dynamic> bk(String status, {String? date, String? time}) =>
        {'id': '$status$date$time', 'status': status, 'walkDate': date, 'startTime': time};

    test('protagonista: en curso, luego solicitud por responder', () {
      expect(pickCaregiverHeroBooking([bk('CONFIRMED', date: '2026-10-02', time: '15:00'), bk('IN_PROGRESS')], now: now)?['status'],
          'IN_PROGRESS');
      expect(pickCaregiverHeroBooking([bk('CONFIRMED', date: '2026-10-02', time: '15:00'), bk('WAITING_CAREGIVER_APPROVAL')], now: now)?['status'],
          'WAITING_CAREGIVER_APPROVAL');
    });

    test('protagonista: de las confirmadas, la más próxima que no pasó', () {
      final picked = pickCaregiverHeroBooking([
        bk('CONFIRMED', date: '2026-10-05', time: '09:00'),
        bk('CONFIRMED', date: '2026-10-03', time: '09:00'),
        bk('CONFIRMED', date: '2026-10-01', time: '09:00'),
      ], now: now);
      expect(picked?['walkDate'], '2026-10-03');
    });

    test('notas rápidas: se arman con la mascota y se reconocen del otro lado', () {
      final text = QuickNote.agua.describe('Luna');
      expect(text, 'Luna tomó agua');
      expect(QuickNote.fromDescription(text), QuickNote.agua);
      expect(iconForNote(text), GIcon.agua);
      expect(iconForNote('Le cambié el agua del plato'), GIcon.nota);
      expect(QuickNote.descanso.describe(null), 'La mascota está descansando');
    });
  });

  group('ChatEvent', () {
    test('propuesta de Meet & Greet con detalles sin emojis', () {
      final e = ChatEvent.parse('📋 MEET & GREET PROPUESTO\n📅 jueves · 17:00\n📍 Parque Urbano\n🤝 Presencial');
      expect(e.kind, ChatEventKind.meetProposed);
      expect(e.details, ['jueves · 17:00', 'Parque Urbano', 'Presencial']);
    });

    test('clasifica confirmado, compatible, incompatible y cancelado', () {
      expect(ChatEvent.parse('✅ Meet & Greet confirmado · jueves').kind, ChatEventKind.meetConfirmed);
      expect(ChatEvent.parse('✅ Meet & Greet finalizado · ¡Todo compatible!').kind, ChatEventKind.meetCompatible);
      expect(ChatEvent.parse('❌ Meet & Greet finalizado · incompatibilidad').kind, ChatEventKind.meetIncompatible);
      final cancelled = ChatEvent.parse('🚫 Meet & Greet cancelado');
      expect(cancelled.kind, ChatEventKind.meetCancelled);
      expect(cancelled.text, 'Meet & Greet cancelado');
    });

    test('texto desconocido queda genérico y legible', () {
      final e = ChatEvent.parse('El cuidador llegó');
      expect(e.kind, ChatEventKind.generic);
      expect(e.text, 'El cuidador llegó');
    });
  });

  group('GardenService', () {
    test('lee los valores del backend', () {
      expect(GardenService.fromApi('PASEO'), GardenService.paseo);
      expect(GardenService.fromApi('guarderia'), GardenService.guarderia);
      expect(GardenService.fromApi('HOSPEDAJE'), GardenService.hospedaje);
      expect(GardenService.fromApi('OTRO'), isNull);
    });
  });

  group('Widgets', () {
    Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: Scaffold(body: Center(child: child)),
          ),
        );

    testWidgets('todos los iconos se dibujan en ambos estados', (tester) async {
      await tester.pumpWidget(host(Wrap(children: [
        for (final i in GIcon.values) ...[
          GardenIcon(i),
          GardenIcon(i, state: GIconState.active),
        ],
      ])));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('inheritColor toma el color del IconTheme; la estrella activa va rellena', (tester) async {
      const red = Color(0xFFFF0000);
      await tester.pumpWidget(host(const IconTheme(
        data: IconThemeData(color: red),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          GardenIcon(GIcon.buscar, inheritColor: true),
          GardenIcon(GIcon.estrella, state: GIconState.active, color: red),
        ]),
      )));
      await tester.pumpAndSettle();
      final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
      // buscar (idle): un glifo, con el color heredado.
      expect(icons.first.color, red);
      // estrella activa: relleno (duoSecondary) con opacidad completa, no 28 %.
      final starFill = icons[1];
      expect(starFill.color, red);
    });

    testWidgets('servicio en vivo no anima si el sistema pide menos movimiento', (tester) async {
      await tester.pumpWidget(host(const GardenIcon(GIcon.paseo, live: true), reduceMotion: true));
      // pumpAndSettle fallaría por timeout si quedara un bucle corriendo.
      await tester.pumpAndSettle();
      expect(find.byType(GardenIcon), findsOneWidget);
    });

    testWidgets('píldora y avatar en vivo muestran el estado', (tester) async {
      final story = BookingStory.of('IN_PROGRESS', ctx, now: now);
      await tester.pumpWidget(host(Column(mainAxisSize: MainAxisSize.min, children: [
        GardenStatusPill(story, service: GardenService.paseo, trailing: '23 min'),
        GardenPetAvatar(name: 'Luna', species: 'DOG', tone: story.tone, service: GardenService.paseo),
      ]), reduceMotion: true));
      await tester.pumpAndSettle();
      expect(find.text('Paseando · 23 min'), findsOneWidget);
    });

    testWidgets('tarjeta protagonista y encabezado en vivo se dibujan', (tester) async {
      final booking = {
        'id': 'b1', 'status': 'IN_PROGRESS', 'serviceType': 'PASEO', 'petName': 'Luna',
        'caregiverName': 'Andrea Rojas',
        'serviceStartedAt': DateTime.now().subtract(const Duration(minutes: 23)).toUtc().toIso8601String(),
      };
      await tester.pumpWidget(host(SingleChildScrollView(
        child: Column(children: [
          GardenBookingHeroCard(booking: booking, onAction: (_) {}, onChat: () {}),
          GardenLiveHero(booking: booking, timerLabel: '00:23:10', distanceKm: 1.6),
        ]),
      ), reduceMotion: true));
      await tester.pumpAndSettle();
      expect(find.text('Luna está paseando con Andrea.'), findsNWidgets(2));
      expect(find.text('Ver mapa'), findsOneWidget);
      expect(find.text('1,6 km'), findsOneWidget);
    });

    testWidgets('sellos de confianza: siempre los cuatro, pendiente si falta', (tester) async {
      await tester.pumpWidget(host(const GardenTrustSeals(
        identityVerified: true, backgroundChecked: false, offersWalks: false, caregiverFirstName: 'Andrea',
      )));
      await tester.pumpAndSettle();
      expect(find.text('Por qué confiar en Andrea'), findsOneWidget);
      for (final t in ['Identidad verificada', 'Antecedentes', 'Pago protegido', 'Seguimiento en vivo']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.text('Fotos durante el servicio'), findsOneWidget);
    });

    testWidgets('progreso de la historia muestra los tres pasos', (tester) async {
      await tester.pumpWidget(host(const GardenStoryProgress(steps: [
        StoryStepItem(GIcon.pagoProtegido, 'Pago verificado', StoryStepState.done),
        StoryStepItem(GIcon.esperando, 'Andrea acepta', StoryStepState.current, detail: 'detalle'),
        StoryStepItem(GIcon.paseo, 'Confirmada', StoryStepState.next),
      ]), reduceMotion: true));
      await tester.pumpAndSettle();
      expect(find.text('Andrea acepta'), findsOneWidget);
      expect(find.text('detalle'), findsOneWidget);
    });

    testWidgets('Brote dibuja las seis poses y se queda quieto', (tester) async {
      await tester.pumpWidget(host(Wrap(children: [
        for (final p in BrotePose.values) Brote(pose: p, size: 80),
      ])));
      // Sin bucles: debe asentarse solo después de la animación de entrada.
      await tester.pumpAndSettle();
      expect(find.byType(Brote), findsNWidgets(BrotePose.values.length));
    });
  });
}
