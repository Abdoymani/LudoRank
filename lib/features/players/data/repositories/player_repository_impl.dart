import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:drift/native.dart';
import 'package:ludo_rank/features/players/data/data_sources/local/player_dao.dart';
import 'package:ludo_rank/features/players/data/models/player_model.dart';
import 'package:ludo_rank/features/players/domain/entities/player.dart';
import 'package:ludo_rank/features/players/domain/exceptions/duplicate_player_name_exception.dart';
import 'package:ludo_rank/features/players/domain/repositories/player_repository.dart';

class PlayerRepositoryImpl implements PlayerRepository {
  final PlayerDao dao;

  PlayerRepositoryImpl(this.dao);

  @override
  Future<List<Player>> getAllPlayers() async {
    final rows = await dao.getAllPlayers();
    return rows.map(PlayerModel.fromDrift).toList();
  }

  @override
  Future<Player?> getPlayerById(String id) async {
    final row = await dao.getPlayerById(id);

    if (row == null) return null;

    return PlayerModel.fromDrift(row);
  }

  /// Throws [DuplicatePlayerNameException] when the name clashes with
  /// another player's once normalised (players.normalized_name is unique).
  @override
  Future<void> addPlayer(Player player) async {
    final name = player.name.trim();

    if (await dao.playerNameExists(name)) {
      throw const DuplicatePlayerNameException();
    }

    final model = PlayerModel.fromEntity(player.copyWith(name: name));

    await _rejectingDuplicates(() => dao.insertPlayer(model.toCompanion()));
  }

  @override
  Future<void> updatePlayer(Player player) async {
    final name = player.name.trim();

    if (await dao.playerNameExists(name, exceptId: player.id)) {
      throw const DuplicatePlayerNameException();
    }

    final model = PlayerModel.fromEntity(player.copyWith(name: name));

    await _rejectingDuplicates(() => dao.updatePlayer(model.toCompanion()));
  }

  /// The check above runs before the write; the unique indexes are the
  /// last word if another write got in between.
  Future<void> _rejectingDuplicates(Future<Object?> Function() write) async {
    try {
      await write();
    } catch (e) {
      // The app opens SQLite on a background isolate, which wraps errors.
      final cause = e is DriftRemoteException ? e.remoteCause : e;
      if (cause is SqliteException && _isNameClash(cause)) {
        throw const DuplicatePlayerNameException();
      }
      rethrow;
    }
  }

  @override
  Future<void> deletePlayer(String id) async {
    await dao.deletePlayer(id);
  }

  static bool _isNameClash(SqliteException e) {
    return e.extendedResultCode == 2067 && // SQLITE_CONSTRAINT_UNIQUE
        (e.message.contains('players.name') ||
            e.message.contains('players.normalized_name'));
  }
}
