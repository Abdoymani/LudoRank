import 'package:drift/drift.dart';
import 'package:ludo_rank/core/database/tables/matches_table.dart';
import 'package:ludo_rank/core/database/tables/players_table.dart';

@TableIndex(name: 'idx_match_players_match', columns: {#matchId})
@TableIndex(name: 'idx_match_players_player', columns: {#playerId})
class MatchPlayers extends Table {
  TextColumn get id => text()();

  TextColumn get matchId => text().references(Matches, #id)();

  TextColumn get playerId => text().references(Players, #id)();

  /// ترتيب اللاعب داخل المباراة
  IntColumn get seat => integer()();

  /// ترتيبه بعد انتهاء المباراة
  IntColumn get rank => integer().nullable()();

  /// النقاط التى حصل عليها
  IntColumn get points => integer().withDefault(const Constant(0))();

  /// هل اللاعب أنهى المباراة؟
  BoolColumn get finished => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
