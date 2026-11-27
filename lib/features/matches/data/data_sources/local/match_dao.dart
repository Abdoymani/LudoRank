import 'package:drift/drift.dart';

import 'package:ludo_rank/core/database/database.dart';
import 'package:ludo_rank/core/database/database.dart' as db;
import 'package:ludo_rank/core/database/tables/matches_table.dart';

part 'match_dao.g.dart';

@DriftAccessor(tables: [Matches])
class MatchDao extends DatabaseAccessor<AppDatabase> with _$MatchDaoMixin {
  MatchDao(super.db);

  Future<MatchData?> getMatchById(String id) {
    return (select(
      matches,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  /// يضيف المباراة. إذا لم يُحدد رقم للمباراة (أو كان 0)،
  /// يتم إعطاؤها الرقم التالى داخل البطولة.
  Future<void> insertMatch(MatchesCompanion match) {
    return transaction(() async {
      var companion = match;

      final number = match.matchNumber;
      if (!number.present || number.value <= 0) {
        companion = match.copyWith(
          matchNumber: Value(await nextMatchNumber(match.tournamentId.value)),
        );
      }

      await into(matches).insert(companion);
    });
  }

  /// الرقم التالى للمباراة داخل البطولة (يبدأ من 1).
  Future<int> nextMatchNumber(String tournamentId) async {
    final maxNumber = matches.matchNumber.max();
    final query = selectOnly(matches)
      ..addColumns([maxNumber])
      ..where(matches.tournamentId.equals(tournamentId));

    final row = await query.getSingle();
    return (row.read(maxNumber) ?? 0) + 1;
  }

  Future<bool> updateMatch(MatchesCompanion match) async {
    if (!match.id.present) {
      throw ArgumentError('Match ID is required to update a match.');
    }

    final updatedRows = await (update(
      matches,
    )..where((tbl) => tbl.id.equals(match.id.value))).write(match);

    return updatedRows > 0;
  }

  /// يحذف المباراة ولاعبيها معًا (المفاتيح الأجنبية مفعلة).
  Future<int> deleteMatch(String id) {
    return transaction(() async {
      await customStatement('DELETE FROM match_players WHERE match_id = ?', [
        id,
      ]);
      return (delete(matches)..where((tbl) => tbl.id.equals(id))).go();
    });
  }

  Future<List<db.MatchData>> getTournamentMatches(String tournamentId) {
    return (select(matches)
          ..where((tbl) => tbl.tournamentId.equals(tournamentId))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.matchNumber)]))
        .get();
  }

  Future<List<db.MatchData>> getAllMatches() {
    return select(matches).get();
  }

  /// حفظ JSON الخاص بحالة اللعبة دون تعديل بيانات المباراة الأخرى.
  ///
  /// يرجع عدد الصفوف التي تم تحديثها:
  /// 1 إذا كانت المباراة موجودة، و0 إذا لم تكن موجودة.
  Future<int> saveGameStateJson({
    required String matchId,
    required String gameStateJson,
  }) {
    return (update(matches)..where((tbl) => tbl.id.equals(matchId))).write(
      MatchesCompanion(gameStateJson: Value(gameStateJson)),
    );
  }

  /// قراءة JSON الخاص بحالة اللعبة.
  ///
  /// يرجع null إذا لم توجد حالة محفوظة أو لم توجد المباراة.
  Future<String?> getGameStateJson(String matchId) async {
    final match = await getMatchById(matchId);
    return match?.gameStateJson;
  }

  /// مسح الحالة المحفوظة فقط، مع الاحتفاظ بسجل المباراة.
  ///
  /// يرجع عدد الصفوف التي تم تحديثها.
  Future<int> clearGameStateJson(String matchId) {
    return (update(matches)..where((tbl) => tbl.id.equals(matchId))).write(
      const MatchesCompanion(gameStateJson: Value(null)),
    );
  }
}
