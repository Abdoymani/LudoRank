import 'package:drift/drift.dart';
import 'package:ludo_rank/core/database/tables/players_table.dart';
import 'package:ludo_rank/core/database/tables/tournaments_table.dart';

/// لا يمكن إضافة نفس اللاعب لنفس البطولة مرتين
/// (الفهرس الفريد يغطى أيضًا البحث بـ tournament_id).
@TableIndex(name: 'idx_tournament_players_player', columns: {#playerId})
@TableIndex(
  name: 'ux_tournament_players_tournament_player',
  columns: {#tournamentId, #playerId},
  unique: true,
)
class TournamentPlayers extends Table {
  TextColumn get id => text()();

  TextColumn get tournamentId => text().references(Tournaments, #id)();

  TextColumn get playerId => text().references(Players, #id)();

  DateTimeColumn get joinedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
