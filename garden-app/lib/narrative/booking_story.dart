import 'package:flutter/material.dart';

import '../design/garden_icons.dart';
import '../design/garden_service.dart';
import '../theme/garden_theme.dart';

// ── RELATO DE LA RESERVA ───────────────────────────────────────────────────
// Única traducción de un estado de reserva a lo que ve la gente: icono, tono,
// texto de la píldora, titular para el dueño, titular para el cuidador y
// próximo paso. Marketplace, Mis reservas, chat, home del cuidador y push
// leen de acá — ninguna pantalla vuelve a escribir su propio
// `if (status == 'IN_PROGRESS') 'En curso'`.
//
// Voz (ver plan de rediseño):
//   • Tuteo. Sujeto = la mascota o la persona, nunca "el sistema".
//   • Nombre de la mascota y PRIMER nombre del cuidador.
//   • Con dinero, cancelaciones y disputas: sin exclamaciones ni chistes.
//   • No prometer lo que el backend no garantiza (plazos, reembolsos).
//
// Estados = enum BookingStatus de garden-api/prisma/schema.prisma.

enum BookingStatus {
  pendingMg('PENDING_MG'),
  pendingPayment('PENDING_PAYMENT'),
  paymentPendingApproval('PAYMENT_PENDING_APPROVAL'),
  waitingCaregiverApproval('WAITING_CAREGIVER_APPROVAL'),
  slotConflict('SLOT_CONFLICT'),
  confirmed('CONFIRMED'),
  inProgress('IN_PROGRESS'),
  completed('COMPLETED'),
  cancelled('CANCELLED'),
  rejectedByCaregiver('REJECTED_BY_CAREGIVER');

  const BookingStatus(this.apiValue);
  final String apiValue;

  static BookingStatus? fromApi(String? value) {
    for (final s in BookingStatus.values) {
      if (s.apiValue == value) return s;
    }
    return null;
  }
}

/// Tono visual del estado. Decide color de píldora, anillo del avatar, etc.
enum StoryTone {
  /// Falta algo de alguien (pago, respuesta). Ámbar.
  waiting,
  /// Coordinación previa (Meet & Greet). Azul.
  info,
  /// Todo listo. Verde.
  good,
  /// Servicio en curso. Color del servicio + pulso.
  live,
  /// Terminó bien. Bosque.
  done,
  /// Cancelado / rechazado. Gris, sin dramatismo.
  neutral,
  /// Conflicto o disputa. Rojo.
  alert,
}

/// Próximo paso sugerido. La pantalla decide a dónde navega cada uno.
enum StoryAction {
  pay,
  chat,
  respond,
  viewMeet,
  chooseOtherTime,
  viewNotes,
  viewMap,
  sendPhoto,
  rate,
  bookAgain,
  findAnother,
  viewDetail,
}

class StoryStep {
  final StoryAction action;
  final String label;
  const StoryStep(this.action, this.label);
}

/// Datos de la reserva que personalizan el relato.
class BookingStoryContext {
  final String? petName;
  final String? caregiverName;
  final GardenService? service;
  final DateTime? start;
  final bool rated;
  final bool disputed;

  /// Cómo se nombra al cuidador si no hay nombre. El dueño lee "tu
  /// cuidador"; el admin, que no es parte de la reserva, "el cuidador".
  final String caregiverFallback;

  const BookingStoryContext({
    this.petName,
    this.caregiverName,
    this.service,
    this.start,
    this.rated = false,
    this.disputed = false,
    this.caregiverFallback = 'tu cuidador',
  });

  /// Lee el JSON de una reserva tal como lo devuelve garden-api
  /// (bookingToResponse en booking.types.ts). [caregiverView]: el "otro" de la
  /// historia es el dueño, no el cuidador — por ahora solo cambia el nombre.
  factory BookingStoryContext.fromBooking(Map<String, dynamic> b,
      {bool caregiverView = false, String caregiverFallback = 'tu cuidador'}) {
    return BookingStoryContext(
      caregiverFallback: caregiverFallback,
      petName: b['petName'] as String?,
      caregiverName: (caregiverView ? b['clientName'] : b['caregiverName']) as String?,
      service: GardenService.fromApi(b['serviceType'] as String?),
      start: bookingStart(b),
      rated: b['ownerRated'] == true || b['ownerRating'] != null,
      disputed: b['hasDisputePending'] == true,
    );
  }

