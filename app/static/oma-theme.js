(function () {
  'use strict';

  // Oma switches automatically using the device/browser's local time:
  // 06:00-17:59 = light, 18:00-05:59 = dark.
  function omaThemeForNow() {
    var hour = new Date().getHours();
    return (hour >= 6 && hour < 18) ? 'light' : 'dark';
  }

  function applyOmaTheme() {
    document.documentElement.setAttribute('data-oma-theme', omaThemeForNow());
  }

  applyOmaTheme();
  window.setInterval(applyOmaTheme, 60 * 1000);
  document.addEventListener('visibilitychange', function () {
    if (!document.hidden) applyOmaTheme();
  });
})();
