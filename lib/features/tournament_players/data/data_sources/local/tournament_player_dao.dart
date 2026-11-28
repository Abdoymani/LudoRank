import 'package:drift/drift.dart';

import 'package:ludo_rank/core/database/database.dart';
import 'package:ludo_rank/core/database/tables/tournament_players_table.dart';

part 'tournament_player_dao.g.dart';

@DriftAccessor(tables: [TournamentPlayers])
class TournamentPlayerDao extends DatabaseAccessor<AppDatabase>
    with _$TournamentPlayerDaoMixin {
  TournamentPlayerDao(super.db);

  /// جميع لاعبى البطولة
  Future<List<TournamentPlayer>> getTournamentPlayers(String tournamentId) {
    return (select(
      tournamentPlayers,
    )..where((tbl) => tbl.tournamentId.equals(tournamentId))).get();
  }

  /// لاعب واحد داخل البطولة
  Future<TournamentPlayer?> getTournamentPlayer(String id) {
    return (select(
      tournamentPlayers,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  /// Tournament statuses that still accept new players. A running
  /// tournament does (players may join mid-tournament); finished,
  /// cancelled or unreadable ones do not.
  static const openStatuses = {'draft', 'ready', 'running'};

  /// إضافة لاعب للبطولة
  Future<void> insertTournamentPlayer(TournamentPlayersCompanion player) {
    return insertTournamentPlayers([player]);
  }

  /// Adds several players in one transaction: all of them or none.
  ///
  /// Throws [StateError] when a target tournament no longer accepts
  /// players.
  Future<void> insertTournamentPlayers(
    List<TournamentPlayersCompanion> players,
  ) {
    return transaction(() async {
      final checked = <String>{};
      for (final player in players) {
        final tournamentId = player.tournamentId.value;
        if (checked.add(tournamentId)) {
          await _ensureAcceptsPlayers(tournamentId);
        }
        await into(tournamentPlayers).insert(player);
      }
    });
  }

  Future<void> _ensureAcceptsPlayers(String tournamentId) async {
    final row = await customSelect(
      'SELECT status FROM tournaments WHERE id = ?',
      variables: [Variable<String>(tournamentId)],
    ).getSingleOrNull();

    // A missing tournament is left to the foreign key.
    if (row == null) return;

    final status = row.read<String>('status');
    if (!openStatuses.contains(status)) {
      throw StateError(
        status == 'finished'
            ? 'البطولة منتهية، لا يمكن إضافة لاعبين جدد.'
            : 'البطولة مغلقة، لا يمكن إضافة لاعبين جدد.',
      );
    }
  }

  /// تحديث بيانات لاعب البطولة
  Future<bool> updateTournamentPlayer(TournamentPlayersCompanion player) {
    return update(tournamentPlayers).replace(player);
  }

  /// حذف لاعب من البطولة
  Future<int> removePlayer(String id) {
    return (delete(tournamentPlayers)..where((tbl) => tbl.id.equals(id))).go();
  }

  /// حذف جميع لاعبى البطولة
  Future<int> removeTournamentPlayers(String tournamentId) {
    return (delete(
      tournamentPlayers,
    )..where((tbl) => tbl.tournamentId.equals(tournamentId))).go();
  }
}
