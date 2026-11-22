import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ludo_rank/app/theme_controller.dart';
import 'package:ludo_rank/core/audio/sound_controller.dart';
import 'package:ludo_rank/core/settings/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettings', () {
    test('defaults: sound on, system theme', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettings.load();

      expect(settings.soundEnabled, isTrue);
      expect(settings.themeMode, 'system');
    });
  });

  group('SoundController', () {
    test('mute is saved and survives a restart', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = SoundController(await AppSettings.load());
      expect(controller.enabled, isTrue);

      var notified = 0;
      controller.addListener(() => notified++);
      await controller.toggle();

      expect(controller.enabled, isFalse);
      expect(notified, 1);

      final restarted = SoundController(await AppSettings.load());
      expect(restarted.enabled, isFalse);
    });

    test('the effects context never takes audio focus from other apps', () {
      expect(
        SoundController.effectsAudioContext.android.audioFocus.name,
        'none',
      );
    });
  });

  group('ThemeController', () {
    test('reads and saves the theme through AppSettings', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
      final controller = ThemeController(settings: await AppSettings.load());
      expect(controller.themeMode, ThemeMode.dark);

      await controller.setThemeMode(ThemeMode.light);
      final reloaded = ThemeController(settings: await AppSettings.load());
      expect(reloaded.themeMode, ThemeMode.light);
    });
  });
}
