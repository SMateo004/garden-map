import '../design/garden_icons.dart';
import 'booking_story.dart';

// ── NOTIFICACIONES DEL BUZÓN ───────────────────────────────────────────────
// El backend guarda `type` como texto libre (Notification.type, VarChar 20) y
// hoy usa unos 60 valores (grep "type: '" en garden-api/src). Antes la
// campana conocía 15, con nombres que el backend no usa (PAYMENT_RECEIVED,
// REVIEW_RECEIVED...): casi todo salía con la campana genérica.
//
// Este archivo es el ÚNICO lugar que traduce un tipo a icono, tono y tema.
// Un tipo nuevo del backend cae en su tema por prefijo, y si no, en "Novedades".

/// De qué trata: decide el icono por defecto y a dónde lleva tocarla.
enum NotificationTopic { booking, service, money, review, chat, account, problem, news }

class NotificationKind {
  final NotificationTopic topic;
  final GIcon icon;
  final StoryTone tone;

  const NotificationKind(this.topic, this.icon, this.tone);

  static const _exact = <String, NotificationKind>{
    // Reservas
    'NEW_BOOKING': NotificationKind(NotificationTopic.booking, GIcon.reservas, StoryTone.waiting),
    'BOOKING_ACCEPTED': NotificationKind(NotificationTopic.booking, GIcon.confirmado, StoryTone.good),
    'BOOKING_REJECTED': NotificationKind(NotificationTopic.booking, GIcon.cancelado, StoryTone.neutral),
    'BOOKING_REJECTED_REFUND_NEEDED': NotificationKind(NotificationTopic.money, GIcon.reembolso, StoryTone.waiting),
    'BOOKING_CANCELLED': NotificationKind(NotificationTopic.booking, GIcon.cancelado, StoryTone.neutral),
    'LATE_CANCELLATION': NotificationKind(NotificationTopic.booking, GIcon.cancelado, StoryTone.waiting),
    'MEET_AND_GREET': NotificationKind(NotificationTopic.booking, GIcon.meetGreet, StoryTone.info),
    'WAITLIST_OPENING': NotificationKind(NotificationTopic.booking, GIcon.calendario, StoryTone.good),
    // Servicio en curso
    'SERVICE_EN_ROUTE': NotificationKind(NotificationTopic.service, GIcon.auto, StoryTone.live),
    'SERVICE_ARRIVED': NotificationKind(NotificationTopic.service, GIcon.ubicacion, StoryTone.live),
    'SERVICE_STARTED': NotificationKind(NotificationTopic.service, GIcon.enVivo, StoryTone.live),
    'SERVICE_CHECKIN_PHOTO': NotificationKind(NotificationTopic.service, GIcon.foto, StoryTone.live),
    'LOCATION_PING_REQUEST': NotificationKind(NotificationTopic.service, GIcon.miUbicacion, StoryTone.info),
    'SERVICE_MARKED_ENDED': NotificationKind(NotificationTopic.service, GIcon.terminado, StoryTone.done),
    'SERVICE_COMPLETED': NotificationKind(NotificationTopic.service, GIcon.terminado, StoryTone.done),
    'WALK_EXPIRY_WARNING': NotificationKind(NotificationTopic.service, GIcon.reloj, StoryTone.waiting),
    'WALK_EXPIRY_END': NotificationKind(NotificationTopic.service, GIcon.terminado, StoryTone.done),
    'SERVICE_EXTENSION': NotificationKind(NotificationTopic.service, GIcon.agregar, StoryTone.info),
    'EXTENSION_PENDING_PAYMENT': NotificationKind(NotificationTopic.service, GIcon.pagarQr, StoryTone.waiting),
    'EXTENSION_PAYMENT_APPROVAL': NotificationKind(NotificationTopic.service, GIcon.pagarQr, StoryTone.waiting),
    'EXTENSION_CONFIRMED': NotificationKind(NotificationTopic.service, GIcon.confirmado, StoryTone.good),
    // Dinero
    'PAYMENT': NotificationKind(NotificationTopic.money, GIcon.pagoProtegido, StoryTone.good),
    'REFUND': NotificationKind(NotificationTopic.money, GIcon.reembolso, StoryTone.good),
    'WITHDRAWAL': NotificationKind(NotificationTopic.money, GIcon.retiro, StoryTone.info),
    'EARNING': NotificationKind(NotificationTopic.money, GIcon.billetera, StoryTone.good),
    'OVERTIME_EARNING': NotificationKind(NotificationTopic.money, GIcon.billetera, StoryTone.good),
    'OVERTIME_FEE': NotificationKind(NotificationTopic.money, GIcon.reloj, StoryTone.waiting),
    'TIP': NotificationKind(NotificationTopic.money, GIcon.regalo, StoryTone.good),
    'TIP_RECEIVED': NotificationKind(NotificationTopic.money, GIcon.regalo, StoryTone.good),
    'GIFT': NotificationKind(NotificationTopic.money, GIcon.regalo, StoryTone.good),
    'REFERRAL_BONUS': NotificationKind(NotificationTopic.money, GIcon.invitar, StoryTone.good),
    'WALLET': NotificationKind(NotificationTopic.money, GIcon.billetera, StoryTone.info),
    'DEBT_RECOVERY': NotificationKind(NotificationTopic.money, GIcon.billetera, StoryTone.waiting),
    // Reseñas y chat
    'REVIEW': NotificationKind(NotificationTopic.review, GIcon.estrella, StoryTone.good),
    'LOW_RATING': NotificationKind(NotificationTopic.problem, GIcon.estrella, StoryTone.alert),
    'CHAT_MESSAGE': NotificationKind(NotificationTopic.chat, GIcon.chat, StoryTone.info),
    // Problemas
    'CLIENT_SOS_URGENT': NotificationKind(NotificationTopic.problem, GIcon.emergencia, StoryTone.alert),
    'SERVICE_INCIDENT_URGENT': NotificationKind(NotificationTopic.problem, GIcon.emergencia, StoryTone.alert),
    'SERVICE_INCIDENT': NotificationKind(NotificationTopic.problem, GIcon.advertencia, StoryTone.alert),
    'INCIDENT': NotificationKind(NotificationTopic.problem, GIcon.advertencia, StoryTone.alert),
    'WALKIN_INCIDENT': NotificationKind(NotificationTopic.problem, GIcon.advertencia, StoryTone.alert),
    'INCIDENT_RESOLVED': NotificationKind(NotificationTopic.problem, GIcon.hecho, StoryTone.good),
    'CHAT_REPORT': NotificationKind(NotificationTopic.problem, GIcon.reportar, StoryTone.alert),
    'BLOCKCHAIN_FAILURE': NotificationKind(NotificationTopic.problem, GIcon.advertencia, StoryTone.alert),
    // Cuenta y perfil
    'CAREGIVER_WELCOME': NotificationKind(NotificationTopic.account, GIcon.huella, StoryTone.good),
    'PROFILE_SUBMITTED': NotificationKind(NotificationTopic.account, GIcon.enviado, StoryTone.info),
    'PROFILE_UNDER_REVIEW': NotificationKind(NotificationTopic.account, GIcon.enRevision, StoryTone.waiting),
    'PROFILE_APPROVED': NotificationKind(NotificationTopic.account, GIcon.verificado, StoryTone.good),
    'PROFILE_REJECTED': NotificationKind(NotificationTopic.account, GIcon.conflicto, StoryTone.alert),
    'REJECTED': NotificationKind(NotificationTopic.account, GIcon.conflicto, StoryTone.alert),
    'APPROVED': NotificationKind(NotificationTopic.account, GIcon.verificado, StoryTone.good),
    'ANTECEDENTES_REJECTED': NotificationKind(NotificationTopic.account, GIcon.antecedentes, StoryTone.alert),
    'ACCOUNT_SUSPENDED': NotificationKind(NotificationTopic.account, GIcon.bloqueado, StoryTone.alert),
    'ACCOUNT_ACTIVATED': NotificationKind(NotificationTopic.account, GIcon.desbloqueado, StoryTone.good),
    'TRAINING_REMINDER': NotificationKind(NotificationTopic.account, GIcon.capacitacion, StoryTone.waiting),
    'STAFF_JOINED': NotificationKind(NotificationTopic.account, GIcon.equipo, StoryTone.good),
    'NIT_VERIFICATION_SUBMITTED': NotificationKind(NotificationTopic.account, GIcon.documento, StoryTone.info),
    'NIT_REJECTED': NotificationKind(NotificationTopic.account, GIcon.documento, StoryTone.alert),
    'PHONE_CHANGE_AUTHORIZED': NotificationKind(NotificationTopic.account, GIcon.telefono, StoryTone.good),
    'PHONE_OTP_MANUAL_HELP': NotificationKind(NotificationTopic.account, GIcon.telefono, StoryTone.waiting),
    'EMAIL_OTP_MANUAL_HELP': NotificationKind(NotificationTopic.account, GIcon.correo, StoryTone.waiting),
    // Novedades
    'ZONE_NOW_AVAILABLE': NotificationKind(NotificationTopic.news, GIcon.mapa, StoryTone.good),
    'INFO': NotificationKind(NotificationTopic.news, GIcon.info, StoryTone.info),
    'SYSTEM': NotificationKind(NotificationTopic.news, GIcon.anuncio, StoryTone.info),
  };

