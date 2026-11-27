import 'package:drift/drift.dart';

import 'package:ludo_rank/core/database/database.dart';
import 'package:ludo_rank/core/database/tables/tournaments_table.dart';

part 'tournament_dao.g.dart';

@DriftAccessor(tables: [Tournaments])
class TournamentDao extends DatabaseAccessor<AppDatabase>
    with _$TournamentDaoMixin {
  TournamentDao(super.db);

  /// جميع البطولات، الأحدث أولًا.
  Future<List<Tournament>> getAllTournaments() {
    return (select(tournaments)..orderBy([
          (tbl) => OrderingTerm.desc(tbl.createdAt),
          (tbl) => OrderingTerm.desc(tbl.rowId),
        ]))
        .get();
  }

  /// Players and matches per tournament, keyed by tournament id, in one
  /// query (the list shows both on every card).
  Future<Map<String, ({int players, int matches})>>
  getTournamentCounts() async {
    final rows = await customSelect(
      'SELECT t.id AS id, '
      '(SELECT COUNT(*) FROM tournament_players tp '
      'WHERE tp.tournament_id = t.id) AS players, '
      '(SELECT COUNT(*) FROM matches m '
      'WHERE m.tournament_id = t.id) AS matches '
      'FROM tournaments t',
      readsFrom: {tournaments},
    ).get();

    return {
      for (final row in rows)
        row.read<String>('id'): (
          players: row.read<int>('players'),
          matches: row.read<int>('matches'),
        ),
    };
  }

  /// بطولة واحدة
  Future<Tournament?> getTournamentById(String id) {
    return (select(
      tournaments,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  /// إضافة بطولة
  Future<void> insertTournament(TournamentsCompanion tournament) {
    return into(tournaments).insert(tournament);
  }

  /// تعديل بطولة
  Future<bool> updateTournament(TournamentsCompanion tournament) {
    return update(tournaments).replace(tournament);
  }

  /// حذف بطولة مع كل ما يتبعها (مبارياتها ولاعبيها).
  Future<int> deleteTournament(String id) {
    return transaction(() async {
      await customStatement(
        'DELETE FROM match_players WHERE match_id IN '
        '(SELECT id FROM matches WHERE tournament_id = ?)',
        [id],
      );
      await customStatement('DELETE FROM matches WHERE tournament_id = ?', [
        id,
      ]);
      await customStatement(
        'DELETE FROM tournament_players WHERE tournament_id = ?',
        [id],
      );
      return (delete(tournaments)..where((tbl) => tbl.id.equals(id))).go();
    });
  }
}
