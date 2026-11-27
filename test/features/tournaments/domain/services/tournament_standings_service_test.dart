import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_rank/core/database/database.dart' as db;
import 'package:ludo_rank/features/match_players/data/repositories/match_player_repository_impl.dart';
import 'package:ludo_rank/features/matches/data/repositories/match_repository_impl.dart';
import 'package:ludo_rank/features/tournament_players/domain/entities/tournament_player.dart';
import 'package:ludo_rank/features/tournaments/domain/services/tournament_standings_service.dart';

final _now = DateTime(2026, 11, 27);

void main() {
  late db.AppDatabase database;

  Future<void> match(String id, String tournament, int number, String status) {
    return database
        .into(database.matches)
        .insert(
          db.MatchesCompanion.insert(
            id: id,
            tournamentId: tournament,
            matchNumber: number,
            status: status,
            playersCount: const Value(2),
          ),
        );
  }

  Future<void> result(String match, String player, int seat, int points) {
    return database
        .into(database.matchPlayers)
        .insert(
          db.MatchPlayersCompanion.insert(
            id: '$match-$player',
            matchId: match,
            playerId: player,
            seat: seat,
            points: Value(points),
            rank: Value(3 - points),
            finished: const Value(true),
          ),
        );
  }

  setUp(() async {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    for (final id in ['t1', 't2']) {
      await database
          .into(database.tournaments)
          .insert(
            db.TournamentsCompanion.insert(
              id: id,
              name: id,
              rounds: 1,
              status: 'running',
              createdAt: _now,
              updatedAt: _now,
            ),
          );
    }
    for (final id in ['p1', 'p2']) {
      await database
          .into(database.players)
          .insert(
            db.PlayersCompanion.insert(
              id: id,
              name: id,
              normalizedName: id,
              createdAt: _now,
              updatedAt: _now,
            ),
          );
    }
    await match('f1', 't1', 1, 'finished');
    await match('f2', 't1', 2, 'finished');
    await match('pending', 't1', 3, 'pending');
    await match('cancelled', 't1', 4, 'cancelled');
    await match('other', 't2', 1, 'finished');
    await result('f1', 'p1', 1, 2);
    await result('f1', 'p2', 2, 1);
    await result('f2', 'p1', 1, 1);
    await result('f2', 'p2', 2, 2);
    await result('pending', 'p1', 1, 2);
    await result('cancelled', 'p2', 1, 2);
    await result('other', 'p1', 1, 2);
  });

  tearDown(() => database.close());

  test('loads every finished match of the tournament in one query', () async {
    final repo = MatchPlayerRepositoryImpl(database.matchPlayerDao);
    final rows = await repo.getFinishedTournamentMatchPlayers('t1');
    expect(rows.map((r) => r.id), ['f1-p1', 'f1-p2', 'f2-p1', 'f2-p2']);
  });

  test('standings count only finished matches of this tournament', () async {
    final snapshot =
        await TournamentStandingsService(
          matchRepository: MatchRepositoryImpl(database.matchDao),
          matchPlayerRepository: MatchPlayerRepositoryImpl(
            database.matchPlayerDao,
          ),
        ).load(
          tournamentId: 't1',
          participants: [
            for (final id in ['p1', 'p2'])
              TournamentPlayer(
                id: 't1-$id',
                tournamentId: 't1',
                playerId: id,
                joinedAt: _now,
              ),
          ],
        );

    expect(snapshot.matches, hasLength(4));
    expect(snapshot.completedMatches, 2);
    final points = {for (final s in snapshot.standings) s.playerId: s.points};
    expect(points, {'p1': 3, 'p2': 3});
    expect(snapshot.standings.every((s) => s.matchesPlayed == 2), isTrue);
  });
}
