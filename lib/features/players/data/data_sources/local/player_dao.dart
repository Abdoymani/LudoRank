import 'package:drift/drift.dart';

import 'package:ludo_rank/core/database/database.dart';
import 'package:ludo_rank/core/database/tables/players_table.dart';
import 'package:ludo_rank/features/players/domain/services/player_name_normalizer.dart';

part 'player_dao.g.dart';

@DriftAccessor(tables: [Players])
class PlayerDao extends DatabaseAccessor<AppDatabase> with _$PlayerDaoMixin {
  PlayerDao(super.db);

  Future<List<Player>> getAllPlayers() {
    return select(players).get();
  }

  Future<Player?> getPlayerById(String id) {
    return (select(
      players,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  Future<void> insertPlayer(PlayersCompanion player) {
    return into(players).insert(player);
  }

  /// Whether another player already has this name once both are
  /// normalised (case, hamza, tashkeel, spacing). [exceptId] skips the
  /// player being renamed.
  Future<bool> playerNameExists(String name, {String? exceptId}) async {
    final normalized = normalizePlayerName(name);
    final query = select(players)
      ..where((tbl) {
        final sameName =
            tbl.normalizedName.equals(normalized) |
            tbl.name.equals(name.trim());
        return exceptId == null
            ? sameName
            : sameName & tbl.id.isNotValue(exceptId);
      })
      ..limit(1);

    return await query.getSingleOrNull() != null;
  }

  Future<bool> updatePlayer(PlayersCompanion player) {
    return update(players).replace(player);
  }

  Future<int> deletePlayer(String id) {
    return (delete(players)..where((tbl) => tbl.id.equals(id))).go();
  }

  //
  Future<int> getPlayersCount() async {
    final query = selectOnly(players)..addColumns([players.id.count()]);

    final result = await query.getSingle();

    return result.read(players.id.count()) ?? 0;
  }
}
