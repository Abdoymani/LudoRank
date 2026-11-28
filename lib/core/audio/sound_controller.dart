import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:ludo_rank/core/audio/game_sound.dart';
import 'package:ludo_rank/core/settings/app_settings.dart';

/// Anything that can play a [GameSound]. Lets game logic trigger sounds
/// without depending on audio plugins (and lets tests use a fake).
abstract interface class GameSoundPlayer {
  void play(GameSound sound);

  /// A short vibration, under the same on/off switch as the sounds.
  void haptic(GameHaptic kind);
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
  final Map<GameSound, List<Future<AudioPlayer>>> _players = {};
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

  @override
  void haptic(GameHaptic kind) {
    if (!_enabled || _disposed) return;
    unawaited(_vibrate(kind));
  }

  Future<void> _vibrate(GameHaptic kind) async {
    try {
      switch (kind) {
        case GameHaptic.light:
          await HapticFeedback.lightImpact();
        case GameHaptic.medium:
          await HapticFeedback.mediumImpact();
      }
    } catch (error) {
      debugPrint('Haptic ${kind.name} failed: $error');
    }
  }

  /// How many players [preload] loads for [sound]. Steps play in quick
  /// succession and rotate through the whole pool during the first move,
  /// so all of their players are loaded up front.
  @visibleForTesting
  static int preloadedPlayersFor(GameSound sound) {
    return sound == GameSound.step || sound == GameSound.stepAlt
        ? _playersPerSound
        : 1;
  }

  /// Loads every sound once (asset copy + native decode), so the first roll
  /// and the first token steps play on time instead of after a load.
  Future<void> preload() async {
    for (final sound in GameSound.values) {
      if (_disposed) return;
      try {
        await _playerAt(sound, preloadedPlayersFor(sound) - 1);
      } catch (error) {
        debugPrint('Sound ${sound.name} preload failed: $error');
      }
    }
  }

  /// Returns pool slot [index] for [sound], creating it with its source
  /// already loaded. Players are reused: replaying is stop + resume, never a
  /// new load, which is what made step sounds lag behind the token.
  Future<AudioPlayer> _playerAt(GameSound sound, int index) {
    final pool = _players.putIfAbsent(sound, () => <Future<AudioPlayer>>[]);
    while (pool.length <= index) {
      final slot = pool.length;
      final created = _createPlayer(sound);
      pool.add(created);
      // A failed load is retried on the next play instead of staying broken.
      unawaited(
        created.then<void>(
          (_) {},
          onError: (Object _) {
            if (slot < pool.length && identical(pool[slot], created)) {
              pool.removeRange(slot, pool.length);
            }
          },
        ),
      );
    }
    return pool[index];
  }

  Future<AudioPlayer> _createPlayer(GameSound sound) async {
    final player = AudioPlayer();
    await player.setAudioContext(effectsAudioContext);
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setPlayerMode(PlayerMode.lowLatency);
    await player.setVolume(sound.volume);
    await player.setSource(AssetSource(sound.asset));
    return player;
  }

  Future<void> _play(GameSound sound) async {
    try {
      final index = _next[sound] ?? 0;
      _next[sound] = (index + 1) % _playersPerSound;

      final player = await _playerAt(sound, index);
      if (!_enabled || _disposed) return;
      // Low-latency players never report completion, so always stop first:
      // it rewinds the loaded sound and lets resume() start a fresh stream.
      // Both calls go out at once (platform calls keep their order), so
      // the sound starts without waiting for a round trip in between.
      unawaited(player.stop());
      await player.resume();
    } catch (error) {
      // Sound is never allowed to break the game.
      debugPrint('Sound ${sound.name} failed: $error');
    }
  }

  Future<void> _stopAll() async {
    for (final pool in _players.values) {
      for (final pending in pool) {
        try {
          await (await pending).stop();
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final pool in _players.values) {
      for (final pending in pool) {
        unawaited(pending.then((player) => player.dispose(), onError: (_) {}));
      }
    }
    _players.clear();
    super.dispose();
  }
}