  static NotificationKind of(String type) {
    final exact = _exact[type];
    if (exact != null) return exact;
    // Respaldo por prefijo para tipos nuevos.
    if (type.startsWith('DISPUTE')) return const NotificationKind(NotificationTopic.problem, GIcon.enRevision, StoryTone.alert);
    if (type.startsWith('BOOKING')) return const NotificationKind(NotificationTopic.booking, GIcon.reservas, StoryTone.info);
    if (type.startsWith('SERVICE') || type.startsWith('WALK') || type.startsWith('EXTENSION')) {
      return const NotificationKind(NotificationTopic.service, GIcon.enVivo, StoryTone.info);
    }
    if (type.contains('INCIDENT') || type.contains('URGENT')) {
      return const NotificationKind(NotificationTopic.problem, GIcon.advertencia, StoryTone.alert);
    }
    if (type.contains('PAYMENT') || type.contains('REFUND') || type.contains('WALLET')) {
      return const NotificationKind(NotificationTopic.money, GIcon.billetera, StoryTone.info);
    }
    return const NotificationKind(NotificationTopic.news, GIcon.notificaciones, StoryTone.info);
  }

  /// Título sin los emojis del backend ("<emoji de auto> Tu cuidador va en camino" →
  /// "Tu cuidador va en camino"): el icono ya dice lo mismo.
  static String clean(String title) {
    final out = StringBuffer();
    for (final r in title.runes) {
      final emoji = (r >= 0x1F300 && r <= 0x1FAFF) || (r >= 0x2600 && r <= 0x27BF) || r == 0xFE0F || r == 0x200D;
      if (!emoji) out.writeCharCode(r);
    }
    return out.toString().replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }
}
