/*
 * Aviso de cookies del sitio gardenbo.com — la landing y las páginas legales. NO va en la app
 * (ni en app.html, su versión web): la app no muestra avisos de cookies.
 *
 * Se muestra abajo la primera vez. "Aceptar" = todas las cookies (incluidas las estadísticas de
 * uso de GARDEN); "Solo necesarias" = sesión y preferencias, sin estadísticas. La elección queda en
 * la cookie `garden_cookies` (all | essential) por un año. La app web solo la lee: con
 * "essential" no envía estadísticas (lib/utils/cookie_consent_web.dart). Sin dependencias.
 */
(function () {
  var NAME = 'garden_cookies';

  function read() {
    var m = document.cookie.match(/(?:^|;\s*)garden_cookies=(all|essential)/);
    return m ? m[1] : null;
  }

  function save(value) {
    var secure = location.protocol === 'https:' ? '; Secure' : '';
    document.cookie = NAME + '=' + value + '; Max-Age=31536000; Path=/; SameSite=Lax' + secure;
    try { window.dispatchEvent(new CustomEvent('garden-cookies', { detail: value })); } catch (e) { /* navegador viejo */ }
  }

  /** Para la app y para volver a abrir el aviso (ej. desde la política de privacidad). */
  window.gardenCookies = { get: read, reset: function () { document.cookie = NAME + '=; Max-Age=0; Path=/'; show(); } };

  var css =
    '#garden-cookies{position:fixed;left:16px;right:16px;bottom:16px;z-index:2147483647;max-width:560px;margin:0 auto;' +
    'background:#FAF7F2;color:#1E2D0F;border:1px solid #D8D6D0;border-radius:16px;padding:16px 18px;' +
    'box-shadow:0 8px 28px rgba(30,45,15,.16);font:14px/1.45 Nunito,system-ui,-apple-system,Segoe UI,Roboto,sans-serif;' +
    'display:flex;flex-wrap:wrap;gap:12px 16px;align-items:center;animation:gcIn .25s ease-out}' +
    '#garden-cookies p{margin:0;flex:1 1 280px}' +
    '#garden-cookies a{color:#5C6E32;font-weight:700}' +
    '#garden-cookies .gc-b{display:flex;gap:8px;flex:0 0 auto;margin-left:auto}' +
    '#garden-cookies button{font:inherit;font-weight:800;border-radius:999px;padding:9px 16px;cursor:pointer;border:1.5px solid #778C43}' +
    '#garden-cookies .gc-yes{background:#778C43;color:#fff}' +
    '#garden-cookies .gc-no{background:transparent;color:#5C6E32}' +
    '#garden-cookies button:focus-visible{outline:3px solid #B9CC86;outline-offset:2px}' +
    '@media (prefers-color-scheme:dark){#garden-cookies{background:#1A1D1B;color:#EEF0EE;border-color:#333834;box-shadow:0 8px 28px rgba(0,0,0,.45)}' +
    '#garden-cookies a{color:#A3BA62}#garden-cookies .gc-no{color:#A3BA62;border-color:#A3BA62}}' +
    '@media (prefers-reduced-motion:reduce){#garden-cookies{animation:none}}' +
    '@keyframes gcIn{from{opacity:0;transform:translateY(12px)}to{opacity:1;transform:none}}';

  function show() {
    if (document.getElementById('garden-cookies')) return;
    if (!document.getElementById('garden-cookies-css')) {
      var st = document.createElement('style');
      st.id = 'garden-cookies-css';
      st.textContent = css;
      document.head.appendChild(st);
    }
    var box = document.createElement('div');
    box.id = 'garden-cookies';
    box.setAttribute('role', 'dialog');
    box.setAttribute('aria-live', 'polite');
    box.setAttribute('aria-label', 'Aviso de cookies');
    box.innerHTML =
      '<p>Usamos cookies para que GARDEN funcione, recordar tu sesión y entender cómo se usa la web para mejorarla. ' +
      'Puedes aceptarlas todas o quedarte solo con las necesarias. <a href="/privacidad.html#cookies">Política de privacidad</a></p>' +
      '<div class="gc-b"><button type="button" class="gc-no">Solo necesarias</button>' +
      '<button type="button" class="gc-yes">Aceptar</button></div>';
    function choose(v) { save(v); box.remove(); }
    box.querySelector('.gc-yes').addEventListener('click', function () { choose('all'); });
    box.querySelector('.gc-no').addEventListener('click', function () { choose('essential'); });
    document.body.appendChild(box);
  }

  function init() { if (!read()) show(); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
