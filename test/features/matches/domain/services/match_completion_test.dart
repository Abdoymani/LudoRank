import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_rank/core/database/database.dart' as db;
import 'package:ludo_rank/core/transactions/transaction_runner.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/game_result.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/turn_state.dart';
import 'package:ludo_rank/features/match_players/data/repositories/match_player_repository_impl.dart';
import 'package:ludo_rank/features/match_players/domain/entities/match_player.dart';
import 'package:ludo_rank/features/matches/data/repositories/match_game_state_repository_impl.dart';
import 'package:ludo_rank/features/matches/data/repositories/match_repository_impl.dart';
import 'package:ludo_rank/features/matches/domain/Use-cases/create_match.dart';
import 'package:ludo_rank/features/matches/domain/entities/match.dart';
import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';
import 'package:ludo_rank/features/matches/domain/services/match_game_service.dart';
import 'package:ludo_rank/features/matches/domain/services/match_game_session.dart';
import 'package:ludo_rank/features/matches/domain/services/match_game_state_validator.dart';
import 'package:ludo_rank/features/matches/presentation/providers/match_game_provider.dart';
import 'package:ludo_rank/features/players/data/repositories/player_repository_impl.dart';
import 'package:ludo_rank/features/players/domain/entities/player.dart';
import 'package:ludo_rank/features/tournament_players/data/repositories/tournament_player_repository_impl.dart';
import 'package:ludo_rank/features/tournament_players/domain/entities/tournament_player.dart';
import 'package:ludo_rank/features/tournaments/data/repositories/tournament_repository_impl.dart';
import 'package:ludo_rank/features/tournaments/domain/entities/tournament.dart';

final _now = DateTime(2026, 11, 27);

/// Fails exactly when the match is marked finished, like a crash in the
/// middle of saving the result.
class _CrashOnFinish extends MatchRepositoryImpl {
  _CrashOnFinish(super.dao);

  bool crash = true;

  @override
  Future<void> update(Match match) async {
    if (crash && match.status == MatchStatus.finished) {
      throw StateError('simulated crash');
    }
    return super.update(match);
  }
}

/// Plays random legal moves until the engine reports a finished game.
void playToEnd(MatchGameSession session, {int seed = 1}) {
  final random = Random(seed);
  final engine = session.engine;
  var guard = 0;
  while (!engine.isFinished) {
    if (++guard > 100000) fail('game never finished');
    if (engine.state.turnState.phase == TurnPhase.rolling) {
      engine.rollDice();
    } else {
      final moves = engine.getValidMoves();
      engine.executeMove(moves[random.nextInt(moves.length)]);
    }
  }
}

