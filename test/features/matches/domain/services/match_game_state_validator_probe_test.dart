// The ten impossible snapshots from the 25 November engine audit (probe P4).
// Derived fields are repaired on load (LudoGameStateNormalizer); real
// contradictions are rejected by MatchGameStateValidator.
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_rank/features/ludo_game/domain/constants/ludo_paths.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_player.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_token.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/position.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/available_rolls.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/dice_roll.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/ludo_game_state.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/ludo_game_state_json_codec.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/turn_state.dart';
import 'package:ludo_rank/features/ludo_game/domain/services/ludo_game_engine.dart';
import 'package:ludo_rank/features/ludo_game/domain/services/ludo_game_state_normalizer.dart';
import 'package:ludo_rank/features/match_players/domain/entities/match_player.dart';
import 'package:ludo_rank/features/matches/domain/entities/match.dart';
import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';
import 'package:ludo_rank/features/matches/domain/services/match_game_state_validator.dart';

LudoPlayer _player(String id, int seat, LudoPlayerColor color) => LudoPlayer(
  id: id,
  playerId: id,
  name: id,
  color: color,
  seat: seat,
  tokens: List.generate(
    4,
    (i) => LudoToken(
      id: '$id-token-$i',
      playerId: id,
      tokenIndex: i,
      position: const Position(row: 0, column: 0),
      positionInPath: -1,
      state: LudoTokenState.initial,
    ),
  ),
);

LudoGameState _midGame() {
  return LudoGameEngine(
    initialState: LudoGameState.initial(
      players: [
        _player('a', 1, LudoPlayerColor.green),
        _player('b', 2, LudoPlayerColor.blue),
      ],
    ),
  ).startGame();
}

LudoGameState _withToken(
  LudoGameState s,
  int playerIdx,
  int tokenIdx,
  LudoToken Function(LudoToken t, LudoPath path) f,
) {
  final p = s.players[playerIdx];
  final path = LudoPaths.forColor(p.color);
  final tokens = [...p.tokens];
  tokens[tokenIdx] = f(tokens[tokenIdx], path);
  final players = [...s.players];
  players[playerIdx] = p.copyWith(tokens: tokens);
  return s.copyWith(players: players);
}

LudoToken _onLoop(LudoToken t, LudoPath p, int step, LudoTokenState state) {
  return t.copyWith(
    positionInPath: step,
    position: p.positionAt(step: step, useHomeLane: false),
    state: state,
  );
}

/// What resume does: normalize, then validate. Null when accepted.
String? _verdict(LudoGameState s) {
  final n = s.players.length;
  final now = DateTime(2026);
  try {
    const MatchGameStateValidator().validate(
      match: Match(
        id: 'm',
        tournamentId: 't',
        playersCount: n,
        status: MatchStatus.playing,
        createdAt: now,
        updatedAt: now,
      ),
      matchPlayers: [
        for (final p in s.players)
          MatchPlayer(
            id: 'mp-${p.playerId}',
            matchId: 'm',
            playerId: p.playerId,
            seat: p.seat,
            points: 0,
            finished: false,
          ),
      ],
      state: LudoGameStateNormalizer.normalize(s),
    );
    return null;
  } on StateError catch (e) {
    return e.message;
  }
}