  /// Fecha y hora de inicio: walkDate (paseo/guardería) o startDate
  /// (hospedaje), más startTime "HH:mm" si existe. Son fechas sin huso en la
  /// base (hora de Bolivia), así que se arman como hora local del teléfono.
  static DateTime? bookingStart(Map<String, dynamic> b) {
    final date = (b['walkDate'] ?? b['startDate']) as String?;
    if (date == null || date.length < 10) return null;
    final d = DateTime.tryParse(date.substring(0, 10));
    if (d == null) return null;
    final t = (b['startTime'] as String?)?.split(':');
    final h = t != null && t.isNotEmpty ? int.tryParse(t[0]) : null;
    final m = t != null && t.length > 1 ? int.tryParse(t[1]) : null;
    return DateTime(d.year, d.month, d.day, h ?? 0, m ?? 0);
  }

  String get pet => _clean(petName) ?? 'tu mascota';
  String get caregiver => _firstName(caregiverName) ?? caregiverFallback;

  static String? _clean(String? s) {
    final v = s?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  static String? _firstName(String? s) => _clean(s)?.split(RegExp(r'\s+')).first;
}

class BookingStory {
  final BookingStatus? status;
  final StoryTone tone;
  final GIcon icon;
  final String pill;
  final String ownerHeadline;
  final String caregiverHeadline;
  final StoryStep? ownerNext;
  final StoryStep? caregiverNext;

  const BookingStory({
    required this.status,
    required this.tone,
    required this.icon,
    required this.pill,
    required this.ownerHeadline,
    required this.caregiverHeadline,
    this.ownerNext,
    this.caregiverNext,
  });

  bool get isLive => tone == StoryTone.live;

  String headlineFor({required bool caregiverView}) =>
      caregiverView ? caregiverHeadline : ownerHeadline;

  StoryStep? nextFor({required bool caregiverView}) =>
      caregiverView ? caregiverNext : ownerNext;

