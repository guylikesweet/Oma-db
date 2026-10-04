import 'package:flutter/material.dart';

import 'core/theme_controller.dart';

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OmaThemePreference>(
      valueListenable: OmaThemeController.preference,
      builder: (context, selected, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Appearance'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor:
                            Theme.of(context).colorScheme.secondary.withOpacity(.12),
                        foregroundColor:
                            Theme.of(context).colorScheme.secondary,
                        child: const Icon(Icons.palette_outlined),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Oma appearance',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Choose how light and dark mode should behave on this device.',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: Column(
                  children: OmaThemePreference.values.map((value) {
                    return RadioListTile<OmaThemePreference>(
                      value: value,
                      groupValue: selected,
                      secondary: Icon(OmaThemeController.icon(value)),
                      title: Text(OmaThemeController.label(value)),
                      subtitle: Text(_description(value)),
                      onChanged: (next) {
                        if (next != null) {
                          OmaThemeController.setPreference(next);
                        }
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _description(OmaThemePreference value) {
    switch (value) {
      case OmaThemePreference.system:
        return 'Follow the phone or browser appearance setting.';
      case OmaThemePreference.sunsetToSunrise:
        return 'Use the device location to follow local daylight; falls back safely when location is unavailable.';
      case OmaThemePreference.light:
        return 'Always use the light theme.';
      case OmaThemePreference.dark:
        return 'Always use the dark theme.';
    }
  }
}