void main() {
  final base = _midGame();

  test('the untouched mid-game state is accepted and normalize keeps it', () {
    expect(_verdict(base), isNull);
    expect(identical(LudoGameStateNormalizer.normalize(base), base), isTrue);
  });

  group('derived fields are repaired on load', () {
    test('normal state on a safe cell becomes safe', () {
      final s = _withToken(
        base,
        0,
        0,
        (t, p) => t.copyWith(state: LudoTokenState.normal),
      );
      expect(_verdict(s), isNull);
      expect(
        LudoGameStateNormalizer.normalize(s).players[0].tokens[0].state,
        LudoTokenState.safe,
      );
    });

    test('safe state on a plain cell becomes normal', () {
      final s = _withToken(
        base,
        0,
        0,
        (t, p) => _onLoop(t, p, 3, LudoTokenState.safe),
      );
      expect(_verdict(s), isNull);
      expect(
        LudoGameStateNormalizer.normalize(s).players[0].tokens[0].state,
        LudoTokenState.normal,
      );
    });

    test('old safeInPair is decoded as safe/normal by its cell', () {
      String legacy(LudoGameState s) => LudoGameStateJsonCodec.encode(
        s,
      ).replaceAll('"state":"safe"', '"state":"safeInPair"');

      final onStart = LudoGameStateJsonCodec.decode(legacy(base));
      expect(onStart.players[0].tokens[0].state, LudoTokenState.safe);
      expect(_verdict(onStart), isNull);

      final plain = _withToken(
        base,
        0,
        0,
        (t, p) => _onLoop(t, p, 3, LudoTokenState.safe),
      );
      final decoded = LudoGameStateJsonCodec.decode(legacy(plain));
      expect(decoded.players[0].tokens[0].state, LudoTokenState.normal);
      expect(_verdict(decoded), isNull);
    });

    test('homeEntryPending on a home-lane token is cleared', () {
      var s = base.copyWith(
        players: [base.players[0].copyWith(hasCaptured: true), base.players[1]],
      );
      s = _withToken(
        s,
        0,
        1,
        (t, p) => t.copyWith(
          positionInPath: 53,
          position: p.positionAt(step: 53, useHomeLane: true),
          state: LudoTokenState.safe,
          homeEntryPending: true,
        ),
      );
      expect(_verdict(s), isNull);
      expect(
        LudoGameStateNormalizer.normalize(
          s,
        ).players[0].tokens[1].homeEntryPending,
        isFalse,
      );
    });

    test('homeEntryPending without any capture is cleared', () {
      final s = _withToken(
        base,
        0,
        0,
        (t, p) => t.copyWith(homeEntryPending: true),
      );
      expect(_verdict(s), isNull);
      expect(
        LudoGameStateNormalizer.normalize(
          s,
        ).players[0].tokens[0].homeEntryPending,
        isFalse,
      );
    });

    test('homeEntryPending on a main-loop token after a capture is kept', () {
      var s = base.copyWith(
        players: [base.players[0].copyWith(hasCaptured: true), base.players[1]],
      );
      s = _withToken(
        s,
        0,
        0,
        (t, p) => _onLoop(
          t,
          p,
          5,
          LudoTokenState.normal,
        ).copyWith(homeEntryPending: true),
      );
      expect(identical(LudoGameStateNormalizer.normalize(s), s), isTrue);
      expect(_verdict(s), isNull);
    });

    test('a token id that does not follow playerId-token-N is rewritten', () {
      final s = _withToken(base, 0, 0, (t, p) => t.copyWith(id: 'zzz'));
      expect(_verdict(s), isNull);
      expect(
        LudoGameStateNormalizer.normalize(s).players[0].tokens[0].id,
        'a-token-0',
      );
    });

    test('rolling with a leftover non-six roll is a real state (capture '
        'bonus) and stays accepted', () {
      final s = base.copyWith(
        turnState: TurnState(
          playerId: 'a',
          rolls: const [DiceRoll(value: 3, sequence: 1)],
          availableRolls: const AvailableRolls(
            rolls: [DiceRoll(value: 3, sequence: 1)],
          ),
          phase: TurnPhase.rolling,
        ),
      );
      expect(_verdict(s), isNull);
    });
  });

  group('contradictions are rejected', () {
    test('two colours on one plain cell', () {
      var s = _withToken(
        base,
        0,
        1,
        (t, p) => _onLoop(t, p, 3, LudoTokenState.normal),
      );
      final target = LudoPaths.green.positionAt(step: 3, useHomeLane: false);
      final blueStep = LudoPaths.blue.mainLoopPath.indexOf(target);
      s = _withToken(
        s,
        1,
        1,
        (t, p) => _onLoop(t, p, blueStep, LudoTokenState.normal),
      );
      expect(_verdict(s), contains('أكثر من لون'));
    });

    test('three own tokens on one plain cell', () {
      var s = base;
      for (final i in [1, 2, 3]) {
        s = _withToken(
          s,
          0,
          i,
          (t, p) => _onLoop(t, p, 4, LudoTokenState.normal),
        );
      }
      expect(_verdict(s), contains('أكثر من قطعتين'));

      // A pair is a legal block.
      s = _withToken(
        s,
        0,
        3,
        (t, p) => t.copyWith(
          positionInPath: -1,
          position: const Position(row: 0, column: 0),
          state: LudoTokenState.initial,
        ),
      );
      expect(_verdict(s), isNull);
    });

    test('playing right after a six', () {
      final s = base.copyWith(
        turnState: TurnState(
          playerId: 'a',
          rolls: const [DiceRoll(value: 6, sequence: 1)],
          availableRolls: const AvailableRolls(
            rolls: [DiceRoll(value: 6, sequence: 1)],
          ),
          sixRollCount: 1,
          phase: TurnPhase.playing,
        ),
      );
      expect(_verdict(s), contains('بعد رمية 6'));
    });
  });
}
