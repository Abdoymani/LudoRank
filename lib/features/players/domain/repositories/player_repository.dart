import '../entities/player.dart';
import '../entities/player_stats.dart';

abstract class PlayerRepository {
  Future<List<Player>> getAllPlayers();

  Future<Player?> getPlayerById(String id);

  Future<void> addPlayer(Player player);

  Future<void> updatePlayer(Player player);

  Future<void> deletePlayer(String id);

  /// Matches, wins and points of every player over finished matches,
  /// by player id. Players without a finished match are left out.
  Future<Map<String, PlayerStats>> getPlayerStats() async => const {};
}
