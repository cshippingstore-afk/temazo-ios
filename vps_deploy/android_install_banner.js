/* /js/android_install_banner.js — Banner "Descarga la app" para visitantes Android.
   v2 (2026-07-27): dismissal SOLO por 7 días (antes era permanente), botón alternativo
   siempre visible como enlace de emergencia, mejor detección "inside app".

   Se muestra al cargar la web si:
   • User-Agent es Android
   • NO está dentro de la propia app (TWA o WebView)
   • No lo han descartado en los últimos 7 días (localStorage)
   • No están en /descargar o /app/

   Estilo: bottom sheet flotante, dismissible, persistente cross-page (delegation).
*/
(function(){
  'use strict';
  if (window.__tzAndroidBannerInit) return;
  window.__tzAndroidBannerInit = true;

  const DISMISS_KEY = 'tz_android_banner_dismissed_at';
  const REDISMISS_DAYS = 7;   // banner vuelve a aparecer tras N días

  // --- Detección ---
  function isAndroid(){
    return /Android/i.test(navigator.userAgent || '');
  }
  function isInsideApp(){
    const ua = navigator.userAgent || '';
    if (/wv\)/i.test(ua)) return true;                  // Android WebView estándar
    if (/Temazo/i.test(ua)) return true;                // Nuestra app propia
    if (document.referrer && document.referrer.startsWith('android-app://')) return true;
    return false;
  }
  function isDismissed(){
    try {
      const ts = localStorage.getItem(DISMISS_KEY);
      if (!ts) return false;
      const age = Date.now() - parseInt(ts, 10);
      const maxAge = REDISMISS_DAYS * 24 * 60 * 60 * 1000;
      return age > 0 && age < maxAge;
    } catch(_) { return false; }
  }
  function markDismissed(){
    try { localStorage.setItem(DISMISS_KEY, String(Date.now())); } catch(_){}
    const el = document.getElementById('tzAndroidBanner');
    if (el) el.remove();
  }
  function shouldShow(){
    if (!isAndroid()) return false;
    if (isInsideApp()) return false;
    if (isDismissed()) return false;
    const p = location.pathname || '';
    if (p === '/descargar' || p.startsWith('/descargar/') || p.startsWith('/app/')) return false;
    return true;
  }

  // --- Inyección de estilos ---
  function injectStyles(){
    if (document.getElementById('tz-android-banner-styles')) return;
    const s = document.createElement('style');
    s.id = 'tz-android-banner-styles';
    s.textContent = `
#tzAndroidBanner {
  position: fixed; left: 12px; right: 12px; bottom: 92px; z-index: 9999;
  background: linear-gradient(135deg, #1a0a2e 0%, #2a1340 100%);
  border: 1px solid rgba(231,76,139,.35);
  border-radius: 14px;
  box-shadow: 0 18px 50px rgba(0,0,0,.55), 0 0 0 1px rgba(231,76,139,.10);
  padding: 14px 16px;
  display: flex; align-items: center; gap: 12px;
  animation: tzbslide .35s cubic-bezier(.2,.7,.3,1);
  color: #fff; font-family: inherit;
  max-width: 600px; margin: 0 auto;
}
@keyframes tzbslide { from{transform:translateY(120%);opacity:0} to{transform:translateY(0);opacity:1} }
#tzAndroidBanner .tzb-icon {
  width: 44px; height: 44px; border-radius: 10px; flex-shrink: 0;
  background: linear-gradient(135deg, #e74c8b, #a855f7);
  display:flex; align-items:center; justify-content:center;
  font-size: 22px; color: #fff;
}
#tzAndroidBanner .tzb-body { flex: 1 1 auto; min-width: 0; }
#tzAndroidBanner .tzb-title { font-size: 14px; font-weight: 700; color: #fff; line-height: 1.2; }
#tzAndroidBanner .tzb-sub { font-size: 11.5px; color: rgba(255,255,255,.65); margin-top: 2px; }
#tzAndroidBanner .tzb-btn {
  background: linear-gradient(135deg, #e74c8b, #a855f7);
  color: #fff; border: 0; border-radius: 999px;
  padding: 9px 16px; font-size: 13px; font-weight: 700; cursor: pointer;
  flex-shrink: 0; text-decoration: none; display: inline-block;
  box-shadow: 0 4px 14px rgba(231,76,139,.40);
  transition: transform .12s, filter .15s;
}
#tzAndroidBanner .tzb-btn:hover { filter: brightness(1.1); transform: translateY(-1px); }
#tzAndroidBanner .tzb-close {
  background: transparent; border: 0; color: rgba(255,255,255,.5);
  cursor: pointer; padding: 4px 8px; font-size: 16px; flex-shrink: 0;
}
#tzAndroidBanner .tzb-close:hover { color: #fff; }
@media (max-width: 480px) {
  #tzAndroidBanner { bottom: 80px; padding: 12px; gap: 10px; }
  #tzAndroidBanner .tzb-btn { padding: 8px 12px; font-size: 12px; }
  #tzAndroidBanner .tzb-sub { display: none; }
}

/* Botón alternativo persistente en el footer (solo Android). Si el user descartó
   el banner, este link fijo garantiza que siempre puede acceder a la descarga. */
#tzAndroidFooterLink {
  display: flex; align-items: center; justify-content: center;
  gap: 8px;
  margin: 20px auto 30px; padding: 10px 18px;
  max-width: 340px;
  border-radius: 999px;
  background: linear-gradient(135deg, rgba(231,76,139,.15), rgba(168,85,247,.15));
  border: 1px solid rgba(231,76,139,.35);
  color: #fff; text-decoration: none; font-size: 13px; font-weight: 600;
  box-shadow: 0 6px 18px rgba(0,0,0,.28);
}
#tzAndroidFooterLink:hover { filter: brightness(1.1); }
#tzAndroidFooterLink .tzf-icon {
  width: 22px; height: 22px; border-radius: 6px;
  background: linear-gradient(135deg, #e74c8b, #a855f7);
  display: flex; align-items: center; justify-content: center;
  font-size: 12px;
}
`;
    document.head.appendChild(s);
  }

  // --- Render banner principal ---
  function renderBanner(){
    if (document.getElementById('tzAndroidBanner')) return;
    injectStyles();
    const el = document.createElement('div');
    el.id = 'tzAndroidBanner';
    el.innerHTML =
      '<div class="tzb-icon">📱</div>' +
      '<div class="tzb-body">' +
        '<div class="tzb-title">Temazo App — versión completa</div>' +
        '<div class="tzb-sub">Música con pantalla bloqueada, en segundo plano y offline</div>' +
      '</div>' +
      '<a class="tzb-btn" href="/app/temazo-full.apk" download>Instalar</a>' +
      '<button type="button" class="tzb-close" aria-label="Cerrar">✕</button>';
    document.body.appendChild(el);
    el.querySelector('.tzb-close').addEventListener('click', markDismissed);
  }

  // --- Render link alternativo (siempre visible en Android, incluso dismissed) ---
  function renderFooterLink(){
    if (document.getElementById('tzAndroidFooterLink')) return;
    // Solo si estamos en Android y NO estamos dentro de la app
    if (!isAndroid() || isInsideApp()) return;
    // Insertar antes del footer o al final del body
    const footer = document.querySelector('footer') || document.body;
    injectStyles();
    const a = document.createElement('a');
    a.id = 'tzAndroidFooterLink';
    a.href = '/app/temazo-full.apk';
    a.setAttribute('download', '');
    a.innerHTML = '<span class="tzf-icon">📱</span>Descargar app Android completa';
    footer.parentNode.insertBefore(a, footer);
  }

  // --- Trigger ---
  function tryShow(){
    if (shouldShow()) {
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => setTimeout(renderBanner, 800));
      } else {
        setTimeout(renderBanner, 800);
      }
    }
    // Footer link se renderiza SIEMPRE que sea Android (aunque banner esté dismissed)
    if (isAndroid() && !isInsideApp()) {
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', renderFooterLink);
      } else {
        renderFooterLink();
      }
    }
  }
  tryShow();

  // --- Debug (opcional, activar con ?debug_banner=1 o localStorage flag) ---
  const debug = (() => {
    try {
      if (new URLSearchParams(location.search).get('debug_banner') === '1') return true;
      return localStorage.getItem('tz_banner_debug') === '1';
    } catch(_){ return false; }
  })();
  if (debug) {
    console.info('[TzAndroidBanner v2]', {
      android: isAndroid(),
      insideApp: isInsideApp(),
      dismissed: isDismissed(),
      dismissedAt: (() => { try { return localStorage.getItem(DISMISS_KEY); } catch(_){ return null }})(),
      willShowBanner: shouldShow(),
      path: location.pathname,
      ua: navigator.userAgent
    });
  }
})();
