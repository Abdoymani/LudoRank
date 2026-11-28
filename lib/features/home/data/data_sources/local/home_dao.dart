import 'package:drift/drift.dart';

import 'package:ludo_rank/core/database/database.dart';
import 'package:ludo_rank/core/database/tables/matches_table.dart';
import 'package:ludo_rank/core/database/tables/players_table.dart';
import 'package:ludo_rank/core/database/tables/tournaments_table.dart';

part 'home_dao.g.dart';

@DriftAccessor(tables: [Players, Tournaments, Matches])
class HomeDao extends DatabaseAccessor<AppDatabase> with _$HomeDaoMixin {
  HomeDao(super.db);

  Future<int> getPlayersCount() async {
    final query = selectOnly(players)..addColumns([players.id.count()]);

    final row = await query.getSingle();

    return row.read(players.id.count()) ?? 0;
  }

  Future<int> getTournamentsCount() async {
    final query = selectOnly(tournaments)..addColumns([tournaments.id.count()]);

    final row = await query.getSingle();

    return row.read(tournaments.id.count()) ?? 0;
  }

  Future<int> getMatchesCount() async {
    final query = selectOnly(matches)..addColumns([matches.id.count()]);

    final row = await query.getSingle();

    return row.read(matches.id.count()) ?? 0;
  }

  Future<int> getFinishedTournamentsCount() async {
    final query = selectOnly(tournaments)
      ..addColumns([tournaments.id.count()])
      ..where(tournaments.status.equals('finished'));

    final row = await query.getSingle();

    return row.read(tournaments.id.count()) ?? 0;
  }

  /// The tournament being played (the newest running one), else the
  /// newest tournament. A new empty draft never hides the running one.
  Future<Tournament?> getLastTournament() {
    return (select(tournaments)
          ..orderBy([
            (tbl) => OrderingTerm.desc(tbl.status.equals('running')),
            (tbl) => OrderingTerm.desc(tbl.createdAt),
            (tbl) => OrderingTerm.desc(tbl.rowId),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<({int players, int matches})> getTournamentCounts(String id) async {
    final row = await customSelect(
      'SELECT '
      '(SELECT COUNT(*) FROM tournament_players WHERE tournament_id = ?1) '
      'AS players, '
      '(SELECT COUNT(*) FROM matches WHERE tournament_id = ?1) AS matches',
      variables: [Variable.withString(id)],
    ).getSingle();

    return (
      players: row.read<int>('players'),
      matches: row.read<int>('matches'),
    );
  }

  /// Matches with their tournament, newest first. [status] limits them to
  /// one stored status value.
  Future<List<(MatchData, Tournament)>> getMatchesWithTournament({
    String? status,
    int? limit,
  }) {
    final query =
        select(matches).join([
          innerJoin(
            tournaments,
            tournaments.id.equalsExp(matches.tournamentId),
          ),
        ])..orderBy([
          OrderingTerm.desc(matches.updatedAt),
          OrderingTerm.desc(matches.createdAt),
          OrderingTerm.desc(matches.matchNumber),
        ]);

    if (status != null) query.where(matches.status.equals(status));
    if (limit != null) query.limit(limit);

    return query
        .map((row) => (row.readTable(matches), row.readTable(tournaments)))
        .get();
  }

  Future<Map<String, String>> getMatchPlayerNames(String matchId) async {
    final rows = await customSelect(
      'SELECT p.id AS id, p.name AS name FROM match_players mp '
      'INNER JOIN players p ON p.id = mp.player_id '
      'WHERE mp.match_id = ? ORDER BY mp.seat',
      variables: [Variable.withString(matchId)],
    ).get();

    return {
      for (final row in rows) row.read<String>('id'): row.read<String>('name'),
    };
  }
}
