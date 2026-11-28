import 'package:ludo_rank/features/tournament_players/domain/entities/tournament_player.dart';

abstract class TournamentPlayerRepository {
  Future<List<TournamentPlayer>> getTournamentPlayers(String tournamentId);

  /// Throws [StateError] when the tournament no longer accepts players
  /// (finished or otherwise closed). Running tournaments accept players.
  Future<void> addPlayer(TournamentPlayer player);

  /// Adds all players in one transaction, or none of them.
  Future<void> addPlayers(List<TournamentPlayer> players);

  Future<void> removePlayer(String id);

  Future<void> removeTournamentPlayers(String tournamentId);

  Future<void> updatePlayer(TournamentPlayer player);
}
