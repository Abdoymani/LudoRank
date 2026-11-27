import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_rank/core/audio/game_sound.dart';
import 'package:ludo_rank/features/ludo_game/domain/constants/ludo_paths.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_player.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_token.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/position.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/ludo_game_state.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/move_option.dart';
import 'package:ludo_rank/features/ludo_game/domain/services/ludo_game_engine.dart';
import 'package:ludo_rank/features/matches/presentation/providers/game_sound_events.dart';

LudoToken _token(
  String playerId,
  int index, {
  LudoTokenState state = LudoTokenState.initial,
  int step = -1,
  Position position = const Position(row: 0, column: 0),
}) {
  return LudoToken(
    id: '$playerId-token-$index',
    playerId: playerId,
    tokenIndex: index,
    position: position,
    positionInPath: step,
    state: state,
  );
}

LudoPlayer _player(
  String id,
  int seat,
  LudoPlayerColor color,
  List<LudoToken> tokens,
) {
  return LudoPlayer(
    id: id,
    playerId: id,
    name: id,
    color: color,
    seat: seat,
    tokens: tokens,
  );
}

LudoGameEngine _freshEngine() {
  return LudoGameEngine(
    initialState: LudoGameState.initial(
      players: [
        _player('a', 1, LudoPlayerColor.green, [
          for (var i = 0; i < 4; i++) _token('a', i),
        ]),
        _player('b', 2, LudoPlayerColor.yellow, [
          for (var i = 0; i < 4; i++) _token('b', i),
        ]),
      ],
    ),
  )..startGame();
}

/// Green token on step 10, yellow token on green's step 14: 10 + 4 captures.
LudoGameEngine _captureEngine() {
  final green = LudoPaths.green;
  final yellow = LudoPaths.yellow;
  final victimCell = green.positionAt(step: 14, useHomeLane: false);

  return LudoGameEngine(
    initialState: LudoGameState.initial(
      players: [
        _player('a', 1, LudoPlayerColor.green, [
          _token(
            'a',
            0,
            state: LudoTokenState.normal,
            step: 10,
            position: green.positionAt(step: 10, useHomeLane: false),
          ),
          _token('a', 1),
          _token('a', 2),
          _token('a', 3),
        ]),
        _player('b', 2, LudoPlayerColor.yellow, [
          _token(
            'b',
            0,
            state: LudoTokenState.normal,
            step: yellow.mainLoopPath.indexOf(victimCell),
            position: victimCell,
          ),
          _token('b', 1),
          _token('b', 2),
          _token('b', 3),
        ]),
      ],
    ),
  )..startGame();
}

void main() {
  group('GameSoundEvents.forRoll', () {
    test('a normal roll plays only the dice sound', () {
      final engine = _freshEngine();
      final before = engine.state;
      engine.registerDiceRoll(value: 3, sequence: 1);

      expect(GameSoundEvents.forRoll(before, engine.state), [GameSound.dice]);
    });

    test('a six plays dice then six', () {
      final engine = _freshEngine();
      final before = engine.state;
      engine.registerDiceRoll(value: 6, sequence: 1);

      expect(GameSoundEvents.forRoll(before, engine.state), [
        GameSound.dice,
        GameSound.six,
      ]);
    });

    test('the third six plays dice then cancelled', () {
      final engine = _freshEngine();
      engine.registerDiceRoll(value: 6, sequence: 1);
      engine.registerDiceRoll(value: 6, sequence: 2);
      final before = engine.state;
      engine.registerDiceRoll(value: 6, sequence: 3);

      expect(GameSoundEvents.forRoll(before, engine.state), [
        GameSound.dice,
        GameSound.cancelled,
      ]);
    });
  });

  group('GameSoundEvents.hapticFor', () {
    test('light for a capture, medium for home and win, none otherwise', () {
      expect(GameSoundEvents.hapticFor(GameSound.capture), GameHaptic.light);
      expect(GameSoundEvents.hapticFor(GameSound.home), GameHaptic.medium);
      expect(GameSoundEvents.hapticFor(GameSound.win), GameHaptic.medium);
      expect(GameSoundEvents.hapticFor(GameSound.enter), isNull);
      expect(GameSoundEvents.hapticFor(null), isNull);
    });
  });

  group('GameSoundEvents.forMove', () {
    test('leaving the base plays the enter sound', () {
      final engine = _freshEngine();
      engine.registerDiceRoll(value: 6, sequence: 1);
      final moves = engine.registerDiceRoll(value: 2, sequence: 2);
      final before = engine.state;
      final move = moves.whereType<ExitToken>().first;
      engine.executeMove(move);

      expect(
        GameSoundEvents.forMove(before, engine.state, move),
        GameSound.enter,
      );
    });

    test('a capture plays the capture sound', () {
      final engine = _captureEngine();
      engine.registerDiceRoll(value: 4, sequence: 1);
      final before = engine.state;
      const move = MoveToken(tokenId: 'a-token-0', steps: 4, rollSequence: 1);
      engine.executeMove(move);

      expect(engine.state.players[1].tokens[0].state, LudoTokenState.initial);
      expect(
        GameSoundEvents.forMove(before, engine.state, move),
        GameSound.capture,
      );
    });

    test('a plain step has no extra sound', () {
      final engine = _captureEngine();
      engine.registerDiceRoll(value: 2, sequence: 1);
      final before = engine.state;
      const move = MoveToken(tokenId: 'a-token-0', steps: 2, rollSequence: 1);
      engine.executeMove(move);

      expect(GameSoundEvents.forMove(before, engine.state, move), isNull);
    });
  });
}
