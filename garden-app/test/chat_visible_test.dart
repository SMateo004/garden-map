import 'package:flutter_test/flutter_test.dart';
import 'package:garden_app/services/chat_service.dart';

/// FcmService no avisa de los mensajes del chat que se está mirando:
/// depende de que ChatService marque bien cuál está a la vista.
void main() {
  ChatService make() => ChatService(baseUrl: 'https://ejemplo.invalid/api', token: 't', currentUserId: 'u1');

  test('al entrar a un chat queda a la vista', () {
    final c = make()..joinBooking('b1');
    expect(ChatService.visibleChatBookingId, 'b1');
    c.dispose();
  });

  test('en segundo plano deja de estar a la vista y vuelve al regresar', () {
    final c = make()..joinBooking('b2');
    c.isForeground = false;
    expect(ChatService.visibleChatBookingId, isNull);
    c.isForeground = true;
    expect(ChatService.visibleChatBookingId, 'b2');
    c.dispose();
  });

  test('al cerrar el chat deja de estar a la vista', () {
    final c = make()..joinBooking('b3');
    c.dispose();
    expect(ChatService.visibleChatBookingId, isNull);
  });

  test('cerrar un chat viejo no borra el que está abierto ahora', () {
    final viejo = make()..joinBooking('b4');
    final nuevo = make()..joinBooking('b5');
    viejo.dispose();
    expect(ChatService.visibleChatBookingId, 'b5');
    nuevo.dispose();
  });
}
