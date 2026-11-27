import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_rank/core/transactions/transaction_runner.dart';
import 'package:ludo_rank/core/database/database.dart' as db;
import 'package:ludo_rank/features/match_players/data/repositories/match_player_repository_impl.dart';
import 'package:ludo_rank/features/match_players/domain/entities/match_player.dart';
import 'package:ludo_rank/features/matches/data/repositories/match_game_state_repository_impl.dart';
import 'package:ludo_rank/features/matches/data/repositories/match_repository_impl.dart';
import 'package:ludo_rank/features/matches/domain/Use-cases/cancel_match.dart';
import 'package:ludo_rank/features/matches/domain/repositories/match_game_state_repository.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/ludo_game_state.dart';
import 'package:ludo_rank/features/matches/domain/Use-cases/create_match.dart';
import 'package:ludo_rank/features/matches/domain/entities/match.dart';
import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';
import 'package:ludo_rank/features/tournament_players/data/repositories/tournament_player_repository_impl.dart';
import 'package:ludo_rank/features/tournament_players/domain/entities/tournament_player.dart';
import 'package:ludo_rank/features/tournaments/data/repositories/tournament_repository_impl.dart';
import 'package:ludo_rank/features/tournaments/domain/entities/tournament.dart';
import 'package:ludo_rank/features/tournaments/domain/services/tournament_lifecycle_service.dart';

final _now = DateTime(2026, 11, 21);

