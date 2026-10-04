(function () {
  'use strict';

  var KEY = 'oma-theme-preference';
  var DARK = 'dark';
  var LIGHT = 'light';

  function preference() {
    return localStorage.getItem(KEY) || 'system';
  }

  function systemTheme() {
    return window.matchMedia &&
      window.matchMedia('(prefers-color-scheme: dark)').matches
      ? DARK
      : LIGHT;
  }

  function fallbackSunTheme() {
    var hour = new Date().getHours();
    return hour >= 6 && hour < 18 ? LIGHT : DARK;
  }

  // NOAA-style sunrise/sunset approximation. It uses browser geolocation when
  // the user permits it, and falls back to a safe 06:00/18:00 schedule.
  function solarTheme(lat, lon) {
    try {
      var now = new Date();
      var start = new Date(now.getFullYear(), 0, 0);
      var day = Math.floor((now - start) / 86400000);
      var lngHour = lon / 15;
      var tz = -now.getTimezoneOffset() / 60;

      function eventTime(rising) {
        var t = day + ((rising ? 6 : 18) - lngHour) / 24;
        var M = (0.9856 * t) - 3.289;
        var L = M + (1.916 * Math.sin(M * Math.PI / 180)) +
          (0.020 * Math.sin(2 * M * Math.PI / 180)) + 282.634;
        L = (L + 360) % 360;
        var RA = Math.atan(0.91764 * Math.tan(L * Math.PI / 180)) * 180 / Math.PI;
        RA = (RA + 360) % 360;
        var Lq = Math.floor(L / 90) * 90;
        var RAq = Math.floor(RA / 90) * 90;
        RA = (RA + (Lq - RAq)) / 15;
        var sinDec = 0.39782 * Math.sin(L * Math.PI / 180);
        var cosDec = Math.cos(Math.asin(sinDec));
        var cosH = (Math.cos(90.833 * Math.PI / 180) -
          (sinDec * Math.sin(lat * Math.PI / 180))) /
          (cosDec * Math.cos(lat * Math.PI / 180));
        if (cosH > 1 || cosH < -1) return null;
        var H = rising
          ? 360 - Math.acos(cosH) * 180 / Math.PI
          : Math.acos(cosH) * 180 / Math.PI;
        H /= 15;
        var UT = H + RA - (0.06571 * t) - 6.622;
        UT = (UT - lngHour + 24) % 24;
        var local = UT + tz;
        return (local + 24) % 24;
      }

      var sunrise = eventTime(true);
      var sunset = eventTime(false);
      if (sunrise == null || sunset == null) return fallbackSunTheme();

      var hour = now.getHours() + now.getMinutes() / 60;
      return hour >= sunrise && hour < sunset ? LIGHT : DARK;
    } catch (_) {
      return fallbackSunTheme();
    }
  }

  function applyTheme() {
    var pref = preference();
    var theme = LIGHT;

    if (pref === 'light') {
      theme = LIGHT;
    } else if (pref === 'dark') {
      theme = DARK;
    } else if (pref === 'sunset') {
      if (navigator.geolocation) {
        navigator.geolocation.getCurrentPosition(
          function (position) {
            var next = solarTheme(
              position.coords.latitude,
              position.coords.longitude
            );
            document.documentElement.setAttribute('data-oma-theme', next);
          },
          function () {
            document.documentElement.setAttribute(
              'data-oma-theme',
              fallbackSunTheme()
            );
          },
          { maximumAge: 3600000, timeout: 4000 }
        );
      } else {
        theme = fallbackSunTheme();
      }
    } else {
      theme = systemTheme();
    }

    document.documentElement.setAttribute('data-oma-theme', theme);
    updateControl();
  }

  function updateControl() {
    var control = document.getElementById('omaThemePreference');
    if (control && control.value !== preference()) {
      control.value = preference();
    }
  }

  function installControl() {
    var control = document.getElementById('omaThemePreference');
    if (!control || control.dataset.omaBound === '1') return;
    control.dataset.omaBound = '1';
    control.addEventListener('change', function () {
      localStorage.setItem(KEY, control.value);
      applyTheme();
    });
    updateControl();
  }

  applyTheme();
  installControl();

  window.setInterval(applyTheme, 60 * 1000);

  document.addEventListener('visibilitychange', function () {
    if (!document.hidden) applyTheme();
  });

  window.addEventListener('storage', function (event) {
    if (event.key === KEY) applyTheme();
  });

  if (window.matchMedia) {
    var media = window.matchMedia('(prefers-color-scheme: dark)');
    if (media.addEventListener) {
      media.addEventListener('change', function () {
        if (preference() === 'system') applyTheme();
      });
    }
  }

  window.addEventListener('DOMContentLoaded', function () {
    installControl();
    applyTheme();
  });
})();
