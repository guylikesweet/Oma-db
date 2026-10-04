import 'package:flutter/material.dart';

enum OmaThemePreference {
  system,
  sunsetToSunrise,
  light,
  dark,
}

class OmaThemeController {
  OmaThemeController._();

  static ThemeMode themeModeFor(
    OmaThemePreference preference, {
    Brightness? systemBrightness,
    DateTime? now,
  }) {
    switch (preference) {
      case OmaThemePreference.light:
        return ThemeMode.light;
      case OmaThemePreference.dark:
        return ThemeMode.dark;
      case OmaThemePreference.system:
        return (systemBrightness ?? Brightness.light) == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light;
      case OmaThemePreference.sunsetToSunrise:
        final value = now ?? DateTime.now();
        final hour = value.hour + value.minute / 60;
        return hour >= 6 && hour < 18 ? ThemeMode.light : ThemeMode.dark;
    }
  }
}