  /// Construye el relato a partir del valor crudo del backend.
  factory BookingStory.of(String? apiStatus, BookingStoryContext c, {DateTime? now}) {
    final status = BookingStatus.fromApi(apiStatus);
    final pet = c.pet;
    final cg = c.caregiver;
    // "a el cuidador" -> "al cuidador" (el admin usa ese genérico).
    final toCg = cg.startsWith('el ') ? 'al ${cg.substring(3)}' : 'a $cg';
    final svc = c.service;
    final when = c.start != null ? whenLabel(c.start!, now: now ?? DateTime.now()) : null;
    final whenSuffix = when != null ? ' $when' : '';

    // Una disputa abierta tapa cualquier otro estado.
    if (c.disputed) {
      return BookingStory(
        status: status,
        tone: StoryTone.alert,
        icon: GIcon.enRevision,
        pill: 'En revisión',
        ownerHeadline: 'Estamos revisando lo que pasó con la reserva de $pet. Te avisamos apenas haya una decisión.',
        caregiverHeadline: 'Hay una revisión abierta sobre la reserva de $pet.',
        ownerNext: const StoryStep(StoryAction.viewDetail, 'Ver detalle'),
        caregiverNext: const StoryStep(StoryAction.viewDetail, 'Ver detalle'),
      );
    }

    switch (status) {
      case BookingStatus.pendingMg:
        return BookingStory(
          status: status,
          tone: StoryTone.info,
          icon: GIcon.meetGreet,
          pill: 'Primero se conocen',
          ownerHeadline: 'Antes del primer ${_noun(svc)}, $cg y $pet se van a conocer.',
          caregiverHeadline: 'Coordina el Meet & Greet con $pet antes del servicio.',
          ownerNext: const StoryStep(StoryAction.viewMeet, 'Ver propuesta'),
          caregiverNext: const StoryStep(StoryAction.viewMeet, 'Ver propuesta'),
        );

      case BookingStatus.pendingPayment:
        return BookingStory(
          status: status,
          tone: StoryTone.waiting,
          icon: GIcon.pagarQr,
          pill: 'Falta pagar',
          ownerHeadline: 'Solo falta el pago para asegurar el ${_noun(svc)} de $pet.',
          caregiverHeadline: 'Esperando el pago de la reserva de $pet.',
          ownerNext: const StoryStep(StoryAction.pay, 'Pagar'),
        );

      case BookingStatus.paymentPendingApproval:
        return BookingStory(
          status: status,
          tone: StoryTone.waiting,
          icon: GIcon.esperando,
          pill: 'Verificando pago',
          ownerHeadline: 'Estamos confirmando tu pago con el banco. Te avisamos apenas esté.',
          caregiverHeadline: 'El pago de la reserva de $pet se está verificando.',
        );

      case BookingStatus.waitingCaregiverApproval:
        return BookingStory(
          status: status,
          tone: StoryTone.waiting,
          icon: GIcon.esperando,
          pill: 'Esperando $toCg',
          ownerHeadline: '$cg está viendo tu solicitud para $pet.',
          caregiverHeadline: '$pet quiere ${_wantVerb(svc)} contigo$whenSuffix.',
          ownerNext: StoryStep(StoryAction.chat, 'Escribir $toCg'),
          caregiverNext: const StoryStep(StoryAction.respond, 'Responder'),
        );

      case BookingStatus.slotConflict:
        return BookingStory(
          status: status,
          tone: StoryTone.alert,
          icon: GIcon.conflicto,
          pill: 'Horario ocupado',
          ownerHeadline: 'Ese horario se ocupó. Elige otro para $pet.',
          caregiverHeadline: 'Hay un cruce de horario con la reserva de $pet.',
          ownerNext: const StoryStep(StoryAction.chooseOtherTime, 'Elegir otro horario'),
        );

      case BookingStatus.confirmed:
        return BookingStory(
          status: status,
          tone: StoryTone.good,
          icon: GIcon.confirmado,
          pill: 'Confirmado',
          ownerHeadline: '¡Listo! $cg ${_doVerb(svc)} $pet$whenSuffix.',
          caregiverHeadline: '${_cap(when) ?? 'Pronto'} ${_youVerb(svc)} $pet. Revisa sus notas.',
          ownerNext: StoryStep(StoryAction.chat, 'Escribir $toCg'),
          caregiverNext: StoryStep(StoryAction.viewNotes, 'Ver notas de $pet'),
        );

      case BookingStatus.inProgress:
        return BookingStory(
          status: status,
          tone: StoryTone.live,
          icon: svc != null ? GIcon.forService(svc) : GIcon.enVivo,
          pill: _livePill(svc),
          ownerHeadline: _liveOwner(svc, pet, cg),
          caregiverHeadline: '${_liveCaregiver(svc, pet)} Envía una foto.',
          ownerNext: svc == GardenService.paseo
              ? const StoryStep(StoryAction.viewMap, 'Ver mapa')
              : StoryStep(StoryAction.chat, 'Escribir $toCg'),
          caregiverNext: const StoryStep(StoryAction.sendPhoto, 'Enviar foto'),
        );

      case BookingStatus.completed:
        return BookingStory(
          status: status,
          tone: StoryTone.done,
          icon: GIcon.terminado,
          pill: svc == GardenService.hospedaje ? 'Terminado' : 'De vuelta en casa',
          ownerHeadline: c.rated
              ? '$pet volvió a casa después de su ${_noun(svc)} con $cg.'
              : '$pet volvió a casa. ¿Cómo le fue con $cg?',
          caregiverHeadline: 'Servicio terminado. Gracias por cuidar a $pet.',
          ownerNext: c.rated
              ? const StoryStep(StoryAction.bookAgain, 'Reservar de nuevo')
              : const StoryStep(StoryAction.rate, 'Calificar'),
        );

      case BookingStatus.cancelled:
        return BookingStory(
          status: status,
          tone: StoryTone.neutral,
          icon: GIcon.cancelado,
          pill: 'Cancelado',
          ownerHeadline: 'La reserva de $pet se canceló.',
          caregiverHeadline: 'La reserva de $pet se canceló.',
          ownerNext: const StoryStep(StoryAction.findAnother, 'Buscar cuidador'),
        );

      case BookingStatus.rejectedByCaregiver:
        return BookingStory(
          status: status,
          tone: StoryTone.neutral,
          icon: GIcon.cancelado,
          pill: 'No disponible',
          ownerHeadline: '$cg no puede esta vez. Busquemos otro cuidador para $pet.',
          caregiverHeadline: 'Rechazaste la solicitud de $pet.',
          ownerNext: const StoryStep(StoryAction.findAnother, 'Buscar otro cuidador'),
        );

      case null:
        return BookingStory(
          status: null,
          tone: StoryTone.neutral,
          icon: GIcon.reservas,
          pill: 'Reserva',
          ownerHeadline: 'Reserva de $pet con $cg.',
          caregiverHeadline: 'Reserva de $pet.',
        );
    }
  }

