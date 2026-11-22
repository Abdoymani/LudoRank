import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'package:ludo_rank/core/audio/game_sound.dart';
import 'package:ludo_rank/core/settings/app_settings.dart';

/// Anything that can play a [GameSound]. Lets game logic trigger sounds
/// without depending on audio plugins (and lets tests use a fake).
abstract interface class GameSoundPlayer {
  void play(GameSound sound);
}

/// App-wide sound effects with a persisted on/off switch.
///
/// Sounds are played as short effects that mix with whatever the user is
/// already listening to: on Android no audio focus is requested (so Spotify,
/// YouTube, etc. keep playing), and on iOS the `ambient` session category is
/// used (mixes with other audio and respects the silent switch).
class SoundController extends ChangeNotifier implements GameSoundPlayer {
  /// Players kept per sound, so rapid repeats (token steps) can overlap
  /// instead of cutting each other off.
  static const int _playersPerSound = 3;

  static final AudioContext effectsAudioContext = AudioContext(
    android: const AudioContextAndroid(
      audioFocus: AndroidAudioFocus.none,
      usageType: AndroidUsageType.game,
      contentType: AndroidContentType.sonification,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  final AppSettings _settings;
  final Map<GameSound, List<AudioPlayer>> _players = {};
  final Map<GameSound, int> _next = {};
  bool _enabled;
  bool _disposed = false;

  SoundController(this._settings) : _enabled = _settings.soundEnabled;

  bool get enabled => _enabled;

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    if (!value) unawaited(_stopAll());
    await _settings.setSoundEnabled(value);
  }

  Future<void> toggle() => setEnabled(!_enabled);

  @override
  void play(GameSound sound) {
    if (!_enabled || _disposed) return;
    unawaited(_play(sound));
  }

  Future<void> _play(GameSound sound) async {
    try {
      final pool = _players.putIfAbsent(sound, () => <AudioPlayer>[]);
      final index = _next[sound] ?? 0;
      _next[sound] = (index + 1) % _playersPerSound;

      AudioPlayer player;
      if (index < pool.length) {
        player = pool[index];
        await player.stop();
      } else {
        player = AudioPlayer();
        await player.setAudioContext(effectsAudioContext);
        await player.setReleaseMode(ReleaseMode.stop);
        pool.add(player);
      }

      await player.play(
        AssetSource(sound.asset),
        volume: sound.volume,
        mode: PlayerMode.lowLatency,
        ctx: effectsAudioContext,
      );
    } catch (error) {
      // Sound is never allowed to break the game.
      debugPrint('Sound ${sound.name} failed: $error');
    }
  }

  Future<void> _stopAll() async {
    for (final pool in _players.values) {
      for (final player in pool) {
        try {
          await player.stop();
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final pool in _players.values) {
      for (final player in pool) {
        unawaited(player.dispose());
      }
    }
    _players.clear();
    super.dispose();
  }
}
