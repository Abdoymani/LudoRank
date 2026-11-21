import 'package:drift/drift.dart';

import 'tournaments_table.dart';

@DataClassName('MatchData')
@TableIndex(name: 'idx_matches_tournament', columns: {#tournamentId})
@TableIndex(
  name: 'ux_matches_tournament_number',
  columns: {#tournamentId, #matchNumber},
  unique: true,
)
class Matches extends Table {
  /// Match ID (UUID)
  TextColumn get id => text()();

  /// Tournament ID
  TextColumn get tournamentId => text().references(Tournaments, #id)();

  /// رقم المباراة داخل البطولة (1, 2, 3, ...).
  /// يتم تعيينه تلقائيًا عند الإنشاء.
  IntColumn get matchNumber => integer()();

  /// pending
  /// playing
  /// finished
  /// cancelled
  TextColumn get status => text()();

  /// Created At
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Updated At
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// Number of players
  IntColumn get playersCount => integer().withDefault(const Constant(0))();

  /// Serialized LudoGameState JSON.
  ///
  /// Null for matches that do not have a saved game state yet.
  TextColumn get gameStateJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