void main() {
  late db.AppDatabase database;
  late TournamentRepositoryImpl tournaments;
  late MatchRepositoryImpl matches;
  late TournamentLifecycleService lifecycle;
  late CreateMatch createMatch;
  late CancelMatch cancelMatch;

  var matchCounter = 0;

  Future<Match> create({String tournamentId = 't1'}) async {
    matchCounter++;
    final match = Match(
      id: 'm$matchCounter',
      tournamentId: tournamentId,
      playersCount: 2,
      status: MatchStatus.pending,
      createdAt: _now,
      updatedAt: _now,
    );
    await createMatch(
      match: match,
      players: [
        for (var seat = 1; seat <= 2; seat++)
          MatchPlayer(
            id: 'm$matchCounter-p$seat',
            matchId: match.id,
            playerId: 'p$seat',
            seat: seat,
            points: 0,
            finished: false,
          ),
      ],
    );
    return (await matches.getById(match.id))!;
  }

  Future<void> setStatus(Match match, MatchStatus status) {
    return matches.update(match.copyWith(status: status));
  }

  Future<TournamentStatus> tournamentStatus() async {
    return (await tournaments.getTournamentById('t1'))!.status;
  }

  setUp(() async {
    matchCounter = 0;
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    tournaments = TournamentRepositoryImpl(database.tournamentDao);
    matches = MatchRepositoryImpl(database.matchDao);
    lifecycle = TournamentLifecycleService(
      tournamentRepository: tournaments,
      matchRepository: matches,
    );
    createMatch = CreateMatch(
      matchRepository: matches,
      matchPlayerRepository: MatchPlayerRepositoryImpl(database.matchPlayerDao),
      tournamentLifecycle: lifecycle,
      transactionRunner: DriftTransactionRunner(database),
    );
    cancelMatch = CancelMatch(
      matchRepository: matches,
      gameStateRepository: MatchGameStateRepositoryImpl(database.matchDao),
      transactionRunner: DriftTransactionRunner(database),
    );

    await tournaments.addTournament(
      Tournament(
        id: 't1',
        name: 'T1',
        status: TournamentStatus.draft,
        rounds: 3,
        createdAt: _now,
        updatedAt: _now,
      ),
    );
    for (final id in ['p1', 'p2']) {
      await database
          .into(database.players)
          .insert(
            db.PlayersCompanion.insert(
              id: id,
              name: id,
              createdAt: _now,
              updatedAt: _now,
            ),
          );
    }
  });

  tearDown(() => database.close());

  group('status transitions', () {
    test('finished and cancelled are final', () {
      for (final to in TournamentStatus.values) {
        expect(
          TournamentStatusTransitions.canTransition(
            TournamentStatus.finished,
            to,
          ),
          isFalse,
        );
        expect(
          TournamentStatusTransitions.canTransition(
            TournamentStatus.cancelled,
            to,
          ),
          isFalse,
        );
      }
    });

    test('running cannot go back to draft', () {
      expect(
        TournamentStatusTransitions.canTransition(
          TournamentStatus.running,
          TournamentStatus.draft,
        ),
        isFalse,
      );
    });
  });

  group('lifecycle', () {
    test('creating the first match moves draft -> running', () async {
      expect(await tournamentStatus(), TournamentStatus.draft);
      await create();
      expect(await tournamentStatus(), TournamentStatus.running);
    });

    test('a failed match creation saves nothing', () async {
      final match = Match(
        id: 'broken',
        tournamentId: 't1',
        playersCount: 2,
        status: MatchStatus.pending,
        createdAt: _now,
        updatedAt: _now,
      );

      // 'ghost' is not a real player, so inserting the match players
      // fails on the foreign key after the match row was written.
      await expectLater(
        createMatch(
          match: match,
          players: [
            for (final (seat, playerId) in [(1, 'p1'), (2, 'ghost')])
              MatchPlayer(
                id: 'broken-$seat',
                matchId: match.id,
                playerId: playerId,
                seat: seat,
                points: 0,
                finished: false,
              ),
          ],
        ),
        throwsA(anything),
      );

      expect(await matches.getById('broken'), isNull);
      expect(await database.select(database.matchPlayers).get(), isEmpty);
      expect(await tournamentStatus(), TournamentStatus.draft);

      // The next real match still gets number 1.
      expect((await create()).matchNumber, 1);
    });

    test('a player who is not in the tournament is refused '
        '(audit probe P4)', () async {
      final tPlayers = TournamentPlayerRepositoryImpl(
        database.tournamentPlayerDao,
      );
      await tPlayers.addPlayer(
        TournamentPlayer(
          id: 't1-p1',
          tournamentId: 't1',
          playerId: 'p1',
          joinedAt: _now,
        ),
      );
      final checked = CreateMatch(
        matchRepository: matches,
        matchPlayerRepository: MatchPlayerRepositoryImpl(
          database.matchPlayerDao,
        ),
        tournamentLifecycle: lifecycle,
        tournamentPlayerRepository: tPlayers,
        transactionRunner: DriftTransactionRunner(database),
      );
      final match = Match(
        id: 'outsider',
        tournamentId: 't1',
        playersCount: 2,
        status: MatchStatus.pending,
        createdAt: _now,
        updatedAt: _now,
      );
      List<MatchPlayer> seats() => [
        for (var seat = 1; seat <= 2; seat++)
          MatchPlayer(
            id: 'outsider-$seat',
            matchId: match.id,
            playerId: 'p$seat',
            seat: seat,
            points: 0,
            finished: false,
          ),
      ];

      // p2 never joined t1.
      await expectLater(
        checked(match: match, players: seats()),
        throwsArgumentError,
      );
      expect(await matches.getById('outsider'), isNull);
      expect(await tournamentStatus(), TournamentStatus.draft);

      await tPlayers.addPlayer(
        TournamentPlayer(
          id: 't1-p2',
          tournamentId: 't1',
          playerId: 'p2',
          joinedAt: _now,
        ),
      );
      await checked(match: match, players: seats());
      expect(await matches.getById('outsider'), isNotNull);
    });

    test('matches get numbers 1, 2, 3', () async {
      final a = await create();
      final b = await create();
      final c = await create();
      expect([a.matchNumber, b.matchNumber, c.matchNumber], [1, 2, 3]);
    });

    test('match number survives a status update', () async {
      await create();
      final second = await create();
      await setStatus(second, MatchStatus.playing);
      expect((await matches.getById(second.id))!.matchNumber, 2);
    });

    test('cannot finish while a match is pending or playing', () async {
      final match = await create();
      expect(
        await lifecycle.finishBlocker('t1'),
        TournamentFinishBlocker.unfinishedMatches,
      );

      await setStatus(match, MatchStatus.playing);
      await expectLater(lifecycle.finish('t1'), throwsStateError);
      expect(await tournamentStatus(), TournamentStatus.running);
    });

    test('cannot finish with only cancelled matches', () async {
      final match = await create();
      await cancelMatch(match.id);
      expect(
        await lifecycle.finishBlocker('t1'),
        TournamentFinishBlocker.noFinishedMatches,
      );
    });

    test('finish: running -> finished, then no new matches', () async {
      final first = await create();
      await setStatus(first, MatchStatus.finished);
      final second = await create();
      await cancelMatch(second.id);

      await lifecycle.finish('t1');
      expect(await tournamentStatus(), TournamentStatus.finished);

      await expectLater(create(), throwsStateError);
      expect(await matches.getTournamentMatches('t1'), hasLength(2));
    });

    // Decision (docs/08_Decisions.md): players may join a RUNNING tournament.
    test(
      'players can still be added while the tournament is running',
      () async {
        await create();
        expect(await tournamentStatus(), TournamentStatus.running);
        expect(
          TournamentStatusTransitions.isOpen(TournamentStatus.running),
          isTrue,
        );

        final tournamentPlayers = TournamentPlayerRepositoryImpl(
          database.tournamentPlayerDao,
        );
        await tournamentPlayers.addPlayer(
          TournamentPlayer(
            id: 'tp-late',
            tournamentId: 't1',
            playerId: 'p2',
            joinedAt: _now,
          ),
        );

        final joined = await tournamentPlayers.getTournamentPlayers('t1');
        expect(joined.map((p) => p.playerId), contains('p2'));
      },
    );

    test('finished and cancelled tournaments are closed to new players', () {
      expect(
        TournamentStatusTransitions.isOpen(TournamentStatus.finished),
        isFalse,
      );
      expect(
        TournamentStatusTransitions.isOpen(TournamentStatus.cancelled),
        isFalse,
      );
    });

    test('a draft tournament cannot be finished', () async {
      expect(
        await lifecycle.finishBlocker('t1'),
        TournamentFinishBlocker.notRunning,
      );
    });
  });

  group('cancel match', () {
    test(
      'cancels pending and playing matches and clears the snapshot',
      () async {
        final pending = await create();
        final playing = await create();
        await setStatus(playing, MatchStatus.playing);
        await database.matchDao.saveGameStateJson(
          matchId: playing.id,
          gameStateJson: '{}',
        );

        await cancelMatch(pending.id);
        await cancelMatch(playing.id);

        expect(
          (await matches.getById(pending.id))!.status,
          MatchStatus.cancelled,
        );
        expect(
          (await matches.getById(playing.id))!.status,
          MatchStatus.cancelled,
        );
        expect(await database.matchDao.getGameStateJson(playing.id), isNull);
      },
    );

    test('refuses to cancel finished or already cancelled matches', () async {
      final finished = await create();
      await setStatus(finished, MatchStatus.finished);
      await expectLater(cancelMatch(finished.id), throwsStateError);

      final cancelled = await create();
      await cancelMatch(cancelled.id);
      await expectLater(cancelMatch(cancelled.id), throwsStateError);
    });

    test('cancel is all-or-nothing: a failed snapshot clear keeps the match '
        'playing', () async {
      final playing = await create();
      await setStatus(playing, MatchStatus.playing);

      final failing = CancelMatch(
        matchRepository: matches,
        gameStateRepository: _FailingClearRepository(),
        transactionRunner: DriftTransactionRunner(database),
      );

      await expectLater(failing(playing.id), throwsStateError);
      expect((await matches.getById(playing.id))!.status, MatchStatus.playing);
    });
  });
}

class _FailingClearRepository implements MatchGameStateRepository {
  @override
  Future<void> clearGameState(String matchId) async =>
      throw StateError('clear failed');

  @override
  Future<LudoGameState?> loadGameState(String matchId) async => null;

  @override
  Future<void> saveGameState({
    required String matchId,
    required LudoGameState state,
  }) async {}
}
