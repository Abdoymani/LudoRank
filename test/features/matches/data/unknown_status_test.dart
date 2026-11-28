import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_rank/core/database/database.dart' as db;
import 'package:ludo_rank/features/matches/data/repositories/match_repository_impl.dart';
import 'package:ludo_rank/features/matches/domain/Use-cases/cancel_match.dart';
import 'package:ludo_rank/features/matches/domain/entities/match.dart';
import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';
import 'package:ludo_rank/features/matches/data/repositories/match_game_state_repository_impl.dart';
import 'package:ludo_rank/features/tournaments/data/repositories/tournament_repository_impl.dart';
import 'package:ludo_rank/features/tournaments/domain/entities/tournament.dart';
import 'package:ludo_rank/features/tournaments/domain/services/tournament_lifecycle_service.dart';

final _now = DateTime(2026, 11, 27);

void main() {
  late db.AppDatabase database;
  late MatchRepositoryImpl matches;
  late TournamentRepositoryImpl tournaments;

  setUp(() async {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    matches = MatchRepositoryImpl(database.matchDao);
    tournaments = TournamentRepositoryImpl(database.tournamentDao);
    await tournaments.addTournament(
      Tournament(
        id: 't1',
        name: 't1',
        status: TournamentStatus.running,
        rounds: 1,
        createdAt: _now,
        updatedAt: _now,
      ),
    );
    await matches.create(
      Match(
        id: 'm1',
        tournamentId: 't1',
        playersCount: 2,
        status: MatchStatus.pending,
        createdAt: _now,
        updatedAt: _now,
      ),
    );
    await database.customStatement("UPDATE matches SET status = 'paused'");
    await database.customStatement(
      "UPDATE tournaments SET status = 'archived'",
    );
  });

  tearDown(() => database.close());

  Future<String> storedMatchStatus() async =>
      (await database.customSelect('SELECT status FROM matches').getSingle())
          .read<String>('status');

  Future<String> storedTournamentStatus() async =>
      (await database
              .customSelect('SELECT status FROM tournaments')
              .getSingle())
          .read<String>('status');

  test('an unknown match status is read as unknown instead of crashing the '
      'list (audit probe P8)', () async {
    final list = await matches.getTournamentMatches('t1');
    expect(list.single.status, MatchStatus.unknown);
    expect((await matches.getById('m1'))!.status, MatchStatus.unknown);
  });

  test('unknown is never written back', () async {
    final match = (await matches.getById('m1'))!;
    await expectLater(matches.update(match), throwsStateError);
    await expectLater(
      matches.update(match.copyWith(id: 'm2')),
      throwsStateError,
    );
    expect(await storedMatchStatus(), 'paused');

    final tournament = (await tournaments.getTournamentById('t1'))!;
    expect(tournament.status, TournamentStatus.unknown);
    await expectLater(
      tournaments.updateTournament(tournament),
      throwsStateError,
    );
    expect(await storedTournamentStatus(), 'archived');
  });

  test('an unknown match cannot be cancelled', () async {
    expect(CancelMatch.canCancel(MatchStatus.unknown), isFalse);
    await expectLater(
      CancelMatch(
        matchRepository: matches,
        gameStateRepository: MatchGameStateRepositoryImpl(database.matchDao),
      )('m1'),
      throwsStateError,
    );
    expect(await storedMatchStatus(), 'paused');
  });

  test('an unknown tournament is closed and cannot change status', () async {
    final lifecycle = TournamentLifecycleService(
      tournamentRepository: tournaments,
      matchRepository: matches,
    );
    expect(
      TournamentStatusTransitions.isOpen(TournamentStatus.unknown),
      isFalse,
    );
    await expectLater(lifecycle.ensureCanCreateMatch('t1'), throwsStateError);
    await expectLater(lifecycle.markRunning('t1'), throwsStateError);
    await expectLater(lifecycle.finish('t1'), throwsStateError);
    expect(await storedTournamentStatus(), 'archived');
  });
}
