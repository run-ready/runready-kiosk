/**
 * Injects auth into the page's localStorage at document_start (before the React app).
 * config.generated.js defines RUNREADY_KIOSK in the extension context.
 */
(function runreadyKioskInject() {
  if (typeof RUNREADY_KIOSK === 'undefined' || !RUNREADY_KIOSK) {
    return;
  }

  var cfg = RUNREADY_KIOSK;
  var lines = ['try {'];

  if (cfg.token) {
    if (cfg.forceTokenSync) {
      lines.push('localStorage.setItem("auth_token", ' + JSON.stringify(cfg.token) + ');');
    } else {
      lines.push(
        'if (!localStorage.getItem("auth_token")) { localStorage.setItem("auth_token", ' +
          JSON.stringify(cfg.token) +
          '); }'
      );
    }
  }

  if (cfg.organizationId) {
    lines.push(
      'localStorage.setItem("selectedOrganizationId", ' + JSON.stringify(cfg.organizationId) + ');'
    );
  }

  if (cfg.calendarKioskMode) {
    lines.push('localStorage.setItem("calendarOps_kioskMode", "true");');
  }

  lines.push('} catch (e) { console.warn("[RunReady Kiosk]", e); }');

  var script = document.createElement('script');
  script.textContent = lines.join('\n');
  var root = document.documentElement || document.head || document.body;
  if (root) {
    root.appendChild(script);
    script.remove();
  }
})();
