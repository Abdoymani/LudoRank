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