  // ── Gramática por servicio ──────────────────────────────────────────────

  static String _noun(GardenService? s) => switch (s) {
        GardenService.paseo     => 'paseo',
        GardenService.guarderia => 'día de guardería',
        GardenService.hospedaje => 'hospedaje',
        null                    => 'servicio',
      };

  // "Luna quiere ___ contigo"
  static String _wantVerb(GardenService? s) => switch (s) {
        GardenService.paseo     => 'pasear',
        GardenService.guarderia => 'pasar el día',
        GardenService.hospedaje => 'quedarse',
        null                    => 'estar',
      };

  // "Andrea ___ Luna mañana"
  static String _doVerb(GardenService? s) => switch (s) {
        GardenService.paseo     => 'pasea a',
        GardenService.hospedaje => 'hospeda a',
        _                       => 'cuida a',
      };

  // "Mañana a las 9:00 ___ Luna"
  static String _youVerb(GardenService? s) => switch (s) {
        GardenService.paseo     => 'paseas a',
        GardenService.hospedaje => 'hospedas a',
        _                       => 'cuidas a',
      };

  static String _livePill(GardenService? s) => switch (s) {
        GardenService.paseo     => 'Paseando',
        GardenService.guarderia => 'En la guardería',
        GardenService.hospedaje => 'Hospedado',
        null                    => 'En curso',
      };

  static String _liveOwner(GardenService? s, String pet, String cg) => switch (s) {
        GardenService.paseo     => '$pet está paseando con $cg.',
        GardenService.guarderia => '$pet está pasando el día con $cg.',
        GardenService.hospedaje => '$pet se está quedando con $cg.',
        null                    => '$pet está con $cg.',
      };

  static String _liveCaregiver(GardenService? s, String pet) => switch (s) {
        GardenService.paseo     => 'Estás paseando a $pet.',
        GardenService.hospedaje => '$pet se está quedando contigo.',
        _                       => 'Estás cuidando a $pet.',
      };

  static String? _cap(String? s) =>
      (s == null || s.isEmpty) ? s : s[0].toUpperCase() + s.substring(1);

  // ── Fechas en lenguaje natural ──────────────────────────────────────────

  /// Tiempo transcurrido corto: "8 min", "1 h 05 min", "2 días".
  static String elapsedLabel(DateTime since, {required DateTime now}) {
    final d = now.difference(since);
    if (d.isNegative || d.inMinutes < 1) return 'recién';
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    if (d.inHours < 24) {
      final m = d.inMinutes % 60;
      return m == 0 ? '${d.inHours} h' : '${d.inHours} h ${m.toString().padLeft(2, '0')} min';
    }
    return d.inDays == 1 ? '1 día' : '${d.inDays} días';
  }

  static const _weekdays = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

  /// "hoy a las 9:00", "mañana a las 15:30", "el sábado a las 9:00",
  /// "el 14/11 a las 9:00".
  static String whenLabel(DateTime start, {required DateTime now}) {
    final local = start.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = day.difference(today).inDays;
    final hh = local.hour.toString();
    final mm = local.minute.toString().padLeft(2, '0');
    // 0:00 = sin hora (hospedaje solo tiene fecha): antes decía
    // "el domingo a las 0:00".
    final at = local.hour == 0 && local.minute == 0
        ? ''
        : local.hour == 1
            ? ' a la $hh:$mm'
            : ' a las $hh:$mm';
    if (diff == 0) return 'hoy$at';
    if (diff == 1) return 'mañana$at';
    if (diff > 1 && diff < 7) return 'el ${_weekdays[local.weekday - 1]}$at';
    final dd = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    return 'el $dd/$mo$at';
  }
}

// ── COLORES POR TONO ─────────────────────────────────────────────────────

class StoryColors {
  final Color ink;
  final Color soft;
  const StoryColors(this.ink, this.soft);

