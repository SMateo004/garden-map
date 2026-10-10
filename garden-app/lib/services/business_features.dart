/// Funciones de negocio que SOLO el admin habilita por negocio (recepción, equipo, permisos
/// del equipo). El backend las manda ya resueltas en `businessFeatures` — en GET
/// /caregiver/my-profile (dueño) y GET /caregiver-staff/whoami (empleado). Ausente = apagada.
/// Mismas claves que garden-api/src/modules/business-features/business-features.service.ts.
class BusinessFeatures {
  BusinessFeatures._();

  static const reception = 'RECEPTION';
  static const staffTeam = 'STAFF_TEAM';
  static const staffBookingDecisions = 'STAFF_BOOKING_DECISIONS';
  static const staffClientChat = 'STAFF_CLIENT_CHAT';

  /// `source` es el perfil del cuidador o la respuesta de whoami.
  static bool has(Map? source, String key) {
    final features = source?['businessFeatures'];
    return features is Map && features[key] == true;
  }
}
