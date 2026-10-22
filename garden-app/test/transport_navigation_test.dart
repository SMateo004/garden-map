import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/screens/service/transport_leg_card.dart';
import 'package:garden_app/utils/navigation_launcher.dart';

void main() {
  group('enlaces de navegación (ruta directa a la casa del dueño)', () {
    test('Google Maps traza la ruta en auto hasta las coordenadas', () {
      final u = NavigationLauncher.uriFor('google', -17.7838, -63.1821).toString();
      expect(u, 'https://www.google.com/maps/dir/?api=1&destination=-17.7838,-63.1821&travelmode=driving');
    });
    test('Waze navega directo', () {
      expect(NavigationLauncher.uriFor('waze', -17.75, -63.18).toString(), 'https://waze.com/ul?ll=-17.75,-63.18&navigate=yes');
    });
    test('Apple Maps con destino y modo auto', () {
      expect(NavigationLauncher.uriFor('apple', -17.75, -63.18).toString(), 'https://maps.apple.com/?daddr=-17.75,-63.18&dirflg=d');
    });
    test('una app desconocida cae en Google Maps', () {
      expect(NavigationLauncher.uriFor('???', 1, 2).host, 'www.google.com');
    });
  });

  group('botón "Navegar a su casa" en la tarjeta del viaje', () {
    Future<void> pump(WidgetTester t, {required String role, required String legStatus, required String bookingStatus, String kind = 'PICKUP', bool withCoords = true}) {
      final leg = <String, dynamic>{
        'kind': kind, 'status': legStatus, 'fee': 15,
        'address': 'Av. Banzer #123',
        if (withCoords) 'addressLat': -17.75,
        if (withCoords) 'addressLng': -63.18,
        'distanceKm': 3,
      };
      return t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TransportLegCard(
              booking: {'id': 'b1', 'status': bookingStatus, 'serviceType': 'HOSPEDAJE', 'petName': 'Toby'},
              leg: leg,
              role: role,
              token: 't',
              baseUrl: 'http://localhost',
              onChanged: () async {},
            ),
          ),
        ),
      ));
    }

    testWidgets('cuidador: recojo programado con la reserva confirmada', (t) async {
      await pump(t, role: 'CAREGIVER', legStatus: 'SCHEDULED', bookingStatus: 'CONFIRMED');
      expect(find.text('Navegar a su casa'), findsOneWidget);
    });
    testWidgets('cuidador: entrega en camino con el servicio en curso', (t) async {
      await pump(t, role: 'CAREGIVER', legStatus: 'EN_ROUTE', bookingStatus: 'IN_PROGRESS', kind: 'DROPOFF');
      expect(find.text('Navegar a su casa'), findsOneWidget);
    });
    testWidgets('el dueño nunca lo ve', (t) async {
      await pump(t, role: 'CLIENT', legStatus: 'SCHEDULED', bookingStatus: 'CONFIRMED');
      expect(find.text('Navegar a su casa'), findsNothing);
    });
    testWidgets('no aparece si ya llegó, ya se hizo o fue cancelado', (t) async {
      for (final s in ['ARRIVED', 'DONE', 'CANCELLED']) {
        await pump(t, role: 'CAREGIVER', legStatus: s, bookingStatus: 'CONFIRMED');
        expect(find.text('Navegar a su casa'), findsNothing, reason: s);
      }
    });
    testWidgets('sin coordenadas (reserva sin confirmar) no hay a dónde navegar', (t) async {
      await pump(t, role: 'CAREGIVER', legStatus: 'SCHEDULED', bookingStatus: 'WAITING_CAREGIVER_APPROVAL', withCoords: false);
      expect(find.text('Navegar a su casa'), findsNothing);
    });
    testWidgets('la entrega no se navega antes de empezar el servicio', (t) async {
      await pump(t, role: 'CAREGIVER', legStatus: 'SCHEDULED', bookingStatus: 'CONFIRMED', kind: 'DROPOFF');
      expect(find.text('Navegar a su casa'), findsNothing);
    });
  });
}
