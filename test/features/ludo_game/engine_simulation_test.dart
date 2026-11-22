import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_rank/features/ludo_game/domain/constants/ludo_paths.dart';
import 'package:ludo_rank/features/ludo_game/domain/constants/safe_cells.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_player.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_token.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/position.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/ludo_game_state.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/ludo_game_state_json_codec.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/move_option.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/turn_state.dart';
import 'package:ludo_rank/features/ludo_game/domain/services/ludo_game_engine.dart';
import 'package:ludo_rank/features/ludo_game/domain/services/ludo_move_tracer.dart';
import 'package:ludo_rank/features/match_players/domain/entities/match_player.dart';
import 'package:ludo_rank/features/matches/domain/entities/match.dart';
import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';
import 'package:ludo_rank/features/matches/domain/services/match_game_state_validator.dart';

/// محاكاة عشوائية لمباريات كاملة بتتأكد إن قواعد اللعبة ما بتتكسرش
/// في أي لحظة. لو اختبار هنا وقع، اطبع الـ seed وأعد المباراة دي بالظبط.
void main() {
  const gamesCount = 600;

  test('random full games keep every rule invariant', () {
    for (var seed = 0; seed < gamesCount; seed++) {
      _playOneGame(seed);
    }
  });

  test('all four colors share one loop and have separate home lanes', () {
    const colors = LudoPlayerColor.values;
    final greenLoop = LudoPaths.green.mainLoopPath;
    final homeCells = <Position>{};

    for (final color in colors) {
      final path = LudoPaths.forColor(color);

      expect(path.mainLoopPath.toSet().length, LudoPath.mainLoopLength);
      expect(SafeCells.contains(path.startingPosition), isTrue);

      final offset = greenLoop.indexOf(path.startingPosition);
      for (var i = 0; i < LudoPath.mainLoopLength; i++) {
        expect(
          path.mainLoopPath[i],
          greenLoop[(i + offset) % LudoPath.mainLoopLength],
        );
      }

      for (final cell in path.homePath.take(5)) {
        expect(greenLoop.contains(cell), isFalse);
        expect(homeCells.add(cell), isTrue);
      }
    }

    for (final safe in SafeCells.all) {
      expect(greenLoop.contains(safe), isTrue);
    }
  });
}

void _playOneGame(int seed) {
  final playersCount = 2 + seed % 3;
  final colors = playersCount == 2
      ? const [LudoPlayerColor.green, LudoPlayerColor.blue]
      : const [
          LudoPlayerColor.green,
          LudoPlayerColor.yellow,
          LudoPlayerColor.blue,
          LudoPlayerColor.red,
        ].take(playersCount).toList();

  final players = [
    for (var i = 0; i < playersCount; i++) _player('p$i', i + 1, colors[i]),
  ];

  final now = DateTime(2026, 1, 1);
  final match = Match(
    id: 'm',
    tournamentId: 't',
    playersCount: playersCount,
    status: MatchStatus.playing,
    createdAt: now,
    updatedAt: now,
  );
  final matchPlayers = [
    for (final p in players)
      MatchPlayer(
        id: 'mp-${p.playerId}',
        matchId: 'm',
        playerId: p.playerId,
        seat: p.seat,
        points: 0,
        finished: false,
      ),
  ];

  final choice = Random(seed);
  final engine = LudoGameEngine(
    initialState: LudoGameState.initial(players: players),
    random: Random(seed * 7 + 1),
  )..startGame();

  var actions = 0;

  while (!engine.isFinished) {
    actions++;
    expect(actions, lessThan(20000), reason: 'seed $seed never ends');

    final phase = engine.state.turnState.phase;

    if (phase == TurnPhase.rolling) {
      engine.rollDice();
    } else {
      expect(phase, TurnPhase.playing, reason: 'seed $seed');

      final moves = engine.getValidMoves();
      expect(moves, isNotEmpty, reason: 'seed $seed playing without moves');

      final move = moves[choice.nextInt(moves.length)];
      _checkTracerMatchesPreview(engine, move, seed);

      final preview = engine.getMoveDestination(move);
      final moverIndex = engine.state.currentPlayerIndex;
      engine.executeMove(move);

      final moved = engine.state.players[moverIndex].tokens.firstWhere(
        (t) => t.id == _tokenId(move),
      );
      if (!moved.isInitial) {
        expect(moved.position, preview, reason: 'seed $seed preview');
      }
    }

    _checkInvariants(engine.state, seed);

    final restored = LudoGameStateJsonCodec.decode(
      LudoGameStateJsonCodec.encode(engine.state),
    );
    expect(restored, engine.state, reason: 'seed $seed codec round-trip');

    if (!engine.isFinished) {
      // نفس اللي بيحصل قبل كل حفظ في التطبيق.
      const MatchGameStateValidator().validate(
        match: match,
        matchPlayers: matchPlayers,
        state: engine.state,
      );
    }
  }

  final ranks = engine.getResult().players.map((p) => p.rank).toList()..sort();
  expect(ranks, [for (var i = 1; i <= playersCount; i++) i]);
}

void _checkTracerMatchesPreview(
  LudoGameEngine engine,
  MoveOption move,
  int seed,
) {
  if (move is! MoveToken) return;

  final player = engine.currentPlayer;
  final token = player.tokens.firstWhere((t) => t.id == move.tokenId);
  final trace = LudoMoveTracer.trace(
    path: LudoPaths.forColor(player.color),
    hasCaptured: player.hasCaptured,
    token: token,
    steps: move.steps,
  );

  expect(trace, isNotNull, reason: 'seed $seed');
  expect(trace!.length, move.steps, reason: 'seed $seed');
  expect(
    trace.last.position,
    engine.getMoveDestination(move),
    reason: 'seed $seed animation path ends where the engine lands',
  );
}

void _checkInvariants(LudoGameState state, int seed) {
  final owners = <Position, Set<String>>{};

  for (final player in state.players) {
    final path = LudoPaths.forColor(player.color);
    final finished = player.tokens.where((t) => t.isFinished).length;

    expect(finished, lessThanOrEqualTo(1), reason: 'seed $seed');

    if (finished == 1) {
      // Fast Mode: أول قطعة توصل تنهي اللاعب، والباقي يرجع البيت.
      expect(
        player.tokens.where((t) => !t.isFinished).every((t) => t.isInitial),
        isTrue,
        reason: 'seed $seed finished player still on board',
      );
      expect(state.finishedPlayerIds, contains(player.playerId));
    }

    for (final token in player.tokens) {
      if (token.isInitial || token.isFinished) continue;

      final inHomeLane = path.homePath.contains(token.position);
      if (inHomeLane) {
        expect(player.hasCaptured, isTrue, reason: 'seed $seed home lane');
      }

      final shouldBeSafe = inHomeLane || SafeCells.contains(token.position);
      expect(
        token.state,
        shouldBeSafe ? LudoTokenState.safe : LudoTokenState.normal,
        reason: 'seed $seed token state ${token.id}',
      );

      owners.putIfAbsent(token.position, () => {}).add(player.playerId);
    }
  }

  owners.forEach((position, ids) {
    if (!SafeCells.contains(position)) {
      expect(ids.length, 1, reason: 'seed $seed two colors share $position');
    }
  });
}

String _tokenId(MoveOption move) => switch (move) {
  MoveToken(:final tokenId) => tokenId,
  ExitToken(:final tokenId) => tokenId,
};

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