void main() {
  late db.AppDatabase database;
  late MatchPlayerRepositoryImpl matchPlayers;
  late _CrashOnFinish matches;
  late MatchGameStateRepositoryImpl gameStates;
  late MatchGameService service;

  const names = {'p1': 'Ahmed', 'p2': 'Omar', 'p3': 'Ali'};

  setUp(() async {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    matchPlayers = MatchPlayerRepositoryImpl(database.matchPlayerDao);
    matches = _CrashOnFinish(database.matchDao);
    gameStates = MatchGameStateRepositoryImpl(database.matchDao);
    service = MatchGameService(
      matchRepository: matches,
      matchPlayerRepository: matchPlayers,
      gameStateRepository: gameStates,
      transactionRunner: DriftTransactionRunner(database),
    );

    final players = PlayerRepositoryImpl(database.playerDao);
    for (final entry in names.entries) {
      await players.addPlayer(
        Player(
          id: entry.key,
          name: entry.value,
          createdAt: _now,
          updatedAt: _now,
        ),
      );
    }
    await TournamentRepositoryImpl(database.tournamentDao).addTournament(
      Tournament(
        id: 't1',
        name: 't1',
        status: TournamentStatus.draft,
        rounds: 1,
        createdAt: _now,
        updatedAt: _now,
      ),
    );
    final tPlayers = TournamentPlayerRepositoryImpl(
      database.tournamentPlayerDao,
    );
    for (final id in names.keys) {
      await tPlayers.addPlayer(
        TournamentPlayer(
          id: 't1-$id',
          tournamentId: 't1',
          playerId: id,
          joinedAt: _now,
        ),
      );
    }
    await CreateMatch(
      matchRepository: matches,
      matchPlayerRepository: matchPlayers,
    )(
      match: Match(
        id: 'm1',
        tournamentId: 't1',
        playersCount: 3,
        status: MatchStatus.pending,
        createdAt: _now,
        updatedAt: _now,
      ),
      players: [
        for (final (i, id) in names.keys.indexed)
          MatchPlayer(
            id: 'm1-$id',
            matchId: 'm1',
            playerId: id,
            seat: i + 1,
            points: 0,
            finished: false,
          ),
      ],
    );
  });

  tearDown(() => database.close());

  Future<MatchGameSession> finishedSession() async {
    final session = await service.startMatch(
      matchId: 'm1',
      playerNames: names,
      random: Random(7),
    );
    playToEnd(session);
    return session;
  }

  test('a crash while saving the result leaves no partial change', () async {
    final session = await finishedSession();

    await expectLater(service.completeMatch(session), throwsStateError);

    // No points on a playing match (the old non-atomic bug).
    final rows = await matchPlayers.getMatchPlayers('m1');
    expect(rows.every((row) => row.points == 0 && row.rank == null), isTrue);
    expect((await matches.getById('m1'))!.status, MatchStatus.playing);

    // The final board was saved before the transaction.
    final saved = await gameStates.loadGameState('m1');
    expect(saved, isNotNull);
    expect(saved!.isFinished, isTrue);
  });

  test('resume after that crash restores the finished game and completes '
      'it without replaying the last move', () async {
    final session = await finishedSession();
    final expected = session.result;
    await expectLater(service.completeMatch(session), throwsStateError);

    matches.crash = false;

    final provider = MatchGameProvider(service: service);
    await provider.resumeMatch(matchId: 'm1');

    expect(provider.error, isNull);
    expect(provider.isGameFinished, isTrue);
    expect(provider.isFinished, isTrue);
    expect(provider.matchStatus, MatchStatus.finished);
    expect(provider.completedPlayers, hasLength(3));

    final rows = await matchPlayers.getMatchPlayers('m1');
    for (final row in rows) {
      final result = expected.getPlayerResult(row.playerId)!;
      expect(row.rank, result.rank);
      expect(row.points, 3 - result.rank + 1);
    }
    expect((await matches.getById('m1'))!.status, MatchStatus.finished);
    expect(await database.matchDao.getGameStateJson('m1'), isNull);
    provider.dispose();
  });

  test('successful completion saves points, status and clears the snapshot '
      'together', () async {
    matches.crash = false;
    final session = await finishedSession();

    final updated = await service.completeMatch(session);

    expect(updated, hasLength(3));
    expect((await matches.getById('m1'))!.status, MatchStatus.finished);
    expect(await database.matchDao.getGameStateJson('m1'), isNull);
    final points = (await matchPlayers.getMatchPlayers(
      'm1',
    )).map((p) => p.points).toList()..sort();
    expect(points, [1, 2, 3]);
  });

  test('completeMatchFromResult rolls back points when the status write '
      'fails (audit probe P1)', () async {
    final session = await service.startMatch(matchId: 'm1', playerNames: names);
    await expectLater(
      service.completeMatchFromResult(
        session: session,
        result: const GameResult(
          isFinished: true,
          players: [
            GamePlayerResult(playerId: 'p1', rank: 1, finished: true),
            GamePlayerResult(playerId: 'p2', rank: 2, finished: true),
            GamePlayerResult(playerId: 'p3', rank: 3, finished: false),
          ],
        ),
      ),
      throwsStateError,
    );
    final rows = await matchPlayers.getMatchPlayers('m1');
    expect(rows.map((e) => e.points), [0, 0, 0]);
    expect(await database.matchDao.getGameStateJson('m1'), isNotNull);
  });

  group('validateFinished', () {
    test(
      'accepts a real finished game and validate() still rejects it',
      () async {
        final session = await finishedSession();
        const validator = MatchGameStateValidator();

        validator.validateFinished(
          match: session.match,
          matchPlayers: session.matchPlayers,
          state: session.state,
        );
        expect(
          () => validator.validate(
            match: session.match,
            matchPlayers: session.matchPlayers,
            state: session.state,
          ),
          throwsStateError,
        );
      },
    );

    test('rejects an active game and a finished game with too few '
        'finishers', () async {
      final session = await service.startMatch(
        matchId: 'm1',
        playerNames: names,
      );
      const validator = MatchGameStateValidator();

      expect(
        () => validator.validateFinished(
          match: session.match,
          matchPlayers: session.matchPlayers,
          state: session.state,
        ),
        throwsStateError,
      );
      expect(
        () => validator.validateFinished(
          match: session.match,
          matchPlayers: session.matchPlayers,
          state: session.state.copyWith(
            isFinished: true,
            turnState: session.state.turnState.copyWith(
              phase: TurnPhase.completed,
            ),
          ),
        ),
        throwsStateError,
      );
    });

    test('saveFinalSnapshot refuses an unfinished game', () async {
      final session = await service.startMatch(
        matchId: 'm1',
        playerNames: names,
      );
      expect(
        () => service.saveFinalSnapshot(session: session),
        throwsStateError,
      );
    });
  });
}
