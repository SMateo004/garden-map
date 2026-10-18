// Elección del aviso de cookies del sitio (web/cookie-consent.js). La app no
// muestra el aviso; en el teléfono las estadísticas siguen su interruptor de Ajustes.
export 'cookie_consent_stub.dart' if (dart.library.html) 'cookie_consent_web.dart';
