import 'package:shared_preferences/shared_preferences.dart';

/// Small key-value settings store for user preferences
/// (theme mode, sound on/off).
///
/// Backed by `shared_preferences`, which replaced Hive in this app.
/// Game data itself lives in the Drift database, not here.
class AppSettings {
  static const String themeModeKey = 'theme_mode';
  static const String soundEnabledKey = 'sound_enabled';

  final SharedPreferences _prefs;

  AppSettings(this._prefs);

  static Future<AppSettings> load() async {
    return AppSettings(await SharedPreferences.getInstance());
  }

  /// 'light', 'dark' or 'system' (default).
  String get themeMode => _prefs.getString(themeModeKey) ?? 'system';

  Future<void> setThemeMode(String value) =>
      _prefs.setString(themeModeKey, value);

  bool get soundEnabled => _prefs.getBool(soundEnabledKey) ?? true;

  Future<void> setSoundEnabled(bool value) =>
      _prefs.setBool(soundEnabledKey, value);
}
