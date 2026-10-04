import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:solar_calculator/solar_calculator.dart';

import '../data/local_database.dart';

enum OmaThemePreference {
  system,
  sunsetToSunrise,
  light,
  dark,
}

class OmaThemeController {
  OmaThemeController._();

  static const _metaKey = 'theme_preference';

  static final preference = ValueNotifier<OmaThemePreference>(
    OmaThemePreference.system,
  );

  static final resolvedMode = ValueNotifier<ThemeMode>(
    ThemeMode.light,
  );

  static LocalDatabase? _local;
  static bool _initialized = false;

  static Future<void> initialize(LocalDatabase local) async {
    if (_initialized) return;
    _local = local;
    _initialized = true;

    final saved = await local.getMeta(_metaKey);
    preference.value = _decode(saved);
    await refresh();
  }

  static OmaThemePreference _decode(String? value) {
    switch (value) {
      case 'sunset_to_sunrise':
        return OmaThemePreference.sunsetToSunrise;
      case 'light':
        return OmaThemePreference.light;
      case 'dark':
        return OmaThemePreference.dark;
      default:
        return OmaThemePreference.system;
    }
  }

  static String _encode(OmaThemePreference value) {
    switch (value) {
      case OmaThemePreference.system:
        return 'system';
      case OmaThemePreference.sunsetToSunrise:
        return 'sunset_to_sunrise';
      case OmaThemePreference.light:
        return 'light';
      case OmaThemePreference.dark:
        return 'dark';
    }
  }

  static Future<void> setPreference(OmaThemePreference value) async {
    preference.value = value;
    await _local?.setMeta(_metaKey, _encode(value));
    await refresh();
  }

  static Future<void> refresh({Brightness? systemBrightness}) async {
    final choice = preference.value;

    switch (choice) {
      case OmaThemePreference.light:
        resolvedMode.value = ThemeMode.light;
        return;
      case OmaThemePreference.dark:
        resolvedMode.value = ThemeMode.dark;
        return;
      case OmaThemePreference.system:
        final brightness =
            systemBrightness ??
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
        resolvedMode.value = brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light;
        return;
      case OmaThemePreference.sunsetToSunrise:
        final dark = await _isDarkBySun();
        resolvedMode.value = dark ? ThemeMode.dark : ThemeMode.light;
    }
  }

  static Future<bool> _isDarkBySun() async {
    try {
      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return _fallbackDarkness();
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
        return _fallbackDarkness();
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );

      final now = DateTime.now();
      final offset = now.timeZoneOffset.inMinutes / 60.0;

      final instant = Instant(
        year: now.year,
        month: now.month,
        day: now.day,
        hour: now.hour,
        minute: now.minute,
        second: now.second,
        timeZoneOffset: offset,
      );

      final solar = SolarCalculator(
        instant,
        position.latitude,
        position.longitude,
        offset,
      );

      return solar.isHoursOfDarkness;
    } catch (_) {
      return _fallbackDarkness();
    }
  }

  static bool _fallbackDarkness() {
    final now = DateTime.now();
    final hour = now.hour + now.minute / 60.0;
    return hour < 6 || hour >= 18;
  }

  static String label(OmaThemePreference value) {
    switch (value) {
      case OmaThemePreference.system:
        return 'System';
      case OmaThemePreference.sunsetToSunrise:
        return 'Sunset to sunrise';
      case OmaThemePreference.light:
        return 'Light';
      case OmaThemePreference.dark:
        return 'Dark';
    }
  }

  static IconData icon(OmaThemePreference value) {
    switch (value) {
      case OmaThemePreference.system:
        return Icons.settings_suggest_outlined;
      case OmaThemePreference.sunsetToSunrise:
        return Icons.brightness_6_outlined;
      case OmaThemePreference.light:
        return Icons.light_mode_outlined;
      case OmaThemePreference.dark:
        return Icons.dark_mode_outlined;
    }
  }
}
