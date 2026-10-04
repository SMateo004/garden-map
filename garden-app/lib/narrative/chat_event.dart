import '../design/garden_icons.dart';
import 'booking_story.dart';

// ── EVENTOS DEL CHAT ───────────────────────────────────────────────────────
// Los mensajes de sistema del chat (isSystem = true) los arma
// garden-api/src/modules/meet-and-greet/meet-and-greet.service.ts. Desde
// octubre 2026 traen `eventType` (MG_PROPOSED, MG_CONFIRMED, ...) y eso decide
// el tipo. Los mensajes anteriores no lo tienen: para ellos queda el respaldo
// que lee el emoji inicial (✅ / ❌ / 📋 / 🚫).
//
// Este archivo es el ÚNICO lugar que interpreta mensajes de sistema. Las
// pantallas reciben un ChatEvent con icono y tono del sistema de diseño, y
// nunca deciden colores leyendo el texto.

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

  /// Tipo que manda el backend en `eventType`, o null si no lo reconoce.
  static ChatEventKind? kindFromType(String? eventType) => switch (eventType) {
        'MG_PROPOSED' => ChatEventKind.meetProposed,
        'MG_CONFIRMED' => ChatEventKind.meetConfirmed,
        'MG_COMPATIBLE' => ChatEventKind.meetCompatible,
        'MG_INCOMPATIBLE' => ChatEventKind.meetIncompatible,
        'MG_CANCELLED' => ChatEventKind.meetCancelled,
        _ => null,
      };

  /// Punto de entrada para pantallas: usa [eventType] si el backend lo mandó
  /// y lo reconoce; si no, deduce el tipo del texto (mensajes viejos).
  factory ChatEvent.from(String raw, {String? eventType}) {
    final kind = kindFromType(eventType);
    if (kind == null) return ChatEvent.parse(raw);
    final lines = raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final first = lines.isEmpty ? '' : lines.first;
    final rest = lines.skip(1).map(stripLeadingEmoji).where((l) => l.isNotEmpty).toList();
    return ChatEvent._ofKind(kind, first, rest);
  }

  /// Cómo se ve cada tipo. El texto sale del mensaje, sin su emoji; solo la
  /// propuesta usa un título fijo porque el backend la manda en mayúsculas.
  factory ChatEvent._ofKind(ChatEventKind kind, String first, List<String> rest) {
    final text = stripLeadingEmoji(first);
    return switch (kind) {
      ChatEventKind.meetProposed => ChatEvent(
          kind: kind, icon: GIcon.meetGreet, tone: StoryTone.info, text: 'Meet & Greet propuesto', details: rest),
      ChatEventKind.meetConfirmed || ChatEventKind.meetCompatible => ChatEvent(
          kind: kind, icon: GIcon.confirmado, tone: StoryTone.good, text: text, details: rest),
      ChatEventKind.meetIncompatible => ChatEvent(
          kind: kind, icon: GIcon.cancelado, tone: StoryTone.alert, text: text, details: rest),
      ChatEventKind.meetCancelled => ChatEvent(
          kind: kind, icon: GIcon.cancelado, tone: StoryTone.neutral, text: text, details: rest),
      ChatEventKind.generic => ChatEvent(
          kind: kind, icon: GIcon.huella, tone: StoryTone.info, text: text, details: rest),
    };
  }

  /// Respaldo para mensajes sin `eventType`: deduce el tipo del emoji inicial.
  factory ChatEvent.parse(String raw) {
    final lines = raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final first = lines.isEmpty ? '' : lines.first;
    final rest = lines.skip(1).map(stripLeadingEmoji).where((l) => l.isNotEmpty).toList();
    final upper = first.toUpperCase();

    final ChatEventKind kind;
    if (first.startsWith('📋') && upper.contains('MEET & GREET')) {
      kind = ChatEventKind.meetProposed;
    } else if (first.startsWith('🚫')) {
      kind = ChatEventKind.meetCancelled;
    } else if (first.startsWith('❌')) {
      kind = upper.contains('MEET & GREET') ? ChatEventKind.meetIncompatible : ChatEventKind.generic;
    } else if (first.startsWith('✅')) {
      kind = upper.contains('FINALIZADO') ? ChatEventKind.meetCompatible : ChatEventKind.meetConfirmed;
    } else {
      kind = ChatEventKind.generic;
    }
    // Un ❌ que no es del Meet & Greet conserva el tono de alerta de antes.
    if (kind == ChatEventKind.generic && first.startsWith('❌')) {
      return ChatEvent(kind: kind, icon: GIcon.cancelado, tone: StoryTone.alert, text: stripLeadingEmoji(first), details: rest);
    }
    return ChatEvent._ofKind(kind, first, rest);
  }
}
