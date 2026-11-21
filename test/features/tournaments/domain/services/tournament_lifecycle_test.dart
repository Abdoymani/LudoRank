import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_rank/core/database/database.dart' as db;
import 'package:ludo_rank/features/match_players/data/repositories/match_player_repository_impl.dart';
import 'package:ludo_rank/features/match_players/domain/entities/match_player.dart';
import 'package:ludo_rank/features/matches/data/repositories/match_game_state_repository_impl.dart';
import 'package:ludo_rank/features/matches/data/repositories/match_repository_impl.dart';
import 'package:ludo_rank/features/matches/domain/Use-cases/cancel_match.dart';
import 'package:ludo_rank/features/matches/domain/Use-cases/create_match.dart';
import 'package:ludo_rank/features/matches/domain/entities/match.dart';
import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';
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
    );
    cancelMatch = CancelMatch(
      matchRepository: matches,
      gameStateRepository: MatchGameStateRepositoryImpl(database.matchDao),
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
  });
}
