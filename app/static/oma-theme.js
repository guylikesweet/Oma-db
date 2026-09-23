(function () {
  'use strict';

  // Automatic Oma theme:
  // 06:00 - 17:59 = Light mode
  // 18:00 - 05:59 = Dark mode
  function omaThemeForNow() {
    var hour = new Date().getHours();

    if (hour >= 6 && hour < 18) {
      return 'light';
    }

    return 'dark';
  }

  function applyOmaTheme() {
    var theme = omaThemeForNow();
    document.documentElement.setAttribute('data-oma-theme', theme);
  }

  // Apply immediately when the page loads.
  applyOmaTheme();

  // Check every minute in case the time crosses 06:00 or 18:00.
  window.setInterval(applyOmaTheme, 60 * 1000);

  // Re-check when the user returns to the page/tab.
  document.addEventListener('visibilitychange', function () {
    if (!document.hidden) {
      applyOmaTheme();
    }
  });
})();
