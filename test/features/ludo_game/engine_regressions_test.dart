import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_rank/features/ludo_game/domain/constants/ludo_paths.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_player.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_token.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/position.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/ludo_game_state.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/move_option.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/turn_state.dart';
import 'package:ludo_rank/features/ludo_game/domain/services/ludo_game_engine.dart';

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

LudoToken _onMainLoop(LudoPath path, String playerId, int index, int step) {
  return _token(
    playerId,
    index,
    state: LudoTokenState.normal,
    step: step,
    position: path.positionAt(step: step, useHomeLane: false),
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

/// Green has a token parked on Main Loop 51 and another token on step 10.
/// Yellow has a token sitting on green's step 14, so 10 + 4 captures it.
LudoGameEngine _parkedOn51Engine() {
  final green = LudoPaths.green;
  final yellow = LudoPaths.yellow;
  final victimCell = green.positionAt(step: 14, useHomeLane: false);
  final yellowStep = yellow.mainLoopPath.indexOf(victimCell);

  return LudoGameEngine(
    initialState: LudoGameState.initial(
      players: [
        _player('a', 1, LudoPlayerColor.green, [
          _onMainLoop(green, 'a', 0, 51),
          _onMainLoop(green, 'a', 1, 10),
          _token('a', 2),
          _token('a', 3),
        ]),
        _player('b', 2, LudoPlayerColor.yellow, [
          _token(
            'b',
            0,
            state: LudoTokenState.normal,
            step: yellowStep,
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

LudoGameState _freshGame() {
  return LudoGameState.initial(
    players: [
      _player('a', 1, LudoPlayerColor.green, [
        for (var i = 0; i < 4; i++) _token('a', i),
      ]),
      _player('b', 2, LudoPlayerColor.blue, [
        for (var i = 0; i < 4; i++) _token('b', i),
      ]),
    ],
  );
}

/// Rolls [count] times, playing the first legal move after each roll.
List<int> _rolls(LudoGameEngine engine, int count) {
  final values = <int>[];
  for (var i = 0; i < count && !engine.isFinished; i++) {
    engine.rollDice();
    values.add(engine.lastRolledValue!);
    while (engine.state.turnState.phase == TurnPhase.playing) {
      engine.executeMove(engine.getValidMoves().first);
    }
  }
  return values;
}

void main() {
  group('Dice source', () {
    test('the default (secure) dice only roll 1 to 6 and roll every face', () {
      final seen = <int>{};
      for (var game = 0; game < 40; game++) {
        final engine = LudoGameEngine(initialState: _freshGame())..startGame();
        seen.addAll(_rolls(engine, 5));
      }
      expect(seen.every((v) => v >= 1 && v <= 6), isTrue);
      expect(seen, {1, 2, 3, 4, 5, 6});
    });

    test('an injected Random gives repeatable dice for tests', () {
      List<int> play() => _rolls(
        LudoGameEngine(initialState: _freshGame(), random: Random(42))
          ..startGame(),
        20,
      );
      expect(play(), play());
    });
  });

  group('Home lane entry after first capture', () {
    test('token parked on Main Loop 51 continues the loop instead of jumping '
        'into the home lane', () {
      final green = LudoPaths.green;
      final engine = _parkedOn51Engine();

      engine.registerDiceRoll(value: 4, sequence: 1);
      engine.executeMove(
        const MoveToken(tokenId: 'a-token-1', steps: 4, rollSequence: 1),
      );
      expect(engine.state.players[0].hasCaptured, isTrue);

      // Capture bonus roll.
      engine.registerDiceRoll(value: 1, sequence: 2);
      engine.executeMove(
        const MoveToken(tokenId: 'a-token-0', steps: 1, rollSequence: 2),
      );

      final parked = engine.state.players[0].tokens[0];
      expect(parked.positionInPath, 0);
      expect(parked.position, green.mainLoopPath[0]);
      expect(green.homePath, isNot(contains(parked.position)));
    });

    test('the same token enters the home lane after completing the lap', () {
      final green = LudoPaths.green;
      final engine = LudoGameEngine(
        initialState: LudoGameState.initial(
          players: [
            LudoPlayer(
              id: 'a',
              playerId: 'a',
              name: 'a',
              color: LudoPlayerColor.green,
              seat: 1,
              hasCaptured: true,
              tokens: [
                _onMainLoop(green, 'a', 0, 49),
                _token('a', 1),
                _token('a', 2),
                _token('a', 3),
              ],
            ),
            _player('b', 2, LudoPlayerColor.yellow, [
              for (var i = 0; i < 4; i++) _token('b', i),
            ]),
          ],
        ),
      )..startGame();

      engine.registerDiceRoll(value: 3, sequence: 1);
      engine.executeMove(
        const MoveToken(tokenId: 'a-token-0', steps: 3, rollSequence: 1),
      );

      final token = engine.state.players[0].tokens[0];
      expect(token.positionInPath, 52);
      expect(token.position, green.homePath[1]);
    });

    test('isParkedOnMainLoopEnd distinguishes Main 51 from Home 51', () {
      final green = LudoPaths.green;
      expect(
        green.isParkedOnMainLoopEnd(step: 51, position: green.mainLoopPath[51]),
        isTrue,
      );
      expect(
        green.isParkedOnMainLoopEnd(step: 51, position: green.homePath[0]),
        isFalse,
      );
      expect(
        green.isParkedOnMainLoopEnd(step: 50, position: green.mainLoopPath[50]),
        isFalse,
      );
    });
  });

  group('Three sixes rule (intentional, confirmed by the owner)', () {
    // A capture does NOT reset the sixes counter. If the capture bonus roll
    // is the third 6 of the turn, the whole turn is cancelled.
    test('a bonus 6 after a capture that is the third six ends the turn', () {
      final green = LudoPaths.green;
      final yellow = LudoPaths.yellow;
      final victimCell = green.positionAt(step: 14, useHomeLane: false);
      final yellowStep = yellow.mainLoopPath.indexOf(victimCell);

      final engine = LudoGameEngine(
        initialState: LudoGameState.initial(
          players: [
            _player('a', 1, LudoPlayerColor.green, [
              _onMainLoop(green, 'a', 0, 20),
              _onMainLoop(green, 'a', 1, 10),
              _token('a', 2),
              _token('a', 3),
            ]),
            _player('b', 2, LudoPlayerColor.yellow, [
              _token(
                'b',
                0,
                state: LudoTokenState.normal,
                step: yellowStep,
                position: victimCell,
              ),
              _token('b', 1),
              _token('b', 2),
              _token('b', 3),
            ]),
          ],
        ),
      )..startGame();

      engine.registerDiceRoll(value: 6, sequence: 1);
      engine.registerDiceRoll(value: 6, sequence: 2);
      engine.registerDiceRoll(value: 4, sequence: 3);
      expect(engine.state.turnState.sixRollCount, 2);

      engine.executeMove(
        const MoveToken(tokenId: 'a-token-1', steps: 4, rollSequence: 3),
      );
      expect(engine.state.players[0].hasCaptured, isTrue);
      expect(engine.state.turnState.phase, TurnPhase.rolling);
      expect(engine.currentPlayer.playerId, 'a');

      // Bonus roll is the third six of the turn.
      engine.registerDiceRoll(value: 6, sequence: 4);

      expect(engine.currentPlayer.playerId, 'b');
      expect(engine.state.turnState.sixRollCount, 0);
      expect(engine.state.turnState.availableRolls.rolls, isEmpty);
    });
  });
}