  static StoryColors of(StoryTone tone, {required bool isDark, GardenService? service}) {
    Color a(Color c, double o) => c.withValues(alpha: o);
    switch (tone) {
      case StoryTone.waiting:
        final c = isDark ? const Color(0xFFFFC24D) : const Color(0xFFB87800);
        return StoryColors(c, a(GardenColors.warning, isDark ? 0.16 : 0.16));
      case StoryTone.info:
        final c = isDark ? const Color(0xFF7AA9FF) : GardenColors.infoDark;
        return StoryColors(c, a(GardenColors.info, 0.14));
      case StoryTone.good:
        final c = isDark ? GardenColors.accent : const Color(0xFF2FA83A);
        return StoryColors(c, a(GardenColors.accent, isDark ? 0.16 : 0.18));
      case StoryTone.live:
        final svc = service ?? GardenService.paseo;
        return StoryColors(svc.ink(isDark), svc.soft(isDark));
      case StoryTone.done:
        final c = isDark ? const Color(0xFF4FD18A) : GardenColors.forest;
        return StoryColors(c, a(GardenColors.forest, isDark ? 0.22 : 0.12));
      case StoryTone.neutral:
        final c = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
        return StoryColors(c, isDark ? GardenColors.darkSurfaceElevated : GardenColors.lightSurfaceElevated);
      case StoryTone.alert:
        final c = isDark ? const Color(0xFFFF7A6B) : const Color(0xFFC0392B);
        return StoryColors(c, a(GardenColors.error, isDark ? 0.18 : 0.10));
    }
  }
}

// ── RESERVA PROTAGONISTA ───────────────────────────────────────────────────

/// Elige la reserva que va arriba de todo en el inicio del dueño, en orden de
/// lo que más necesita su atención:
///   en vivo → horario ocupado → Meet & Greet → confirmada (hasta 3 h después
///   de la hora de inicio) → esperando al cuidador → terminada sin calificar
///   (hasta 3 días después).
/// Las PENDING_PAYMENT no entran: suelen ser QR abandonados.
Map<String, dynamic>? pickHeroBooking(List<Map<String, dynamic>> bookings, {required DateTime now}) {
  bool recentStart(Map<String, dynamic> b) {
    final start = BookingStoryContext.bookingStart(b);
    return start == null || now.isBefore(start.add(const Duration(hours: 3)));
  }

  bool recentlyEndedUnrated(Map<String, dynamic> b) {
    if (b['ownerRated'] == true || b['ownerRating'] != null) return false;
    final ended = DateTime.tryParse(b['serviceEndedAt'] as String? ?? '');
    return ended != null && now.difference(ended.toLocal()).inHours < 72;
  }

  final rules = <(String, bool Function(Map<String, dynamic>))>[
    ('IN_PROGRESS', (_) => true),
    ('SLOT_CONFLICT', (_) => true),
    ('PENDING_MG', (_) => true),
    ('CONFIRMED', recentStart),
    ('WAITING_CAREGIVER_APPROVAL', (_) => true),
    ('COMPLETED', recentlyEndedUnrated),
  ];
  for (final (status, ok) in rules) {
    for (final b in bookings) {
      if (b['status'] == status && ok(b)) return b;
    }
  }
  return null;
}

/// Reserva protagonista del inicio del cuidador: lo que lo necesita ahora.
///   en curso → solicitud por responder → Meet & Greet → la confirmada más
///   próxima (hasta 3 h después de su hora de inicio).
Map<String, dynamic>? pickCaregiverHeroBooking(List<Map<String, dynamic>> bookings, {required DateTime now}) {
  for (final status in const ['IN_PROGRESS', 'WAITING_CAREGIVER_APPROVAL', 'PENDING_MG']) {
    for (final b in bookings) {
      if (b['status'] == status) return b;
    }
  }
  Map<String, dynamic>? soonest;
  DateTime? soonestStart;
  for (final b in bookings) {
    if (b['status'] != 'CONFIRMED') continue;
    final start = BookingStoryContext.bookingStart(b);
    if (start == null || now.isAfter(start.add(const Duration(hours: 3)))) continue;
    if (soonestStart == null || start.isBefore(soonestStart)) {
      soonest = b;
      soonestStart = start;
    }
  }
  return soonest;
}
