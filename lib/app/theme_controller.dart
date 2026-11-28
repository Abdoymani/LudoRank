import 'package:flutter/material.dart';
import 'package:ludo_rank/core/settings/app_settings.dart';

class ThemeController extends ChangeNotifier {
  final AppSettings _settings;

  late ThemeMode _themeMode;

  ThemeController({required AppSettings settings}) : _settings = settings {
    _themeMode = _parseThemeMode(_settings.themeMode);
  }

  ThemeMode get themeMode => _themeMode;

  ThemeMode _parseThemeMode(dynamic value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;

    final savedValue = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };

    // Save the new setting before updating the UI.
    await _settings.setThemeMode(savedValue);

    _themeMode = mode;
    notifyListeners();
  }
}
