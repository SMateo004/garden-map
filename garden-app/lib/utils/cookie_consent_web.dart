import 'dart:html' as html;

/// La app no muestra el aviso de cookies (solo el sitio: web/cookie-consent.js en la
/// landing y las páginas legales). Pero si en el sitio la persona eligió "Solo
/// necesarias" (cookie `garden_cookies=essential`, mismo dominio), la app web
/// respeta esa elección y no envía estadísticas. Sin elección, siguen como siempre.
/// Se lee en cada envío: si cambia, vale desde ese momento.
bool cookieAnalyticsAllowed() => !RegExp(r'(?:^|;\s*)garden_cookies=essential(?:;|$)').hasMatch(html.document.cookie ?? '');
