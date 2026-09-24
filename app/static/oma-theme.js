(function () {
  'use strict';

  function omaThemeForNow() {
    var hour = new Date().getHours();

    // Light mode: 06:00 - 17:59
    if (hour >= 6 && hour < 18) {
      return 'light';
    }

    // Dark mode: 18:00 - 05:59
    return 'dark';
  }

  function applyOmaTheme() {
    var theme = omaThemeForNow();

    document.documentElement.setAttribute(
      'data-oma-theme',
      theme
    );
  }

  // Apply immediately when the page loads.
  applyOmaTheme();

  // Check again every minute so the theme changes automatically
  // when the scheduled time is reached.
  window.setInterval(
    applyOmaTheme,
    60 * 1000
  );

  // Re-check when the user returns to the page/app.
  document.addEventListener(
    'visibilitychange',
    function () {
      if (!document.hidden) {
        applyOmaTheme();
      }
    }
  );
})();
