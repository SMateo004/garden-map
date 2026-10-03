import '../design/garden_icons.dart';
import 'booking_story.dart';

// ── EVENTOS DEL CHAT ───────────────────────────────────────────────────────
// Los mensajes de sistema del chat (isSystem = true) hoy llegan como texto con
// un emoji al principio (✅ / ❌ / 📋 / 🚫), armados en
// garden-api/src/modules/meet-and-greet/meet-and-greet.service.ts.
//
// Este archivo es el ÚNICO lugar que interpreta ese texto. Las pantallas
// reciben un ChatEvent tipado con icono y tono del sistema de diseño, y nunca
// deciden colores leyendo el emoji.
//
// Siguiente paso (requiere migración en la base de producción, se decide
// aparte): que el backend mande un campo `eventType` y este parser pase a ser
// solo el respaldo para mensajes viejos.

enum ChatEventKind {
  meetProposed,
  meetConfirmed,
  meetCompatible,
  meetIncompatible,
  meetCancelled,
  generic,
}

class ChatEvent {
  final ChatEventKind kind;
  final GIcon icon;
  final StoryTone tone;

  /// Texto para mostrar, sin el emoji inicial.
  final String text;

  /// Líneas de detalle (fecha, lugar, modalidad) sin sus emojis.
  final List<String> details;

  const ChatEvent({
    required this.kind,
    required this.icon,
    required this.tone,
    required this.text,
    this.details = const [],
  });

  static final _leadingSymbols = RegExp(
    r'^[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}\s]+',
    unicode: true,
  );

  static String stripLeadingEmoji(String s) => s.replaceFirst(_leadingSymbols, '').trim();

  factory ChatEvent.parse(String raw) {
    final lines = raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final first = lines.isEmpty ? '' : lines.first;
    final rest = lines.skip(1).map(stripLeadingEmoji).where((l) => l.isNotEmpty).toList();
    final upper = first.toUpperCase();

    if (first.startsWith('📋') && upper.contains('MEET & GREET')) {
      return ChatEvent(
        kind: ChatEventKind.meetProposed,
        icon: GIcon.meetGreet,
        tone: StoryTone.info,
        text: 'Meet & Greet propuesto',
        details: rest,
      );
    }
    if (first.startsWith('🚫')) {
      return ChatEvent(
        kind: ChatEventKind.meetCancelled,
        icon: GIcon.cancelado,
        tone: StoryTone.neutral,
        text: stripLeadingEmoji(first),
        details: rest,
      );
    }
    if (first.startsWith('❌')) {
      return ChatEvent(
        kind: upper.contains('MEET & GREET') ? ChatEventKind.meetIncompatible : ChatEventKind.generic,
        icon: GIcon.cancelado,
        tone: StoryTone.alert,
        text: stripLeadingEmoji(first),
        details: rest,
      );
    }
    if (first.startsWith('✅')) {
      final finished = upper.contains('FINALIZADO');
      return ChatEvent(
        kind: finished ? ChatEventKind.meetCompatible : ChatEventKind.meetConfirmed,
        icon: GIcon.confirmado,
        tone: StoryTone.good,
        text: stripLeadingEmoji(first),
        details: rest,
      );
    }
    return ChatEvent(
      kind: ChatEventKind.generic,
      icon: GIcon.huella,
      tone: StoryTone.info,
      text: stripLeadingEmoji(first),
      details: rest,
    );
  }
}
